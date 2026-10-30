// Chaîne de sync, côté Mac (docs/SYNC.md §5 et §6) : publie l'état chiffré sur le relais et applique les quelques
// commandes chiffrées envoyées par le téléphone. Le relais ne voit que des blobs opaques ; S ne quitte jamais le Mac
// autrement que par l'écran des réglages (QR, lien, 12 mots).
//
// Configuration dans <données>/config.json (écrit en 0600) :
//   { "sync": { "enabled": true, "relay": "https://aimpire.sidali.dev/", "secret": "<S en hex>" } }
// Variable : AIMPIRE_RELAIS (relais proposé par défaut à la création, sinon https://aimpire.sidali.dev/).

import crypto from 'node:crypto';
import { gzipSync } from 'node:zlib';
import {
  genererSecret, deriveId, deriveWriteToken, deriveKeys, encryptBlob, decryptJson, toWords, toLink, bourrerGzip, PALIER_BOURRAGE,
  RELAIS_PAR_DEFAUT,
} from './sync-crypto.js';
import { qrEnLignes } from './qr.js';

export const PERIODE_MS = 3000;              // envoi et lecture des commandes toutes les 3 s
export const BATTEMENT_MS = 60_000;          // état renvoyé au moins une fois par minute, même inchangé : son ts authentifié
                                             // est la seule preuve de fraîcheur que le téléphone accepte (§3)
export const ECART_MIN_MS = 10_000;          // deux publications dues à un changement d'état sont espacées d'au moins 10 s
export const REESSAI_401_MS = 10 * 60_000;   // jeton refusé par le relais : nouvel essai dans 10 min
export const VERSION_ENVELOPPE = 1;          // à incrémenter à chaque changement incompatible de l'état publié
export const FENETRE_CMD_MS = 10 * 60_000;   // une commande vieille (ou en avance) de plus de 10 min est refusée
export const MEMOIRE_NONCES_MS = 15 * 60_000;
const MAX_NONCES = 500;
const MAX_RESULTATS = 10;
const ATTENTES_RESEAU = [3, 6, 15, 30, 60];   // secondes, après des échecs réseau successifs
const RE_NONCE = /^[0-9a-f]{32}$/;
const RE_SECRET = /^[0-9a-f]{32}$/;

/** Relais accepté : https partout, http seulement en local (tests). Renvoie l'URL normalisée avec « / » final, ou null. */
export function relaisValide(texte) {
  let u;
  try { u = new URL(String(texte || '').trim()); } catch { return null; }
  const local = ['127.0.0.1', 'localhost', '[::1]'].includes(u.hostname);
  if (u.protocol !== 'https:' && !(u.protocol === 'http:' && local)) return null;
  if (u.username || u.password || u.search || u.hash) return null;
  return u.origin + (u.pathname.endsWith('/') ? u.pathname : u.pathname + '/');
}

/**
 * Empreinte qui décide d'un envoi : l'état sans ce qui bouge à chaque tour de scan (`tick`, `peak`, `ago` des bâtiments,
 * qui compte les secondes), les annexes sans horodatage (`digest.since`). Les résultats de commandes en font partie, pour que
 * le téléphone voie vite la réponse à ce qu'il a demandé.
 */
export function empreinteEtat(etatJson, annexes) {
  const e = JSON.parse(etatJson);
  delete e.tick;
  delete e.peak;   // pic de nourriture interne, recalculé (et décroissant) à chaque tour
  for (const v of e.villages || []) for (const b of v.buildings || []) delete b.ago;   // le battement de 60 s le rafraîchit
  const a = annexes ? { ...annexes, digest: annexes.digest ? { ...annexes.digest, since: 0 } : annexes.digest } : null;
  return crypto.createHash('sha256').update(JSON.stringify(e)).update('\n').update(JSON.stringify(a)).digest('hex');
}

/**
 * Crée le module de sync.
 * dep : {
 *   reglages()            objet config.json courant (lu et modifié en place),
 *   sauverReglages()      l'écrit sur disque,
 *   etatServi()           JSON de l'état tel que GET /state le sert (déjà flouté en mode discret), ou '' s'il n'est pas prêt,
 *   annexes()             { rapport, journal, digest } ou des null en mode discret,
 *   appliquer             { reclamer(village), construire(id), reglage(cle, val) } -> { ok, erreur },
 *   evenement(e)          ajoute un événement au journal du jeu,
 *   log                   { info, warn, error },
 *   maintenant()          horloge (tests),
 *   fetch                 fetch (tests),
 *   automatique           false pour ne lancer aucune minuterie (tests),
 *   intervallePutMs       écart minimal entre deux PUT (1100 ms, le relais en accepte un par seconde),
 * }
 */
export function creerSync(dep) {
  const maintenant = dep.maintenant || Date.now;
  const fetcher = dep.fetch || globalThis.fetch;
  const log = dep.log || { info() {}, warn() {}, error() {} };

  let chaine = null;        // { S, relay, id, W, cles, lien, mots, qr }
  let minuteur = null, enCours = false;
  let derniereEmpreinte = '', dernierEnvoi = 0, derniersOctets = 0, erreur = '', arretee = false;
  // Toute commande antérieure au démarrage de ce processus est refusée : les nonces ne vivent qu'en mémoire, et le serveur
  // redémarre avec le jeu. Une commande légitime perdue pendant le redémarrage donne seulement « Le Mac n'a pas répondu ».
  const demarrage = maintenant();
  let echecs = 0, reprendreA = 0, commandesRecues = 0;
  const resultats = [];               // 10 derniers résultats de commandes, servis dans annexes.commandes
  const nonces = new Map();           // nonce -> heure de réception

  function charger() {
    const c = dep.reglages().sync;
    if (!c || !c.enabled || !RE_SECRET.test(String(c.secret || '')) || !relaisValide(c.relay)) { chaine = null; return; }
    const relay = relaisValide(c.relay);
    chaine = { S: c.secret, relay, id: deriveId(c.secret), W: deriveWriteToken(c.secret), cles: deriveKeys(c.secret),
      lien: toLink(c.secret, relay), mots: toWords(c.secret) };
    chaine.qr = qrEnLignes(chaine.lien);
  }

  const url = (chemin) => new URL(chemin, chaine.relay).toString();
  const entetes = (avecJeton) => ({ 'X-AImpire-Id': chaine.id, ...(avecJeton ? { Authorization: 'Bearer ' + chaine.W } : {}) });

  function echecReseau(e) {
    echecs++;
    const s = ATTENTES_RESEAU[Math.min(echecs - 1, ATTENTES_RESEAU.length - 1)];
    reprendreA = maintenant() + s * 1000;
    erreur = `Relay unreachable (${e?.cause?.code || e?.name || 'network'}), retrying in ${s} s`;
    if (echecs === 1 || echecs % 10 === 0) log.warn('sync: relay unreachable', e?.message || e);
  }
  // 401 : le relais refuse le jeton (chaîne purgée puis revendiquée, ou relais qui ment). On réessaie de loin en loin plutôt
  // que d'arrêter pour toujours : un relais qui revient à la raison retrouve la chaîne sans intervention.
  function revendiquee() {
    reprendreA = maintenant() + REESSAI_401_MS;
    erreur = 'The relay refuses this chain token. Retrying in 10 min; if it keeps happening, delete the chain and create a new one.';
    if (!arretee) log.error('sync: 401 from the relay, retrying in 10 min');
    arretee = true;   // jusqu'au prochain essai
  }
  function attendreRelais(r) {
    const s = Math.min(300, Math.max(1, Number(r.headers.get('retry-after')) || 10));
    reprendreA = maintenant() + s * 1000;
  }

  function enveloppe(ts) {
    const etat = dep.etatServi();
    if (!etat) return null;
    const ann = dep.annexes() || { rapport: null, journal: null, digest: null };
    const annexes = { ...ann, commandes: resultats.slice() };
    return { etat, annexes, json: `{"type":"etat","v":${VERSION_ENVELOPPE},"ts":${ts},"etat":${etat},"annexes":${JSON.stringify(annexes)}}` };
  }

  async function publier(force = false) {
    const t = maintenant();
    const env = enveloppe(t);
    if (!env) return;
    const h = empreinteEtat(env.etat, env.annexes);
    if (!force && h === derniereEmpreinte && t - dernierEnvoi < BATTEMENT_MS) return;
    if (!force && h !== derniereEmpreinte && t - dernierEnvoi < (dep.ecartMinMs ?? ECART_MIN_MS)) return;   // repris au tour suivant
    // gzip bourré au palier de 16 Kio : le relais ne suit pas la taille exacte de l'état (§3)
    const blob = encryptBlob(chaine.cles, bourrerGzip(gzipSync(Buffer.from(env.json, 'utf8')), PALIER_BOURRAGE));
    const r = await fetcher(url('blob'), { method: 'PUT', headers: { ...entetes(true), 'Content-Type': 'application/octet-stream' }, body: blob, signal: AbortSignal.timeout(15000) });
    if (r.status === 200) {
      derniereEmpreinte = h; dernierEnvoi = t; derniersOctets = blob.length; echecs = 0; arretee = false;
      if (erreur) erreur = '';
    } else if (r.status === 401) revendiquee();
    else if (r.status === 413) { erreur = `State too large for the relay (${Math.round(blob.length / 1024)} KB)`; reprendreA = t + BATTEMENT_MS; }
    else if (r.status === 429) attendreRelais(r);
    else { erreur = `The relay answered ${r.status} to the upload`; reprendreA = t + 15000; }
    await r.body?.cancel?.().catch(() => {});
  }

  async function lireCommandes() {
    const r = await fetcher(url('cmd'), { headers: entetes(true), signal: AbortSignal.timeout(15000) });
    if (r.status === 404) { await r.body?.cancel?.().catch(() => {}); return; }   // rien encore publié sur ce relais
    if (r.status === 401) { await r.body?.cancel?.().catch(() => {}); return revendiquee(); }
    if (r.status === 429) { await r.body?.cancel?.().catch(() => {}); return attendreRelais(r); }
    if (r.status !== 200) { await r.body?.cancel?.().catch(() => {}); return; }
    const { cmds } = await r.json();
    let appliquee = false;
    for (const b64 of Array.isArray(cmds) ? cmds : []) if (traiterCommande(String(b64))) appliquee = true;
    if (appliquee) {   // le téléphone voit le résultat sans attendre le tour suivant (le relais accepte 1 PUT par seconde)
      const reste = dernierEnvoi + (dep.intervallePutMs ?? 1100) - maintenant();
      if (reste > 0) await new Promise((r) => setTimeout(r, reste));
      await publier(true);
    }
  }

  /** Valide et applique une commande (§6). Renvoie true si un résultat a été consigné. */
  function traiterCommande(b64) {
    let c;
    try { c = decryptJson(chaine.cles, Buffer.from(b64, 'base64')); }
    catch { log.warn('sync: command rejected (mac or format), ignored'); return false; }
    const t = maintenant();
    for (const [n, tn] of nonces) if (t - tn > MEMOIRE_NONCES_MS) nonces.delete(n);
    const nonce = c && typeof c.nonce === 'string' ? c.nonce : '';
    if (RE_NONCE.test(nonce) && nonces.has(nonce)) { log.warn('sync: replayed command, ignored'); return false; }
    const consigner = (ok, err, texte) => {
      resultats.push({ nonce: RE_NONCE.test(nonce) ? nonce : '', ok, erreur: err || '', t });
      if (resultats.length > MAX_RESULTATS) resultats.splice(0, resultats.length - MAX_RESULTATS);
      commandesRecues++;
      if (ok) dep.evenement({ type: 'telephone', text: texte });
      else log.warn('sync: command refused:', err);
      return true;
    };
    if (!c || typeof c !== 'object' || c.type !== 'cmd') return consigner(false, 'unexpected message type');
    if (!Number.isFinite(c.ts) || Math.abs(t - c.ts) > FENETRE_CMD_MS) return consigner(false, 'expired command (check the time on the phone and the Mac)');
    if (!RE_NONCE.test(nonce)) return consigner(false, 'invalid nonce');
    if (c.ts < demarrage) return consigner(false, 'command sent before AImpire started on the Mac, send it again');
    nonces.set(nonce, t);
    while (nonces.size > MAX_NONCES) nonces.delete(nonces.keys().next().value);
    const champ = (k) => (typeof c[k] === 'string' && c[k].length <= 200 ? c[k] : '');
    let r;
    switch (c.action) {
      case 'reclamer':
        if (!champ('village')) return consigner(false, 'missing village');
        r = dep.appliquer.reclamer(champ('village'));
        return consigner(r.ok, r.erreur, 'From the phone: reward claimed');
      case 'construire':
        if (!champ('id')) return consigner(false, 'missing monument');
        r = dep.appliquer.construire(champ('id'));
        return consigner(r.ok, r.erreur, 'From the phone: construction started');
      case 'reglage': {
        if (champ('cle') !== 'privacy' || !['normal', 'flou'].includes(champ('val'))) return consigner(false, 'unknown setting');
        // Un réglage plus ancien que le dernier appliqué (relais qui réordonne, ou choix fait depuis sur le Mac) est refusé.
        const sc = dep.reglages().sync;
        if (sc && c.ts <= (Number(sc.dernierReglage) || 0)) return consigner(false, 'a newer setting has already been applied');
        r = dep.appliquer.reglage('privacy', champ('val'));
        if (r.ok && sc) { sc.dernierReglage = c.ts; dep.sauverReglages(); }
        return consigner(r.ok, r.erreur, champ('val') === 'flou' ? 'From the phone: discreet mode on' : 'From the phone: discreet mode off');
      }
      default:
        return consigner(false, 'action not allowed from the phone');
    }
  }

  async function tour() {
    if (!chaine || enCours || maintenant() < reprendreA) return;
    enCours = true;
    try {
      await publier();
      if (!arretee && maintenant() >= reprendreA) await lireCommandes();   // arretee : le PUT vient de prendre un 401
    } catch (e) {
      if (e?.name === 'SyntaxError') log.warn('sync: unreadable answer from the relay');
      else echecReseau(e);
    } finally { enCours = false; }
  }

  function demarrer() {
    arreter();
    charger();
    if (!chaine) return;
    arretee = false; echecs = 0; reprendreA = 0; erreur = ''; derniereEmpreinte = '';
    if (dep.automatique !== false) {   // les tests appellent tour() eux-mêmes
      minuteur = setInterval(tour, PERIODE_MS);
      minuteur.unref?.();
      setTimeout(tour, 50).unref?.();
    }
    log.info(`sync active to ${chaine.relay} (chain ${chaine.id.slice(0, 6)})`);
  }
  function arreter() { if (minuteur) clearInterval(minuteur); minuteur = null; }

  /** Réponse de GET /sync. `masquer` (mode discret) : ni lien, ni mots, ni QR, pour qu'un partage d'écran ne montre jamais S. */
  function etat({ masquer = false } = {}) {
    if (!chaine) return { enabled: false };
    const secret = masquer ? { masque: true } : { lien: chaine.lien, mots: chaine.mots, qr: { taille: chaine.qr.taille, modules: chaine.qr.modules } };
    return { enabled: true, relay: chaine.relay, id_court: chaine.id.slice(0, 6), ...secret, dernier_envoi: dernierEnvoi,
      octets: derniersOctets, erreur, commandes: commandesRecues };
  }

  /** Le mode discret vient d'être changé sur le Mac : une commande du téléphone plus ancienne ne l'annulera pas. */
  function reglageLocal() {
    const sc = dep.reglages().sync;
    if (!sc) return;
    sc.dernierReglage = Math.max(Number(sc.dernierReglage) || 0, maintenant());
    dep.sauverReglages();
  }

  /** POST /sync?action=creer : tire S, l'enregistre et démarre. Renvoie { code, corps }. */
  function creer(relaisDemande, { masquer = false } = {}) {
    if (chaine) return { code: 409, corps: { ok: false, error: 'a chain already exists' } };
    const relay = relaisValide(relaisDemande || process.env.AIMPIRE_RELAIS || RELAIS_PAR_DEFAUT);
    if (!relay) return { code: 400, corps: { ok: false, error: 'invalid relay (https, or http on a local network)' } };
    dep.reglages().sync = { enabled: true, relay, secret: genererSecret().toString('hex') };
    dep.sauverReglages();
    resultats.length = 0; nonces.clear(); commandesRecues = 0; dernierEnvoi = 0; derniersOctets = 0;
    demarrer();
    return { code: 200, corps: etat({ masquer }) };
  }

  /** POST /sync?action=supprimer : efface le blob sur le relais (au mieux), oublie S. */
  async function supprimer() {
    const avant = chaine;
    arreter();
    chaine = null;
    delete dep.reglages().sync;
    dep.sauverReglages();
    let relais = 'no chain';
    if (avant) {
      try {
        const r = await fetcher(new URL('blob', avant.relay).toString(), { method: 'DELETE',
          headers: { 'X-AImpire-Id': avant.id, Authorization: 'Bearer ' + avant.W }, signal: AbortSignal.timeout(5000) });
        relais = r.status === 200 ? 'erased from the relay' : `relay: ${r.status}`;
        await r.body?.cancel?.().catch(() => {});
      } catch { relais = 'relay unreachable, the blob will expire there in 30 days'; }
      log.info(`sync: chain ${avant.id.slice(0, 6)} deleted (${relais})`);
    }
    resultats.length = 0; nonces.clear(); commandesRecues = 0; dernierEnvoi = 0; derniersOctets = 0; erreur = ''; arretee = false;
    return { ok: true, relais };
  }

  demarrer();
  return { etat, creer, supprimer, tour, traiterCommande, arreter, reglageLocal, get chaine() { return chaine; } };
}
