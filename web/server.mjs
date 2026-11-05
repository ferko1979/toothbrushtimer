// Fogmosás web dashboard + relay. Node >= 18, no dependencies.
//
// The relay forwards ONE encrypted message from the phone to the browser tab that
// showed the QR code, then forgets it. It never sees keys or plaintext and stores
// nothing on disk. Protocol: PROTOCOL.md.
//
//   PORT=8080 node server.mjs

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { testUpload } from './testupload.mjs';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), 'public');
const PORT = Number(process.env.PORT || 8080);
const TTL_MS = 120_000;          // a message waits at most 2 minutes
const POLL_MS = 25_000;          // long-poll timeout
const MAX_BODY = 512 * 1024;     // 512 KiB of base64url
const SID = /^[A-Za-z0-9_-]{22}$/;
const BODY = /^[A-Za-z0-9_-]+$/;

const messages = new Map();      // sid -> { body, expires }
const waiters = new Map();       // sid -> Set<(body) => void>

// Simple per-IP rate limit: 60 relay requests per minute.
const hits = new Map();
function limited(ip) {
  const now = Date.now();
  const h = hits.get(ip) || { n: 0, reset: now + 60_000 };
  if (now > h.reset) { h.n = 0; h.reset = now + 60_000; }
  h.n++;
  hits.set(ip, h);
  return h.n > 60;
}

setInterval(() => {
  const now = Date.now();
  for (const [sid, m] of messages) if (m.expires < now) messages.delete(sid);
  for (const [ip, h] of hits) if (h.reset < now) hits.delete(ip);
}, 10_000).unref();

const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon', '.json': 'application/json' };

const SECURITY = {
  'Content-Security-Policy': "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
};

function send(res, status, body = '', headers = {}) {
  res.writeHead(status, { ...SECURITY, 'Cache-Control': 'no-store', ...headers });
  res.end(body);
}

function serveStatic(req, res, pathname) {
  // "/l" is the link inside the QR code: same page (it tells phone users to use the app).
  const rel = pathname === '/' || pathname === '/l' ? 'index.html' : pathname.slice(1);
  const file = path.normalize(path.join(ROOT, rel));
  if (!file.startsWith(ROOT + path.sep)) return send(res, 404, 'Not found');
  fs.readFile(file, (err, data) => {
    if (err) return send(res, 404, 'Not found');
    send(res, 200, data, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
  });
}

function readBody(req, max) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    let over = false;
    req.on('data', (c) => {
      size += c.length;
      if (over) { if (size > 4 * max) req.destroy(); return; }   // drain a little, then cut
      if (size > max) { over = true; reject(new Error('too large')); return; }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8').trim()));
    req.on('error', reject);
  });
}

async function relay(req, res, sid) {
  const ip = req.socket.remoteAddress || '?';
  if (limited(ip)) return send(res, 429, 'Too many requests');

  if (req.method === 'POST') {
    let body;
    try { body = await readBody(req, MAX_BODY); } catch { return send(res, 413, 'Too large', { Connection: 'close' }); }
    if (!BODY.test(body) || body.length < 120) return send(res, 400, 'Bad envelope');
    const ws = waiters.get(sid);
    if (ws && ws.size) {
      waiters.delete(sid);
      for (const w of ws) w(body);
    } else {
      if (messages.has(sid)) return send(res, 409, 'Already sent');
      messages.set(sid, { body, expires: Date.now() + TTL_MS });
    }
    return send(res, 204);
  }

  if (req.method === 'GET') {
    const m = messages.get(sid);
    if (m) { messages.delete(sid); return send(res, 200, m.body, { 'Content-Type': 'text/plain' }); }
    let done = false;
    const finish = (body) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      const set = waiters.get(sid);
      if (set) { set.delete(finish); if (!set.size) waiters.delete(sid); }
      if (body) send(res, 200, body, { 'Content-Type': 'text/plain' }); else send(res, 204);
    };
    const timer = setTimeout(() => finish(null), POLL_MS);
    req.on('close', () => finish(null));
    if (!waiters.has(sid)) waiters.set(sid, new Set());
    waiters.get(sid).add(finish);
    return;
  }

  send(res, 405, 'Method not allowed', { Allow: 'GET, POST' });
}

export function createServer() {
  return http.createServer((req, res) => {
    const url = new URL(req.url, 'http://x');
    const m = url.pathname.match(/^\/api\/relay\/([^/]+)$/);
    if (m) {
      if (!SID.test(m[1])) return send(res, 400, 'Bad session id');
      relay(req, res, m[1]).catch(() => send(res, 500, 'Error'));
      return;
    }
    const up = url.pathname.match(/^\/api\/test-upload\/([^/]+)$/);
    if (up) return testUpload(req, res, decodeURIComponent(up[1]), send);
    if (url.pathname === '/healthz') return send(res, 200, 'ok');
    if (req.method !== 'GET' && req.method !== 'HEAD') return send(res, 405, 'Method not allowed');
    serveStatic(req, res, url.pathname);
  });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  createServer().listen(PORT, () => console.log(`Fogmosás web: http://localhost:${PORT}`));
}
