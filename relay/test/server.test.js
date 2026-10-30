// Tests du relais : écriture avec jeton, refus sans jeton ou avec un mauvais jeton, ETag et 304, long-poll réveillé par
// un PUT, file de commandes, limites, ids invalides, suppression, persistance et purge.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { creerRelais, cleIp, idDuJeton, LIMITES, nomTelechargementValide } from '../server.js';
import { deriveId, deriveWriteToken, encryptJson, decryptJson, genererSecret } from '../../daemon/sync-crypto.js';

const S = '000102030405060708090a0b0c0d0e0f';
const ID = deriveId(S);
const W = deriveWriteToken(S);
const AUTRE_W = deriveWriteToken('ffeeddccbbaa99887766554433221100');

async function demarrer(options = {}) {
  const dossier = options.dossier === undefined ? fs.mkdtempSync(path.join(os.tmpdir(), 'relais-test-')) : options.dossier;
  const relais = creerRelais({ journal: () => {}, ...options, dossier });
  await new Promise((r) => relais.server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${relais.server.address().port}`;
  return { relais, base, dossier, fin: () => relais.fermer() };
}

const entetes = (id = ID, jeton = null, extra = {}) => ({ 'X-AImpire-Id': id, ...(jeton ? { Authorization: 'Bearer ' + jeton } : {}), ...extra });
const blob = (obj = { type: 'etat', ts: Date.now() }) => encryptJson(S, obj, { gzip: true });
const put = (base, corps, jeton = W, id = ID, extra = {}) => fetch(base + '/blob', { method: 'PUT', headers: entetes(id, jeton, extra), body: corps });
const attendreMs = (ms) => new Promise((r) => setTimeout(r, ms));

test('santé et page d\'accueil sans script', async () => {
  const { base, fin } = await demarrer();
  try {
    const h = await (await fetch(base + '/health')).json();
    assert.equal(h.ok, true);
    assert.equal(h.version, '0.6.0');
    assert.equal(h.ids, 0);
    const r = await fetch(base + '/');
    assert.equal(r.status, 200);
    assert.match(r.headers.get('content-security-policy'), /default-src 'none'/);
    assert.equal(r.headers.get('cache-control'), 'no-store');
    const page = await r.text();
    assert.doesNotMatch(page, /<script/i);
    assert.match(page, /Paste/);
  } finally { await fin(); }
});

test('id invalide : 400 sur toutes les routes de données', async () => {
  const { base, fin } = await demarrer();
  try {
    for (const id of ['', 'abc', ID.toUpperCase(), ID + '0', 'g'.repeat(32)]) {
      const r = await fetch(base + '/blob', { headers: id ? { 'X-AImpire-Id': id } : {} });
      assert.equal(r.status, 400, `id « ${id} »`);
    }
    assert.equal((await fetch(base + '/cmd', { method: 'POST', headers: { 'X-AImpire-Id': 'xyz' }, body: blob() })).status, 400);
    assert.equal((await put(base, blob(), W, 'pas-un-id')).status, 400);
  } finally { await fin(); }
});

test('écriture : jeton exigé, première écriture revendique l\'id, mauvais jeton refusé', async () => {
  const { base, fin, relais } = await demarrer({ limites: { putParIdMs: 1 } });
  try {
    assert.equal((await put(base, blob(), null)).status, 401, 'sans jeton');
    assert.equal((await put(base, blob(), 'abc')).status, 401, 'jeton mal formé');
    assert.equal(relais.chaines.size, 0, 'rien de créé sans jeton');
    const b = blob({ type: 'etat', ts: 1, etat: { villages: [] } });
    const r = await put(base, b);
    assert.equal(r.status, 200);
    const corps = await r.json();
    assert.equal(corps.ok, true);
    assert.match(corps.etag, /^"[0-9a-f]{32}"$/);
    assert.equal((await put(base, blob(), AUTRE_W)).status, 401, 'autre jeton sur un id revendiqué');
    assert.equal((await put(base, Buffer.from('pas un blob'))).status, 400, 'blob mal formé');
    assert.equal((await put(base, Buffer.alloc(80, 1))).status, 400, 'longueur incompatible avec AES');
    // Lecture sans jeton : le relais rend le blob tel quel, opaque, que seul S déchiffre.
    const g = await fetch(base + '/blob', { headers: entetes() });
    assert.equal(g.status, 200);
    assert.equal(g.headers.get('etag'), corps.etag);
    assert.ok(Number(g.headers.get('x-aimpire-maj')) > 0);
    assert.equal(g.headers.get('content-type'), 'application/octet-stream');
    const lu = Buffer.from(await g.arrayBuffer());
    assert.deepEqual(lu, b);
    assert.deepEqual(decryptJson(S, lu).etat, { villages: [] });
  } finally { await fin(); }
});

test('ETag : 304 si inchangé, 200 après un nouveau PUT', async () => {
  const { base, fin } = await demarrer({ limites: { putParIdMs: 1 } });
  try {
    const etag = (await (await put(base, blob())).json()).etag;
    const r304 = await fetch(base + '/blob', { headers: entetes(ID, null, { 'If-None-Match': etag }) });
    assert.equal(r304.status, 304);
    assert.equal(r304.headers.get('etag'), etag);
    assert.equal((await fetch(base + '/blob', { headers: entetes(ID, null, { 'If-None-Match': '"autre"' }) })).status, 200);
    await attendreMs(5);
    const etag2 = (await (await put(base, blob({ type: 'etat', ts: 2 }))).json()).etag;
    assert.notEqual(etag2, etag);
    const r = await fetch(base + '/blob', { headers: entetes(ID, null, { 'If-None-Match': etag }) });
    assert.equal(r.status, 200);
    assert.equal(r.headers.get('etag'), etag2);
    assert.equal((await fetch(base + '/blob', { headers: entetes('0'.repeat(32)) })).status, 404, 'id inconnu');
  } finally { await fin(); }
});

test('long-poll : réveillé par un PUT, sinon 304 au bout de wait secondes', async () => {
  const { base, fin } = await demarrer({ limites: { putParIdMs: 1 } });
  try {
    const etag = (await (await put(base, blob({ type: 'etat', ts: 1 }))).json()).etag;
    const t0 = Date.now();
    const attente = fetch(base + '/blob?wait=10', { headers: entetes(ID, null, { 'If-None-Match': etag }) });
    await attendreMs(300);
    const nouveau = blob({ type: 'etat', ts: 2 });
    assert.equal((await put(base, nouveau)).status, 200);
    const r = await attente;
    assert.equal(r.status, 200);
    assert.ok(Date.now() - t0 < 3000, 'réveil immédiat, pas au bout des 10 s');
    assert.deepEqual(Buffer.from(await r.arrayBuffer()), nouveau);
    // Sans PUT : 304 au bout de wait (1 s ici).
    const etag2 = r.headers.get('etag');
    const t1 = Date.now();
    const r2 = await fetch(base + '/blob?wait=1', { headers: entetes(ID, null, { 'If-None-Match': etag2 }) });
    assert.equal(r2.status, 304);
    assert.ok(Date.now() - t1 >= 900, 'a bien attendu');
  } finally { await fin(); }
});

test('long-poll : au plus 4 attentes par id, la cinquième reçoit 304 tout de suite', async () => {
  const { base, fin } = await demarrer({ limites: { putParIdMs: 1 } });
  try {
    const etag = (await (await put(base, blob())).json()).etag;
    const ctl = new AbortController();
    const quatre = Array.from({ length: 4 }, () => fetch(base + '/blob?wait=20', { headers: entetes(ID, null, { 'If-None-Match': etag }), signal: ctl.signal }).catch(() => null));
    await attendreMs(200);
    const t0 = Date.now();
    const r = await fetch(base + '/blob?wait=20', { headers: entetes(ID, null, { 'If-None-Match': etag }) });
    assert.equal(r.status, 304);
    assert.ok(Date.now() - t0 < 1000);
    ctl.abort();
    await Promise.all(quatre);
  } finally { await fin(); }
});

test('file de commandes : ajout sans jeton, lecture avec jeton, ordre conservé, file pleine refusée', async () => {
  const { base, fin } = await demarrer({ limites: { fileCmds: 3 } });
  try {
    const cmd = (n) => encryptJson(S, { type: 'cmd', ts: Date.now(), nonce: String(n).padStart(32, '0'), action: 'reglage', cle: 'privacy', val: 'flou' });
    const post = (corps, id = ID) => fetch(base + '/cmd', { method: 'POST', headers: entetes(id), body: corps });
    assert.equal((await post(cmd(0))).status, 404, 'id encore inconnu');
    await put(base, blob());
    const envoyes = [cmd(1), cmd(2), cmd(3)];
    for (const c of envoyes) assert.equal((await post(c)).status, 202);
    const plein = await post(cmd(4));
    assert.equal(plein.status, 429, 'file pleine');
    assert.ok(plein.headers.get('retry-after'));
    assert.equal((await post(Buffer.from('court'))).status, 400, 'commande mal formée');
    assert.equal((await post(Buffer.alloc(4096 + 49, 1))).status, 413, 'trop grosse');
    assert.equal((await fetch(base + '/cmd', { headers: entetes() })).status, 401, 'lecture sans jeton');
    assert.equal((await fetch(base + '/cmd', { headers: entetes(ID, AUTRE_W) })).status, 401, 'lecture avec un autre jeton');
    const r = await (await fetch(base + '/cmd', { headers: entetes(ID, W) })).json();
    assert.deepEqual(r.cmds.map((b) => Buffer.from(b, 'base64')), envoyes);
    assert.equal(decryptJson(S, Buffer.from(r.cmds[1], 'base64')).nonce, '2'.padStart(32, '0'));
    assert.deepEqual((await (await fetch(base + '/cmd', { headers: entetes(ID, W) })).json()).cmds, [], 'file vidée');
    assert.equal((await post(cmd(5))).status, 202, 'place libérée');
  } finally { await fin(); }
});

test('limites : PUT par seconde, requêtes par IP, nouvelles chaînes par IP, plafond global, taille', async () => {
  let t = 1_000_000;
  const { base, fin } = await demarrer({ maintenant: () => t, limites: { requetesParIp: 12, nouveauxIdsParIp: 2, maxIds: 3, maxBlob: 1024 } });
  try {
    assert.equal((await put(base, blob())).status, 200);
    const r = await put(base, blob());
    assert.equal(r.status, 429, 'deux PUT dans la même seconde');
    assert.ok(Number(r.headers.get('retry-after')) >= 1);
    t += 1000;
    assert.equal((await put(base, blob())).status, 200, 'une seconde plus tard');
    t += 1000;
    assert.equal((await put(base, Buffer.alloc(1024 + 49 + 16, 1))).status, 413, 'blob trop gros');
    // Nouvelles chaînes : 2 par IP (la première comptait déjà)
    const s2 = genererSecret();
    assert.equal((await put(base, encryptJson(s2, {}), deriveWriteToken(s2), deriveId(s2))).status, 200);
    const s3 = genererSecret();
    const r3 = await put(base, encryptJson(s3, {}), deriveWriteToken(s3), deriveId(s3));
    assert.equal(r3.status, 429, 'troisième chaîne pour la même IP');
    // Requêtes par IP : 12 sur la fenêtre, on vient d'en faire 6
    let code = 0, n = 0;
    while (code !== 429 && n < 20) { code = (await fetch(base + '/blob', { headers: entetes() })).status; n++; }
    assert.equal(code, 429);
    assert.equal(n, 7, 'bloqué à la treizième requête');
    assert.equal((await fetch(base + '/health')).status, 200, '/health hors limite');
    t += 5 * 60_000;
    assert.equal((await fetch(base + '/blob', { headers: entetes() })).status, 200, 'fenêtre écoulée');
  } finally { await fin(); }
});

test('revendication : l\'id doit appartenir au jeton présenté (id = H(W))', async () => {
  const { base, fin, relais } = await demarrer();
  try {
    assert.equal(idDuJeton(W), ID);
    // Quelqu'un qui connaît l'id (purgé ou jamais créé) mais pas W ne peut pas le prendre avec son propre jeton.
    assert.equal((await put(base, blob(), AUTRE_W, ID)).status, 401);
    assert.equal(relais.chaines.size, 0);
    assert.equal((await put(base, blob(), W, ID)).status, 200);
  } finally { await fin(); }
});

test('nouvelles chaînes : comptées par /48 en IPv6, plafond global par jour', async () => {
  assert.equal(cleIp('2001:db8:1:2::5'), '2001:db8:1:2::/64');
  assert.equal(cleIp('2001:db8:1:2::5', 3), '2001:db8:1::/48');
  assert.equal(cleIp('2001:db8:1:ffff:1::9', 3), '2001:db8:1::/48');
  assert.equal(cleIp('::ffff:1.2.3.4', 3), '1.2.3.4');
  assert.ok(LIMITES.maxBlob <= 256 * 1024, 'blob plafonné à 256 Kio');
  const nouvelle = async (base, ip) => { const s = genererSecret(); return (await put(base, encryptJson(s, {}), deriveWriteToken(s), deriveId(s), { 'X-Forwarded-For': ip })).status; };
  const a = await demarrer({ confianceProxy: true, limites: { nouveauxIdsParIp: 2, nouveauxIdsTotal: 100 } });
  try {
    assert.equal(await nouvelle(a.base, '2001:db8:1:1::1'), 200);
    assert.equal(await nouvelle(a.base, '2001:db8:1:2::1'), 200, 'autre /64, même /48');
    assert.equal(await nouvelle(a.base, '2001:db8:1:3::1'), 429, 'le /48 a épuisé son quota');
    assert.equal(await nouvelle(a.base, '2001:db8:2:1::1'), 200, 'autre /48');
  } finally { await a.fin(); }
  const b = await demarrer({ confianceProxy: true, limites: { nouveauxIdsParIp: 10, nouveauxIdsTotal: 2 } });
  try {
    assert.equal(await nouvelle(b.base, '1.1.1.1'), 200);
    assert.equal(await nouvelle(b.base, '2.2.2.2'), 200);
    assert.equal(await nouvelle(b.base, '3.3.3.3'), 429, 'plafond global du jour');
  } finally { await b.fin(); }
});

test('plafond global de chaînes : 507', async () => {
  const { base, fin } = await demarrer({ limites: { maxIds: 2 } });
  try {
    for (let i = 0; i < 2; i++) { const s = genererSecret(); assert.equal((await put(base, encryptJson(s, {}), deriveWriteToken(s), deriveId(s))).status, 200); }
    const s = genererSecret();
    assert.equal((await put(base, encryptJson(s, {}), deriveWriteToken(s), deriveId(s))).status, 507);
  } finally { await fin(); }
});

test('derrière un proxy : limites par IP lues dans X-Forwarded-For (dernier saut)', async () => {
  const { base, fin } = await demarrer({ confianceProxy: true, limites: { requetesParIp: 2 } });
  try {
    const g = (ip) => fetch(base + '/', { headers: { 'X-Forwarded-For': `6.6.6.6, ${ip}` } });
    assert.equal((await g('1.1.1.1')).status, 200);
    assert.equal((await g('1.1.1.1')).status, 200);
    assert.equal((await g('1.1.1.1')).status, 429);
    assert.equal((await g('2.2.2.2')).status, 200, 'autre client');
    assert.equal((await g('2001:db8:1:2::5')).status, 200);
    assert.equal((await g('2001:db8:1:2::6')).status, 200);
    assert.equal((await g('2001:db8:1:2:aaaa::7')).status, 429, 'même /64 en IPv6');
  } finally { await fin(); }
});

test('suppression : jeton exigé, blob, file et fichier effacés, attentes libérées', async () => {
  const { base, fin, dossier } = await demarrer();
  try {
    const etag = (await (await put(base, blob())).json()).etag;
    assert.ok(fs.existsSync(path.join(dossier, ID + '.json')));
    const attente = fetch(base + '/blob?wait=10', { headers: entetes(ID, null, { 'If-None-Match': etag }) });
    await attendreMs(150);
    assert.equal((await fetch(base + '/blob', { method: 'DELETE', headers: entetes() })).status, 401);
    assert.equal((await fetch(base + '/blob', { method: 'DELETE', headers: entetes(ID, AUTRE_W) })).status, 401);
    assert.equal((await fetch(base + '/blob', { method: 'DELETE', headers: entetes(ID, W) })).status, 200);
    assert.equal((await attente).status, 404, 'l\'attente en cours apprend la suppression');
    assert.equal((await fetch(base + '/blob', { headers: entetes() })).status, 404);
    assert.equal(fs.existsSync(path.join(dossier, ID + '.json')), false);
    assert.equal((await fetch(base + '/blob', { method: 'DELETE', headers: entetes(ID, W) })).status, 404);
  } finally { await fin(); }
});

test('persistance : un fichier par id rechargé au démarrage, purge après 30 jours sans PUT', async () => {
  let t = Date.now();
  const a = await demarrer({ maintenant: () => t });
  const b = blob();
  await put(a.base, b);
  await a.fin();
  const enregistre = JSON.parse(fs.readFileSync(path.join(a.dossier, ID + '.json'), 'utf8'));
  assert.deepEqual(Object.keys(enregistre).sort(), ['blob', 'empreinte', 'maj']);
  assert.equal(enregistre.empreinte.length, 64);
  assert.ok(!JSON.stringify(enregistre).includes(W), 'W n\'est jamais écrit en clair');
  const r = await demarrer({ dossier: a.dossier, maintenant: () => t });
  try {
    const g = await fetch(r.base + '/blob', { headers: entetes() });
    assert.equal(g.status, 200);
    assert.deepEqual(Buffer.from(await g.arrayBuffer()), b);
    assert.equal((await put(r.base, blob(), AUTRE_W)).status, 401, 'l\'empreinte a survécu au redémarrage');
    t += 31 * 24 * 3600_000;
    r.relais.purger();
    assert.equal((await fetch(r.base + '/blob', { headers: entetes() })).status, 404);
    assert.equal(fs.existsSync(path.join(a.dossier, ID + '.json')), false);
  } finally { await r.fin(); }
});

// --- Mises à jour : /update.json et /download/<fichier> ---

function dossierVersions() {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'versions-test-'));
  fs.writeFileSync(path.join(d, 'update.json'), JSON.stringify({ version: '0.5.0', mac: { url: 'https://aimpire.sidali.dev/download/AImpire-0.5.0-macos.zip', sha256: 'a'.repeat(64) } }));
  fs.writeFileSync(path.join(d, 'AImpire-0.5.0-macos.zip'), Buffer.alloc(3000, 7));
  fs.writeFileSync(path.join(d, 'aimpire-0.5.0.apk'), 'apk');
  fs.writeFileSync(path.join(d, 'secret.txt'), 'non');
  return d;
}

test('noms de fichiers téléchargeables : forme stricte', () => {
  for (const ok of ['AImpire-0.5.0-macos.zip', 'aimpire-0.5.0.apk', 'AImpire-10.20.300-macos.zip']) assert.equal(nomTelechargementValide(ok), true, ok);
  for (const non of ['', 'update.json', 'secret.txt', '../AImpire-0.5.0-macos.zip', 'AImpire-0.5-macos.zip', 'AImpire-0.5.0-macos.zip/',
    'aimpire-0.5.0.apk.idsig', 'AImpire-0.5.0-macos-arm64.zip', 'aimpire-0.5.0.APK', 'aimpire-a.b.c.apk', '.aimpire-0.5.0.apk',
    'aimpire-0.5.0.apk\n', 'aimpire-0..5.0.apk', 'sous/aimpire-0.5.0.apk', 'aimpire-12345.0.0.apk', null, 42]) {
    assert.equal(nomTelechargementValide(non), false, String(non));
  }
});

test('update.json et téléchargements servis depuis le dossier des versions', async () => {
  const versions = dossierVersions();
  const { base, fin } = await demarrer({ versions });
  try {
    const r = await fetch(base + '/update.json');
    assert.equal(r.status, 200);
    assert.match(r.headers.get('content-type'), /application\/json/);
    assert.equal((await r.json()).version, '0.5.0');
    const head = await fetch(base + '/update.json', { method: 'HEAD' });
    assert.equal(head.status, 200);

    const z = await fetch(base + '/download/AImpire-0.5.0-macos.zip');
    assert.equal(z.status, 200);
    assert.equal(z.headers.get('content-type'), 'application/zip');
    assert.equal(z.headers.get('content-length'), '3000');
    assert.match(z.headers.get('content-disposition'), /attachment; filename="AImpire-0.5.0-macos.zip"/);
    assert.equal((await z.arrayBuffer()).byteLength, 3000);
    const a = await fetch(base + '/download/aimpire-0.5.0.apk', { method: 'HEAD' });
    assert.equal(a.status, 200);
    assert.equal(a.headers.get('content-type'), 'application/vnd.android.package-archive');
    assert.equal(a.headers.get('content-length'), '3');

    for (const chemin of ['/download/secret.txt', '/download/update.json', '/download/aimpire-0.6.0.apk', '/download/',
      '/download/..%2Fsecret.txt', '/download/%2e%2e/secret.txt', '/download/sous/aimpire-0.5.0.apk']) {
      const n = await fetch(base + chemin);
      assert.equal(n.status, 404, chemin);
      await n.text();
    }
    const post = await fetch(base + '/download/aimpire-0.5.0.apk', { method: 'POST' });
    assert.equal(post.status, 405);
  } finally { await fin(); }
});

test('liens symboliques refusés, manifeste illisible en 503, rien sans dossier des versions', async () => {
  const versions = dossierVersions();
  const ailleurs = fs.mkdtempSync(path.join(os.tmpdir(), 'ailleurs-'));
  fs.writeFileSync(path.join(ailleurs, 'x'), 'secret');
  fs.symlinkSync(path.join(ailleurs, 'x'), path.join(versions, 'aimpire-0.9.0.apk'));
  const { base, fin } = await demarrer({ versions });
  try {
    assert.equal((await fetch(base + '/download/aimpire-0.9.0.apk')).status, 404);
    fs.writeFileSync(path.join(versions, 'update.json'), '{ pas du json');
    assert.equal((await fetch(base + '/update.json')).status, 503);
    fs.rmSync(path.join(versions, 'update.json'));
    assert.equal((await fetch(base + '/update.json')).status, 404);
  } finally { await fin(); }
  const sans = await demarrer();
  try {
    assert.equal((await fetch(sans.base + '/update.json')).status, 404);
    assert.equal((await fetch(sans.base + '/download/aimpire-0.5.0.apk')).status, 404);
  } finally { await sans.fin(); }
});
