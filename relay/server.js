// Relais de sync AImpire (voir docs/SYNC.md, section 4).
//
// Rôle : garder, pour chaque chaîne, le dernier état chiffré publié par le Mac et une petite file de commandes
// chiffrées envoyées par le téléphone. Le relais ne connaît que des ids, des empreintes de jeton d'écriture et des
// blobs opaques : il ne peut ni lire ni fabriquer un état ou une commande (AES-256-CBC + HMAC-SHA256 côté clients).
//
// Routes :
//   PUT    /blob          écrit le blob de la chaîne (X-AImpire-Id, Authorization: Bearer <W>)
//   GET    /blob[?wait=]  lit le blob, ETag et If-None-Match, attente longue jusqu'à 25 s
//   DELETE /blob          efface la chaîne (blob, file, fichier)
//   POST   /cmd           ajoute une commande chiffrée à la file (X-AImpire-Id seulement)
//   GET    /cmd           vide la file (X-AImpire-Id, Authorization)
//   GET    /health        { ok, version, ids, uptime }
//   GET    /update.json   manifeste de mise à jour des apps (fichier update.json du dossier des versions)
//   GET    /download/<f>  fichier publié : AImpire-<x.y.z>-macos.zip ou aimpire-<x.y.z>.apk, rien d'autre
//   GET    /              page statique d'explication, sans script
//
// Variables : PORT (7701), AIMPIRE_RELAY_DATA (dossier des fichiers, sinon mémoire seulement),
// AIMPIRE_RELEASES_DIR (dossier des versions publiées, monté en lecture seule ; sans lui, /update.json et /download/ sont en 404),
// AIMPIRE_TRUST_PROXY (1 derrière Traefik : l'IP vient du dernier saut de X-Forwarded-For), HOST (0.0.0.0).
// Node 22, aucune dépendance.

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { isIP } from 'node:net';
import { createHash, timingSafeEqual } from 'node:crypto';
import { pathToFileURL } from 'node:url';

export const VERSION = '0.6.0';

const MINUTE = 60_000;
const JOUR = 24 * 60 * MINUTE;

/** Limites par défaut (docs/SYNC.md §4). Les tests en passent de plus petites. */
export const LIMITES = {
  maxBlob: 256 * 1024,           // PUT /blob : 256 Kio (un état mesuré fait 21 Ko gzippé, 32 Ko une fois bourré)
  maxCmd: 4 * 1024,              // POST /cmd : 4 Kio
  fileCmds: 20,                  // commandes en attente par id
  maxIds: 500,                   // chaînes au total (au-delà : 507)
  attentesParId: 4,              // long-polls simultanés par id
  attentesTotal: 200,            // long-polls simultanés au total
  attenteMaxS: 25,               // durée maximale d'un long-poll
  requetesParIp: 600, fenetreIpMs: 5 * MINUTE,
  putParIdMs: 1000,              // 1 PUT /blob par seconde et par id
  cmdParIp: 30, fenetreCmdMs: MINUTE,
  nouveauxIdsParIp: 10, fenetreNouveauxMs: JOUR,   // par IPv4, ou par /48 en IPv6 (un /64 ne coûte rien à un attaquant)
  nouveauxIdsTotal: 100,         // nouvelles chaînes par jour, toutes IP confondues
  purgeMs: 30 * JOUR,            // chaîne sans PUT depuis 30 jours : effacée
};

const RE_ID = /^[0-9a-f]{32}$/;
const RE_JETON = /^Bearer ([0-9a-f]{64})$/;
const RE_FICHIER = /^([0-9a-f]{32})\.json$/;
// Fichiers téléchargeables : deux formes exactes, version x.y.z en chiffres (pas de « .. », de « / » ni de « % » possibles).
const RE_TELECHARGEMENT = /^(?:AImpire-\d{1,4}\.\d{1,4}\.\d{1,4}-macos\.zip|aimpire-\d{1,4}\.\d{1,4}\.\d{1,4}\.apk)$/;
const TYPES_TELECHARGEMENT = { '.zip': 'application/zip', '.apk': 'application/vnd.android.package-archive' };
const MAX_MANIFESTE = 64 * 1024;

/** Nom de fichier téléchargeable accepté par GET /download/<nom> (forme stricte, voir RE_TELECHARGEMENT). */
export const nomTelechargementValide = (nom) => typeof nom === 'string' && RE_TELECHARGEMENT.test(nom);

// Forme d'un blob (docs/SYNC.md §3), contrôlable sans clé : version 1, au moins 65 octets, chiffré multiple de 16.
// Recopiée de daemon/sync-crypto.js (estBlobBienForme) pour que l'image du relais reste autonome.
export function blobBienForme(b) {
  return b.length >= 65 && b[0] === 1 && (b.length - 49) % 16 === 0;
}

const empreinte = (W) => createHash('sha256').update(W, 'utf8').digest('hex');
// id = hex(SHA-256("aimpire-id" ‖ W))[0:32] (docs/SYNC.md §2), recopié de daemon/sync-crypto.js (idDuJeton) : à la première
// écriture, le relais vérifie que l'id appartient bien au W présenté. Connaître un id ne suffit donc pas à le revendiquer.
export const idDuJeton = (W) => createHash('sha256').update('aimpire-id', 'utf8').update(W, 'utf8').digest('hex').slice(0, 32);
const etagDe = (blob) => '"' + createHash('sha256').update(blob).digest('hex').slice(0, 32) + '"';

/** Clé d'IP pour les limites : IPv4 telle quelle (y compris ::ffff:a.b.c.d), IPv6 réduite à son préfixe (/64 par défaut). */
export function cleIp(ip, groupesPrefixe = 4) {
  const brut = String(ip || '').trim();
  if (brut.startsWith('::ffff:') && isIP(brut.slice(7)) === 4) return brut.slice(7);
  if (isIP(brut) !== 6) return brut || 'inconnue';
  const [tete, queue = ''] = brut.split('::');
  const a = tete ? tete.split(':') : [];
  const b = queue ? queue.split(':') : [];
  const groupes = brut.includes('::') ? [...a, ...Array(8 - a.length - b.length).fill('0'), ...b] : a;
  return groupes.slice(0, groupesPrefixe).map((g) => g.toLowerCase().replace(/^0+(?=.)/, '')).join(':') + '::/' + groupesPrefixe * 16;
}

/** Fenêtre glissante en mémoire : au plus `max` évènements par clé sur `ms` millisecondes. */
class Fenetre {
  constructor(max, ms) { this.max = max; this.ms = ms; this.t = new Map(); }
  _liste(cle, maintenant) {
    const l = (this.t.get(cle) || []).filter((x) => maintenant - x < this.ms);
    if (l.length) this.t.set(cle, l); else this.t.delete(cle);
    return l;
  }
  /** Secondes à attendre si la limite est atteinte, sinon 0. N'enregistre rien. */
  attente(cle, maintenant) {
    const l = this._liste(cle, maintenant);
    return l.length < this.max ? 0 : Math.max(1, Math.ceil((l[0] + this.ms - maintenant) / 1000));
  }
  noter(cle, maintenant) { const l = this.t.get(cle) || []; l.push(maintenant); this.t.set(cle, l); }
  /** Vérifie et enregistre en une fois. Renvoie 0 si accepté, sinon les secondes à attendre. */
  essayer(cle, maintenant) { const s = this.attente(cle, maintenant); if (!s) this.noter(cle, maintenant); return s; }
  nettoyer(maintenant) { for (const cle of [...this.t.keys()]) this._liste(cle, maintenant); }
}

/** Écriture atomique : fichier temporaire, fsync, renommage. */
function ecrireAtomique(f, data) {
  const tmp = f + '.tmp';
  const fd = fs.openSync(tmp, 'w', 0o600);
  try { fs.writeSync(fd, data); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
  fs.renameSync(tmp, f);
}

/** Lit le corps d'une requête sans dépasser `max` octets. */
function lireCorps(req, max) {
  return new Promise((resolve) => {
    const annonce = Number(req.headers['content-length']);
    if (Number.isFinite(annonce) && annonce > max) { req.resume(); return resolve({ trop: true }); }
    const morceaux = [];
    let total = 0, fini = false;
    const finir = (r) => { if (!fini) { fini = true; resolve(r); } };
    req.on('data', (c) => {
      if (fini) return;
      total += c.length;
      if (total > max) { morceaux.length = 0; req.resume(); return finir({ trop: true }); }
      morceaux.push(c);
    });
    req.on('end', () => finir({ corps: Buffer.concat(morceaux) }));
    req.on('error', () => finir({ erreur: true }));
    req.on('aborted', () => finir({ erreur: true }));
  });
}

const PAGE = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>AImpire relay</title>
<style>
body{margin:0;background:#2b1220;color:#f4efe4;font:17px/1.55 system-ui,sans-serif}
main{max-width:34rem;margin:0 auto;padding:2.5rem 1rem}
h1{color:#d4af37;font-weight:600;letter-spacing:.04em}
code{background:#3b1a2c;padding:.1rem .35rem;border-radius:4px}
.n{opacity:.7;font-size:.9rem}
</style></head><body><main>
<h1>AImpire</h1>
<p>This link pairs your phone with AImpire on your Mac. It opens in the app, not in the browser.</p>
<p>In the AImpire app on your phone, on the pairing screen: copy this link, then tap <b>Paste</b>.
You can also type the 12 words shown on the Mac.</p>
<p class="n">This relay only sees encrypted data. This page has no script and does not read the end of the link
(after the #), which stays in your browser.</p>
</main></body></html>
`;

/**
 * Crée le relais. Options : dossier (persistance, null = mémoire seulement), confianceProxy, limites (surcharge partielle),
 * maintenant (horloge, pour les tests), journal (fonction de log, console.log par défaut).
 */
export function creerRelais(options = {}) {
  const L = { ...LIMITES, ...(options.limites || {}) };
  const maintenant = options.maintenant || Date.now;
  const journal = options.journal || ((ligne) => console.log(ligne));
  const dossier = options.dossier || null;
  const versions = options.versions ? path.resolve(options.versions) : null;   // dossier des versions publiées (lecture seule)
  const demarre = maintenant();

  /** id -> { empreinte, blob, etag, maj, cmds: Buffer[], attentes: Set } */
  const chaines = new Map();
  let attentesTotal = 0;

  const parIp = new Fenetre(L.requetesParIp, L.fenetreIpMs);
  const putParId = new Fenetre(1, L.putParIdMs);
  const cmdParIp = new Fenetre(L.cmdParIp, L.fenetreCmdMs);
  const nouveauxParIp = new Fenetre(L.nouveauxIdsParIp, L.fenetreNouveauxMs);
  const nouveauxTotal = new Fenetre(L.nouveauxIdsTotal, L.fenetreNouveauxMs);

  // --- Persistance : un fichier par id, rechargé au démarrage ---
  const fichier = (id) => path.join(dossier, id + '.json');
  function sauver(id, c) {
    if (!dossier) return;
    try { ecrireAtomique(fichier(id), JSON.stringify({ empreinte: c.empreinte, maj: c.maj, blob: c.blob.toString('base64') })); }
    catch (e) { journal(`write error ${id.slice(0, 6)}…: ${e.message}`); }
  }
  function effacerFichier(id) {
    if (!dossier) return;
    try { fs.unlinkSync(fichier(id)); } catch {}
  }
  if (dossier) {
    fs.mkdirSync(dossier, { recursive: true });
    for (const nom of fs.readdirSync(dossier)) {
      const m = RE_FICHIER.exec(nom);
      if (!m) continue;
      try {
        const d = JSON.parse(fs.readFileSync(path.join(dossier, nom), 'utf8'));
        const blob = Buffer.from(String(d.blob || ''), 'base64');
        if (!/^[0-9a-f]{64}$/.test(d.empreinte) || !blobBienForme(blob)) continue;
        chaines.set(m[1], { empreinte: d.empreinte, blob, etag: etagDe(blob), maj: Number(d.maj) || 0, cmds: [], attentes: new Set() });
      } catch {}
    }
  }

  function purger() {
    const t = maintenant();
    for (const [id, c] of chaines) if (t - c.maj > L.purgeMs) supprimer(id, c);
    for (const f of [parIp, putParId, cmdParIp, nouveauxParIp, nouveauxTotal]) f.nettoyer(t);
  }
  purger();
  const minuterie = setInterval(purger, 3600_000);
  minuterie.unref();

  // --- Réponses ---
  const BASE = { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' };
  function json(res, code, obj, extra = {}) {
    if (res.headersSent || res.destroyed) return;
    res.writeHead(code, { ...BASE, 'Content-Type': 'application/json; charset=utf-8', ...extra });
    res.end(JSON.stringify(obj));
  }
  const trop = (res, s, quoi = 'too many requests') => json(res, 429, { error: quoi }, { 'Retry-After': String(s) });
  const tags = (c) => ({ ETag: c.etag, 'X-AImpire-Maj': String(c.maj) });
  function envoyerBlob(res, c) {
    if (res.headersSent || res.destroyed) return;
    res.writeHead(200, { ...BASE, ...tags(c), 'Content-Type': 'application/octet-stream', 'Content-Length': c.blob.length });
    res.end(c.blob);
  }
  function inchange(res, c) {
    if (res.headersSent || res.destroyed) return;
    res.writeHead(304, { ...BASE, ...tags(c) });
    res.end();
  }

  // --- Long-poll ---
  function liberer(c, a) {
    if (c.attentes.delete(a)) { attentesTotal--; clearTimeout(a.minuteur); }
  }
  function attendre(res, c, secondes) {
    if (c.attentes.size >= L.attentesParId || attentesTotal >= L.attentesTotal) return inchange(res, c);
    const a = { res, minuteur: null };
    a.minuteur = setTimeout(() => { liberer(c, a); inchange(res, c); }, secondes * 1000);
    c.attentes.add(a);
    attentesTotal++;
    res.on('close', () => liberer(c, a));
  }
  function reveiller(c, faire) {
    for (const a of [...c.attentes]) { liberer(c, a); faire(a.res); }
  }

  function supprimer(id, c) {
    chaines.delete(id);
    effacerFichier(id);
    reveiller(c, (res) => json(res, 404, { error: 'unknown chain' }));
  }

  /** Jeton d'écriture présenté : sa valeur si la forme est bonne, sinon null. */
  function jeton(req) {
    const m = RE_JETON.exec(String(req.headers.authorization || ''));
    return m ? m[1] : null;
  }
  function jetonValide(req, c) {
    const W = jeton(req);
    if (!W) return false;
    const a = Buffer.from(empreinte(W), 'hex'), b = Buffer.from(c.empreinte, 'hex');
    return a.length === b.length && timingSafeEqual(a, b);
  }

  /** Adresse du client (dernier saut de X-Forwarded-For derrière un proxy de confiance), brute. */
  function ipBrute(req) {
    if (options.confianceProxy) {
      const xff = req.headers['x-forwarded-for'];
      if (typeof xff === 'string' && xff.trim()) {
        const liste = xff.split(',').map((s) => s.trim()).filter(Boolean);
        if (liste.length) return liste[liste.length - 1];
      }
    }
    return req.socket.remoteAddress;
  }

  // --- Routes ---
  async function putBlob(req, res, id, ipNouveaux) {
    const c = chaines.get(id);
    const W = jeton(req);
    if (!W || (c && !jetonValide(req, c))) { req.resume(); return json(res, 401, { error: 'write token missing or wrong' }); }
    const s = putParId.attente(id, maintenant());
    if (s) { req.resume(); return trop(res, s); }
    const r = await lireCorps(req, L.maxBlob);
    if (r.trop) return json(res, 413, { error: 'blob too large' }, { Connection: 'close' });
    if (r.erreur) return;
    if (!blobBienForme(r.corps)) return json(res, 400, { error: 'malformed blob' });
    let cible = chaines.get(id);   // relu : une autre requête a pu créer ou effacer la chaîne pendant la lecture du corps
    if (cible && !jetonValide(req, cible)) return json(res, 401, { error: 'write token missing or wrong' });
    if (!cible) {
      if (idDuJeton(W) !== id) return json(res, 401, { error: 'write token missing or wrong' });   // id qui n'appartient pas à ce W
      if (chaines.size >= L.maxIds) return json(res, 507, { error: 'relay full' });
      const sn = nouveauxParIp.attente(ipNouveaux, maintenant()) || nouveauxTotal.attente('tous', maintenant());
      if (sn) return trop(res, sn, 'too many new chains');
      nouveauxParIp.noter(ipNouveaux, maintenant());
      nouveauxTotal.noter('tous', maintenant());
      cible = { empreinte: empreinte(W), blob: null, etag: '', maj: 0, cmds: [], attentes: new Set() };
      chaines.set(id, cible);
    }
    const sp = putParId.essayer(id, maintenant());
    if (sp) return trop(res, sp);
    cible.blob = r.corps;
    cible.etag = etagDe(r.corps);
    cible.maj = maintenant();
    sauver(id, cible);
    reveiller(cible, (attente) => envoyerBlob(attente, cible));
    json(res, 200, { ok: true, etag: cible.etag });
  }

  function getBlob(req, res, id, url) {
    const c = chaines.get(id);
    if (!c) return json(res, 404, { error: 'unknown chain' });
    const inm = req.headers['if-none-match'];
    if (inm !== c.etag) return envoyerBlob(res, c);
    const w = Math.min(L.attenteMaxS, Math.max(0, Math.floor(Number(url.searchParams.get('wait')) || 0)));
    if (!w) return inchange(res, c);
    attendre(res, c, w);
  }

  function deleteBlob(req, res, id) {
    const c = chaines.get(id);
    if (!c) return json(res, 404, { error: 'unknown chain' });
    if (!jetonValide(req, c)) return json(res, 401, { error: 'write token missing or wrong' });
    supprimer(id, c);
    json(res, 200, { ok: true });
  }

  async function postCmd(req, res, id, ip) {
    const c = chaines.get(id);
    if (!c) { req.resume(); return json(res, 404, { error: 'unknown chain' }); }
    const s = cmdParIp.essayer(ip, maintenant());
    if (s) { req.resume(); return trop(res, s); }
    const r = await lireCorps(req, L.maxCmd);
    if (r.trop) return json(res, 413, { error: 'command too large' }, { Connection: 'close' });
    if (r.erreur) return;
    if (!blobBienForme(r.corps)) return json(res, 400, { error: 'malformed command' });
    const cible = chaines.get(id);
    if (!cible) return json(res, 404, { error: 'unknown chain' });
    if (cible.cmds.length >= L.fileCmds) return trop(res, 5, 'command queue full');
    cible.cmds.push(r.corps);
    json(res, 202, { ok: true });
  }

  function getCmd(req, res, id) {
    const c = chaines.get(id);
    if (!c) return json(res, 404, { error: 'unknown chain' });
    if (!jetonValide(req, c)) return json(res, 401, { error: 'write token missing or wrong' });
    const cmds = c.cmds.map((b) => b.toString('base64'));
    c.cmds = [];
    json(res, 200, { cmds });
  }

  // --- Mises à jour : manifeste et fichiers publiés, lus à chaque requête dans le dossier des versions ---
  /** Fichier régulier du dossier des versions (pas de lien symbolique, pas de sortie du dossier), ou null. */
  function fichierPublie(nom) {
    if (!versions) return null;
    const f = path.join(versions, nom);
    if (path.dirname(f) !== versions) return null;
    try {
      const st = fs.lstatSync(f);
      return st.isFile() ? { f, taille: st.size, mtime: st.mtime } : null;
    } catch { return null; }
  }

  function manifeste(req, res) {
    const p = fichierPublie('update.json');
    if (!p || p.taille > MAX_MANIFESTE) return json(res, 404, { error: 'no published version' });
    let texte;
    try { texte = fs.readFileSync(p.f, 'utf8'); JSON.parse(texte); }
    catch { return json(res, 503, { error: 'unreadable manifest' }); }
    const corps = Buffer.from(texte, 'utf8');
    res.writeHead(200, { ...BASE, 'Cache-Control': 'no-cache', 'Content-Type': 'application/json; charset=utf-8',
      'Content-Length': corps.length, 'Last-Modified': p.mtime.toUTCString() });
    res.end(req.method === 'HEAD' ? undefined : corps);
  }

  function telecharger(req, res, nom) {
    if (!nomTelechargementValide(nom)) return json(res, 404, { error: 'not found' });
    const p = fichierPublie(nom);
    if (!p) return json(res, 404, { error: 'not found' });
    res.writeHead(200, { ...BASE, 'Cache-Control': 'public, max-age=3600', 'Content-Type': TYPES_TELECHARGEMENT[path.extname(nom)],
      'Content-Length': p.taille, 'Content-Disposition': `attachment; filename="${nom}"`, 'Last-Modified': p.mtime.toUTCString() });
    if (req.method === 'HEAD') return res.end();
    const flux = fs.createReadStream(p.f);
    flux.on('error', () => res.destroy());
    res.on('close', () => flux.destroy());
    flux.pipe(res);
  }

  async function traiter(req, res) {
    const debut = maintenant();
    let url;
    try { url = new URL(req.url, 'http://relais'); } catch { return json(res, 400, { error: 'invalid address' }); }
    const idBrut = String(req.headers['x-aimpire-id'] || '');
    res.on('finish', () => journal(`${req.method} ${url.pathname} ${res.statusCode} ${maintenant() - debut}ms ${idBrut ? idBrut.slice(0, 6) + '…' : '-'}`));

    if (req.method === 'GET' && url.pathname === '/health') {
      return json(res, 200, { ok: true, version: VERSION, ids: chaines.size, uptime: Math.round((maintenant() - demarre) / 1000) });
    }
    const brute = ipBrute(req);
    const ip = cleIp(brute);
    const s = parIp.essayer(ip, maintenant());
    if (s) { req.resume(); return trop(res, s); }

    if (req.method === 'GET' && url.pathname === '/') {
      res.writeHead(200, { ...BASE, 'Content-Type': 'text/html; charset=utf-8',
        'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'", 'Referrer-Policy': 'no-referrer' });
      return res.end(PAGE);
    }
    if (url.pathname === '/update.json' || url.pathname.startsWith('/download/')) {
      req.resume();
      if (req.method !== 'GET' && req.method !== 'HEAD') return json(res, 405, { error: 'method not allowed' }, { Allow: 'GET, HEAD' });
      return url.pathname === '/update.json' ? manifeste(req, res) : telecharger(req, res, url.pathname.slice('/download/'.length));
    }
    if (url.pathname !== '/blob' && url.pathname !== '/cmd') { req.resume(); return json(res, 404, { error: 'not found' }); }
    if (!RE_ID.test(idBrut)) { req.resume(); return json(res, 400, { error: 'invalid X-AImpire-Id' }); }
    const id = idBrut;
    const route = `${req.method} ${url.pathname}`;
    switch (route) {
      case 'PUT /blob': return putBlob(req, res, id, cleIp(brute, 3));
      case 'GET /blob': return getBlob(req, res, id, url);
      case 'DELETE /blob': return deleteBlob(req, res, id);
      case 'POST /cmd': return postCmd(req, res, id, ip);
      case 'GET /cmd': return getCmd(req, res, id);
      default: req.resume(); return json(res, 405, { error: 'method not allowed' });
    }
  }

  const server = http.createServer((req, res) => {
    traiter(req, res).catch((e) => { journal(`error: ${e.message}`); json(res, 500, { error: 'internal error' }); });
  });
  server.keepAliveTimeout = 30_000;   // au-dessus du long-poll de 25 s

  function fermer() {
    clearInterval(minuterie);
    for (const c of chaines.values()) reveiller(c, (res) => { if (!res.headersSent) { res.writeHead(503, BASE); res.end(); } });
    return new Promise((r) => { server.close(() => r()); server.closeAllConnections?.(); });
  }

  return { server, chaines, fermer, purger };
}

// --- Lancement direct : node relay/server.js ---
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const port = Number(process.env.PORT || 7701);
  const dossier = process.env.AIMPIRE_RELAY_DATA || null;
  const relais = creerRelais({ dossier, versions: process.env.AIMPIRE_RELEASES_DIR || null, confianceProxy: ['1', 'true', 'oui'].includes(String(process.env.AIMPIRE_TRUST_PROXY || '').toLowerCase()) });
  relais.server.listen(port, process.env.HOST || '0.0.0.0', () => {
    console.log(`AImpire relay v${VERSION} on port ${port}, ${dossier ? 'data in ' + dossier : 'in-memory storage only'}, releases ${process.env.AIMPIRE_RELEASES_DIR || 'not served'}, ${relais.chaines.size} chain(s) loaded`);
  });
  const arret = () => { relais.fermer().then(() => process.exit(0)); setTimeout(() => process.exit(0), 3000).unref(); };
  process.on('SIGTERM', arret);
  process.on('SIGINT', arret);
}
