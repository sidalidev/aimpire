// Tests du scan incrémental : `node --test daemon/test/`. Fixtures synthétiques (aucun journal réel, aucune donnée perso).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

process.env.AIMPIRE_HOME = fs.mkdtempSync(path.join(os.tmpdir(), 'aimpire-test-'));
const { scanFile, unitOf, dayKey, emptyTally } = await import('../scan.js');

const tmp = () => path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'aimpire-scan-')), 's.jsonl');
const ts = (i) => new Date(Date.UTC(2026, 9, 10, 12, i)).toISOString();
const user = (i, text) => JSON.stringify({ type: 'user', cwd: '/home/demo/proj-a', timestamp: ts(i), message: { role: 'user', content: text } });
const tool = (i, name, input, id = 'toolu_' + i) => JSON.stringify({ type: 'assistant', timestamp: ts(i), message: { model: 'claude-sonnet-5-5', content: [{ type: 'tool_use', id, name, input }], usage: { output_tokens: 10, input_tokens: 100 } } });
const result = (i, id, text) => JSON.stringify({ type: 'user', timestamp: ts(i), message: { role: 'user', content: [{ type: 'tool_result', tool_use_id: id, content: text }] } });

async function scanAll(file) {
  const c = { kind: 'session' };
  const food = {};
  await scanFile(file, c, food, { badLines: 0, versions: {}, lastLineAt: 0 });
  return { c, food };
}

test('commit = or, édition = bois, lecture = parchemins, test vert = or', async () => {
  const f = tmp();
  fs.writeFileSync(f, [user(0, 'fais le boulot'), tool(1, 'Edit', { file_path: 'a.js' }), tool(2, 'Read', { file_path: 'a.js' }),
    tool(3, 'Bash', { command: 'git commit -m x' }), tool(4, 'Bash', { command: 'npm test' }, 't1'), result(5, 't1', '12 passed'), ''].join('\n'));
  const { c } = await scanAll(f);
  assert.equal(c.tally.bois, 1);
  assert.equal(c.tally.parchemins, 1);
  assert.equal(c.tally.commits, 1);
  assert.equal(c.tally.testsOk, 1);
  assert.equal(c.tally.or, 2);
  assert.equal(c.cwd, '/home/demo/proj-a');
  assert.equal(c.tally.pierre, 2);   // le test compte double, `git commit` ne compte pas comme pierre
});

test('un fichier qui grandit pendant la lecture ne compte rien deux fois', async () => {
  const f = tmp();
  fs.writeFileSync(f, tool(1, 'Bash', { command: 'git commit -m a' }) + '\n');
  const c = { kind: 'session' };
  const stats = { badLines: 0, versions: {}, lastLineAt: 0 };
  await scanFile(f, c, {}, stats);
  assert.equal(c.tally.commits, 1);
  fs.appendFileSync(f, tool(2, 'Bash', { command: 'git commit -m b' }) + '\n');
  await scanFile(f, c, {}, stats);
  await scanFile(f, c, {}, stats);   // rien de nouveau : pas de relecture
  assert.equal(c.tally.commits, 2);
  assert.equal(stats.badLines, 0);
});

test('ligne coupée au milieu d\'un caractère UTF-8 puis complétée', async () => {
  const f = tmp();
  const line = Buffer.from(user(1, 'crème brûlée à Zürich') + '\n');
  const cut = 60;
  fs.writeFileSync(f, line.subarray(0, cut));
  const c = { kind: 'session' };
  const stats = { badLines: 0, versions: {}, lastLineAt: 0 };
  await scanFile(f, c, {}, stats);
  fs.appendFileSync(f, line.subarray(cut));
  await scanFile(f, c, {}, stats);
  assert.equal(stats.badLines, 0);
  assert.equal(c.asked, 'crème brûlée à Zürich');
});

test('fichier tronqué : les compteurs repartent de zéro', async () => {
  const f = tmp();
  fs.writeFileSync(f, [tool(1, 'Edit', {}), tool(2, 'Edit', {}), ''].join('\n'));
  const c = { kind: 'session' };
  await scanFile(f, c, {}, null);
  assert.equal(c.tally.bois, 2);
  fs.writeFileSync(f, tool(1, 'Edit', {}) + '\n');
  await scanFile(f, c, {}, null);
  assert.equal(c.tally.bois, 1);
});

test('famine : quotaLimits rejeté', async () => {
  const f = tmp();
  fs.writeFileSync(f, JSON.stringify({ type: 'assistant', timestamp: ts(1), quotaLimits: { status: 'rejected', resetsAt: 1800000000, rateLimitType: 'five_hour' }, message: { model: 'claude-opus-5-5', content: [] } }) + '\n');
  const { c } = await scanAll(f);
  assert.equal(c.quota.status, 'rejected');
  assert.equal(c.quota.resetsAt, 1800000000);
});

test('signaux : outil en attente, question, fin de tour, erreur API', async () => {
  const f = tmp();
  fs.writeFileSync(f, [user(0, 'question ?'), tool(1, 'AskUserQuestion', { questions: [] }, 'q1'),
    JSON.stringify({ type: 'system', subtype: 'api_error', timestamp: ts(2), error: { message: 'x' }, retryAttempt: 3 }),
    JSON.stringify({ type: 'system', subtype: 'turn_duration', timestamp: ts(3), durationMs: 1000 }), ''].join('\n'));
  const { c } = await scanAll(f);
  assert.ok(c.pending.q1);
  assert.equal(c.pending.q1.name, 'AskUserQuestion');
  assert.equal(c.errors, 1);
  assert.equal(c.retry, 3);
  assert.ok(c.turnEnd);
  fs.appendFileSync(f, result(4, 'q1', 'réponse') + '\n' + user(5, 'ok vas-y') + '\n');
  await scanFile(f, c, {}, null);
  assert.deepEqual(c.pending, {});
});

test('registre par jour en heure locale', async () => {
  const f = tmp();
  fs.writeFileSync(f, tool(1, 'Bash', { command: 'git commit -m a' }) + '\n');
  const { c } = await scanAll(f);
  const k = dayKey(Date.parse(ts(1)));
  assert.equal(c.tally.days[k].commits, 1);
  assert.equal(c.tally.days[k].or, 1);
  assert.ok(c.tally.days[k].min >= 10);
});

test('unitOf : modèles connus et inconnus', () => {
  assert.equal(unitOf('claude-opus-5-5'), 'chevalier');
  assert.equal(unitOf('claude-sonnet-5-5'), 'soldat');
  assert.equal(unitOf('claude-haiku-5-5'), 'eclaireur');
  assert.equal(unitOf('claude-fable-5-1'), 'mage');
  assert.equal(unitOf('<synthetic>'), 'paysan');
  assert.equal(unitOf('claude-nouveau-6'), 'paysan');
});

test('emptyTally a toutes les clés attendues', () => {
  const t = emptyTally();
  for (const k of ['bois', 'pierre', 'parchemins', 'or', 'commits', 'tests', 'testsOk', 'days']) assert.ok(k in t);
});
