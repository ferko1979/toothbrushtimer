import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createServer } from '../server.mjs';
import { seal } from './phone.mjs';

const vector = JSON.parse(readFileSync(new URL('./vector.json', import.meta.url)));

async function withServer(fn) {
  const srv = createServer();
  await new Promise((r) => srv.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${srv.address().port}`;
  try { await fn(base); } finally { srv.close(); srv.closeAllConnections?.(); }
}

const sid = () => crypto.randomBytes(16).toString('base64url');

test('envelope from the test vector opens with the web private key', () => {
  const web = crypto.createECDH('prime256v1');
  web.setPrivateKey(Buffer.from(vector.webPrivate, 'base64url'));
  const env = Buffer.from(vector.envelope, 'base64url');
  const shared = web.computeSecret(env.subarray(0, 65));
  const key = Buffer.from(crypto.hkdfSync('sha256', shared, Buffer.from(vector.sid), Buffer.from('fogmosas-web-v1'), 32));
  const d = crypto.createDecipheriv('aes-256-gcm', key, env.subarray(65, 77));
  d.setAAD(Buffer.from(vector.sid));
  d.setAuthTag(env.subarray(env.length - 16));
  const plain = Buffer.concat([d.update(env.subarray(77, env.length - 16)), d.final()]).toString('utf8');
  assert.equal(plain, vector.plaintext);
});

test('message posted before the browser polls is delivered once', async () => {
  await withServer(async (base) => {
    const s = sid();
    const body = seal(Buffer.from(vector.webPublic, 'base64url'), s, Buffer.from('{"v":1}'));
    assert.equal((await fetch(`${base}/api/relay/${s}`, { method: 'POST', body })).status, 204);
    assert.equal((await fetch(`${base}/api/relay/${s}`, { method: 'POST', body })).status, 409);
    const r = await fetch(`${base}/api/relay/${s}`);
    assert.equal(r.status, 200);
    assert.equal(await r.text(), body);
    // Gone after delivery: the next poll waits (we abort it).
    const ac = new AbortController();
    setTimeout(() => ac.abort(), 300);
    await assert.rejects(fetch(`${base}/api/relay/${s}`, { signal: ac.signal }));
  });
});

test('long poll is woken by the phone', async () => {
  await withServer(async (base) => {
    const s = sid();
    const body = seal(Buffer.from(vector.webPublic, 'base64url'), s, Buffer.from('{"v":1}'));
    const poll = fetch(`${base}/api/relay/${s}`);
    await new Promise((r) => setTimeout(r, 150));
    await fetch(`${base}/api/relay/${s}`, { method: 'POST', body });
    const r = await poll;
    assert.equal(r.status, 200);
    assert.equal(await r.text(), body);
  });
});

test('rejects bad input', async () => {
  await withServer(async (base) => {
    assert.equal((await fetch(`${base}/api/relay/short`)).status, 400);
    assert.equal((await fetch(`${base}/api/relay/${sid()}`, { method: 'POST', body: 'not base64 !!' })).status, 400);
    assert.equal((await fetch(`${base}/api/relay/${sid()}`, { method: 'POST', body: 'A'.repeat(600 * 1024) })).status, 413);
    assert.equal((await fetch(`${base}/api/relay/${sid()}`, { method: 'DELETE' })).status, 405);
    assert.equal((await fetch(`${base}/../server.mjs`)).status, 404);
  });
});

test('serves the page with a strict CSP', async () => {
  await withServer(async (base) => {
    for (const p of ['/', '/l']) {
      const r = await fetch(base + p);
      assert.equal(r.status, 200);
      assert.match(r.headers.get('content-security-policy'), /script-src 'self'/);
      assert.match(await r.text(), /QR-kód/);
    }
  });
});
