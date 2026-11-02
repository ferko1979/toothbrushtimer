// Plays the phone's part of the protocol with Node's crypto (same steps as WebLink.kt / WebLink.swift).
import crypto from 'node:crypto';

export function parseQr(qr) {
  const u = new URL(qr);
  const [sid, key] = u.hash.slice(1).split('.');
  return { base: `${u.origin}${u.pathname.replace(/\/l$/, '')}`, sid, webPublic: Buffer.from(key, 'base64url') };
}

export function seal(webPublic, sid, plaintext) {
  const phone = crypto.createECDH('prime256v1');
  phone.generateKeys();
  const key = Buffer.from(crypto.hkdfSync('sha256', phone.computeSecret(webPublic), Buffer.from(sid), Buffer.from('fogmosas-web-v1'), 32));
  const nonce = crypto.randomBytes(12);
  const c = crypto.createCipheriv('aes-256-gcm', key, nonce);
  c.setAAD(Buffer.from(sid));
  return Buffer.concat([phone.getPublicKey(), nonce, c.update(plaintext), c.final(), c.getAuthTag()]).toString('base64url');
}

/** A realistic snapshot with two profiles over 40 days. */
export function sampleSnapshot(today = new Date('2026-11-02T12:00:00Z')) {
  const days = (seed, target) => Array.from({ length: 40 }, (_, i) => {
    const d = new Date(today); d.setUTCDate(today.getUTCDate() - (39 - i));
    const r = Math.sin(seed * 31 + i * 7.3) * 0.5 + 0.5;
    const n = r < 0.12 ? 0 : r < 0.3 ? 1 : 2;
    return { d: d.toISOString().slice(0, 10), n, avgS: n ? Math.round(80 + r * 70) : 0, goalHits: n ? Math.round(n * r) : 0, tapOff: n,
      floss: r > 0.45, mouthwash: r > 0.8, interdental: false, tongue: r > 0.7, sens: r > 0.9 ? 2 : r > 0.82 ? 1 : 0, bleed: i % 9 === 0 };
  }).filter((x) => x.n || x.floss || x.bleed || x.sens);
  const report = (name) => ({ title: `Fogápolási jelentés – ${name}`, subtitle: '2026.10.04. – 2026.11.02. (30 nap)', sections: [
    { title: 'Fogmosás', lines: ['Fogmosások: 48 (27 napon a 30 napból; reggel 23, este 25)', 'Átlagos időtartam: 1:52 (cél: 2:00), célidőt elérte: 46%'] },
    { title: 'Tünetek', lines: ['Fogérzékenység: 4 napon (ebből erős: 1)', 'Ínyvérzés: 3 napon'] }] });
  return { v: 1, generated: today.toISOString(), locale: 'hu', profiles: [
    { name: 'Anna', child: false, avatar: '🧑', goals: { perDay: 2, targetS: 120 }, streak: 4, stickers: 0, orthodontic: false, days: days(1, 120),
      insights: [{ text: 'Az ínyed az utóbbi 2 hétben 4 napon vérzett. Ha a vérzés 2 hétnél tovább tart, keresd fel a fogorvosodat. Ez nem orvosi diagnózis.', alert: true },
        { text: 'Amióta gyakrabban fogselymezel (3 → 9 nap / 2 hét), ritkábban vérzik az ínyed (6 → 4 nap).', alert: false }], report: report('Anna') },
    { name: 'Bence', child: true, avatar: '🦖', goals: { perDay: 2, targetS: 120 }, streak: 9, stickers: 17, orthodontic: false, days: days(2, 120),
      insights: [], report: report('Bence') }] };
}
