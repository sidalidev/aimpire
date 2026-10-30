#!/usr/bin/env node
// Faux relais pour essayer le mode téléphone sans le vrai relais ni daemon/sync.js (docs/SYNC.md §4 et §7).
// Il joue à la fois le relais et le Mac : il lit l'état d'un serveur AImpire local, le chiffre avec la chaîne de test,
// le sert en long-poll (GET /blob, ETag, If-None-Match, X-AImpire-Maj), puis déchiffre les commandes reçues par POST /cmd,
// les applique sur ce serveur local (mêmes routes que le jeu sur le Mac) et renvoie le résultat dans annexes.commandes.
//
//   node tools/faux-relais.mjs [--port 8787] [--hote 127.0.0.1] [--serveur http://127.0.0.1:7781]
//                              [--donnees <dossier du serveur, pour son jeton>] [--secret <hex>] [--etat <fichier JSON>]
//                              [--discret]
//
// Sans --secret : S = 000102…0f, la chaîne des vecteurs (docs/SYNC-VECTEURS.json), dont les 12 mots sont
// « abandon amount liar amount expire adjust cage candy arch gather drum buyer ».
// Avec --etat : sert ce fichier (un état /state enregistré) au lieu d'interroger un serveur, sans commandes. Le fichier
// peut aussi contenir { "etat": …, "annexes": … } (rapport, journal et digest servis avec l'état, comme le Mac) et
// "temps_relatifs": true : les heures (since, last, t, retourA) négatives ou nulles y sont des écarts en ms par rapport
// au moment où l'état est servi (godot/tests/etat-demo.json, Empire inventé pour les captures).
// Outil d'essai : il connaît S, ce que le vrai relais ne fait jamais.

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { deriveId, deriveKeys, encryptJson, decryptJson, estBlobBienForme, toWords, toLink } from '../daemon/sync-crypto.js';

const ici = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const opt = (nom, defaut) => { const i = args.indexOf('--' + nom); return i >= 0 ? args[i + 1] : defaut; };
const drapeau = (nom) => args.includes('--' + nom);

const vecteurs = JSON.parse(fs.readFileSync(path.join(ici, '..', 'docs', 'SYNC-VECTEURS.json'), 'utf8'));
const SECRET = Buffer.from(opt('secret', vecteurs.secret_hex), 'hex');
const ID = deriveId(SECRET);
const CLES = deriveKeys(SECRET);
const PORT = Number(opt('port', 8787));
const HOTE = opt('hote', '127.0.0.1');
const SERVEUR = opt('serveur', 'http://127.0.0.1:7781');
const DONNEES = opt('donnees', '');
const FICHIER_ETAT = opt('etat', '');
const DISCRET = drapeau('discret');
const JETON = DONNEES ? fs.readFileSync(path.join(DONNEES, 'token'), 'utf8').trim() : '';

let blob = null, etag = '', maj = 0, dernierHash = '', dernierEnvoi = 0;
const attentes = new Set();         // réponses en long-poll : { res, minuteur }
const resultats = [];               // annexes.commandes (10 dernières)
const noncesVus = new Map();        // nonce -> heure

const journal = (...m) => console.log(new Date().toISOString().slice(11, 19), ...m);

async function lire(route, options = {}) {
  const r = await fetch(SERVEUR + route, { ...options, headers: { ...(JETON ? { Authorization: 'Bearer ' + JETON } : {}), ...(options.headers || {}) } });
  if (!r.ok) throw new Error(`${route} : ${r.status}`);
  return r.json();
}

// Heures relatives (ms, négatives) d'un état de démonstration rendues absolues au moment où il est servi.
const CLES_HEURE = new Set(['since', 'last', 't', 'retourA']);
function heuresAbsolues(o, maintenant) {
  if (Array.isArray(o)) return o.map((x) => heuresAbsolues(x, maintenant));
  if (!o || typeof o !== 'object') return o;
  const r = {};
  for (const [k, v] of Object.entries(o)) r[k] = CLES_HEURE.has(k) && typeof v === 'number' && v <= 0 ? maintenant + v : heuresAbsolues(v, maintenant);
  return r;
}

// Enveloppe d'état (§3) : état servi, annexes (rapport, journal, digest), résultats des commandes.
async function construireEnveloppe() {
  let etat, annexes;
  if (FICHIER_ETAT) {
    let lu = JSON.parse(fs.readFileSync(FICHIER_ETAT, 'utf8'));
    if (lu.temps_relatifs) lu = heuresAbsolues(lu, Date.now() - (Date.now() % 60000));   // stable sur une minute
    if (lu.etat && typeof lu.etat === 'object') {
      etat = lu.etat;
      annexes = { rapport: null, journal: null, digest: null, ...(lu.annexes || {}) };
    } else {
      etat = lu;
      annexes = { rapport: null, journal: null, digest: null };
    }
  } else {
    etat = await lire('/state');
    if (DISCRET || etat.privacy === 'flou' || !JETON) {
      annexes = { rapport: null, journal: null, digest: null };
    } else {
      const [jour, semaine, j, digest] = await Promise.all([
        lire('/rapport?periode=jour'), lire('/rapport?periode=semaine'), lire('/journal'), lire('/digest'),
      ]);
      annexes = { rapport: { jour: jour.texte, semaine: semaine.texte }, journal: (j.entrees || []).slice(-60), digest };
    }
  }
  annexes.commandes = resultats.slice(-10);
  return { type: 'etat', v: 1, ts: Date.now(), etat, annexes };
}

// Toutes les 3 s : nouveau blob si l'état a changé (sans « tick »), ou au moins une fois par minute.
async function publier() {
  try {
    const env = await construireEnveloppe();
    const { tick, ...sansTick } = env.etat;
    const h = crypto.createHash('sha256').update(JSON.stringify([sansTick, env.annexes])).digest('hex');
    if (h !== dernierHash || Date.now() - dernierEnvoi > 60_000) {
      blob = encryptJson(CLES, env, { gzip: true });
      etag = '"' + crypto.createHash('sha256').update(blob).digest('hex').slice(0, 32) + '"';
      maj = Date.now();
      dernierHash = h; dernierEnvoi = maj;
      journal(`état publié : ${blob.length} octets, ${(env.etat.villages || []).length} villages, etag ${etag}`);
      for (const a of attentes) { clearTimeout(a.minuteur); servirBlob(a.res); }
      attentes.clear();
    }
  } catch (e) {
    journal('lecture de l\'état impossible :', e.message);
  }
  setTimeout(publier, 3000);
}

function servirBlob(res) {
  res.writeHead(200, { 'Content-Type': 'application/octet-stream', ETag: etag, 'X-AImpire-Maj': String(maj), 'Cache-Control': 'no-store' });
  res.end(blob);
}

const envoyer = (res, code, obj) => { res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); res.end(JSON.stringify(obj)); };

// Une commande du téléphone, comme le ferait daemon/sync.js (§6) : mac, type, fenêtre de 10 min, nonce neuf, action connue.
async function appliquer(corps) {
  let cmd;
  try { cmd = decryptJson(CLES, corps); } catch (e) { journal('commande jetée (mac ou format) :', e.message); return; }
  const r = { nonce: String(cmd.nonce || ''), ok: false, erreur: '', t: Date.now() };
  const routes = {
    reclamer: () => `/reclamer?village=${encodeURIComponent(cmd.village)}`,
    construire: () => `/construire?id=${encodeURIComponent(cmd.id)}`,
    reglage: () => (cmd.cle === 'privacy' && ['normal', 'flou'].includes(cmd.val) ? `/reglage?cle=privacy&val=${cmd.val}` : null),
  };
  if (cmd.type !== 'cmd') r.erreur = 'unexpected type';
  else if (Math.abs(Date.now() - Number(cmd.ts)) > 10 * 60_000) r.erreur = 'command too old';
  else if (!/^[0-9a-f]{32}$/.test(r.nonce) || noncesVus.has(r.nonce)) r.erreur = 'invalid or replayed nonce';
  else if (!routes[cmd.action] || !routes[cmd.action]()) r.erreur = 'unknown action';
  else if (FICHIER_ETAT || !JETON) r.erreur = 'test relay without a server, not applied';
  else {
    noncesVus.set(r.nonce, Date.now());
    try { await lire(routes[cmd.action](), { method: 'POST' }); r.ok = true; } catch (e) { r.erreur = e.message; }
  }
  journal('commande reçue :', JSON.stringify(cmd), '=>', r.ok ? 'appliquée' : r.erreur);
  resultats.push(r);
  if (resultats.length > 10) resultats.shift();
  dernierHash = '';   // republier tout de suite avec le résultat
}

const serveur = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  const id = req.headers['x-aimpire-id'];
  const debut = Date.now();
  res.on('finish', () => journal(req.method, url.pathname + url.search, res.statusCode, `${Date.now() - debut} ms`, id ? id.slice(0, 6) + '…' : ''));
  if (url.pathname === '/health') return envoyer(res, 200, { ok: true, faux: true, ids: 1 });
  if (!/^[0-9a-f]{32}$/.test(id || '')) return envoyer(res, 400, { error: 'X-AImpire-Id manquant ou mal formé' });
  if (id !== ID || !blob) return envoyer(res, 404, { error: 'id inconnu' });
  if (req.method === 'GET' && url.pathname === '/blob') {
    const attente = Math.min(Number(url.searchParams.get('wait') || 0), 25);
    if (req.headers['if-none-match'] !== etag) return servirBlob(res);
    if (!attente) { res.writeHead(304, { ETag: etag, 'X-AImpire-Maj': String(maj) }); return res.end(); }
    const a = { res, minuteur: setTimeout(() => { attentes.delete(a); res.writeHead(304, { ETag: etag, 'X-AImpire-Maj': String(maj) }); res.end(); }, attente * 1000) };
    attentes.add(a);
    req.on('close', () => { clearTimeout(a.minuteur); attentes.delete(a); });
    return;
  }
  if (req.method === 'POST' && url.pathname === '/cmd') {
    const morceaux = [];
    let taille = 0;
    req.on('data', (c) => { taille += c.length; if (taille <= 4096) morceaux.push(c); });
    req.on('end', () => {
      const corps = Buffer.concat(morceaux);
      if (taille > 4096) return envoyer(res, 413, { error: 'trop gros' });
      if (!estBlobBienForme(corps)) return envoyer(res, 400, { error: 'blob mal formé' });
      envoyer(res, 202, { ok: true });
      appliquer(corps);
    });
    return;
  }
  envoyer(res, 404, { error: 'not found' });
});

serveur.listen(PORT, HOTE, () => {
  journal(`faux relais sur http://${HOTE}:${PORT}/  chaîne ${ID.slice(0, 6)}  état ${FICHIER_ETAT || SERVEUR}`);
  journal(`lien : ${toLink(SECRET, `http://${HOTE}:${PORT}/`)}`);
  journal(`mots : ${toWords(SECRET).join(' ')}`);
  publier();
});
