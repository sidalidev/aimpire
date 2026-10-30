// Cryptographie de la chaîne de sync AImpire (voir docs/SYNC.md).
// Fonctions pures, sans état ni accès disque : utilisées par sync.js (Mac), par les tests et par le générateur de vecteurs.
// Tout repose sur node:crypto et node:zlib, aucune dépendance externe.
// Le client Godot (godot/sync_crypto.gd) implémente exactement la même chose ; docs/SYNC-VECTEURS.json fait foi entre les deux.

import {
  createHash,
  createHmac,
  createCipheriv,
  createDecipheriv,
  hkdfSync,
  randomBytes,
  timingSafeEqual,
} from 'node:crypto';
import { gzipSync, gunzipSync } from 'node:zlib';
import { MOTS } from './bip39-english.js';

/** Taille du secret S en octets (128 bits, comme 12 mots BIP39). */
export const TAILLE_SECRET = 16;

/** Relais de référence, utilisé par défaut pour les liens. */
export const RELAIS_PAR_DEFAUT = 'https://aimpire.sidali.dev/';

/** Premier octet de tout blob : version du format. */
export const VERSION_BLOB = 1;

/** Tailles fixes du format de blob : version (1) ‖ iv (16) ‖ chiffré (16 × n, n ≥ 1) ‖ mac (32). */
export const TAILLE_IV = 16;
export const TAILLE_MAC = 32;
export const TAILLE_MIN_BLOB = 1 + TAILLE_IV + 16 + TAILLE_MAC; // 65

/** Taille maximale d'un clair décompressé (protection contre les bombes gzip). */
export const MAX_CLAIR = 16 * 1024 * 1024;

const RE_HEX = /^[0-9a-f]*$/i;
const RE_ID = /^[0-9a-f]{32}$/;

// ---------------------------------------------------------------------------
// Outils internes
// ---------------------------------------------------------------------------

/** Normalise S : Buffer, Uint8Array ou chaîne hex de 32 caractères. Renvoie un Buffer neuf de 16 octets ou lève. */
function secret(S) {
  let octets;
  if (typeof S === 'string') {
    if (S.length !== TAILLE_SECRET * 2 || !RE_HEX.test(S)) throw new Error('Invalid secret: 32 hex characters expected');
    octets = Buffer.from(S, 'hex');
  } else if (S instanceof Uint8Array) {
    octets = Buffer.from(S);
  } else {
    throw new Error('Invalid secret: Buffer, Uint8Array or hex string expected');
  }
  if (octets.length !== TAILLE_SECRET) throw new Error(`Invalid secret: ${TAILLE_SECRET} bytes expected`);
  return octets;
}

/** HKDF-SHA256 (RFC 5869), sel vide (donc 32 octets nuls), info en UTF-8. */
function hkdf(S, info, longueur) {
  return Buffer.from(hkdfSync('sha256', S, Buffer.alloc(0), Buffer.from(info, 'utf8'), longueur));
}

/** Accepte soit les clés { enc, mac } déjà dérivées, soit S. */
function cles(clesOuSecret) {
  if (clesOuSecret && !(clesOuSecret instanceof Uint8Array) && typeof clesOuSecret === 'object' && clesOuSecret.enc && clesOuSecret.mac) {
    const enc = Buffer.from(clesOuSecret.enc), mac = Buffer.from(clesOuSecret.mac);
    if (enc.length !== 32 || mac.length !== 32) throw new Error('Invalid keys: 32 bytes expected for enc and mac');
    return { enc, mac };
  }
  return deriveKeys(clesOuSecret);
}

/** Octets d'un clair : Buffer et Uint8Array tels quels, chaîne en UTF-8, autre valeur en JSON compact. */
function octetsDe(clair) {
  if (clair instanceof Uint8Array) return Buffer.from(clair);
  if (typeof clair === 'string') return Buffer.from(clair, 'utf8');
  return Buffer.from(JSON.stringify(clair), 'utf8');
}

// ---------------------------------------------------------------------------
// Secret, identifiant et clés
// ---------------------------------------------------------------------------

/** Tire un nouveau secret S de 16 octets (aléa cryptographique). */
export function genererSecret() {
  return randomBytes(TAILLE_SECRET);
}

/** Jeton d'écriture W = hex(HKDF(S, "aimpire-write", 32)), 64 caractères. Envoyé en « Authorization: Bearer W ». */
export function deriveWriteToken(S) {
  return hkdf(secret(S), 'aimpire-write', 32).toString('hex');
}

/**
 * id = hex(SHA-256("aimpire-id" ‖ W en ASCII))[0:32]. Seule chose qui identifie la chaîne auprès du relais.
 * Dérivé de W pour que le relais puisse vérifier, à la première écriture, que celui qui revendique l'id connaît W
 * (donc S) : connaître l'id ne suffit pas à le revendiquer, même après une purge.
 */
export function idDuJeton(W) {
  return createHash('sha256').update(Buffer.from('aimpire-id', 'utf8')).update(String(W), 'utf8').digest('hex').slice(0, 32);
}

export function deriveId(S) {
  return idDuJeton(deriveWriteToken(S));
}

/** Empreinte de W gardée par le relais : hex(SHA-256(W en ASCII)). */
export function empreinteJeton(W) {
  return createHash('sha256').update(String(W), 'utf8').digest('hex');
}

/** K_enc = HKDF(S, "aimpire-enc", 32) et K_mac = HKDF(S, "aimpire-mac", 32). */
export function deriveKeys(S) {
  const s = secret(S);
  return { enc: hkdf(s, 'aimpire-enc', 32), mac: hkdf(s, 'aimpire-mac', 32) };
}

/** Vérifie qu'une chaîne a la forme d'un id (32 caractères hex minuscules). */
export function estIdValide(id) {
  return typeof id === 'string' && RE_ID.test(id);
}

// ---------------------------------------------------------------------------
// Blobs chiffrés : AES-256-CBC + PKCS7, puis HMAC-SHA256 (chiffrer puis authentifier)
// ---------------------------------------------------------------------------

/**
 * Vérifie la forme d'un blob sans clé (ce que le relais peut contrôler) :
 * version 1, longueur ≥ 65, chiffré multiple de 16.
 */
export function estBlobBienForme(blob) {
  return blob instanceof Uint8Array
    && blob.length >= TAILLE_MIN_BLOB
    && blob[0] === VERSION_BLOB
    && (blob.length - 1 - TAILLE_IV - TAILLE_MAC) % 16 === 0;
}

/**
 * Chiffre des octets : blob = 0x01 ‖ iv ‖ AES-256-CBC(K_enc, iv, PKCS7(clair)) ‖ HMAC-SHA256(K_mac, iv ‖ chiffré).
 * clesOuSecret : { enc, mac } ou S. clair : Buffer, Uint8Array, chaîne (UTF-8) ou objet (JSON compact).
 * iv : 16 octets (Buffer ou hex) ; tiré au hasard s'il est absent. À ne jamais réutiliser en dehors des vecteurs de test.
 */
export function encryptBlob(clesOuSecret, clair, iv = randomBytes(TAILLE_IV)) {
  const { enc, mac } = cles(clesOuSecret);
  const v = typeof iv === 'string' ? Buffer.from(iv, 'hex') : Buffer.from(iv);
  if (v.length !== TAILLE_IV) throw new Error('Invalid iv: 16 bytes expected');
  const chiffreur = createCipheriv('aes-256-cbc', enc, v); // PKCS7 activé par défaut
  const chiffre = Buffer.concat([chiffreur.update(octetsDe(clair)), chiffreur.final()]);
  const etiquette = createHmac('sha256', mac).update(v).update(chiffre).digest();
  return Buffer.concat([Buffer.from([VERSION_BLOB]), v, chiffre, etiquette]);
}

/**
 * Déchiffre un blob et renvoie le clair (Buffer). Le mac est vérifié en temps constant AVANT tout déchiffrement.
 * Lève une erreur si le format, le mac ou le remplissage ne conviennent pas.
 */
export function decryptBlob(clesOuSecret, blob) {
  const b = blob instanceof Uint8Array ? Buffer.from(blob) : null;
  if (!b || !estBlobBienForme(b)) throw new Error('Invalid blob: unknown format or version');
  const { enc, mac } = cles(clesOuSecret);
  const iv = b.subarray(1, 1 + TAILLE_IV);
  const chiffre = b.subarray(1 + TAILLE_IV, b.length - TAILLE_MAC);
  const recu = b.subarray(b.length - TAILLE_MAC);
  const attendu = createHmac('sha256', mac).update(iv).update(chiffre).digest();
  if (!timingSafeEqual(attendu, recu)) throw new Error('Blob refused: wrong mac');
  const dechiffreur = createDecipheriv('aes-256-cbc', enc, iv);
  try {
    return Buffer.concat([dechiffreur.update(chiffre), dechiffreur.final()]);
  } catch {
    throw new Error('Blob refused: wrong padding');
  }
}

/**
 * gzip dont l'en-tête ne dépend pas de la machine : zlib écrit l'OS dans l'octet 9 (0x13 sur macOS, 0x03 sur Linux),
 * ce qui changeait les blobs et les vecteurs de test selon la machine. On le fixe à 0x03 (Unix).
 */
export function gzipStable(octets) {
  const g = gzipSync(octets);
  g[9] = 0x03;
  return g;
}

/** Le clair commence-t-il par l'en-tête gzip (1f 8b) ? Un JSON commence toujours par « { » ou « [ ». */
export function estGzip(octets) {
  return octets.length >= 2 && octets[0] === 0x1f && octets[1] === 0x8b;
}

/** Chiffre un objet en JSON compact, compressé en gzip si gzip est vrai (états du Mac). */
export function encryptJson(clesOuSecret, obj, { gzip = false, iv, palier = 0 } = {}) {
  const brut = Buffer.from(JSON.stringify(obj), 'utf8');
  const clair = gzip ? (palier ? bourrerGzip(gzipStable(brut), palier) : gzipStable(brut)) : brut;
  return encryptBlob(clesOuSecret, clair, iv);
}

/** Palier de bourrage des états compressés : la taille d'un blob ne varie que par pas de 16 Kio. */
export const PALIER_BOURRAGE = 16 * 1024;

/**
 * Bourre un gzip jusqu'à `palier × n − 1` octets (le remplissage PKCS7 ajoute ensuite 1 à 16 octets, donc un chiffré de
 * `palier × n` octets exactement). Le bourrage va dans le champ FEXTRA de l'en-tête gzip (RFC 1952 §2.3.1, sous-champ
 * « AP » rempli de zéros), que tout décodeur gzip saute : le clair décompressé est inchangé. Le relais ne voit donc la
 * taille de l'état qu'à 16 Kio près (passage en mode discret, rythme de travail).
 */
export function bourrerGzip(gz, palier = PALIER_BOURRAGE) {
  const g = Buffer.from(gz);
  if (g.length < 18 || g[0] !== 0x1f || g[1] !== 0x8b || g[2] !== 8 || g[3] !== 0) throw new Error('plain gzip expected (no flags)');
  const cible = Math.ceil((g.length + 6 + 1) / palier) * palier - 1;
  const n = cible - g.length - 6;   // octets de données du sous-champ
  if (n > 0xffff - 4) throw new Error('step too large for the FEXTRA field');
  const extra = Buffer.alloc(2 + 4 + n);
  extra.writeUInt16LE(4 + n, 0);    // XLEN
  extra.write('AP', 2, 'latin1');   // SI1 SI2
  extra.writeUInt16LE(n, 4);        // LEN
  const tete = Buffer.from(g.subarray(0, 10));
  tete[3] = 0x04;                   // FLG.FEXTRA
  return Buffer.concat([tete, extra, g.subarray(10)]);
}

/** Déchiffre un blob et renvoie l'objet JSON, que le clair soit gzippé ou non. */
export function decryptJson(clesOuSecret, blob) {
  let clair = decryptBlob(clesOuSecret, blob);
  if (estGzip(clair)) clair = gunzipSync(clair, { maxOutputLength: MAX_CLAIR });
  return JSON.parse(clair.toString('utf8'));
}

// ---------------------------------------------------------------------------
// 12 mots BIP39 (128 bits + 4 bits de somme de contrôle), liste anglaise
// ---------------------------------------------------------------------------

/** S vers 12 mots BIP39 anglais, exactement comme un portefeuille Bitcoin. */
export function toWords(S) {
  const s = secret(S);
  const controle = createHash('sha256').update(s).digest()[0] >> 4; // 4 premiers bits du SHA-256
  let bits = 0n;
  for (const octet of s) bits = (bits << 8n) | BigInt(octet);
  bits = (bits << 4n) | BigInt(controle); // 132 bits
  const mots = [];
  for (let i = 11; i >= 0; i--) mots.push(MOTS[Number((bits >> BigInt(i * 11)) & 0x7ffn)]);
  return mots;
}

/**
 * 12 mots (tableau ou chaîne) vers S. Insensible à la casse et aux espaces superflus.
 * Lève une erreur si un mot est inconnu, si le nombre est faux ou si la somme de contrôle ne correspond pas.
 */
export function fromWords(words) {
  const liste = (Array.isArray(words) ? words.join(' ') : String(words ?? '')).trim().toLowerCase().split(/\s+/).filter(Boolean);
  if (liste.length !== 12) throw new Error('Exactly 12 words are needed');
  let bits = 0n;
  for (const mot of liste) {
    const index = MOTS.indexOf(mot);
    if (index < 0) throw new Error(`Unknown word: ${mot}`);
    bits = (bits << 11n) | BigInt(index);
  }
  const controle = Number(bits & 0xfn);
  let entropie = bits >> 4n;
  const s = Buffer.alloc(TAILLE_SECRET);
  for (let i = TAILLE_SECRET - 1; i >= 0; i--) { s[i] = Number(entropie & 0xffn); entropie >>= 8n; }
  if (controle !== createHash('sha256').update(s).digest()[0] >> 4) throw new Error('Wrong checksum: check the words');
  return s;
}

// ---------------------------------------------------------------------------
// Lien d'appairage : https://aimpire.sidali.dev/#s=<base64url(S)>
// ---------------------------------------------------------------------------

/** S vers lien d'appairage. Le secret est dans le fragment (#), que les navigateurs n'envoient jamais au serveur. */
export function toLink(S, base = RELAIS_PAR_DEFAUT) {
  const racine = base.endsWith('/') ? base : `${base}/`;
  return `${racine}#s=${secret(S).toString('base64url')}`;
}

/** Lien d'appairage vers S. Lève une erreur si le fragment est absent ou mal formé. */
export function fromLink(url) {
  const texte = String(url ?? '').trim();
  const diese = texte.indexOf('#');
  if (diese < 0) throw new Error('Invalid link: missing fragment');
  const valeur = new URLSearchParams(texte.slice(diese + 1)).get('s');
  if (!valeur || !/^[A-Za-z0-9_-]+={0,2}$/.test(valeur)) throw new Error('Invalid link: s parameter missing or malformed');
  const s = Buffer.from(valeur.replace(/=+$/, ''), 'base64url');
  if (s.length !== TAILLE_SECRET) throw new Error('Invalid link: secret has the wrong size');
  return s;
}

/** Relais déduit d'un lien : son origine (schéma, hôte, port) suivie de « / ». */
export function relaisDuLien(url) {
  return new URL(String(url).trim()).origin + '/';
}
