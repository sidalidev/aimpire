// Mode discret (blur.js) : l'état flouté ne contient aucun nom de village, chemin, titre, demande ou réponse,
// et les pseudonymes de village sont stables et réversibles côté serveur seulement.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { flouter, creerPseudo, resoudreVillage, romain } from '../blur.js';

const VID = '/home/demo/dev/client-acme';
const SECRETS = ['client-acme', 'Client-Acme', 'Refonte facturation', 'corrige la TVA', 'feature/acme-tva', 'audit-acme', 'mcp__acme_crm__search'];

function etatSynthetique() {
  const b = {
    id: 'a1b2c3d4-0000-4000-8000-000000000001', title: 'Refonte facturation', type: 'forge', level: 3, xp: 120,
    res: { bois: 1, pierre: 2, parchemins: 3, or: 4 }, commits: 2, tests: 1, testsOk: 1, model: 'opus', unit: 'chevalier', cost: 3,
    armure: 'fer', effort: 'high', usd: 1.5, tokens: 1000, branch: 'feature/acme-tva', ago: 12, lastTool: 'mcp__acme_crm__search',
    asked: 'corrige la TVA pour client-acme', said: 'C\'est fait pour client-acme', working: true, sleeping: false, ruin: false,
    remote: false, entry: 'cli', attention: 'question', state: 'mcp__acme_crm__search', last: 1, errors: 0, compacts: 0, hidden: false, x: 1, z: 2,
    subs: [{ id: 's1', title: 'audit-acme', tool: 'Bash', working: true, unit: 'paysan', workflow: 'audit-acme' }],
  };
  const v = { id: VID, name: 'client-acme', cwd: '/home/demo/Dev/client-acme', x: 1, z: 2, ang: 0.5, level: 2, levelName: 'bourg', xp: 120,
    res: b.res, objectif: { texte: 'Livrer client-acme', res: 'or', cible: 10, progress: 0.5, have: 5, done: false, depuis: '2026-10-01' },
    province: 'client-acme', buildings: [b], last: 1, idleDays: 3, vitalite: 80, attention: 1 };
  return {
    tick: 7, scanning: { done: 1, total: 1 }, privacy: 'normal', villages: [v],
    attention: [{ kind: 'question', since: 1, session: b.id, village: VID, villageName: 'client-acme', title: 'Refonte facturation', tool: 'mcp__acme_crm__search' }],
    events: [{ t: 5, type: 'reprise', village: VID, text: 'Retour à client-acme !' }, { t: 6, type: 'or', village: VID, building: b.id, n: 3 }],
    empire: { titre: 'Consul', bois: 1, pierre: 1, parchemins: 1, or: 1, tresor: 100, sessions: 1, actives: 1, attention: 1, serie: 2,
      quests: [{ village: VID, name: 'client-acme', idle: 3, since: 1, done: true, claimed: false, reward: 35 }],
      suggestions: [{ id: VID, texte: 'Livrer client-acme', res: 'or', cible: 20 }],
      aujourdhui: { or: 1, commits: 1, testsOk: 0, min: 30, usd: 1, villages: { [VID]: { or: 1, min: 30, commits: 1 } } },
      monuments: [], calendrier: { saison: 'ete', jour: 'XII' }, fete: null, rare: null },
    food: { saison: 0.2, hiver: 0.1, famine: false, retourA: null, type: '', parUnite: { chevalier: 1 } },
    log: ['opus · Refonte facturation : Bash (client-acme)'],
    journal: Array.from({ length: 5 }, (_, i) => ({ t: i, type: 'recompense', village: VID, text: `+${i} or pour avoir relancé client-acme` })),
    quests: { date: 'x', list: [{ village: VID, name: 'client-acme', done: true }] },
    ledger: { sessions: { [b.id]: { v: VID, days: {} } }, days: { '2026-10-19': { villages: { [VID]: {} } } } },
    order: [VID], slots: { [VID]: 0 }, wasIdle: { [VID]: false }, suggestions: [{ id: VID, texte: 'client-acme' }],
    done: { ['obj:' + VID]: 1 }, prevRes: {}, bonus: { or: 0 }, peak: {}, installedAt: 1, lastSeen: 1,
  };
}

test('flouter : liste blanche, aucun nom, chemin, titre, demande ou outil MCP nommé', () => {
  const pseudo = creerPseudo('jeton-local');
  const out = flouter(etatSynthetique(), pseudo);
  const json = JSON.stringify(out);
  for (const s of SECRETS) assert.ok(!json.toLowerCase().includes(s.toLowerCase()), `« ${s} » ne doit pas apparaître`);
  assert.ok(!json.includes('/users/'), 'aucun chemin');
  for (const k of ['journal', 'ledger', 'order', 'slots', 'wasIdle', 'suggestions', 'quests', 'done', 'prevRes', 'bonus'])
    assert.equal(out[k], undefined, `${k} absent`);
  assert.deepEqual(out.empire.suggestions, []);
  assert.equal(out.empire.aujourdhui.villages, undefined);
  assert.equal(out.privacy, 'flou');
  const v = out.villages[0];
  assert.equal(v.name, 'Village I');
  assert.match(v.id, /^v[0-9a-f]{10}$/);
  assert.equal(out.attention[0].village, v.id, 'pseudonyme cohérent partout');
  assert.equal(out.events[0].village, v.id);
  assert.equal(out.empire.quests[0].village, v.id);
  assert.equal(out.empire.quests[0].name, 'Village I');
  assert.equal(v.buildings[0].state, 'mcp');
  assert.equal(v.buildings[0].subs[0].title, 'task');
  assert.equal(out.events[0].text, 'village revived');
  assert.equal(out.events[1].text, undefined, 'pas de texte inventé');
  assert.equal(out.food.saison, 0.2);
  assert.equal(out.empire.tresor, 100);
});

test('pseudonymes : stables pour une clé, différents d\'une clé à l\'autre, résolus côté serveur', () => {
  const p1 = creerPseudo('a'), p2 = creerPseudo('b');
  assert.equal(p1(VID), creerPseudo('a')(VID));
  assert.notEqual(p1(VID), p2(VID));
  assert.equal(p1(''), '');
  assert.equal(resoudreVillage(p1(VID), [VID, '/x'], p1), VID);
  assert.equal(resoudreVillage(VID, [VID], p1), VID, 'le vrai id marche toujours (mode normal)');
  assert.equal(resoudreVillage(p2(VID), [VID], p1), '', 'pseudonyme d\'une autre clé : inconnu');
  assert.equal(romain(14), 'XIV');
});
