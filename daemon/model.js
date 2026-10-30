// Le modèle du jeu : villages (dossiers), bâtiments (sessions), unités (modèle), nourriture (forfait), objectifs,
// registre durable (ce qui a été gagné chaque jour), signaux d'attention. Tout est calculé depuis le cache de scan.js ; rien n'est inventé.
import fs from 'node:fs';
import path from 'node:path';
import { unitOf, FOOD_COST, dayKey } from './scan.js';
import { DAY, WORK_MS, SLEEP_MS, RUIN_MS } from './config.js';
import { file, readJson } from './paths.js';
import { calendar, rareEvent } from './calendar.js';
import { suggestGoals } from './goals.js';

const BUILDING_LEVELS = [0, 50, 200, 600, 1500];
const VILLAGE_LEVELS = [['vicus', 1, 0], ['oppidum', 3, 500], ['urbs', 6, 2000], ['metropolis', 10, 6000]];
const EMPIRE_TITLES = [['Citizen', 0], ['Decurion', 1000], ['Tribune', 3000], ['Praetor', 8000], ['Consul', 15000], ['Proconsul', 30000], ['Dictator', 60000], ['Caesar', 120000]];
// Les monuments se paient avec l'or gagné depuis l'installation ; les prix sont en « jours de travail » (médiane d'or par jour actif).
export const MONUMENTS = [
  { id: 'jardins', nom: 'Forum Gardens', jours: 6 },
  { id: 'statue', nom: 'Statue of Minerva', jours: 10 },
  { id: 'colonnade', nom: 'Colonnade', jours: 18 },
  { id: 'temple', nom: 'Temple of Jupiter', jours: 30 },
  { id: 'arc', nom: 'Triumphal Arch', jours: 45 },
  { id: 'aqueduc', nom: 'Aqueduct', jours: 60 },
  { id: 'amphitheatre', nom: 'Amphitheater', jours: 90 },
  { id: 'pantheon', nom: 'Pantheon', jours: 120 },
];
const RINGS = [[8, 22], [14, 40], [20, 58], [28, 76]];
const ARMOR = { low: 'tunic', medium: 'leather', high: 'lorica', xhigh: 'lorica segmentata', max: 'lorica segmentata' };
const RES = ['bois', 'pierre', 'parchemins', 'or'];

export const xpOf = (t) => Math.round(t.bois + Math.floor(t.linesAdded / 20) + t.pierre + t.parchemins + 8 * t.or);
const levelOf = (xp) => BUILDING_LEVELS.filter((s) => xp >= s).length;
const short = (m) => (m && !m.startsWith('<') ? m : '').replace('claude-', '').replace(/-\d{8}$/, '');
const median = (xs) => { const a = [...xs].sort((x, y) => x - y); return a.length ? a[Math.floor(a.length / 2)] : 0; };

function buildingType(c) {
  const t = c.tally;
  if (!t || t.tools < 3) return 'cabane';
  if (t.cost > 60 || xpOf(t) >= 1500) return 'chateau';
  const scores = { atelier: t.edits * 2 + t.linesAdded / 40, forge: t.pierre * 2 + t.tests, bibliotheque: t.parchemins, tour: t.tour * 2 };
  return Object.entries(scores).sort((a, b) => b[1] - a[1])[0][0];
}

// Les villages se centralisent : plus un village est développé, plus il est proche du Forum.
// `score` = niveau puis XP ; on ne réordonne que si l'écart est net (15 %), pour éviter que deux villages proches permutent sans cesse.
function placeVillages(S, ids, score) {
  const prev = S.order || [];
  let order = [...ids].sort((a, b) => score[b] - score[a]);
  const stable = prev.filter((id) => ids.includes(id));
  if (stable.length === ids.length) {
    let ok = true;
    const lvl = (x) => Math.floor(score[x] / 100000), xp = (x) => score[x] % 100000;
    for (let i = 1; i < stable.length; i++) {
      const a = stable[i - 1], b = stable[i];
      if (lvl(b) > lvl(a) || (lvl(b) === lvl(a) && xp(b) > xp(a) * 1.15 + 50)) ok = false;
    }
    if (ok) order = stable;
  }
  S.order = order;
  S.slots = Object.fromEntries(order.map((id, k) => [id, k]));
  const pos = {};
  for (const id of ids) {
    let k = S.slots[id], ring = 0;
    while (ring < RINGS.length - 1 && k >= RINGS[ring][0]) { k -= RINGS[ring][0]; ring++; }
    const [n, r] = RINGS[ring];
    const a = (k / n) * Math.PI * 2 + (ring % 2 ? 0 : Math.PI / n);
    pos[id] = { x: +(Math.cos(a) * r).toFixed(2), z: +(Math.sin(a) * r).toFixed(2), ang: a };
  }
  return pos;
}

// Configuration : <données>/aimpire.json. { villages: { nom|cwd: { objectif, cible:{or:20}, depuis, province } }, alias: { cwd: cwd }, ignore: [nom|cwd] }
let goalsCache = { mtime: -1, data: {} };
function readGoals(now) {
  let mtime = 0; try { mtime = fs.statSync(file('aimpire.json')).mtimeMs; } catch {}
  if (mtime !== goalsCache.mtime) goalsCache = { mtime, data: readJson(file('aimpire.json'), {}) };
  const g = goalsCache.data;
  g.villages ||= {}; g.alias ||= {}; g.ignore ||= [];
  return g;
}

// Un dossier de travail devient un village : les worktrees Claude (`…/.claude/worktrees/x`) rejoignent leur dépôt, les alias de la config s'appliquent.
function villageOf(cwd, goals) {
  let c = cwd.replace(/[\\/]+$/, '');
  const wt = /^(.*)[\\/]\.claude[\\/]worktrees[\\/][^\\/]+$/.exec(c);
  if (wt) c = wt[1];
  for (const [from, to] of Object.entries(goals.alias)) if (c.toLowerCase() === String(from).toLowerCase()) c = to;
  return c;
}

// Signaux d'attention d'une session : ce qui mérite un coup d'œil, du plus urgent au moins urgent. Rien si tu as répondu depuis.
function attentionOf(c, reg, now) {
  const out = [];
  const asked = c.askedTs || 0, age = now - (c.last || 0);
  const busy = reg ? reg.status === 'busy' : null;
  const pending = Object.entries(c.pending || {}).filter(([, p]) => p.ts > asked);
  const q = pending.find(([, p]) => p.name === 'AskUserQuestion');
  if (q) out.push({ kind: 'question', since: q[1].ts });
  else {
    // un outil lancé sans résultat : permission si la session est signalée inactive (registre), ou sans registre après 90 s de silence.
    // Avec le registre « busy », c'est un outil long (Bash, navigateur), pas une permission.
    const p = pending.find(([, p]) => now - p.ts > 8000);
    if (p && age < 2 * 3600 * 1000 && ((busy === false && age > 8000) || (busy === null && age > 90000))) out.push({ kind: 'permission', since: p[1].ts, tool: p[1].name });
  }
  if (c.turnEnd && c.turnEnd > asked && !q && now - c.turnEnd < 6 * 3600 * 1000 && now - c.turnEnd > 5000) out.push({ kind: 'fini', since: c.turnEnd });
  if (c.lastError && c.lastError > asked && (c.retry || 0) >= 3 && now - c.lastError < 30 * 60 * 1000) out.push({ kind: 'erreur', since: c.lastError });
  if (busy === true && age > 10 * 60 * 1000 && c.lastTool && !/^mcp__(computer-use|claude-in-chrome|Claude_Browser)/.test(c.lastTool)) out.push({ kind: 'silence', since: c.last });
  return out;
}

export function buildState(S, cache, now) {
  const goals = readGoals(now);
  S.events ||= []; S.done ||= {}; S.ledger ||= { sessions: {} }; S.bonus ||= { or: 0 };
  S.installedAt ||= now;
  const push = (ev) => { S.events.push({ t: now, ...ev }); if (S.events.length > 60) S.events.shift(); };
  const prev = S.prevRes || {};
  const villages = new Map();
  const registry = cache.registry || {};
  const attention = [];

  for (const [f, c] of Object.entries(cache.files)) {
    if (c.kind !== 'session' || !c.tally) continue;
    const cwd = villageOf(c.cwd || path.basename(path.dirname(f)), goals);
    const name = path.basename(cwd);
    if (goals.ignore.some((x) => String(x).toLowerCase() === name.toLowerCase() || String(x).toLowerCase() === cwd.toLowerCase())) continue;
    const vid = cwd.toLowerCase();
    if (!villages.has(vid)) villages.set(vid, { id: vid, name, cwd, buildings: [], res: { bois: 0, pierre: 0, parchemins: 0, or: 0 } });
    const v = villages.get(vid);
    const t = c.tally, xp = xpOf(t);
    const id = path.basename(f, '.jsonl');
    // registre durable : la copie par jour de cette session survit à la purge du cache (totaux monotones, séries, rapports)
    S.ledger.sessions[id] = { v: vid, days: t.days || {} };
    const age = now - (c.last || c.mtime || 0);
    const reg = registry[id];
    const working = age < WORK_MS || !!(reg && reg.status === 'busy' && now - reg.updatedAt < 60000 && age < 10 * 60 * 1000);
    const sleeping = !working && age > SLEEP_MS, ruin = age > RUIN_MS;
    const unit = unitOf(c.model);
    const subs = (cache.subs[f] || []).map((s) => ({ id: s.id, title: s.title, tool: s.tool, working: s.working, unit: s.unit, workflow: s.workflow }));
    const prevRes = prev[id];
    if (prevRes) for (const r of RES) if (t[r] > prevRes[r]) push({ type: r, village: vid, building: id, n: Math.round(t[r] - prevRes[r]) });
    const lvl = levelOf(xp);
    if (prevRes && lvl > prevRes.lvl) push({ type: 'niveau', village: vid, building: id, text: `${c.customTitle || c.title || c.firstAsk || 'Session'} reaches level ${lvl}` });
    prev[id] = { bois: t.bois, pierre: t.pierre, parchemins: t.parchemins, or: t.or, lvl };
    const att = ruin ? [] : attentionOf(c, reg, now);
    for (const a of att) attention.push({ ...a, session: id, village: vid, villageName: name, title: c.customTitle || c.title || c.firstAsk || 'session' });
    v.buildings.push({
      id, title: c.customTitle || c.title || c.firstAsk || 'session', type: buildingType(c), level: lvl, xp,
      res: { bois: Math.round(t.bois + t.linesAdded / 20), pierre: Math.round(t.pierre), parchemins: Math.round(t.parchemins), or: t.or },
      commits: t.commits, tests: t.tests, testsOk: t.testsOk || 0,
      model: short(c.model), unit, cost: FOOD_COST[unit], armure: ARMOR[c.effort] || 'leather', effort: c.effort || '',
      usd: +(t.cost || 0).toFixed(2), tokens: t.tokens, branch: c.branch || '',
      ago: Math.round(age / 1000), lastTool: c.lastTool || '', asked: c.asked || '', said: c.said || '',
      working, sleeping, ruin, remote: !!(reg && reg.remote), entry: reg ? reg.entrypoint : '',
      attention: att.length ? att[0].kind : '',
      state: working ? (c.lastTool ? (c.sub ? 'sub-agent · ' : '') + c.lastTool : 'thinking') : ruin ? 'ruin' : sleeping ? 'asleep'
        : att.length ? { question: 'is asking you a question', permission: 'waiting for permission', fini: 'done', erreur: 'API error', silence: 'suspicious silence' }[att[0].kind] : 'awaiting your orders',
      subs, last: c.last || 0, errors: c.errors || 0, compacts: c.compacts || 0,
    });
    for (const r of RES) v.res[r] += v.buildings[v.buildings.length - 1].res[r];
  }
  S.prevRes = prev;
  attention.sort((a, b) => ({ question: 0, permission: 1, erreur: 2, fini: 3, silence: 4 }[a.kind] - { question: 0, permission: 1, erreur: 2, fini: 3, silence: 4 }[b.kind]) || b.since - a.since);
  S.attention = attention;

  // registre : agrégat par jour (tout l'historique connu) et par village
  const days = {};
  for (const s of Object.values(S.ledger.sessions)) for (const [k, d] of Object.entries(s.days || {})) {
    const agg = (days[k] ||= { bois: 0, pierre: 0, parchemins: 0, or: 0, commits: 0, tests: 0, testsOk: 0, usd: 0, min: 0, villages: {} });
    for (const r of Object.keys(d)) if (r !== 'villages') agg[r] += d[r];
    const vv = (agg.villages[s.v] ||= { or: 0, min: 0, commits: 0 });
    vv.or += d.or || 0; vv.min += d.min || 0; vv.commits += d.commits || 0;
  }
  S.ledger.days = days;
  const dayKeys = Object.keys(days).sort();
  const todayKey = dayKey(now);
  const installKey = dayKey(S.installedAt);

  const ids = [...villages.keys()];
  const names = {};
  for (const v of villages.values()) names[v.name] = (names[v.name] || 0) + 1;
  for (const v of villages.values()) if (names[v.name] > 1) v.name = path.basename(path.dirname(v.cwd)) + '/' + v.name;
  const levelOfVillage = (v, xp) => { let l = 1; VILLAGE_LEVELS.forEach(([, minB, minXp], i) => { if (v.buildings.length >= minB || xp >= minXp) l = i + 1; }); return l; };
  const score = {};
  for (const [vid, v] of villages) { const xp = v.buildings.reduce((a, b) => a + b.xp, 0); score[vid] = levelOfVillage(v, xp) * 100000 + xp; }
  const pos = placeVillages(S, ids, score);
  const empire = { bois: 0, pierre: 0, parchemins: 0, or: 0, xp: 0, villages: ids.length, sessions: 0, actives: 0 };
  S.villages = ids.map((vid) => {
    const v = villages.get(vid);
    v.buildings.sort((a, b) => b.last - a.last);
    const xp = v.buildings.reduce((s, b) => s + b.xp, 0);
    const level = levelOfVillage(v, xp), levelName = VILLAGE_LEVELS[level - 1][0];
    const p = pos[vid];
    const u = { x: Math.cos(p.ang), z: Math.sin(p.ang) }, w = { x: -u.z, z: u.x };
    v.buildings.forEach((b, i) => {
      const row = Math.floor(i / 2), col = i % 2 ? 1 : -1;
      b.x = +(p.x + w.x * col * 3.8 + u.x * (row * 4.2 - 1.0)).toFixed(2);
      b.z = +(p.z + w.z * col * 3.8 + u.z * (row * 4.2 - 1.0)).toFixed(2);
      b.hidden = i >= 8;
    });
    // objectif : compté depuis `depuis` (sinon depuis l'installation), via le registre par jour, jamais sur tout l'historique
    const g = goals.villages[v.name] || goals.villages[vid] || goals.villages[v.cwd] || null;
    let objectif = null;
    if (g && g.cible) {
      const [res, target] = Object.entries(g.cible)[0];
      const sinceKey = dayKey(g.depuis ? (typeof g.depuis === 'number' ? g.depuis : Date.parse(g.depuis)) : S.installedAt);
      let have = 0;
      for (const k of dayKeys) if (k >= sinceKey) for (const s of Object.values(S.ledger.sessions)) if (s.v === vid && s.days[k]) have += s.days[k][res] || 0;
      have = Math.round(have);
      objectif = { texte: g.objectif || '', res, cible: target, progress: Math.min(1, have / target), have, done: have >= target, depuis: sinceKey };
      if (objectif.done && !S.done['obj:' + vid + ':' + sinceKey]) {
        S.done['obj:' + vid + ':' + sinceKey] = now;
        const prime = S.rare && S.rare.id === 'augure' ? 10 : 5;
        S.bonus.or += prime;
        push({ type: 'objectif', village: vid, text: `${v.name}: ${g.objectif || 'goal'} reached! (+${prime} gold)` });
      }
    }
    if (level >= 4 && !S.done['cite:' + vid]) { S.done['cite:' + vid] = now; push({ type: 'succes', village: vid, text: `${v.name} becomes a metropolis!` }); }
    for (const r of RES) empire[r] += v.res[r];
    empire.xp += xp; empire.sessions += v.buildings.length; empire.actives += v.buildings.filter((b) => b.working).length;
    const last = Math.max(0, ...v.buildings.map((b) => b.last || 0));
    const idleDays = last ? (now - last) / DAY : 99;
    const vitalite = Math.round(100 * Math.max(0, Math.min(1, 1 - (idleDays - 1) / 13)));
    return { id: vid, name: v.name, cwd: v.cwd, x: p.x, z: p.z, ang: +p.ang.toFixed(3), level, levelName, xp, res: v.res, objectif,
      province: g?.province || '', buildings: v.buildings, last, idleDays: +idleDays.toFixed(1), vitalite,
      attention: attention.filter((a) => a.village === vid).length };
  });
  empire.titre = EMPIRE_TITLES.filter(([, min]) => empire.xp >= min).pop()[0];

  // --- Remettre du mouvement : série de jours actifs, ordres du Sénat, bonus quand un village endormi reprend ---
  const active = (k) => (days[k]?.min || 0) >= 10 || (days[k]?.commits || 0) > 0;
  let serie = 0;
  for (let d = 0; d < 365; d++) {
    if (active(dayKey(now - d * DAY))) serie++;
    else if (d > 0) break;                                // aujourd'hui peut encore venir
  }
  empire.serie = serie;
  S.activeDays = dayKeys.filter(active).slice(-90);
  if (!S.quests || S.quests.date !== todayKey) {
    const pick = S.villages.filter((v) => v.idleDays >= 2 && v.idleDays <= 21 && v.xp > 30)
      .sort((a, b) => ((b.objectif && !b.objectif.done) - (a.objectif && !a.objectif.done)) || b.xp - a.xp).slice(0, 3);
    S.quests = { date: todayKey, list: pick.map((v) => ({ village: v.id, name: v.name, idle: Math.floor(v.idleDays), since: now, done: false, reward: 20 + Math.floor(v.idleDays) * 5 })) };
    if (pick.length) push({ type: 'senat', text: `The Senate orders: revive ${pick.map((v) => v.name).join(', ')}` });
  }
  S.bonus ||= { or: 0 };
  for (const q of S.quests.list) {
    const v = S.villages.find((x) => x.id === q.village);
    if (!q.done && v && v.last > q.since) { q.done = true; q.claimed = false; push({ type: 'reprise', village: v.id, text: `${v.name} comes back to life! Claim your reward at the Forum` }); }
  }
  S.wasIdle ||= {};
  for (const v of S.villages) {
    const idle = v.idleDays > 3;
    if (S.wasIdle[v.id] && !idle && !S.quests.list.some((q) => q.village === v.id)) push({ type: 'reprise', village: v.id, text: `Back to ${v.name}!` });
    S.wasIdle[v.id] = idle;
  }

  // --- Trésor : l'or gagné depuis l'installation (+100 de départ, + récompenses), pas tout l'historique. Prix en jours de travail. ---
  let orSince = 0;
  for (const k of dayKeys) if (k >= installKey) orSince += days[k].or || 0;
  const orParJour = median(dayKeys.filter(active).map((k) => days[k].or || 0).filter((x) => x > 0));
  S.baseline ||= { or: Math.max(3, orParJour || 10), at: now };
  if (now - S.baseline.at > 30 * DAY && orParJour) { S.baseline = { or: Math.max(3, Math.min(S.baseline.or * 1.25, Math.max(S.baseline.or * 0.75, orParJour))), at: now }; }
  S.spent ||= 0; S.monuments ||= [];
  empire.orSince = Math.round(orSince);
  empire.tresor = Math.max(0, Math.round(100 + orSince + S.bonus.or - S.spent));
  empire.monuments = MONUMENTS.map((m) => ({ ...m, cout: Math.round(m.jours * S.baseline.or), bati: S.monuments.includes(m.id) }));
  empire.quests = S.quests.list;
  empire.endormis = S.villages.filter((v) => v.vitalite < 50).length;
  empire.attention = attention.length;
  empire.aujourdhui = days[todayKey] || { or: 0, commits: 0, testsOk: 0, min: 0, usd: 0 };
  S.empire = empire;

  // --- Nourriture : moisson (5 h) et hiver (7 j), échelle = pic observé avec décroissance lente ; famine = quotaLimits rejeté encore actif ---
  const food = cache.food || {};
  let saison = 0, hiver = 0; const parUnite = {};
  for (const [k, by] of Object.entries(food)) {
    const age = now - Number(k);
    const sum = Object.values(by).reduce((a, b) => a + b, 0);
    if (age < 5 * 3600 * 1000) { saison += sum; for (const [u, x] of Object.entries(by)) parUnite[u] = (parUnite[u] || 0) + x; }
    if (age < 7 * DAY) hiver += sum;
  }
  const keys = Object.keys(food).map(Number).sort((a, b) => a - b);
  const sums = keys.map((k) => Object.values(food[k]).reduce((a, b) => a + b, 0));
  let peakS = saison;
  for (let i = 0; i < keys.length; i++) { let s5 = 0; for (let j = i; j < keys.length && keys[j] - keys[i] < 5 * 3600 * 1000; j++) s5 += sums[j]; peakS = Math.max(peakS, s5); }
  const prevPeak = S.peak || { saison: 1, hiver: 1, at: now };
  const decay = Math.pow(0.98, (now - (prevPeak.at || now)) / DAY);   // le pic s'oublie à 2 % par jour, pour suivre un changement de forfait
  S.peak = { saison: Math.max(1, peakS, prevPeak.saison * decay), hiver: Math.max(1, hiver, (prevPeak.hiver || 1) * decay), at: now };
  let quota = null;
  for (const c of Object.values(cache.files)) if (c.quota && c.quota.ts && (!quota || c.quota.ts > quota.ts)) quota = c.quota;
  const famine = !!(quota && quota.status === 'rejected' && quota.resetsAt * 1000 > now);
  const tot = Object.values(parUnite).reduce((a, b) => a + b, 0) || 1;
  S.food = {
    saison: +(saison / S.peak.saison).toFixed(3), hiver: +(hiver / S.peak.hiver).toFixed(3), famine,
    retourA: famine ? quota.resetsAt * 1000 : null, type: quota?.rateLimitType || '',
    parUnite: Object.fromEntries(Object.entries(parUnite).map(([u, x]) => [u, +(x / tot).toFixed(3)])),
  };
  if (famine && !S.done['famine:' + quota.resetsAt]) { S.done['famine:' + quota.resetsAt] = now; push({ type: 'famine', text: 'Famine: your plan quota is used up, the villagers are resting' }); }
  if (S.food.saison > 0.8 && !S.done['faim:' + Math.floor(now / (5 * 3600 * 1000))]) { S.done['faim:' + Math.floor(now / (5 * 3600 * 1000))] = now; push({ type: 'faim', text: 'Harvest reserves are running low' }); }

  // --- Calendrier romain, événement rare du jour, fête payée, propositions d'objectifs ---
  const commits7 = dayKeys.filter((k) => now - Date.parse(k) < 7 * DAY).reduce((a, k) => a + (days[k].commits || 0), 0);
  S.calendrier = calendar(now, S.installedAt);
  const rare = rareEvent(now, { commits7, opus: S.villages.some((v) => v.buildings.some((b) => b.unit === 'chevalier' && now - b.last < DAY)), serie });
  if (rare && !S.done['rare:' + rare.jour]) { S.done['rare:' + rare.jour] = now; if (rare.or) S.bonus.or += rare.or; push({ type: 'rare', text: rare.nom + (rare.or ? ` (+${rare.or} gold)` : '') }); }
  S.rare = rare;
  if (S.fete && S.fete.until < now) S.fete = null;
  empire.fete = S.fete || null;
  empire.calendrier = S.calendrier;
  empire.rare = rare;
  empire.tresor = Math.max(0, Math.round(100 + orSince + S.bonus.or - S.spent));
  S.suggestions = suggestGoals(S.villages, goals, S.baseline.or);
  empire.suggestions = S.suggestions;

  // --- Succès : la qualité, pas la consommation ---
  const ok = (key, text) => { if (!S.done[key]) { S.done[key] = now; push({ type: 'succes', text }); } };
  if (empire.actives >= 10) ok('dix', '10 sessions at once!');
  if (serie >= 7) ok('serie7', 'Seven days in a row');
  if (serie >= 30) ok('serie30', 'Thirty days in a row: a Vestal watches over the Empire');
  const commits30 = dayKeys.filter((k) => now - Date.parse(k) < 30 * DAY).reduce((a, k) => a + (days[k].commits || 0), 0);
  if (commits30 >= 100) ok('commits100', '100 commits in a month');
  const opusShare = S.food.parUnite.chevalier || 0;
  if (dayKeys.filter(active).length >= 7 && opusShare < 0.3 && empire.actives > 0) ok('econome:' + Math.floor(now / (7 * DAY)), 'Thrifty: a week with few Legates');
  const totals = dayKeys.reduce((a, k) => { a.commits += days[k].commits || 0; a.testsOk += days[k].testsOk || 0; return a; }, { commits: 0, testsOk: 0 });
  if (totals.commits >= 1000) ok('commits1000', 'A thousand commits: the Empire archives are overflowing');
  if (totals.testsOk >= 100) ok('tests100', 'A hundred green tests');
  if (S.villages.length >= 10) ok('dixvillages', 'Ten villages under your rule');
  if (S.monuments.length >= 1) ok('monument1', 'First monument at the Forum');
  if (S.monuments.length >= 5) ok('monument5', 'Five monuments: Rome is watching you');
  if (S.monuments.includes('temple')) ok('temple', 'The Temple of Jupiter towers over the Forum');
  if ((S.quests?.list || []).filter((q) => q.claimed).length >= 1 && !S.done['relanceur']) ok('relanceur', 'Reviver: a sleeping village lives again thanks to the Senate');
  if (S.villages.some((v) => v.level >= 3)) ok('urbs', 'First urbs');
  const wd = new Date(now).getDay();
  if (wd === 1 && !active(dayKey(now - DAY)) && !active(dayKey(now - 2 * DAY)) && dayKeys.filter(active).length >= 5) ok('repos:' + dayKey(now), 'Well-earned rest: a weekend without sessions');
  if (S.villages.some((v) => v.buildings.some((b) => b.working && b.ruin === false && S.wasIdle[v.id] === false)) && S.done['reprise_ruine']) {}

  S.log = S.villages.flatMap((v) => v.buildings.filter((b) => b.working).map((b) => `${b.model || 'claude'} · ${b.title}: ${b.state} (${v.name})`)).slice(0, 8);
  if (!S.log.length) S.log = ['All sessions are awaiting your orders'];
}
