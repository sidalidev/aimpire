// Tests de l'encodeur QR (daemon/qr.js). Le décodage réel a été vérifié hors de Node (CoreImage de macOS et OpenCV) ;
// ici on vérifie la structure (version, repères, bits de format) et on fige la matrice du lien de référence.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { encoderQr, qrEnLignes } from '../qr.js';

const LIEN = 'https://aimpire.sidali.dev/#s=AAECAwQFBgcICQoLDA0ODw';

test('version minimale au niveau M', () => {
  assert.equal(encoderQr('A').version, 1);
  assert.equal(encoderQr('x'.repeat(14)).version, 1);    // 14 octets : capacité de la version 1-M
  assert.equal(encoderQr('x'.repeat(15)).version, 2);
  assert.equal(encoderQr(LIEN).version, 4);               // 52 octets
  assert.equal(encoderQr('x'.repeat(62)).version, 4);
  assert.equal(encoderQr('x'.repeat(63)).version, 5);
  assert.equal(encoderQr('x'.repeat(2331)).version, 40);
  assert.throws(() => encoderQr('x'.repeat(2332)));
});

test('repères de position, rythme et module sombre', () => {
  const q = encoderQr(LIEN);
  const n = q.taille;
  assert.equal(n, 33);
  const m = q.modules;
  for (const [x0, y0] of [[0, 0], [n - 7, 0], [0, n - 7]]) {
    for (let y = 0; y < 7; y++) for (let x = 0; x < 7; x++) {
      const d = Math.max(Math.abs(x - 3), Math.abs(y - 3));
      assert.equal(m[y0 + y][x0 + x], d !== 2, `repère (${x0},${y0}) module ${x},${y}`);
    }
  }
  for (let i = 8; i < n - 8; i++) { assert.equal(m[6][i], i % 2 === 0); assert.equal(m[i][6], i % 2 === 0); }
  assert.equal(m[n - 8][8], true);
});

test('bits de format : niveau M et masque annoncé, deux copies identiques', () => {
  for (const texte of ['A', LIEN, 'Bonjour é à ü '.repeat(10), 'z'.repeat(300)]) {
    const q = encoderQr(texte);
    const m = q.modules, n = q.taille;
    const a = [], b = [];
    for (let i = 0; i <= 5; i++) a.push(m[i][8]);
    a.push(m[7][8], m[8][8], m[8][7]);
    for (let i = 9; i < 15; i++) a.push(m[8][14 - i]);
    for (let i = 0; i < 8; i++) b.push(m[8][n - 1 - i]);
    for (let i = 8; i < 15; i++) b.push(m[n - 15 + i][8]);
    assert.deepEqual(a, b);
    const bits = a.reduce((acc, v, i) => acc | ((v ? 1 : 0) << i), 0) ^ 0x5412;
    assert.equal(bits >> 13, 0, 'niveau M (00)');
    assert.equal((bits >> 10) & 7, q.masque);
  }
});

test('matrice figée du lien de référence (décodée par CoreImage et OpenCV)', () => {
  const q = qrEnLignes(LIEN);
  assert.equal(q.taille, 33);
  assert.equal(q.modules.length, 33);
  const h = createHash('sha256').update(q.modules.join('\n')).digest('hex');
  assert.equal(h, EMPREINTE_LIEN);
});

const EMPREINTE_LIEN = '9aab85583733b2205cc460d8745e89e730901f199ef1137fc5b67e4fb9eeb53d';
