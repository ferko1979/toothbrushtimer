// Generates the cross-platform test vector for the web-link envelope (PROTOCOL.md).
// Usage: node tools/make-vector.mjs > test/vector.json
import crypto from 'node:crypto';

const h = (s) => crypto.createHash('sha256').update(s).digest();
const b64 = (b) => Buffer.from(b).toString('base64url');

const sid = 'fogmosasTestSession01x';
const web = crypto.createECDH('prime256v1'); web.setPrivateKey(h('fogmosas web test key'));
const phone = crypto.createECDH('prime256v1'); phone.setPrivateKey(h('fogmosas phone test key'));
const nonce = Buffer.from([...Array(12).keys()]);
const plaintext = Buffer.from('{"hello":"fogmosás","n":2}', 'utf8');

const shared = phone.computeSecret(web.getPublicKey());
const key = Buffer.from(crypto.hkdfSync('sha256', shared, Buffer.from(sid), Buffer.from('fogmosas-web-v1'), 32));
const c = crypto.createCipheriv('aes-256-gcm', key, nonce);
c.setAAD(Buffer.from(sid));
const ct = Buffer.concat([c.update(plaintext), c.final(), c.getAuthTag()]);
const envelope = Buffer.concat([phone.getPublicKey(), nonce, ct]);

console.log(JSON.stringify({
  sid,
  webPrivate: b64(web.getPrivateKey()), webPublic: b64(web.getPublicKey()),
  phonePrivate: b64(phone.getPrivateKey()), phonePublic: b64(phone.getPublicKey()),
  nonce: b64(nonce), sharedSecret: b64(shared), key: b64(key),
  plaintext: plaintext.toString('utf8'), envelope: b64(envelope),
  qr: `https://fogmosas.example/l#${sid}.${b64(web.getPublicKey())}`,
}, null, 2));
