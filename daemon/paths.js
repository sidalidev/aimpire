// Où vivent les données d'AImpire (jamais dans le dossier de l'app, qui est en lecture seule une fois exportée) :
// AIMPIRE_HOME, sinon ~/Library/Application Support/AImpire (macOS), %APPDATA%\AImpire (Windows), $XDG_DATA_HOME/aimpire.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';

export function dataDir() {
  if (process.env.AIMPIRE_HOME) return process.env.AIMPIRE_HOME;
  if (process.platform === 'darwin') return path.join(os.homedir(), 'Library', 'Application Support', 'AImpire');
  if (process.platform === 'win32') return path.join(process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming'), 'AImpire');
  return path.join(process.env.XDG_DATA_HOME || path.join(os.homedir(), '.local', 'share'), 'aimpire');
}
export const DATA = dataDir();
fs.mkdirSync(DATA, { recursive: true });
export const file = (...p) => path.join(DATA, ...p);

// Dossier des journaux Claude Code : CLAUDE_CONFIG_DIR est respecté comme le fait Claude Code lui-même.
export const CLAUDE_DIR = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');

// Écriture atomique : fichier temporaire, fsync, puis renommage. Un crash en cours d'écriture laisse l'ancien fichier intact.
export function writeAtomic(f, data) {
  const tmp = f + '.tmp';
  const fd = fs.openSync(tmp, 'w', 0o600);
  try { fs.writeSync(fd, data); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
  fs.renameSync(tmp, f);
}

export function readJson(f, fallback) {
  try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { return fallback; }
}

// Jeton local exigé sur les routes qui modifient l'état : généré au démarrage, lisible seulement par l'utilisateur (0600).
export function ensureToken() {
  const f = file('token');
  try {
    const t = fs.readFileSync(f, 'utf8').trim();
    if (t.length >= 32) return t;
  } catch {}
  const t = crypto.randomBytes(24).toString('hex');
  writeAtomic(f, t);
  return t;
}

// Petit .env local (ELEVENLABS_API_KEY=…) : jamais dans le dépôt, jamais affiché.
export function readEnvFile() {
  const out = {};
  try {
    for (const l of fs.readFileSync(file('.env'), 'utf8').split('\n')) {
      const m = /^\s*([A-Z0-9_]+)\s*=\s*"?([^"]*)"?\s*$/.exec(l);
      if (m) out[m[1]] = m[2];
    }
  } catch {}
  return out;
}
