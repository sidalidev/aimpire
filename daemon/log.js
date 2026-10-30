// Journal du serveur : <data>/logs/server.log, rotation à 1 Mo × 3, niveau par AIMPIRE_LOG (debug|info|warn|error).
// Règle : on journalise des métadonnées (compteurs, fichiers, durées), jamais le contenu d'une session.
import fs from 'node:fs';
import path from 'node:path';
import { file } from './paths.js';

const LEVELS = { debug: 0, info: 1, warn: 2, error: 3 };
const min = LEVELS[process.env.AIMPIRE_LOG] ?? LEVELS.info;
const DIR = file('logs');
fs.mkdirSync(DIR, { recursive: true });
const LOG = path.join(DIR, 'server.log');
const MAX = 1 << 20;

function rotate() {
  let size = 0; try { size = fs.statSync(LOG).size; } catch {}
  if (size < MAX) return;
  for (let i = 2; i >= 1; i--) { try { fs.renameSync(`${LOG}.${i}`, `${LOG}.${i + 1}`); } catch {} }
  try { fs.renameSync(LOG, `${LOG}.1`); } catch {}
}

function write(level, args) {
  if (LEVELS[level] < min) return;
  const line = `${new Date().toISOString()} ${level.padEnd(5)} ${args.map((a) => (a instanceof Error ? a.message : typeof a === 'string' ? a : JSON.stringify(a))).join(' ')}\n`;
  rotate();
  try { fs.appendFileSync(LOG, line); } catch {}
  if (level === 'error' || level === 'warn') process.stderr.write(line); else process.stdout.write(line);
}

export const log = {
  debug: (...a) => write('debug', a),
  info: (...a) => write('info', a),
  warn: (...a) => write('warn', a),
  error: (...a) => write('error', a),
  path: LOG,
};
