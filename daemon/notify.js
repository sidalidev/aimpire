// Notifications macOS pour les signaux d'attention : terminal-notifier si présent (cliquable, ouvre l'app Claude), sinon osascript.
// Garde-fous : une par signal (clé session|kind), au plus une toutes les 2 min (regroupées), heures calmes, jamais de contenu
// de session dans le texte (seulement le nom du village et le genre de signal).
import { execFile } from 'node:child_process';
import fs from 'node:fs';
import { file, readJson } from './paths.js';
import { log } from './log.js';

const NOTIFIER = ['/opt/homebrew/bin/terminal-notifier', '/usr/local/bin/terminal-notifier'].find((p) => fs.existsSync(p));
const LABELS = { question: 'is asking you a question', permission: 'is waiting for permission', erreur: 'keeps getting API errors', fini: 'is done', silence: 'has gone suspiciously silent' };

let cfgAt = 0, cfg = {};
function config() {
  if (Date.now() - cfgAt > 10000) { cfgAt = Date.now(); cfg = readJson(file('config.json'), {}); }
  const n = cfg.notify || {};
  return { enabled: n.enabled !== false, kinds: n.kinds || ['question', 'permission', 'erreur'], quiet: n.quiet || null, minGapMs: (n.minGapMin || 2) * 60000 };
}

function inQuietHours(q, now) {
  if (!q || q.length !== 2) return false;
  const [h, m] = [new Date(now).getHours(), new Date(now).getMinutes()];
  const cur = h * 60 + m;
  const [a, b] = q.map((s) => { const [hh, mm] = String(s).split(':').map(Number); return hh * 60 + (mm || 0); });
  return a <= b ? cur >= a && cur < b : cur >= a || cur < b;
}

function send(title, text) {
  if (NOTIFIER) execFile(NOTIFIER, ['-title', title, '-message', text, '-group', 'aimpire', '-activate', 'com.anthropic.claudefordesktop'], () => {});
  else execFile('osascript', ['-e', `display notification ${JSON.stringify(text)} with title ${JSON.stringify(title)}`], () => {});
}

const seen = new Map();   // clé -> horodatage de la notification
let lastSent = 0, pending = [];

// À appeler à chaque tick avec S.attention. Les signaux disparus sont oubliés (ils pourront renotifier s'ils reviennent plus tard).
export function notifyAttention(attention, now = Date.now()) {
  const c = config();
  if (!c.enabled) return;
  const keys = new Set();
  for (const a of attention) {
    if (!c.kinds.includes(a.kind)) continue;
    const key = `${a.session}|${a.kind}`;
    keys.add(key);
    if (seen.has(key)) continue;
    if (now - a.since > 2 * 3600 * 1000) { seen.set(key, now); continue; }   // trop vieux : on ne réveille pas pour ça
    seen.set(key, now);
    pending.push(a);
  }
  for (const k of seen.keys()) if (!keys.has(k) && now - seen.get(k) > 10 * 60 * 1000) seen.delete(k);
  if (!pending.length || now - lastSent < c.minGapMs || inQuietHours(c.quiet, now)) return;
  if (pending.length === 1) {
    const a = pending[0];
    send(`AImpire · ${a.villageName}`, `A session ${LABELS[a.kind] || a.kind}`);
  } else {
    const villages = [...new Set(pending.map((a) => a.villageName))].slice(0, 4).join(', ');
    send('AImpire', `${pending.length} sessions are waiting for you (${villages})`);
  }
  log.info('notification', pending.length);
  pending = []; lastSent = now;
}
