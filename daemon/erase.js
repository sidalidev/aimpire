// « Erase everything » côté Mac : vide le dossier de données d'AImpire (progression, sauvegardes, cache, cache des voix,
// clés de la chaîne de sync, jeton local, journaux, .env). Jamais rien hors de ce dossier, jamais rien dans le dossier
// des journaux de sessions (~/.claude ou CLAUDE_CONFIG_DIR), qu'AImpire ne fait que lire.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const dedans = (a, b) => a === b || a.startsWith(b.endsWith(path.sep) ? b : b + path.sep);

/** Le dossier peut-il être vidé ? Ni la racine, ni le dossier personnel ou un de ses parents, ni ~/.claude (ni dedans, ni autour). */
export function effacementPermis(dossier, dossierSessions, maison = os.homedir()) {
  if (!dossier || !path.isAbsolute(dossier)) return false;
  const d = path.resolve(dossier), c = path.resolve(dossierSessions || path.join(maison, '.claude')), h = path.resolve(maison);
  if (d === path.parse(d).root) return false;
  if (dedans(h, d)) return false;              // le dossier personnel lui-même, ou un de ses parents
  if (dedans(d, c) || dedans(c, d)) return false;
  return true;
}

/** Vide le dossier (sans suivre les liens symboliques) et renvoie le nombre d'éléments effacés. Lève une erreur si refusé. */
export function viderDonnees(dossier, dossierSessions, maison = os.homedir()) {
  if (!effacementPermis(dossier, dossierSessions, maison)) throw new Error('erase refused for this folder');
  let n = 0;
  let noms = [];
  try { noms = fs.readdirSync(dossier); } catch { return 0; }
  for (const nom of noms) {
    fs.rmSync(path.join(dossier, nom), { recursive: true, force: true });
    n++;
  }
  return n;
}
