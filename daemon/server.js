// Serveur AImpire : lit les journaux Claude Code (scan.js), calcule le modèle du jeu (model.js), sert l'état au client Godot.
// Lecture seule, zéro token, local seulement : 127.0.0.1, pas de CORS, jeton exigé sur tout ce qui modifie l'état.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { scanFile, listFiles, pruneFood, unitOf, readRegistry } from './scan.js';
import { buildState, MONUMENTS } from './model.js';
import { speak, voicesEnabled } from './voices.js';
import { DATA, file, writeAtomic, readJson, ensureToken, CLAUDE_DIR } from './paths.js';
import { PORT, VERSION, SCHEMA, WORK_MS } from './config.js';
import { log } from './log.js';
import { doAction } from './actions.js';
import { notifyAttention } from './notify.js';
import { report } from './report.js';
import { setGoal, clearGoal } from './goals.js';
import { creerSync } from './sync.js';
import { flouter, creerPseudo, resoudreVillage, TYPE_LABELS } from './blur.js';
import { viderDonnees } from './erase.js';

const SAVE = file('save.json'), CACHE = file('cache.json');
const TOKEN = ensureToken();
const started = Date.now();
const parentPid = Number((process.argv.find((a) => a.startsWith('--parent-pid=')) || '').split('=')[1]) || 0;

// --- Sauvegarde : schéma, migrations, sauvegardes quotidiennes ---
const MIGRATIONS = {};   // { 1: (data) => data2 }
function loadSave() {
  let s = readJson(SAVE, null);
  if (!s) s = readJson(SAVE + '.bak', {});
  if ((s.schema || 0) > SCHEMA) { log.warn('save.json comes from a newer version, set aside'); try { fs.renameSync(SAVE, SAVE + '.future'); } catch {} s = {}; }
  for (let v = s.schema || 0; v < SCHEMA; v++) if (MIGRATIONS[v]) s = MIGRATIONS[v](s);
  s.schema = SCHEMA;
  return s;
}
let S = loadSave();
S.townCenter = { x: 0, z: 0 }; S.tick = 0;
const cache = readJson(CACHE, {});
cache.files ||= {}; cache.subs ||= {}; cache.food ||= {}; cache.schema = SCHEMA;
let dirtyCache = false, scanning = { done: 0, total: 0 };
const stats = { badLines: 0, lastScanMs: 0, lastLineAt: 0, versions: {} };

const PERSIST = ['fete', 'schema', 'order', 'done', 'peak', 'prevRes', 'activeDays', 'quests', 'bonus', 'wasIdle', 'spent', 'monuments', 'installedAt', 'ledger', 'baseline', 'lastSeen', 'journal'];
let lastSaveHash = '', lastSaveAt = 0;
let effacement = false;   // « Erase everything » en cours : plus rien n'est écrit dans le dossier de données
function persist(force = false) {
  if (effacement) return;
  const data = JSON.stringify(Object.fromEntries(PERSIST.map((k) => [k, S[k]])));
  const h = crypto.createHash('sha1').update(data).digest('hex');
  const now = Date.now();
  if (h === lastSaveHash) return;
  if (!force && now - lastSaveAt < 30000) return;
  try {
    if (fs.existsSync(SAVE)) fs.copyFileSync(SAVE, SAVE + '.bak');
    writeAtomic(SAVE, data);
    const day = new Date().toLocaleDateString('sv');
    const daily = file(`save-${day}.json`);
    if (!fs.existsSync(daily)) {
      writeAtomic(daily, data);
      const old = fs.readdirSync(DATA).filter((f) => /^save-\d{4}-\d{2}-\d{2}\.json$/.test(f)).sort().slice(0, -7);
      for (const f of old) try { fs.unlinkSync(file(f)); } catch {}
    }
    lastSaveHash = h; lastSaveAt = now;
  } catch (e) { log.error('save', e); }
}
let lastCacheAt = 0;
function persistCache(force = false) {
  if (!dirtyCache || effacement) return;
  const now = Date.now();
  if (!force && now - lastCacheAt < 60000) return;
  try { writeAtomic(CACHE, JSON.stringify(cache)); dirtyCache = false; lastCacheAt = now; } catch (e) { log.error('cache', e); }
}

// --- Surveillance : fs.watch (FSEvents) marque les fichiers modifiés ; un listFiles complet toutes les 60 s sert de filet ---
const dirty = new Set();
let watching = false, lastList = 0, listed = { sessions: [], subs: [] };
try {
  fs.watch(path.join(CLAUDE_DIR, 'projects'), { recursive: true }, (_ev, name) => { if (name && String(name).endsWith('.jsonl')) dirty.add(path.join(CLAUDE_DIR, 'projects', String(name))); });
  fs.watch(path.join(CLAUDE_DIR, 'sessions'), () => dirty.add('registry'));
  watching = true;
} catch (e) { log.warn('fs.watch unavailable, polling only', e); }

// --- Scan : fichiers modifiés à chaque tour, tous les fichiers de temps en temps ---
async function scanRound(full) {
  const now = Date.now(), t0 = now;
  if (full || !watching || now - lastList > 60000 || dirty.size) { listed = listFiles(now); lastList = now; }
  const { sessions, subs } = listed;
  dirty.clear();
  const keep = new Set(sessions.map((s) => s.file));
  for (const f of Object.keys(cache.files)) if (!keep.has(f)) { delete cache.files[f]; dirtyCache = true; }
  const todo = sessions.filter((s) => full || !cache.files[s.file] || cache.files[s.file].mtime !== s.mtime)
    .sort((a, b) => b.mtime - a.mtime);
  scanning = { done: 0, total: todo.length };
  let n = 0;
  for (const s of todo) {
    const c = (cache.files[s.file] ||= { kind: 'session' });
    c.kind = 'session';
    if (await scanFile(s.file, c, cache.food, stats)) dirtyCache = true;
    scanning.done++;
    if (++n % 50 === 0) persistCache(true);
    await new Promise((r) => setImmediate(r));
  }
  const bySession = {};
  for (const sub of subs) {
    const c = (cache.subfiles ||= {})[sub.file] ||= {};
    await scanFile(sub.file, c, {}, stats);
    (bySession[sub.session] ||= []).push({ id: sub.id, title: c.firstAsk || 'tâche', tool: c.lastTool || '',
      working: !!(c.last && now - c.last < WORK_MS), unit: unitOf(c.model), workflow: sub.workflow });
  }
  cache.subs = bySession;
  for (const f of Object.keys(cache.subfiles || {})) if (!subs.some((s) => s.file === f)) delete cache.subfiles[f];
  cache.registry = readRegistry();
  pruneFood(cache.food, now);
  stats.lastScanMs = Date.now() - t0;
}

// --- Réglages côté serveur (<données>/config.json) : mode discret pour les partages d'écran, notifications ---
const CONFIG = file('config.json');
let settings = readJson(CONFIG, {});
function saveSettings() { if (effacement) return; try { writeAtomic(CONFIG, JSON.stringify(settings, null, 2)); } catch (e) { log.error('config', e); } }

// Mode discret : liste blanche de l'état servi (blur.js). Fait côté serveur pour que rien de sensible n'atteigne l'écran
// (captures, visio) ni l'état publié pour le téléphone. Les ids de village deviennent des pseudonymes stables.
const pseudo = creerPseudo(TOKEN);
const flou = () => settings.privacy === 'flou';

// Recalcule l'état servi (après un POST qui change S, pour que le client le voie tout de suite).
function publish(recompute = false) {
  if (recompute) { try { buildState(S, cache, Date.now()); } catch (e) { log.error('model', e); } }
  ready = true;
  stateJson = JSON.stringify(flou() ? flouter(S, pseudo) : S);
  stateEtag = '"' + crypto.createHash('sha1').update(stateJson).digest('hex').slice(0, 16) + '"';
}

// --- Boucle : rapide quand un client regarde, lente sinon ---
let busy = false, rounds = 0, lastClient = 0, stateJson = '', stateEtag = '', ready = false;
async function loop() {
  if (busy) return;
  busy = true;
  try { await scanRound(rounds % 60 === 0); } catch (e) { log.error('scan', e); }
  rounds++;
  try { buildState(S, cache, Date.now()); } catch (e) { log.error('model', e); }
  try { notifyAttention(S.attention || []); } catch (e) { log.error('notify', e); }
  journal();
  S.tick++; S.scanning = scanning;
  publish();
  persist(); persistCache();
  busy = false;
  const idle = Date.now() - lastClient > 10000;
  setTimeout(loop, idle ? 10000 : 1000);
  if (parentPid) { try { process.kill(parentPid, 0); } catch { log.info('parent gone, stopping'); shutdown(); } }
}
function shutdown() {
  sync?.arreter();
  persist(true); persistCache(true);
  try { fs.unlinkSync(file('server.pid')); } catch {}
  process.exit(0);
}
process.on('SIGTERM', shutdown); process.on('SIGINT', shutdown);
process.on('uncaughtException', (e) => { log.error('fatal', e); persist(true); persistCache(true); process.exit(1); });

// Journal de l'Empire : les événements marquants sont conservés (500 derniers), pas seulement la file de 60 du client.
let journalSeq = 0;
function journal() {
  S.journal ||= [];
  const last = S.journal.length ? S.journal[S.journal.length - 1].t : 0;
  for (const e of S.events || []) {
    if (e.t <= last || ['bois', 'pierre', 'parchemins', 'or', 'faim'].includes(e.type)) continue;
    S.journal.push({ t: e.t, type: e.type, village: e.village || '', text: e.text || '' });
  }
  if (S.journal.length > 500) S.journal.splice(0, S.journal.length - 500);
}

// Ce qui s'est passé depuis ta dernière visite (le client appelle POST /vu quand tu regardes).
function digest(now) {
  const since = S.lastSeen || now;
  const d = { since, commits: 0, testsOk: 0, or: 0, villages: new Set(), events: [] };
  for (const [k, day] of Object.entries(S.ledger?.days || {})) {
    if (Date.parse(k) < since - 86400000) continue;
    d.commits += day.commits || 0; d.testsOk += day.testsOk || 0; d.or += day.or || 0;
    for (const [v, x] of Object.entries(day.villages || {})) if (x.min > 0 || x.commits > 0) d.villages.add(v);
  }
  d.events = (S.journal || []).filter((e) => e.t > since).slice(-8);
  return { ...d, villages: [...d.villages], attention: (S.attention || []).length };
}

// --- Actions partagées par les routes locales et par les commandes du téléphone (sync.js) : { ok, erreur } ---
function regler(cle, val) {
  if (cle !== 'privacy' || !['normal', 'flou'].includes(val)) return { ok: false, erreur: 'unknown setting' };
  settings.privacy = val; saveSettings(); publish(); log.info('discreet mode', val);
  return { ok: true };
}
function reclamer(village) {
  // en mode discret, le client ne connaît que le pseudonyme du village
  const vrai = resoudreVillage(String(village || ''), (S.quests?.list || []).map((x) => x.village), pseudo);
  const quest = (S.quests?.list || []).find((x) => x.village === vrai && x.done && !x.claimed);
  if (!quest) return { ok: false, erreur: 'no reward to claim for this village' };
  quest.claimed = true; S.bonus.or += quest.reward;
  events({ type: 'recompense', text: `+${quest.reward} gold for reviving ${quest.name}!` });
  persist(true); publish(true);
  return { ok: true };
}
function construire(id) {
  const m = MONUMENTS.find((x) => x.id === id);
  if (!m) return { ok: false, erreur: 'unknown monument' };
  if ((S.monuments || []).includes(m.id)) return { ok: false, erreur: 'already built' };
  if ((S.empire?.tresor || 0) < m.cout) return { ok: false, erreur: 'not enough gold' };
  S.monuments.push(m.id); S.spent = (S.spent || 0) + m.cout;
  events({ type: 'monument', text: `${m.nom} rises at the Forum!` });
  persist(true); publish(true);
  return { ok: true };
}

// Annexes de l'état publié pour le téléphone : rapport, journal, digest. En mode discret, elles valent null : elles ne
// quittent pas le Mac (et l'état lui-même passe par la liste blanche de blur.js, sans journal ni registre).
function annexes() {
  if (settings.privacy === 'flou') return { rapport: null, journal: null, digest: null };
  const now = Date.now();
  return { rapport: { jour: report(S, 'jour', now), semaine: report(S, 'semaine', now) }, journal: (S.journal || []).slice(-60), digest: digest(now) };
}

const sync = creerSync({
  reglages: () => settings, sauverReglages: saveSettings,
  etatServi: () => (ready ? stateJson : ''), annexes,
  appliquer: { reclamer, construire, reglage: regler },
  evenement: (e) => { events(e); publish(); }, log,
});

const readBody = (req) => new Promise((resolve) => { let b = ''; req.on('data', (c) => { b += c; if (b.length > 65536) req.destroy(); }); req.on('end', () => resolve(b)); });

// --- HTTP ---
const send = (res, code, obj) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(obj)); };
const hostOk = (req) => /^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/.test(req.headers.host || '') && !req.headers.origin;
const authOk = (req) => (req.headers.authorization || '') === 'Bearer ' + TOKEN;
const events = (e) => { S.events ||= []; S.events.push({ t: Date.now(), ...e }); if (S.events.length > 60) S.events.shift(); };

const server = http.createServer((req, res) => {
  if (!hostOk(req)) return send(res, 403, { error: 'local only' });
  const url = new URL(req.url, 'http://x');
  if (req.method === 'GET' && url.pathname === '/state') {
    lastClient = Date.now();
    if (!ready) return send(res, 200, { ready: false, scanning });
    if (req.headers['if-none-match'] === stateEtag) { res.writeHead(304); return res.end(); }
    res.writeHead(200, { 'Content-Type': 'application/json', ETag: stateEtag }); return res.end(stateJson);
  }
  if (req.method === 'GET' && url.pathname === '/health') {
    return send(res, 200, { ok: true, version: VERSION, schema: SCHEMA, uptime: Math.round((Date.now() - started) / 1000), scanning,
      files: Object.keys(cache.files).length, lastScanMs: stats.lastScanMs, lastLineAt: stats.lastLineAt, badLines: stats.badLines,
      claudeVersions: Object.keys(stats.versions), claudeDir: CLAUDE_DIR, data: DATA, voiceEnabled: voicesEnabled(),
      memoryMb: Math.round(process.memoryUsage().rss / 1048576), sync: !!sync.chaine });
  }
  if (!authOk(req)) return send(res, 401, { error: 'missing token' });
  if (req.method === 'GET' && url.pathname === '/voix') {
    speak(url.searchParams.get('t') || '', url.searchParams.get('v')).then((buf) => {
      if (!buf) { res.writeHead(204); return res.end(); }
      res.writeHead(200, { 'Content-Type': 'audio/mpeg' }); res.end(buf);
    }).catch(() => { res.writeHead(204); res.end(); });
    return;
  }
  // Mode discret : le digest ne nomme aucun village, le rapport et le journal ne sont pas montrés à l'écran.
  if (req.method === 'GET' && url.pathname === '/digest') { const d = digest(Date.now()); return send(res, 200, flou() ? { ...d, villages: d.villages.map(pseudo), events: [] } : d); }
  if (req.method === 'POST' && url.pathname === '/reglage') {
    const cle = url.searchParams.get('cle'), val = url.searchParams.get('val');
    const r = regler(cle, val);
    if (r.ok) sync.reglageLocal();   // une commande du téléphone plus ancienne que ce choix ne l'annulera pas
    return send(res, r.ok ? 200 : 400, { ok: r.ok });
  }
  if (req.method === 'POST' && url.pathname === '/vu') { S.lastSeen = Date.now(); persist(true); return send(res, 200, { ok: true }); }
  if (req.method === 'GET' && url.pathname === '/rapport') return send(res, 200, { texte: flou() ? '# Report\n\nUnavailable in discreet mode (H to turn it off).' : report(S, url.searchParams.get('periode') || 'jour', Date.now()) });
  if (req.method === 'GET' && url.pathname === '/journal') return send(res, 200, { entrees: (S.journal || []).slice(-200).map((e) => (flou() ? { t: e.t, type: e.type, text: TYPE_LABELS[e.type] || 'event' } : e)) });
  if (req.method === 'POST' && url.pathname === '/action') {
    const kind = url.searchParams.get('kind'), id = url.searchParams.get('session');
    let b = null, cwd = '';
    for (const v of S.villages || []) for (const x of v.buildings) if (x.id === id) { b = x; cwd = v.cwd; }
    if (!b) return send(res, 400, { ok: false, error: 'unknown session' });
    const f = Object.keys(cache.files).find((x) => x.endsWith('/' + id + '.jsonl')) || '';
    const pr = cache.files[f]?.pr || '';
    doAction(kind, { cwd, file: f, pr }).then((r) => send(res, r.ok ? 200 : 400, r));
    return;
  }
  // Fête : 50 or pour une journée de feux d'artifice et de fanfares (puits d'or, purement cosmétique)
  if (req.method === 'POST' && url.pathname === '/fete') {
    const cout = Math.round(6 * (S.baseline?.or || 7));
    if ((S.empire?.tresor || 0) < cout) return send(res, 400, { ok: false, error: 'not enough gold' });
    S.spent = (S.spent || 0) + cout; S.fete = { until: Date.now() + 24 * 3600 * 1000, cout };
    events({ type: 'fete', text: 'Festival across the Empire: fireworks until tomorrow!' });
    persist(true); publish(true);
    return send(res, 200, { ok: true });
  }
  // Objectifs : fixer, accepter une proposition, retirer. Écrit <données>/aimpire.json.
  if (req.method === 'POST' && url.pathname === '/objectif') {
    if (flou()) return send(res, 400, { ok: false, error: 'goals are unavailable in discreet mode' });   // le client ne voit que des noms floutés
    const q = url.searchParams;
    const ok = q.get('retirer') ? clearGoal(q.get('village')) : setGoal(q.get('village'), q.get('texte'), q.get('res') || 'or', Number(q.get('cible')), q.get('depuis'));
    if (ok) { events({ type: 'senat', text: q.get('retirer') ? `Goal removed for ${q.get('village')}` : `New goal for ${q.get('village')}: ${q.get('texte')}` }); publish(true); }
    return send(res, ok ? 200 : 400, { ok });
  }
  if (req.method === 'POST' && url.pathname === '/reclamer') {
    const r = reclamer(url.searchParams.get('village'));
    return send(res, r.ok ? 200 : 400, { ok: r.ok });
  }
  if (req.method === 'POST' && url.pathname === '/construire') {
    const r = construire(url.searchParams.get('id'));
    return send(res, r.ok ? 200 : 400, { ok: r.ok });
  }
  // Chaîne de sync (docs/SYNC.md §5) : révèle S (QR, lien, mots), donc derrière le jeton local comme le reste.
  // En mode discret, ni le lien, ni les mots, ni le QR ne sont servis : rien à montrer par erreur pendant un partage d'écran.
  if (url.pathname === '/sync' && req.method === 'GET') return send(res, 200, sync.etat({ masquer: flou() }));
  if (url.pathname === '/sync' && req.method === 'POST') {
    const action = url.searchParams.get('action');
    if (action === 'creer') { const r = sync.creer(url.searchParams.get('relais'), { masquer: flou() }); return send(res, r.code, r.corps); }
    if (action === 'supprimer') { sync.supprimer().then((r) => send(res, 200, r), (e) => send(res, 500, { ok: false, error: e.message })); return; }
    return send(res, 400, { ok: false, error: 'unknown action' });
  }
  // Erase everything : la chaîne est effacée du relais (au mieux), le dossier de données vidé, puis le serveur s'arrête.
  // Rien n'est jamais effacé dans CLAUDE_DIR (erase.js le refuse). Le jeu efface ensuite ses propres réglages et quitte.
  if (req.method === 'POST' && url.pathname === '/effacer') {
    sync.supprimer().catch(() => ({ relais: 'relay unreachable' })).then((r) => {
      effacement = true;
      try {
        const n = viderDonnees(DATA, CLAUDE_DIR);
        send(res, 200, { ok: true, effaces: n, relais: r.relais });
      } catch (e) {
        effacement = false;
        return send(res, 500, { ok: false, error: e.message });
      }
      setTimeout(() => process.exit(0), 200);
    });
    return;
  }
  send(res, 404, { error: 'not found' });
});
server.on('error', (e) => { log.error(e.code === 'EADDRINUSE' ? `port ${PORT} already in use (set AIMPIRE_PORT to change it)` : e.message); process.exit(1); });
server.listen(PORT, '127.0.0.1', () => {
  writeAtomic(file('server.pid'), String(process.pid));
  log.info(`AImpire v${VERSION} on http://127.0.0.1:${PORT}  data: ${DATA}`);
  loop();
});
