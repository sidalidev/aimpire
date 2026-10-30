import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { effacementPermis, viderDonnees } from '../erase.js';

const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'aimpire-erase-'));

test('effacementPermis : dossier propre à AImpire seulement', () => {
  const h = '/home/x';
  assert.equal(effacementPermis('/home/x/Library/Application Support/AImpire', '/home/x/.claude', h), true);
  assert.equal(effacementPermis('/', '/home/x/.claude', h), false);
  assert.equal(effacementPermis('/home/x', '/home/x/.claude', h), false);
  assert.equal(effacementPermis('/home', '/home/x/.claude', h), false);
  assert.equal(effacementPermis('/home/x/.claude', '/home/x/.claude', h), false);
  assert.equal(effacementPermis('/home/x/.claude/projects', '/home/x/.claude', h), false);
  assert.equal(effacementPermis('relatif/AImpire', '/home/x/.claude', h), false);
  assert.equal(effacementPermis('', '/home/x/.claude', h), false);
});

test('viderDonnees : vide le dossier, ne suit pas les liens, ne touche pas au dossier des sessions', () => {
  const racine = tmp();
  const donnees = path.join(racine, 'AImpire'), sessions = path.join(racine, '.claude');
  fs.mkdirSync(path.join(donnees, 'voix-cache'), { recursive: true });
  fs.mkdirSync(path.join(sessions, 'projects'), { recursive: true });
  fs.writeFileSync(path.join(sessions, 'projects', 'a.jsonl'), '{}\n');
  fs.writeFileSync(path.join(donnees, 'save.json'), '{}');
  fs.writeFileSync(path.join(donnees, 'config.json'), '{"sync":{}}');
  fs.writeFileSync(path.join(donnees, '.env'), 'ELEVENLABS_API_KEY=x');
  fs.writeFileSync(path.join(donnees, 'voix-cache', 'a.mp3'), 'x');
  fs.symlinkSync(sessions, path.join(donnees, 'lien'));
  assert.equal(viderDonnees(donnees, sessions, racine + '/maison'), 5);
  assert.deepEqual(fs.readdirSync(donnees), []);
  assert.equal(fs.readFileSync(path.join(sessions, 'projects', 'a.jsonl'), 'utf8'), '{}\n');
  assert.throws(() => viderDonnees(sessions, sessions, racine + '/maison'));
  fs.rmSync(racine, { recursive: true, force: true });
});

test('POST /effacer : jeton exigé, dossier de données vidé, journaux de sessions intacts, serveur arrêté', async () => {
  const racine = tmp();
  const donnees = path.join(racine, 'AImpire'), sessions = path.join(racine, '.claude');
  fs.mkdirSync(path.join(sessions, 'projects', '-x'), { recursive: true });
  fs.writeFileSync(path.join(sessions, 'projects', '-x', 's.jsonl'), '');
  const port = 7800 + Math.floor(Math.random() * 150);
  const serveur = spawn(process.execPath, [path.join(import.meta.dirname, '..', 'server.js')], {
    env: { ...process.env, AIMPIRE_HOME: donnees, CLAUDE_CONFIG_DIR: sessions, AIMPIRE_PORT: String(port), AIMPIRE_LOG: 'error', AIMPIRE_RELAIS: '' },
    stdio: 'ignore',
  });
  const fin = new Promise((r) => serveur.on('exit', r));
  try {
    const base = `http://127.0.0.1:${port}`;
    for (let i = 0; i < 100; i++) {
      try { if ((await fetch(base + '/health')).ok) break; } catch {}
      await new Promise((r) => setTimeout(r, 100));
    }
    assert.equal((await fetch(base + '/effacer', { method: 'POST' })).status, 401);
    const jeton = fs.readFileSync(path.join(donnees, 'token'), 'utf8').trim();
    const r = await fetch(base + '/effacer', { method: 'POST', headers: { Authorization: 'Bearer ' + jeton } });
    assert.equal(r.status, 200);
    assert.equal((await r.json()).ok, true);
    await Promise.race([fin, new Promise((_, ko) => setTimeout(() => ko(new Error('server still running')), 5000))]);
    await new Promise((r) => setTimeout(r, 300));
    assert.deepEqual(fs.readdirSync(donnees), []);
    assert.deepEqual(fs.readdirSync(path.join(sessions, 'projects', '-x')), ['s.jsonl']);
  } finally {
    serveur.kill();
    fs.rmSync(racine, { recursive: true, force: true });
  }
});
