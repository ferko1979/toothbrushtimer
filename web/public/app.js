/* Fogmosás web dashboard. Pairing protocol: ../PROTOCOL.md */
'use strict';

const INFO = 'fogmosas-web-v1';
const PAIR_TIMEOUT_MS = 5 * 60 * 1000;
const $ = (id) => document.getElementById(id);
const enc = new TextEncoder();

const b64 = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const unb64 = (s) => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4)), (c) => c.charCodeAt(0));

function basePath() {
  return location.pathname.replace(/\/(l|index\.html)?$/, '');
}

// ------------------------------------------------------------------ crypto

async function newSession() {
  const sid = b64(crypto.getRandomValues(new Uint8Array(16)));      // 22 chars
  const keys = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, false, ['deriveBits']);
  const pub = new Uint8Array(await crypto.subtle.exportKey('raw', keys.publicKey));  // 65 bytes, 0x04||x||y
  return { sid, keys, pub, qr: `${location.origin}${basePath()}/l#${sid}.${b64(pub)}` };
}

async function open(session, envelopeB64) {
  const env = unb64(envelopeB64);
  if (env.length < 65 + 12 + 16 || env[0] !== 4) throw new Error('bad envelope');
  const phonePub = await crypto.subtle.importKey('raw', env.slice(0, 65), { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const shared = await crypto.subtle.deriveBits({ name: 'ECDH', public: phonePub }, session.keys.privateKey, 256);
  const hkdf = await crypto.subtle.importKey('raw', shared, 'HKDF', false, ['deriveKey']);
  const key = await crypto.subtle.deriveKey({ name: 'HKDF', hash: 'SHA-256', salt: enc.encode(session.sid), info: enc.encode(INFO) },
    hkdf, { name: 'AES-GCM', length: 256 }, false, ['decrypt']);
  const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: env.slice(65, 77), additionalData: enc.encode(session.sid) }, key, env.slice(77));
  return JSON.parse(new TextDecoder().decode(plain));
}

// ------------------------------------------------------------------ pairing

let session = null;
let pairing = 0;   // generation counter: a renewed QR cancels the old poll loop

async function startPairing() {
  const gen = ++pairing;
  $('pair-status').textContent = 'Várom a telefont…';
  session = await newSession();
  const qr = qrcode(0, 'M');
  qr.addData(session.qr);
  qr.make();
  $('qr').src = qr.createDataURL(6, 4);
  const started = Date.now();
  while (gen === pairing) {
    if (Date.now() - started > PAIR_TIMEOUT_MS) {
      $('pair-status').textContent = 'A kód lejárt, újat készítettem.';
      return startPairing();
    }
    let res;
    try {
      res = await fetch(`${basePath()}/api/relay/${session.sid}`, { cache: 'no-store' });
    } catch {
      $('pair-status').textContent = 'Nincs kapcsolat a szerverrel, újrapróbálom…';
      await new Promise((r) => setTimeout(r, 3000));
      continue;
    }
    if (gen !== pairing) return;
    if (res.status === 200) {
      try {
        const data = await open(session, (await res.text()).trim());
        session = null;   // one-time: forget the private key
        showDashboard(data);
      } catch (e) {
        $('pair-status').textContent = 'A csomagot nem sikerült kinyitni. Próbáld újra egy új kóddal.';
        startPairing();
      }
      return;
    }
    if (res.status !== 204) await new Promise((r) => setTimeout(r, 2000));
  }
}

// ------------------------------------------------------------------ helpers

function el(tag, attrs = {}, ...children) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') e.className = v;
    else if (k === 'text') e.textContent = v;
    else e.setAttribute(k, v);
  }
  for (const c of children.flat(Infinity)) if (c != null) e.append(c);
  return e;
}

const SVG = 'http://www.w3.org/2000/svg';
function svg(tag, attrs = {}) {
  const e = document.createElementNS(SVG, tag);
  for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v);
  return e;
}

const clock = (s) => `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, '0')}`;
const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const huDay = (s) => s.slice(5).replace('-', '.') + '.';

function lastDays(n, endIso) {
  const end = new Date(endIso + 'T12:00:00');
  return Array.from({ length: n }, (_, i) => { const d = new Date(end); d.setDate(end.getDate() - (n - 1 - i)); return iso(d); });
}

// ------------------------------------------------------------------ dashboard

let data = null;

function showDashboard(d) {
  data = d;
  $('pair').hidden = true;
  $('phone-hint').hidden = true;
  $('dash').hidden = false;
  $('logout').hidden = false;
  const gen = new Date(d.generated);
  $('dash-sub').textContent = `Frissítve: ${gen.toLocaleString('hu-HU')} · Az adatok csak ebben a böngészőlapban vannak.`;
  const tabs = $('tabs');
  tabs.replaceChildren();
  d.profiles.forEach((p, i) => {
    const b = el('button', { class: 'tab', role: 'tab', 'aria-selected': String(i === 0), text: `${p.avatar} ${p.name}` });
    b.addEventListener('click', () => {
      for (const t of tabs.children) t.setAttribute('aria-selected', 'false');
      b.setAttribute('aria-selected', 'true');
      renderProfile(p);
    });
    tabs.append(b);
  });
  tabs.hidden = d.profiles.length < 2;
  renderProfile(d.profiles[0]);
}

function renderProfile(p) {
  $('dash-title').textContent = `${p.avatar} ${p.name}`;
  const today = data.generated.slice(0, 10);
  const days30 = lastDays(30, today);
  const byDay = Object.fromEntries(p.days.map((x) => [x.d, x]));
  const in30 = days30.map((d) => byDay[d]).filter(Boolean);
  const brushes = in30.reduce((a, x) => a + x.n, 0);
  const avg = brushes ? in30.reduce((a, x) => a + x.avgS * x.n, 0) / brushes : 0;
  const hits = in30.reduce((a, x) => a + x.goalHits, 0);
  const floss = in30.filter((x) => x.floss).length;

  const tile = (v, l) => el('div', { class: 'card tile' }, el('div', { class: 'v', text: v }), el('div', { class: 'l', text: l }));
  const tiles = el('div', { class: 'tiles' },
    tile(`🔥 ${p.streak}`, 'nap sorozat (napi cél teljesítve)'),
    tile(clock(avg), `átlagos fogmosás (cél: ${clock(p.goals.targetS)})`),
    tile(brushes ? `${Math.round((100 * hits) / brushes)}%` : '–', 'célidőt elérte (30 nap)'),
    tile(`${floss} / 30`, 'nap fogselyemmel'));

  const insights = el('div', { class: 'card' }, el('h2', { text: 'Megfigyelések' }));
  if (p.insights.length) {
    insights.append(el('ul', { class: 'insights' }, p.insights.map((t) => el('li', { class: t.alert ? 'alert' : '', text: t.text }))));
  } else insights.append(el('p', { class: 'muted', text: 'Nincs különösebb észrevétel. Így tovább!' }));

  const report = el('div', { class: 'card report' }, el('h2', { text: p.report.title }), el('p', { class: 'muted small', text: p.report.subtitle }),
    p.report.sections.map((s) => [el('h3', { text: s.title }), el('ul', {}, s.lines.map((l) => el('li', { text: l })))]));

  $('profile').replaceChildren(
    tiles,
    el('div', { class: 'grid2' }, durationChart(p, days30, byDay), careCalendar(p, today, byDay)),
    el('div', { class: 'grid2' }, insights, report),
    tableView(p, days30, byDay),
  );
}

function durationChart(p, days, byDay) {
  const W = 480, H = 220, L = 36, R = 8, T = 12, B = 24;
  const vals = days.map((d) => byDay[d]?.avgS || 0);
  const max = Math.max(p.goals.targetS * 1.25, ...vals);
  const y = (v) => T + (H - T - B) * (1 - v / max);
  const step = (W - L - R) / days.length;
  const bw = Math.max(step - 2, 2);   // 2px gap between bars
  const s = svg('svg', { viewBox: `0 0 ${W} ${H}`, role: 'img', 'aria-label': 'Átlagos fogmosási idő naponta, az utóbbi 30 nap' });
  const grid = svg('g', { class: 'grid' }), axis = svg('g', { class: 'axis' });
  for (let t = 0; t <= max; t += 60) {
    grid.append(svg('line', { x1: L, x2: W - R, y1: y(t), y2: y(t) }));
    const tx = svg('text', { x: L - 6, y: y(t) + 4, 'text-anchor': 'end' }); tx.textContent = clock(t); axis.append(tx);
  }
  [0, 7, 14, 21, 29].forEach((i) => {
    const tx = svg('text', { x: L + step * i + step / 2, y: H - 6, 'text-anchor': 'middle' }); tx.textContent = huDay(days[i]); axis.append(tx);
  });
  s.append(grid, axis);
  const wrap = el('div', { class: 'chart' });
  const tip = el('div', { class: 'tooltip', hidden: '' });
  days.forEach((d, i) => {
    const v = vals[i];
    const x = L + step * i + (step - bw) / 2;
    const g = svg('g');
    const hit = svg('rect', { class: 'bar-hit', x: L + step * i, y: T, width: step, height: H - T - B });
    const h = Math.max(y(0) - y(v), v > 0 ? 2 : 0);
    // Rounded top, square baseline: a path instead of a rect with rx.
    const r = Math.min(4, bw / 2, h);
    const bar = svg('path', { class: 'bar', d: h ? `M${x},${y(0)} V${y(0) - h + r} q0,-${r} ${r},-${r} H${x + bw - r} q${r},0 ${r},${r} V${y(0)} Z` : '' });
    const show = () => {
      const day = byDay[d];
      tip.textContent = day && day.n ? `${huDay(d)} · ${day.n}× · átlag ${clock(day.avgS)}` : `${huDay(d)} · nem volt mérés`;
      tip.style.left = `${Math.min(Math.max(((x + bw / 2) / W) * 100, 18), 82)}%`;
      tip.style.top = `${(y(v) / H) * 100}%`;
      tip.hidden = false;
      bar.classList.add('hl');
    };
    const hide = () => { tip.hidden = true; bar.classList.remove('hl'); };
    hit.addEventListener('mouseenter', show); hit.addEventListener('mouseleave', hide);
    hit.addEventListener('touchstart', show, { passive: true });
    g.append(hit, bar);
    s.append(g);
  });
  s.append(svg('line', { class: 'goal', x1: L, x2: W - R, y1: y(p.goals.targetS), y2: y(p.goals.targetS) }));
  wrap.append(s, tip);
  return el('div', { class: 'card' }, el('h2', { text: 'Fogmosási idő (napi átlag)' }), wrap,
    el('div', { class: 'legend' }, el('span', {}, el('span', { class: 'sw' }), 'napi átlag'), el('span', {}, el('span', { class: 'dash' }), 'célidő')));
}

function careCalendar(p, today, byDay) {
  const days = lastDays(35, today);
  const first = new Date(days[0] + 'T12:00:00');
  const pad = (first.getDay() + 6) % 7;   // Monday first
  const cal = el('div', { class: 'cal' }, ['H', 'K', 'Sze', 'Cs', 'P', 'Szo', 'V'].map((d) => el('div', { class: 'dow', text: d })));
  for (let i = 0; i < pad; i++) cal.append(el('div', { class: 'day empty' }));
  for (const d of days) {
    const x = byDay[d];
    const marks = [];
    if (x?.floss) marks.push(el('span', { class: 'mark', text: '🧵' }));
    if (x?.bleed) marks.push(el('span', { class: 'mark bleed', text: '●' }));
    if (x?.sens) marks.push(el('span', { class: 'mark sens', text: x.sens > 1 ? '▲▲' : '▲' }));
    const label = [huDay(d), x?.n ? `${x.n} fogmosás` : 'nincs fogmosás', x?.floss ? 'fogselyem' : '', x?.bleed ? 'ínyvérzés' : '',
      x?.sens ? (x.sens > 1 ? 'erős érzékenység' : 'enyhe érzékenység') : ''].filter(Boolean).join(', ');
    cal.append(el('div', { class: `day${x?.floss ? ' floss' : ''}`, title: label, 'aria-label': label },
      el('span', { text: d.slice(8) }), el('span', { class: 'n', text: x?.n ? `${x.n}×` : '' }), el('span', {}, marks)));
  }
  return el('div', { class: 'card' }, el('h2', { text: 'Fogápolási napló (5 hét)' }), cal,
    el('div', { class: 'legend' }, el('span', { text: '🧵 fogselyem' }), el('span', {}, el('b', { class: 'bleed', text: '● ' }), 'ínyvérzés'),
      el('span', {}, el('b', { class: 'sens', text: '▲ ' }), 'érzékenység (▲▲ erős)')));
}

function tableView(p, days, byDay) {
  const rows = days.slice().reverse().map((d) => byDay[d]).filter(Boolean);
  const yes = (b) => (b ? 'igen' : '');
  return el('details', { class: 'card' }, el('summary', { text: 'Táblázat (30 nap)' }),
    el('table', { class: 'data' },
      el('thead', {}, el('tr', {}, ['Nap', 'Fogmosás', 'Átlag', 'Célidő elérve', 'Fogselyem', 'Szájvíz', 'Érzékenység', 'Ínyvérzés'].map((h) => el('th', { text: h })))),
      el('tbody', {}, rows.map((x) => el('tr', {}, [huDay(x.d), String(x.n), x.n ? clock(x.avgS) : '', String(x.goalHits), yes(x.floss), yes(x.mouthwash),
        ['', 'enyhe', 'erős'][x.sens] || '', yes(x.bleed)].map((v) => el('td', { text: v })))))));
}

// ------------------------------------------------------------------ start

$('renew').addEventListener('click', () => startPairing());
$('print').addEventListener('click', () => window.print());
$('logout').addEventListener('click', () => { data = null; location.replace(`${basePath()}/`); });

if (location.pathname.endsWith('/l') && /Android|iPhone|iPad/i.test(navigator.userAgent)) $('phone-hint').hidden = false;
if (!window.crypto?.subtle) {
  $('pair-status').textContent = 'Ehhez a böngészőhöz biztonságos (https) kapcsolat kell.';
} else {
  startPairing();
}
