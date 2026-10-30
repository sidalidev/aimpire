// Calendrier romain cosmétique et événements rares déterministes (graine = jour, donc identiques à chaque relance).
// Rien ici n'est obligatoire ni pénalisant : ce sont des rendez-vous qui donnent de la vie à l'Empire.
import { dayKey } from './scan.js';
import { DAY } from './config.js';

const MOIS = ['Ianuarius', 'Februarius', 'Martius', 'Aprilis', 'Maius', 'Iunius', 'Quintilis', 'Sextilis', 'September', 'October', 'November', 'December'];
const IDES = [13, 13, 15, 13, 15, 13, 15, 13, 13, 15, 13, 13];
// fêtes fixes : [mois 1-12, jour début, jour fin, id, nom, effet cosmétique]
const FETES = [
  [4, 12, 19, 'cerealia', 'Cerealia', 'ble'], [4, 21, 21, 'parilia', 'Parilia', 'fanions'], [4, 28, 30, 'floralia', 'Floralia', 'fleurs'],
  [8, 23, 23, 'vulcanalia', 'Vulcanalia', 'forges'], [12, 17, 23, 'saturnales', 'Saturnales', 'fanions'],
  [6, 24, 24, 'fors_fortuna', 'Fors Fortuna', 'fanions'], [10, 15, 15, 'october_equus', 'October Equus', 'fanions'],
];
const hash = (s) => { let h = 2166136261; for (const c of String(s)) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); } return h >>> 0; };

export function calendar(now, installedAt) {
  const d = new Date(now);
  const m = d.getMonth(), j = d.getDate();
  const fete = FETES.find(([mm, a, b]) => mm === m + 1 && j >= a && j <= b);
  const anniv = installedAt && new Date(installedAt).getMonth() === m && new Date(installedAt).getDate() === j && now - installedAt > 300 * DAY;
  const saison = m >= 2 && m <= 4 ? 'printemps' : m >= 5 && m <= 7 ? 'ete' : m >= 8 && m <= 10 ? 'automne' : 'hiver';
  const label = j === 1 ? `Kalends of ${MOIS[m]}` : j === IDES[m] ? `Ides of ${MOIS[m]}` : j === 5 || j === 7 ? `Nones of ${MOIS[m]}` : `${MOIS[m]} ${j}`;
  return { jour: label, mois: MOIS[m], kalendes: j === 1, ides: j === IDES[m], saison,
    fete: anniv ? { id: 'anniversaire', nom: 'Anniversary of the Empire', effet: 'fanions' } : fete ? { id: fete[3], nom: fete[4], effet: fete[5] } : null };
}

// Événement rare du jour : environ un jour sur dix, tiré de la graine du jour. Actif 48 h, petit bonus d'or une seule fois.
const RARES = [
  { id: 'caravane', nom: 'A merchant caravan is camping at the Forum', or: 15, cond: () => true },
  { id: 'comete', nom: 'A comet crosses the sky', or: 10, cond: () => true },
  { id: 'jeux', nom: 'Circus games: five clean commits this week', or: 25, cond: (s) => s.commits7 >= 5 },
  { id: 'legat', nom: 'A passing Legate inspects your villages', or: 10, cond: (s) => s.opus },
  { id: 'vestale', nom: 'A Vestal watches over your streak', or: 20, cond: (s) => s.serie >= 30 },
  { id: 'augure', nom: 'The omens are good: a goal reached today is worth double', or: 0, cond: () => true },
];
export function rareEvent(now, stats) {
  for (const back of [0, 1]) {
    const k = dayKey(now - back * DAY);
    const h = hash('rare|' + k);
    if (h % 10 !== 0) continue;
    const candidates = RARES.filter((r) => r.cond(stats));
    if (!candidates.length) continue;
    const r = candidates[h % candidates.length];
    return { ...r, jour: k, depuis: Date.parse(k) };
  }
  return null;
}
