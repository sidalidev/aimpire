// Mode discret (partages d'écran, visio, et état publié pour le téléphone) : liste blanche de l'état servi.
// On construit un nouvel objet avec seulement ce que le client affiche, au lieu de cloner l'état puis d'effacer : un champ
// ajouté plus tard au modèle (journal, registre, chemins) ne peut donc pas fuiter par oubli.
// Les ids de village (chemin du projet en minuscules) sont remplacés par des pseudonymes stables (« v » + 10 caractères hex,
// HMAC du jeton local) : le serveur sait les relier au vrai village (reclamer), personne d'autre.
import crypto from 'node:crypto';

const ROMAINS = [['M', 1000], ['CM', 900], ['D', 500], ['CD', 400], ['C', 100], ['XC', 90], ['L', 50], ['XL', 40], ['X', 10], ['IX', 9], ['V', 5], ['IV', 4], ['I', 1]];
export function romain(n) {
  let r = '';
  for (const [k, v] of ROMAINS) while (n >= v) { r += k; n -= v; }
  return r;
}

/** Fabrique de pseudonymes stables pour une clé donnée (le jeton local) : vid -> « v3f9a… ». */
export function creerPseudo(cle) {
  const memo = new Map();
  return (vid) => {
    const k = String(vid ?? '');
    if (!k) return '';
    if (!memo.has(k)) {
      if (memo.size > 5000) memo.clear();
      memo.set(k, 'v' + crypto.createHmac('sha256', String(cle)).update(k).digest('hex').slice(0, 10));
    }
    return memo.get(k);
  };
}

const garder = (o, cles) => Object.fromEntries(cles.filter((k) => o && o[k] !== undefined).map((k) => [k, o[k]]));

const CLES_BATIMENT = ['id', 'type', 'level', 'xp', 'res', 'commits', 'tests', 'testsOk', 'model', 'unit', 'cost', 'armure', 'effort',
  'usd', 'tokens', 'ago', 'working', 'sleeping', 'ruin', 'remote', 'attention', 'last', 'errors', 'compacts', 'hidden', 'x', 'z'];
const CLES_VILLAGE = ['x', 'z', 'ang', 'level', 'levelName', 'xp', 'res', 'last', 'idleDays', 'vitalite', 'attention'];
const CLES_EMPIRE = ['bois', 'pierre', 'parchemins', 'or', 'xp', 'villages', 'sessions', 'actives', 'titre', 'serie', 'orSince', 'tresor',
  'monuments', 'endormis', 'attention', 'fete', 'calendrier', 'rare'];

// Libellés neutres des événements en mode discret (journal, événements) (le texte d'origine peut contenir des noms).
export const TYPE_LABELS = { bois: 'wood', pierre: 'stone', parchemins: 'scrolls', or: 'gold', niveau: 'level up', objectif: 'goal', succes: 'achievement',
  senat: 'Senate', reprise: 'village revived', famine: 'famine', faim: 'harvest', rare: 'rare event', recompense: 'reward', monument: 'monument',
  fete: 'festival', telephone: 'phone' };

// État de session sans nom d'outil MCP (« mcp__serveur__outil » peut nommer un client) : on garde le premier segment.
const outil = (t) => (String(t || '').startsWith('mcp__') ? 'mcp' : String(t || ''));
const etatSession = (b) => {
  const s = String(b.state || '');
  return b.lastTool && s.endsWith(b.lastTool) ? s.slice(0, s.length - String(b.lastTool).length) + outil(b.lastTool) : s;
};

/**
 * État flouté : seulement les champs affichés par le client, noms et titres remplacés, ids de village pseudonymisés.
 * Ni journal, ni registre, ni ordre, ni emplacements, ni propositions d'objectifs.
 */
export function flouter(S, pseudo) {
  const nom = {};
  const villages = (S.villages || []).map((v, i) => {
    nom[v.id] = 'Village ' + romain(i + 1);
    const o = v.objectif ? { ...garder(v.objectif, ['res', 'cible', 'progress', 'have', 'done', 'depuis']), texte: 'Goal' } : null;
    let k = 1;
    const buildings = (v.buildings || []).map((b) => ({
      ...garder(b, CLES_BATIMENT), title: 'Session ' + k++, asked: '', said: '', branch: '', lastTool: outil(b.lastTool), state: etatSession(b),
      subs: (b.subs || []).map((s) => ({ ...garder(s, ['id', 'working', 'unit']), title: 'task', tool: outil(s.tool) })),
    }));
    return { ...garder(v, CLES_VILLAGE), id: pseudo(v.id), name: nom[v.id], cwd: '', province: '', objectif: o, buildings };
  });
  const e = S.empire || {};
  const aujourdhui = e.aujourdhui ? Object.fromEntries(Object.entries(e.aujourdhui).filter(([k]) => k !== 'villages')) : undefined;
  const empire = {
    ...garder(e, CLES_EMPIRE), aujourdhui, suggestions: [],
    quests: (e.quests || []).map((q) => ({ ...garder(q, ['idle', 'since', 'done', 'claimed', 'reward']), village: pseudo(q.village), name: nom[q.village] || 'Village' })),
  };
  const attention = (S.attention || []).map((a) => ({ ...garder(a, ['kind', 'since', 'session']), tool: outil(a.tool), village: pseudo(a.village), villageName: nom[a.village] || 'Village', title: 'Session' }));
  const events = (S.events || []).map((x) => ({ ...garder(x, ['t', 'type', 'building', 'n']), village: pseudo(x.village), text: x.text ? TYPE_LABELS[x.type] || 'event' : undefined }));
  const log = villages.flatMap((v) => v.buildings.filter((b) => b.working).map((b) => `${b.model} · ${b.title}: ${b.state} (${v.name})`)).slice(0, 8);
  return {
    tick: S.tick, scanning: S.scanning, privacy: 'flou', villages, empire, attention, events,
    food: S.food ? garder(S.food, ['saison', 'hiver', 'famine', 'retourA', 'type', 'parUnite']) : S.food,
    log: log.length ? log : ['All sessions are awaiting your orders'],
  };
}

/** Retrouve le vrai id d'un village à partir de son pseudonyme (ou de son vrai id), parmi les ids connus. */
export function resoudreVillage(id, idsConnus, pseudo) {
  if (idsConnus.includes(id)) return id;
  return idsConnus.find((v) => pseudo(v) === id) || '';
}
