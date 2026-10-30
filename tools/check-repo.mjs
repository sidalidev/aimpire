// Repository checks run by the CI (and by tools/release-android.sh with the built APK):
//   1. Android permissions: those enabled in godot/export_presets.cfg (and, given an APK, those of the APK through
//      `aapt2 dump permissions`) must all be listed in docs/permissions.txt.
//   2. Tracked files: no long or en dashes, authorship markers, assistant files, personal paths or addresses,
//      third-party game names or voice mp3; LICENSE and relay/LICENSE present.
//   3. The latest review in docs/security/ is less than 6 months old.
//   4. The versions agree (project.godot, export preset, daemon) and CHANGELOG.md has an entry for that version.
//   5. godot/about_texts.gd is up to date with its sources.
// Usage: node tools/check-repo.mjs [path/to/app.apk]
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const lire = (f) => fs.readFileSync(path.join(racine, f), 'utf8');
const erreurs = [];
const ok = (m) => console.log('ok   ' + m);
const ko = (m) => { erreurs.push(m); console.error('FAIL ' + m); };

// 1. Permissions
const attendues = new Set(lire('docs/permissions.txt').split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#')));
const presets = lire('godot/export_presets.cfg');
const android = presets.split(/^\[preset\.\d+\]$/m).find((s) => /^platform="Android"$/m.test(s)) || '';
const options = presets.split(/^\[preset\.\d+\.options\]$/m).find((s) => /^permissions\/internet=/m.test(s)) || '';
if (!android || !options) ko('Android preset not found in godot/export_presets.cfg');
const duPreset = [];
for (const [, nom] of options.matchAll(/^permissions\/([a-z0-9_]+)=true$/gm)) duPreset.push('android.permission.' + nom.toUpperCase());
const custom = /^permissions\/custom_permissions=PackedStringArray\((.*)\)$/m.exec(options);
for (const [, nom] of (custom ? custom[1] : '').matchAll(/"([^"]+)"/g)) duPreset.push(nom);
const enTrop = duPreset.filter((p) => !attendues.has(p));
if (enTrop.length) ko(`export preset requests unlisted permissions: ${enTrop.join(', ')}`);
else ok(`export preset permissions: ${duPreset.join(', ') || 'none'}`);
const apk = process.argv[2];
if (apk) {
  const sdk = process.env.ANDROID_HOME || path.join(process.env.HOME || '', 'Library/Android/sdk');
  const outils = fs.existsSync(path.join(sdk, 'build-tools')) ? fs.readdirSync(path.join(sdk, 'build-tools')).sort() : [];
  const aapt2 = outils.length ? path.join(sdk, 'build-tools', outils.at(-1), 'aapt2') : 'aapt2';
  const r = spawnSync(aapt2, ['dump', 'permissions', apk], { encoding: 'utf8' });
  if (r.status !== 0) ko(`aapt2 dump permissions failed on ${apk}`);
  else {
    const duApk = [...r.stdout.matchAll(/uses-permission(?:-sdk-23)?: name='([^']+)'/g)].map((m) => m[1]);
    const apkEnTrop = duApk.filter((p) => !attendues.has(p));
    if (apkEnTrop.length) ko(`APK requests unlisted permissions: ${apkEnTrop.join(', ')}`);
    else ok(`APK permissions: ${duApk.join(', ') || 'none'}`);
  }
}

// 2. Forbidden text. The game shows coding sessions of a tool whose name is "Claude Code": that name is allowed only in
// the files that describe or read those sessions. Authorship markers are refused everywhere.
const grep = (args) => {
  const r = spawnSync('git', ['grep', '-n', '-I', ...args], { cwd: racine, encoding: 'utf8' });
  return r.status === 0 ? r.stdout.trim().split('\n') : [];
};
const ceFichier = ':!tools/check-repo.mjs';
const tirets = grep(['-e', '—', '-e', '–', '--', '.', ceFichier]);
if (tirets.length) ko(`long or en dash:\n  ${tirets.slice(0, 20).join('\n  ')}`); else ok('no long or en dash');
const marqueurs = grep(['-i', '-E', '-e', 'co-authored-by', '-e', 'generated (by|with) (ai|claude)', '-e', 'noreply@anthropic', '-e', 'written by (ai|claude)', '--', '.', ceFichier]);
if (marqueurs.length) ko(`authorship marker:\n  ${marqueurs.slice(0, 20).join('\n  ')}`); else ok('no authorship marker');
const SUJET = ['daemon/', 'godot/hud.gd', 'godot/person.gd', 'README.md', 'skills/'];
const nom = grep(['-w', 'Claude', '--', '.', ceFichier, ...SUJET.map((p) => ':!' + p)]);
if (nom.length) ko(`"Claude" outside the files that read or describe sessions:\n  ${nom.slice(0, 20).join('\n  ')}`); else ok('no AI mention outside the session files');
const suivis = execFileSync('git', ['ls-files'], { cwd: racine, encoding: 'utf8' }).split('\n');
const interdits = suivis.filter((f) => /(^|\/)(CLAUDE\.md|AGENTS\.md|\.claude\/|\.cursor(\/|rules$|$)|NUIT-)/i.test(f));
if (interdits.length) ko(`tracked assistant files: ${interdits.join(', ')}`); else ok('no assistant files tracked');
// "/Users/" is matched with its case (tests use lowercased fake paths); the rest in any case.
const PERSO = ['/users/sidali', '/home/sid', 'dockerbop', 'mybops', '@gmail.com', 'lector-vault'];
const chemins = [...new Set([
  ...grep(['-F', '-e', '/Users/', '--', '.', ceFichier]),
  ...grep(['-i', '-F', ...PERSO.flatMap((m) => ['-e', m]), '--', '.', ceFichier]),
])];
if (chemins.length) ko(`personal path or address:\n  ${chemins.slice(0, 20).join('\n  ')}`); else ok('no personal path or address');
const MARQUES = ['Clash of Clans', 'Age of Empires', 'Supercell'];
const marques = grep(['-i', '-F', ...MARQUES.flatMap((m) => ['-e', m]), '--', '.', ceFichier]);
if (marques.length) ko(`third-party game name:\n  ${marques.slice(0, 20).join('\n  ')}`); else ok('no third-party game name');
const licences = ['LICENSE', 'relay/LICENSE'].filter((f) => !suivis.includes(f));
if (licences.length) ko(`missing license file: ${licences.join(', ')}`); else ok('LICENSE and relay/LICENSE present');
const voix = suivis.filter((f) => /^godot\/assets\/voix\/.*\.mp3(\.import)?$/.test(f));
if (voix.length) ko(`${voix.length} voice file(s) tracked under godot/assets/voix/ (generated locally by tools/gen-voices.mjs)`);
else ok('no voice mp3 tracked');

// 3. Security review age
const revues = fs.readdirSync(path.join(racine, 'docs/security')).filter((f) => /^\d{4}-\d{2}-\d{2}\.md$/.test(f)).sort();
if (!revues.length) ko('no security review in docs/security/');
else {
  const jours = (Date.now() - Date.parse(revues.at(-1).slice(0, 10) + 'T00:00:00Z')) / 86400000;
  if (jours > 183) ko(`latest security review ${revues.at(-1)} is ${Math.floor(jours)} days old (6 months at most)`);
  else ok(`latest security review ${revues.at(-1)} (${Math.max(0, Math.floor(jours))} days old)`);
}

// 4. Versions and changelog
const version = (/^version\/name="([^"]+)"$/m.exec(presets) || [])[1] || '';
const versions = {
  'export preset version/name': version,
  'export preset application/version': (/^application\/version="([^"]+)"$/m.exec(presets) || [])[1],
  'project.godot config/version': (/^config\/version="([^"]+)"$/m.exec(lire('godot/project.godot')) || [])[1],
  'daemon/config.js VERSION': (/VERSION = '([^']+)'/.exec(lire('daemon/config.js')) || [])[1],
};
const differentes = Object.entries(versions).filter(([, v]) => v !== version);
if (!version || differentes.length) ko(`versions disagree: ${JSON.stringify(versions)}`); else ok(`version ${version} everywhere`);
if (!lire('CHANGELOG.md').split('\n').some((l) => l.startsWith(`## ${version} (`))) ko(`CHANGELOG.md has no "## ${version} (" entry`);
else ok(`CHANGELOG.md has an entry for ${version}`);

// 5. Embedded About texts
const gen = spawnSync(process.execPath, [path.join(racine, 'tools/gen-about.mjs'), '--check'], { encoding: 'utf8' });
if (gen.status !== 0) ko((gen.stderr || gen.stdout).trim()); else ok('godot/about_texts.gd up to date');

if (erreurs.length) { console.error(`\n${erreurs.length} check(s) failed`); process.exit(1); }
console.log('\nall checks passed');
