// Actions « vertes » : rien ne consomme de tokens, rien ne parle à Anthropic. Liste blanche fermée, exécution sans shell.
// Le jeu ne lance jamais de tâche ni n'envoie de message à une session : ce serait une action rouge, hors périmètre.
import { execFile } from 'node:child_process';
import fs from 'node:fs';
import { log } from './log.js';

const CLAUDE_BUNDLE = 'com.anthropic.claudefordesktop';

const run = (cmd, args) => new Promise((resolve) => execFile(cmd, args, { timeout: 5000 }, (e) => resolve(!e)));
const isDir = (p) => { try { return fs.statSync(p).isDirectory(); } catch { return false; } };
const isHttp = (u) => /^https:\/\/(github\.com|gitlab\.com|bitbucket\.org)\//.test(String(u || ''));

export const ACTIONS = {
  // ouvrir le dossier du village dans le Finder
  dossier: { cout: 'aucun', run: (b) => (isDir(b.cwd) ? run('open', [b.cwd]) : false) },
  // révéler le journal de la session (lecture seule) dans le Finder
  journal: { cout: 'aucun', run: (b) => (fs.existsSync(b.file) ? run('open', ['-R', b.file]) : false) },
  // un terminal placé dans le dossier (rien n'est tapé dedans)
  terminal: { cout: 'aucun', run: (b) => (isDir(b.cwd) ? run('open', ['-a', 'Terminal', b.cwd]) : false) },
  // la PR de la session, si elle existe (hôtes git connus seulement)
  pr: { cout: 'aucun', run: (b) => (isHttp(b.pr) ? run('open', [b.pr]) : false) },
  // mettre l'app Claude au premier plan (le lien profond vers une session n'est pas connu : on active l'app)
  claude: { cout: 'aucun', run: () => run('open', ['-b', CLAUDE_BUNDLE]) },
};

export async function doAction(kind, b) {
  const a = ACTIONS[kind];
  if (!a || a.cout !== 'aucun') return { ok: false, error: 'unknown action' };
  const ok = await a.run(b);
  log.info('action', kind, ok ? 'ok' : 'refused');
  return { ok };
}
