#!/usr/bin/env node
// Fusionne une plateforme dans le manifeste de mise à jour (update.json servi par le relais, voir godot/update.gd).
//   node tools/publier-maj.mjs --existant <update.json actuel ou vide> --plateforme mac|android --version x.y.z
//        --url <https://…/download/fichier> --sha256 <hex> --taille <octets> [--notes <fichier texte>]  > update.json
// L'autre plateforme est gardée telle quelle avec sa propre version ; la version du haut est la plus récente des deux.

import fs from 'node:fs';

const args = process.argv.slice(2);
const opt = (nom, defaut = '') => { const i = args.indexOf('--' + nom); return i >= 0 ? args[i + 1] : defaut; };
const echec = (m) => { console.error('publier-maj : ' + m); process.exit(1); };

const plateforme = opt('plateforme');
const version = opt('version');
const url = opt('url');
const sha256 = opt('sha256');
const taille = Number(opt('taille', '0'));
if (!['mac', 'android'].includes(plateforme)) echec('plateforme mac ou android attendue');
if (!/^\d{1,4}\.\d{1,4}\.\d{1,4}$/.test(version)) echec('version x.y.z attendue');
if (!/^https?:\/\/[^/?#@\s]+\/download\/[A-Za-z0-9._-]+$/.test(url)) echec('URL de téléchargement invalide');
if (!/^[0-9a-f]{64}$/.test(sha256)) echec('sha256 invalide');

let existant = {};
try {
  const brut = opt('existant') ? fs.readFileSync(opt('existant'), 'utf8').trim() : '';
  if (brut) existant = JSON.parse(brut);
  if (typeof existant !== 'object' || existant === null || Array.isArray(existant)) existant = {};
} catch { existant = {}; }

const comparer = (a, b) => {
  const pa = String(a).split('.').map(Number), pb = String(b).split('.').map(Number);
  for (let i = 0; i < 3; i++) if ((pa[i] || 0) !== (pb[i] || 0)) return (pa[i] || 0) > (pb[i] || 0) ? 1 : -1;
  return 0;
};

const sortie = {};
for (const p of ['mac', 'android']) {
  const e = existant[p];
  if (p === plateforme) sortie[p] = { version, url, sha256, taille };
  else if (e && typeof e === 'object' && typeof e.url === 'string') sortie[p] = { version: String(e.version || existant.version || ''), url: e.url, sha256: String(e.sha256 || ''), taille: Number(e.taille || 0) };
}
const versions = Object.values(sortie).map((e) => e.version).filter((v) => /^\d+\.\d+\.\d+$/.test(v));
const haut = versions.reduce((m, v) => (comparer(v, m) > 0 ? v : m), version);
const notesFichier = opt('notes');
const notes = notesFichier && fs.existsSync(notesFichier) ? fs.readFileSync(notesFichier, 'utf8').trim() : '';
const resultat = { version: haut, ...sortie, notes: haut === version ? notes : String(existant.notes || ''), publie: new Date().toISOString() };
process.stdout.write(JSON.stringify(resultat, null, 2) + '\n');
