// Objectifs : lecture et écriture de <données>/aimpire.json (atomique), et propositions sans IA tirées des titres de sessions.
import fs from 'node:fs';
import { file, readJson, writeAtomic } from './paths.js';

const GOALS = file('aimpire.json');

export function readGoalsFile() {
  const g = readJson(GOALS, {});
  g.villages ||= {}; g.alias ||= {}; g.ignore ||= [];
  return g;
}

// Fixe (ou remplace) l'objectif d'un village : { objectif, cible: { res: n }, depuis }.
export function setGoal(village, texte, res, cible, depuis) {
  if (!village || !['or', 'commits', 'bois', 'pierre', 'parchemins'].includes(res) || !(cible > 0)) return false;
  const g = readGoalsFile();
  g.villages[village] = { ...(g.villages[village] || {}), objectif: String(texte || '').slice(0, 80), cible: { [res]: Math.round(cible) }, depuis: depuis || new Date().toLocaleDateString('sv') };
  writeAtomic(GOALS, JSON.stringify(g, null, 2));
  return true;
}

export function clearGoal(village) {
  const g = readGoalsFile();
  if (!g.villages[village]) return false;
  delete g.villages[village].objectif; delete g.villages[village].cible; delete g.villages[village].depuis;
  writeAtomic(GOALS, JSON.stringify(g, null, 2));
  return true;
}

// Propositions : on cherche dans les titres de sessions une version, un mot-clé de livraison ou une clé de ticket.
// La cible (or) est la médiane d'or par jour actif, multipliée par 5 jours. Aucun appel à un modèle : des regex.
const PATTERNS = [
  [/\bv?(\d+\.\d+(?:\.\d+)?)\b/i, (m) => `Ship v${m[1]}`],
  [/\b(release|livrer|livraison|déploiement|deploy|mise en prod|publier|soumission|resubmission|store)\b/i, () => 'Ship the next version'],
  [/\b(mvp|prototype|poc)\b/i, () => 'Release the MVP'],
  [/\b(migration|migrer|refonte|refactor)\b/i, () => 'Finish the migration'],
  [/\b([A-Z]{2,6}-\d{2,5})\b/, (m) => `Wrap up ${m[1]}`],
  [/\b(audit|sécurité|security)\b/i, () => 'Wrap up the audit'],
];
export function suggestGoals(villages, goals, orParJour) {
  const out = [];
  for (const v of villages) {
    if (goals.villages[v.name]?.cible || goals.villages[v.id]?.cible || v.idleDays > 21) continue;
    const titles = v.buildings.slice(0, 6).map((b) => String(b.title || ''));
    let texte = '';
    for (const t of titles) { for (const [re, f] of PATTERNS) { const m = re.exec(t); if (m) { texte = f(m); break; } } if (texte) break; }
    if (!texte) continue;
    out.push({ village: v.name, id: v.id, texte, res: 'or', cible: Math.max(5, Math.round((orParJour || 5) * 5)) });
  }
  return out.slice(0, 4);
}
