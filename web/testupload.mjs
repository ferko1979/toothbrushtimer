// Test recordings from the apps' password-protected test mode (WAV + JSON timeline + tester's remark).
// Enabled only when TEST_UPLOAD_CODE is set (the same tester password the apps ask for). Files go to
// TEST_UPLOAD_DIR (default ./test-uploads/<device>/), and when GOOGLE_SERVICE_ACCOUNT (the service
// account's JSON key) and DRIVE_FOLDER_ID are set, on to that Google Drive folder (a shared drive the
// service account is a member of: service accounts have no storage of their own).
//
//   POST /api/test-upload/<file name>   headers: X-Tester-Code, X-Tester-Device   body: the file

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

export const NAME = /^denthub-brush-\d{8}-\d{6}(\.wav|\.json|-remark\.txt)$/;
const DEVICE = /^[A-Za-z0-9_-]{1,64}$/;
const MAX = 40 * 1024 * 1024;

function same(a, b) {
  const x = Buffer.from(String(a)), y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

export function testUpload(req, res, name, send, env = process.env) {
  const code = env.TEST_UPLOAD_CODE;
  if (!code) return send(res, 503, 'Test upload is not enabled');
  if (req.method !== 'POST') return send(res, 405, 'Method not allowed', { Allow: 'POST' });
  if (!same(req.headers['x-tester-code'] || '', code)) return send(res, 401, 'Wrong tester code');
  if (!NAME.test(name)) return send(res, 400, 'Bad file name');
  const device = String(req.headers['x-tester-device'] || 'unknown');
  if (!DEVICE.test(device)) return send(res, 400, 'Bad device id');
  const dir = path.join(env.TEST_UPLOAD_DIR || path.join(process.cwd(), 'test-uploads'), device);
  fs.mkdirSync(dir, { recursive: true });
  const tmp = path.join(dir, `.${name}.${process.pid}.part`);
  const out = fs.createWriteStream(tmp);
  let size = 0, failed = false;
  req.on('data', (c) => {
    size += c.length;
    if (size > MAX && !failed) { failed = true; out.destroy(); fs.rmSync(tmp, { force: true }); send(res, 413, 'Too large'); req.destroy(); }
  });
  req.pipe(out);
  out.on('finish', async () => {
    if (failed) return;
    const file = path.join(dir, name);
    fs.renameSync(tmp, file);
    if (env.GOOGLE_SERVICE_ACCOUNT && env.DRIVE_FOLDER_ID) {
      try {
        await driveUpload(file, `${device}_${name}`, env);
        fs.rmSync(file, { force: true });
      } catch (e) {
        console.error('Drive upload failed (kept on disk):', e.message);
      }
    }
    send(res, 201, 'ok');
  });
  out.on('error', () => { if (!failed) { failed = true; send(res, 500, 'Write error'); } });
}

const b64url = (b) => Buffer.from(b).toString('base64url');
let token = null;

async function accessToken(env) {
  if (token && token.exp > Date.now() + 60_000) return token.value;
  const key = JSON.parse(env.GOOGLE_SERVICE_ACCOUNT);
  const now = Math.floor(Date.now() / 1000);
  const head = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64url(JSON.stringify({
    iss: key.client_email, scope: 'https://www.googleapis.com/auth/drive.file',
    aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600,
  }));
  const sig = crypto.createSign('RSA-SHA256').update(`${head}.${claims}`).sign(key.private_key).toString('base64url');
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${head}.${claims}.${sig}` }),
  });
  if (!r.ok) throw new Error(`token ${r.status}`);
  const j = await r.json();
  token = { value: j.access_token, exp: Date.now() + j.expires_in * 1000 };
  return token.value;
}

async function driveUpload(file, name, env) {
  const boundary = 'b' + crypto.randomBytes(12).toString('hex');
  const meta = JSON.stringify({ name, parents: [env.DRIVE_FOLDER_ID] });
  const type = name.endsWith('.wav') ? 'audio/wav' : name.endsWith('.json') ? 'application/json' : 'text/plain';
  const body = Buffer.concat([
    Buffer.from(`--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${meta}\r\n--${boundary}\r\nContent-Type: ${type}\r\n\r\n`),
    fs.readFileSync(file),
    Buffer.from(`\r\n--${boundary}--`),
  ]);
  const r = await fetch('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true', {
    method: 'POST', body,
    headers: { Authorization: `Bearer ${await accessToken(env)}`, 'Content-Type': `multipart/related; boundary=${boundary}` },
  });
  if (!r.ok) throw new Error(`drive ${r.status} ${await r.text()}`);
}
