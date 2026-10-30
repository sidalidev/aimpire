// Builds godot/about_texts.gd for the About screen (godot/about.gd) from CHANGELOG.md, PRIVACY.md, SECURITY.md and the
// most recent review in docs/security/. Run by the release scripts; `--check` exits with 1 if the file is out of date (CI).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const lire = (f) => fs.readFileSync(path.join(racine, f), 'utf8');

const revues = fs.readdirSync(path.join(racine, 'docs/security')).filter((f) => /^\d{4}-\d{2}-\d{2}\.md$/.test(f)).sort();
if (!revues.length) throw new Error('no review in docs/security/');
const m = /SHA-256:\s*```\s*([0-9A-Fa-f:]{64,95})\s*```/.exec(lire('SECURITY.md'));
const empreinte = m ? m[1].replace(/:/g, '').toLowerCase() : '';
if (!/^[0-9a-f]{64}$/.test(empreinte)) throw new Error('no SHA-256 signing fingerprint in SECURITY.md');

const contenu = `extends RefCounted
# Built by tools/gen-about.mjs from CHANGELOG.md, PRIVACY.md, SECURITY.md and docs/security/. Do not edit by hand.

const SECURITY_REVIEW := ${JSON.stringify(revues.at(-1).slice(0, 10))}
const SIGNING_SHA256_ANDROID := ${JSON.stringify(empreinte)}
const CHANGELOG := ${JSON.stringify(lire('CHANGELOG.md'))}
const PRIVACY := ${JSON.stringify(lire('PRIVACY.md'))}
`;
const cible = path.join(racine, 'godot/about_texts.gd');
if (process.argv.includes('--check')) {
  const actuel = fs.existsSync(cible) ? fs.readFileSync(cible, 'utf8') : '';
  if (actuel !== contenu) { console.error('godot/about_texts.gd is out of date: run node tools/gen-about.mjs'); process.exit(1); }
  console.log('godot/about_texts.gd is up to date');
} else {
  fs.writeFileSync(cible, contenu);
  console.log(`godot/about_texts.gd: review ${revues.at(-1).slice(0, 10)}, certificate ${empreinte.slice(0, 8)}…${empreinte.slice(-4)}`);
}
