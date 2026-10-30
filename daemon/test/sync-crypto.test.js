// Tests de la cryptographie de sync : vecteurs partagés (docs/SYNC-VECTEURS.json), aller-retour, refus des blobs altérés.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { hkdfSync } from 'node:crypto';
import { gunzipSync } from 'node:zlib';
import {
  deriveId, idDuJeton, bourrerGzip, deriveWriteToken, empreinteJeton, deriveKeys, estIdValide, estBlobBienForme,
  encryptBlob, decryptBlob, encryptJson, decryptJson, toWords, fromWords, toLink, fromLink, relaisDuLien, genererSecret,
} from '../sync-crypto.js';
import { construireVecteurs } from '../scripts/genere-vecteurs-sync.js';

const V = JSON.parse(fs.readFileSync(new URL('../../docs/SYNC-VECTEURS.json', import.meta.url), 'utf8'));
const S = V.secret_hex;
const hex = (b) => Buffer.from(b).toString('hex');
const octets = (h) => Buffer.from(h, 'hex');

test('vecteurs : id, jeton d\'écriture, clés, mots, lien', () => {
  assert.equal(deriveId(S), V.id);
  assert.equal(idDuJeton(V.jeton_ecriture), V.id, 'id vérifiable par le relais à partir de W');
  assert.ok(estIdValide(V.id));
  assert.equal(deriveWriteToken(S), V.jeton_ecriture);
  assert.equal(empreinteJeton(V.jeton_ecriture), V.empreinte_jeton);
  const k = deriveKeys(S);
  assert.equal(hex(k.enc), V.k_enc_hex);
  assert.equal(hex(k.mac), V.k_mac_hex);
  assert.deepEqual(toWords(S), V.mots);
  assert.equal(toLink(S), V.lien);
  assert.equal(hex(fromLink(V.lien)), S);
  assert.equal(hex(fromWords(V.mots)), S);
  assert.equal(relaisDuLien(V.lien), 'https://aimpire.sidali.dev/');
});

test('vecteurs : le fichier correspond au générateur', () => {
  const G = construireVecteurs();
  for (const k of ['id', 'jeton_ecriture', 'empreinte_jeton', 'k_enc_hex', 'k_mac_hex', 'mots', 'lien', 'blob', 'blob_bourre', 'blob_commande', 'negatifs', 'hkdf_rfc5869', 'bip39_officiels'])
    assert.deepEqual(G[k], V[k], k);
});

test('vecteurs : blob chiffré avec iv fixe, octet pour octet', () => {
  const b = encryptBlob(S, V.blob.clair, V.blob.iv_hex);
  assert.equal(hex(b), V.blob.blob_hex);
  assert.equal(b.toString('base64'), V.blob.blob_base64);
  assert.equal(hex(b.subarray(17, b.length - 32)), V.blob.chiffre_hex);
  assert.equal(hex(b.subarray(b.length - 32)), V.blob.mac_hex);
  assert.equal(decryptBlob(S, octets(V.blob.blob_hex)).toString('utf8'), V.blob.clair);
});

test('vecteurs : état gzippé et commande', () => {
  assert.equal(hex(encryptBlob(S, octets(V.blob_gzip.gzip_hex), V.blob_gzip.iv_hex)), V.blob_gzip.blob_hex);
  assert.deepEqual(JSON.parse(gunzipSync(octets(V.blob_gzip.gzip_hex)).toString()), V.blob_gzip.objet);
  assert.deepEqual(decryptJson(S, octets(V.blob_gzip.blob_hex)), V.blob_gzip.objet);
  assert.equal(hex(encryptJson(S, V.blob_commande.objet, { iv: V.blob_commande.iv_hex })), V.blob_commande.blob_hex);
  assert.deepEqual(decryptJson(S, octets(V.blob_commande.blob_hex)), V.blob_commande.objet);
});

test('bourrage : taille par paliers, clair inchangé, refus d\'un gzip à drapeaux', () => {
  assert.equal(hex(encryptBlob(S, octets(V.blob_bourre.gzip_hex), V.blob_bourre.iv_hex)), V.blob_bourre.blob_hex);
  assert.deepEqual(decryptJson(S, octets(V.blob_bourre.blob_hex)), V.blob_bourre.objet);
  assert.equal((octets(V.blob_bourre.gzip_hex).length + 1) % 256, 0);
  const tailles = new Set();
  for (const n of [10, 500, 3000, 9000]) {
    const etat = { type: 'etat', ts: 1, etat: { texte: genererSecret().toString('hex').repeat(n / 32 + 1) } };
    const b = encryptJson(S, etat, { gzip: true, palier: 16384 });
    assert.equal((b.length - 49) % 16384, 0, 'chiffré multiple du palier');
    assert.deepEqual(decryptJson(S, b), etat);
    tailles.add(b.length);
  }
  assert.equal(tailles.size, 1, 'des états de tailles différentes donnent le même blob');
  assert.throws(() => bourrerGzip(octets(V.blob_bourre.gzip_hex)), /no flags/);
});

test('blob altéré, mauvaise clé ou mauvais format : refusé', () => {
  for (const [cas, h] of Object.entries(V.negatifs)) assert.throws(() => decryptBlob(S, octets(h)), Error, cas);
  assert.throws(() => decryptBlob(S, octets(V.negatifs.mac_faux_hex)), /wrong mac/);
  assert.equal(estBlobBienForme(octets(V.negatifs.version_inconnue_hex)), false);
  assert.equal(estBlobBienForme(octets(V.negatifs.trop_court_hex)), false);
  assert.equal(estBlobBienForme(octets(V.blob.blob_hex)), true);
});

test('aller-retour avec un secret aléatoire et un iv aléatoire', () => {
  const s = genererSecret();
  const k = deriveKeys(s);
  const etat = { type: 'etat', ts: Date.now(), etat: { villages: [{ id: 'v', name: 'Été à Rome', buildings: [] }], tick: 42 } };
  for (const gzip of [false, true]) {
    const a = encryptJson(k, etat, { gzip }), b = encryptJson(k, etat, { gzip });
    assert.notEqual(hex(a), hex(b)); // iv différent à chaque fois
    assert.deepEqual(decryptJson(s, a), etat);
  }
  for (const n of [0, 1, 15, 16, 17, 1000]) {
    const clair = Buffer.alloc(n, 7);
    const b = encryptBlob(s, clair);
    assert.equal(b.length, 1 + 16 + (Math.floor(n / 16) + 1) * 16 + 32);
    assert.ok(decryptBlob(k, b).equals(clair));
  }
  assert.ok(fromWords(toWords(s)).equals(s));
  assert.ok(fromLink(toLink(s, 'http://127.0.0.1:8787')).equals(s));
});

test('HKDF : vecteurs officiels RFC 5869', () => {
  for (const c of V.hkdf_rfc5869)
    assert.equal(hex(hkdfSync('sha256', octets(c.ikm_hex), octets(c.sel_hex), octets(c.info_hex), c.longueur)), c.okm_hex, c.cas);
});

test('BIP39 : vecteurs officiels, mots et liens invalides', () => {
  for (const c of V.bip39_officiels) {
    assert.equal(toWords(c.entropie_hex).join(' '), c.mots);
    assert.equal(hex(fromWords(c.mots)), c.entropie_hex);
  }
  assert.equal(hex(fromWords('  Abandon ABANDON abandon abandon abandon abandon abandon abandon abandon abandon abandon  about ')), '0'.repeat(32));
  for (const m of V.mots_invalides) assert.throws(() => fromWords(m));
  for (const l of V.liens_invalides) assert.throws(() => fromLink(l));
});
