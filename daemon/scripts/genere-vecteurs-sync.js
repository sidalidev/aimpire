// Génère docs/SYNC-VECTEURS.json : vecteurs partagés entre le Mac (daemon/sync-crypto.js) et le client Godot (godot/sync_crypto.gd).
// Usage : cd daemon && node scripts/genere-vecteurs-sync.js
// Les valeurs « officielles » (RFC 5869, BIP39) sont recopiées des publications de référence, pas recalculées ici :
// elles vérifient chaque implémentation indépendamment de l'autre.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  deriveId, deriveWriteToken, empreinteJeton, deriveKeys,
  encryptBlob, bourrerGzip, toWords, toLink, RELAIS_PAR_DEFAUT, gzipStable } from '../sync-crypto.js';

const ICI = path.dirname(fileURLToPath(import.meta.url));
export const FICHIER = path.join(ICI, '..', '..', 'docs', 'SYNC-VECTEURS.json');

const hex = (b) => Buffer.from(b).toString('hex');

export function construireVecteurs() {
  const S = Buffer.from('000102030405060708090a0b0c0d0e0f', 'hex');
  const k = deriveKeys(S);
  const W = deriveWriteToken(S);

  // Blob de référence : JSON compact chiffré avec un iv fixe.
  const iv = '00112233445566778899aabbccddeeff';
  const clair = JSON.stringify({ tick: 1, villages: [] });
  const blob = encryptBlob(k, clair, iv);
  const corps = blob.subarray(17, blob.length - 32);

  // Blob d'état comme le Mac l'envoie : enveloppe JSON, gzip, puis chiffrement.
  const iv2 = 'ffeeddccbbaa99887766554433221100';
  const enveloppe = { type: 'etat', ts: 1760000000000, etat: { tick: 1, villages: [] } };
  const gz = gzipStable(Buffer.from(JSON.stringify(enveloppe), 'utf8'));
  const blobGzip = encryptBlob(k, gz, iv2);

  // État bourré (§3) : le même gzip avec un champ FEXTRA de remplissage, palier réduit à 256 octets pour garder le fichier court.
  const iv4 = '0123456789abcdef0123456789abcdef';
  const gzBourre = bourrerGzip(gz, 256);
  const blobBourre = encryptBlob(k, gzBourre, iv4);

  // Commande comme le téléphone l'envoie (JSON non compressé).
  const iv3 = '0f0e0d0c0b0a09080706050403020100';
  const commande = { type: 'cmd', ts: 1760000000000, nonce: '000102030405060708090a0b0c0d0e0f', action: 'construire', id: 'colisee' };
  const blobCmd = encryptBlob(k, JSON.stringify(commande), iv3);

  // Cas négatifs : tous doivent être refusés par decryptBlob avec S.
  const macFaux = Buffer.from(blob); macFaux[macFaux.length - 1] ^= 0x01;
  const chiffreModifie = Buffer.from(blob); chiffreModifie[20] ^= 0x80;
  const ivModifie = Buffer.from(blob); ivModifie[1] ^= 0x01;
  const versionInconnue = Buffer.from(blob); versionInconnue[0] = 0x02;
  const autreCle = encryptBlob(deriveKeys('ffffffffffffffffffffffffffffffff'), clair, iv);

  return {
    description: 'Vecteurs de la chaîne de sync AImpire (docs/SYNC.md). Générés par daemon/scripts/genere-vecteurs-sync.js ; vérifiés par daemon/test/sync-crypto.test.js et godot/tests/test_sync_crypto.gd.',
    secret_hex: hex(S),
    id: deriveId(S),
    jeton_ecriture: W,
    empreinte_jeton: empreinteJeton(W),
    k_enc_hex: hex(k.enc),
    k_mac_hex: hex(k.mac),
    mots: toWords(S),
    lien: toLink(S, RELAIS_PAR_DEFAUT),
    blob: {
      iv_hex: iv,
      clair,
      chiffre_hex: hex(corps),
      mac_hex: hex(blob.subarray(blob.length - 32)),
      blob_hex: hex(blob),
      blob_base64: blob.toString('base64'),
    },
    blob_gzip: {
      iv_hex: iv2,
      objet: enveloppe,
      gzip_hex: hex(gz),
      blob_hex: hex(blobGzip),
    },
    blob_bourre: {
      iv_hex: iv4,
      palier: 256,
      objet: enveloppe,
      gzip_hex: hex(gzBourre),
      blob_hex: hex(blobBourre),
    },
    blob_commande: {
      iv_hex: iv3,
      objet: commande,
      blob_hex: hex(blobCmd),
    },
    negatifs: {
      mac_faux_hex: hex(macFaux),
      chiffre_modifie_hex: hex(chiffreModifie),
      iv_modifie_hex: hex(ivModifie),
      version_inconnue_hex: hex(versionInconnue),
      trop_court_hex: hex(blob.subarray(0, 64)),
      autre_cle_hex: hex(autreCle),
    },
    hkdf_rfc5869: [
      { cas: 'RFC 5869 A.1', ikm_hex: '0b'.repeat(22), sel_hex: '000102030405060708090a0b0c', info_hex: 'f0f1f2f3f4f5f6f7f8f9', longueur: 42,
        okm_hex: '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865' },
      { cas: 'RFC 5869 A.3 (sel et info vides)', ikm_hex: '0b'.repeat(22), sel_hex: '', info_hex: '', longueur: 42,
        okm_hex: '8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8' },
    ],
    bip39_officiels: [
      { entropie_hex: '00000000000000000000000000000000', mots: 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about' },
      { entropie_hex: '7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f', mots: 'legal winner thank year wave sausage worth useful legal winner thank yellow' },
      { entropie_hex: '80808080808080808080808080808080', mots: 'letter advice cage absurd amount doctor acoustic avoid letter advice cage above' },
      { entropie_hex: 'ffffffffffffffffffffffffffffffff', mots: 'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong' },
      { entropie_hex: '9e885d952ad362caeb4efe34a8e91bd2', mots: 'ozone drill grab fiber curtain grace pudding thank cruise elder eight picnic' },
    ],
    mots_invalides: [
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon',
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon aimpire',
    ],
    liens_invalides: [
      'https://aimpire.sidali.dev/',
      'https://aimpire.sidali.dev/#s=',
      'https://aimpire.sidali.dev/#s=AAECAwQFBgcICQoLDA0O',
      'https://aimpire.sidali.dev/#s=AAECAwQFBgcICQoLDA0ODxA',
      'https://aimpire.sidali.dev/#s=AAECAwQFBgcICQoLDA0OD$',
    ],
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  fs.writeFileSync(FICHIER, JSON.stringify(construireVecteurs(), null, 2) + '\n');
  console.log('écrit', path.relative(process.cwd(), FICHIER));
}
