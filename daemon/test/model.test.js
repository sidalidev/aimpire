// Tests du modèle : villages, worktrees, trésor depuis l'installation, objectifs depuis une date, attention, stabilité du placement.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

process.env.AIMPIRE_HOME = fs.mkdtempSync(path.join(os.tmpdir(), 'aimpire-model-'));
const { buildState, xpOf, MONUMENTS } = await import('../model.js');
const { emptyTally, dayKey } = await import('../scan.js');
const { DAY } = await import('../config.js');

const NOW = Date.parse('2026-10-16T12:00:00');
function session(file, cwd, { last = NOW - 5000, commits = 0, bois = 0, model = 'claude-sonnet-5-5', days = {}, pending = {}, askedTs = 0, turnEnd = 0 } = {}) {
  const t = emptyTally();
  t.commits = commits; t.or = commits; t.bois = bois; t.tools = 5; t.days = days;
  return [file, { kind: 'session', cwd, last, mtime: last, tally: t, model, title: path.basename(cwd), pending, askedTs, turnEnd }];
}
const cacheOf = (...sessions) => ({ files: Object.fromEntries(sessions), subs: {}, food: {}, registry: {} });

test('un dossier = un village, un worktree rejoint son dépôt', () => {
  const S = {};
  const cache = cacheOf(session('/j/a.jsonl', '/home/demo/proj-a'), session('/j/b.jsonl', '/home/demo/proj-a/.claude/worktrees/feature-x'), session('/j/c.jsonl', '/home/demo/proj-b'));
  buildState(S, cache, NOW);
  assert.equal(S.villages.length, 2);
  const a = S.villages.find((v) => v.name === 'proj-a');
  assert.equal(a.buildings.length, 2);
});

test('le trésor ne compte que l\'or gagné depuis l\'installation', () => {
  const S = { installedAt: NOW - 1000 };
  const today = dayKey(NOW), before = dayKey(NOW - 10 * DAY);
  const cache = cacheOf(session('/j/a.jsonl', '/home/demo/proj-a', { commits: 50, days: { [before]: { or: 45, commits: 45, min: 60 }, [today]: { or: 5, commits: 5, min: 30 } } }));
  buildState(S, cache, NOW);
  assert.equal(S.empire.orSince, 5);
  assert.equal(S.empire.tresor, 105);
  assert.ok(S.empire.or >= 50);   // l'historique reste dans les niveaux et l'XP
  assert.ok(S.empire.monuments.every((m) => m.cout > 0));
  assert.equal(S.empire.monuments.length, MONUMENTS.length);
});

test('objectif compté depuis `depuis`, pas sur tout l\'historique', () => {
  const home = process.env.AIMPIRE_HOME;
  fs.writeFileSync(path.join(home, 'aimpire.json'), JSON.stringify({ villages: { 'proj-a': { objectif: 'v1', cible: { or: 3 }, depuis: '2026-10-15' } } }));
  const S = {};
  const cache = cacheOf(session('/j/a.jsonl', '/home/demo/proj-a', { commits: 20, days: { '2026-10-01': { or: 17, commits: 17, min: 10 }, '2026-10-16': { or: 3, commits: 3, min: 10 } } }));
  buildState(S, cache, NOW);
  const v = S.villages[0];
  assert.equal(v.objectif.have, 3);
  assert.equal(v.objectif.done, true);
  fs.unlinkSync(path.join(home, 'aimpire.json'));
});

test('attention : question en attente, fin de tour, rien si tu as répondu depuis', () => {
  const S = {};
  const cache = cacheOf(
    session('/j/q.jsonl', '/home/demo/q', { last: NOW - 60000, pending: { t1: { name: 'AskUserQuestion', ts: NOW - 60000 } }, askedTs: NOW - 120000 }),
    session('/j/f.jsonl', '/home/demo/f', { last: NOW - 60000, turnEnd: NOW - 60000, askedTs: NOW - 120000 }),
    session('/j/ok.jsonl', '/home/demo/ok', { last: NOW - 60000, turnEnd: NOW - 90000, askedTs: NOW - 60000 }),
  );
  buildState(S, cache, NOW);
  const kinds = Object.fromEntries(S.attention.map((a) => [a.villageName, a.kind]));
  assert.equal(kinds.q, 'question');
  assert.equal(kinds.f, 'fini');
  assert.equal(kinds.ok, undefined);
  assert.equal(S.attention[0].kind, 'question');   // la question passe avant la fin de tour
});

test('permission : pas quand le registre dit « busy » (outil long), oui quand il dit « idle »', () => {
  const mk = (status) => {
    const S = {};
    const cache = cacheOf(session('/j/p.jsonl', '/home/demo/p', { last: NOW - 30000, pending: { t1: { name: 'Bash', ts: NOW - 30000 } }, askedTs: NOW - 60000 }));
    cache.registry = { p: { status, updatedAt: NOW } };
    buildState(S, cache, NOW);
    return S.attention.map((a) => a.kind);
  };
  assert.deepEqual(mk('busy'), []);
  assert.deepEqual(mk('idle'), ['permission']);
});

test('le placement des villages est stable à 15 % près', () => {
  const S = {};
  const cache = cacheOf(session('/j/a.jsonl', '/h/a', { bois: 100 }), session('/j/b.jsonl', '/h/b', { bois: 95 }));
  buildState(S, cache, NOW);
  const order1 = [...S.order];
  cache.files['/j/b.jsonl'].tally.bois = 105;   // b dépasse a de peu : pas de permutation
  buildState(S, cache, NOW);
  assert.deepEqual(S.order, order1);
  cache.files['/j/b.jsonl'].tally.bois = 400;   // écart net : b passe devant
  buildState(S, cache, NOW);
  assert.equal(S.order[0], '/h/b');
});

test('xp : l\'or pèse huit fois plus qu\'une ressource ordinaire', () => {
  const t = emptyTally();
  t.bois = 10; t.or = 1;
  assert.equal(xpOf(t), 18);
});

test('aucun appel à Anthropic ni à claude -p dans le serveur', () => {
  const dir = path.join(path.dirname(new URL(import.meta.url).pathname), '..');
  for (const f of fs.readdirSync(dir).filter((x) => x.endsWith('.js'))) {
    const src = fs.readFileSync(path.join(dir, f), 'utf8');
    assert.ok(!/api\.anthropic\.com|claude -p|claude_agent_sdk|@anthropic-ai/.test(src), `${f} parle à Anthropic`);
  }
});
