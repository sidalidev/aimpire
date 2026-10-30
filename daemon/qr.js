// Encodeur QR minimal, sans dépendance (ISO/IEC 18004) : mode octets, correction M, version la plus petite qui convient
// (1 à 40), masque choisi par les pénalités de la norme. Sert à afficher le lien de la chaîne de sync dans les réglages.
// Algorithme repris de la bibliothèque « QR Code generator » de Project Nayuki (licence MIT), réécrit et réduit au
// strict nécessaire : un seul segment en octets, un seul niveau de correction.

// Niveau M : octets de correction par bloc et nombre de blocs, par version (index 0 inutilisé).
const ECC_PAR_BLOC = [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28];
const NB_BLOCS = [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49];
const BITS_FORMAT_M = 0;   // indicateur de niveau dans les bits de format : L=1, M=0, Q=3, H=2

const bit = (x, i) => ((x >>> i) & 1) !== 0;

/** Nombre de modules disponibles pour les données et la correction (hors motifs fixes). */
function modulesBruts(ver) {
  let r = (16 * ver + 128) * ver + 64;
  if (ver >= 2) {
    const n = Math.floor(ver / 7) + 2;
    r -= (25 * n - 10) * n - 55;
    if (ver >= 7) r -= 36;
  }
  return r;
}
const octetsDonnees = (ver) => Math.floor(modulesBruts(ver) / 8) - ECC_PAR_BLOC[ver] * NB_BLOCS[ver];

// --- Reed-Solomon sur GF(2^8), polynôme 0x11D ---
function mul(x, y) {
  let z = 0;
  for (let i = 7; i >= 0; i--) {
    z = (z << 1) ^ ((z >>> 7) * 0x11d);
    z ^= ((y >>> i) & 1) * x;
  }
  return z;
}
function diviseur(degre) {
  const r = new Array(degre).fill(0);
  r[degre - 1] = 1;
  let racine = 1;
  for (let i = 0; i < degre; i++) {
    for (let j = 0; j < r.length; j++) {
      r[j] = mul(r[j], racine);
      if (j + 1 < r.length) r[j] ^= r[j + 1];
    }
    racine = mul(racine, 0x02);
  }
  return r;
}
function reste(donnees, div) {
  const r = div.map(() => 0);
  for (const b of donnees) {
    const f = b ^ r.shift();
    r.push(0);
    div.forEach((c, i) => { r[i] ^= mul(c, f); });
  }
  return r;
}

/** Découpe en blocs, ajoute la correction et entrelace (norme §7.6). */
function avecCorrection(donnees, ver) {
  const nb = NB_BLOCS[ver], ecc = ECC_PAR_BLOC[ver];
  const total = Math.floor(modulesBruts(ver) / 8);
  const courts = nb - (total % nb);
  const longueurCourte = Math.floor(total / nb);
  const div = diviseur(ecc);
  const blocs = [];
  for (let i = 0, k = 0; i < nb; i++) {
    const d = donnees.slice(k, k + longueurCourte - ecc + (i < courts ? 0 : 1));
    k += d.length;
    const e = reste(d, div);
    if (i < courts) d.push(0);
    blocs.push(d.concat(e));
  }
  const out = [];
  for (let i = 0; i < blocs[0].length; i++) {
    blocs.forEach((b, j) => { if (i !== longueurCourte - ecc || j >= courts) out.push(b[i]); });
  }
  return out;
}

/** Positions des motifs d'alignement pour une version. */
function alignements(ver, taille) {
  if (ver === 1) return [];
  const n = Math.floor(ver / 7) + 2;
  const pas = Math.floor((ver * 8 + n * 3 + 5) / (n * 4 - 4)) * 2;
  const r = [6];
  for (let pos = taille - 7; r.length < n; pos -= pas) r.splice(1, 0, pos);
  return r;
}

/**
 * Encode du texte (UTF-8) en QR. Renvoie { version, taille, masque, modules } où modules[y][x] vaut true pour un module
 * sombre. Pas de zone de silence : à l'affichage, laisser 4 modules clairs tout autour.
 */
export function encoderQr(texte) {
  const octets = [...Buffer.from(String(texte), 'utf8')];
  // Version minimale : 4 bits de mode, 8 ou 16 bits de longueur, puis les octets.
  let ver = 1;
  for (; ver <= 40; ver++) {
    const bitsLongueur = ver < 10 ? 8 : 16;
    if (octets.length < 2 ** bitsLongueur && 4 + bitsLongueur + 8 * octets.length <= octetsDonnees(ver) * 8) break;
  }
  if (ver > 40) throw new Error('Text too long for a QR code');
  const capacite = octetsDonnees(ver) * 8;
  const bits = [];
  const ajouter = (val, n) => { for (let i = n - 1; i >= 0; i--) bits.push((val >>> i) & 1); };
  ajouter(0b0100, 4);                                 // mode octets
  ajouter(octets.length, ver < 10 ? 8 : 16);
  for (const o of octets) ajouter(o, 8);
  ajouter(0, Math.min(4, capacite - bits.length));    // terminateur
  ajouter(0, (8 - (bits.length % 8)) % 8);            // alignement sur l'octet
  for (let p = 0xec; bits.length < capacite; p ^= 0xec ^ 0x11) ajouter(p, 8);   // remplissage 0xEC, 0x11…
  const donnees = [];
  for (let i = 0; i < bits.length; i += 8) donnees.push(parseInt(bits.slice(i, i + 8).join(''), 2));

  const taille = ver * 4 + 17;
  const m = Array.from({ length: taille }, () => new Array(taille).fill(false));
  const fixe = Array.from({ length: taille }, () => new Array(taille).fill(false));
  const poser = (x, y, sombre) => { m[y][x] = sombre; fixe[y][x] = true; };

  // Motifs fixes : rythme, repères de position, alignements, format (réservé), version.
  for (let i = 0; i < taille; i++) { poser(6, i, i % 2 === 0); poser(i, 6, i % 2 === 0); }
  for (const [cx, cy] of [[3, 3], [taille - 4, 3], [3, taille - 4]]) {
    for (let dy = -4; dy <= 4; dy++) for (let dx = -4; dx <= 4; dx++) {
      const d = Math.max(Math.abs(dx), Math.abs(dy)), x = cx + dx, y = cy + dy;
      if (x >= 0 && x < taille && y >= 0 && y < taille) poser(x, y, d !== 2 && d !== 4);
    }
  }
  const al = alignements(ver, taille);
  for (let i = 0; i < al.length; i++) for (let j = 0; j < al.length; j++) {
    if ((i === 0 && j === 0) || (i === 0 && j === al.length - 1) || (i === al.length - 1 && j === 0)) continue;
    for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) poser(al[i] + dx, al[j] + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
  }
  const format = (masque) => {
    const d = (BITS_FORMAT_M << 3) | masque;
    let r = d;
    for (let i = 0; i < 10; i++) r = (r << 1) ^ ((r >>> 9) * 0x537);
    const b = ((d << 10) | r) ^ 0x5412;
    for (let i = 0; i <= 5; i++) poser(8, i, bit(b, i));
    poser(8, 7, bit(b, 6)); poser(8, 8, bit(b, 7)); poser(7, 8, bit(b, 8));
    for (let i = 9; i < 15; i++) poser(14 - i, 8, bit(b, i));
    for (let i = 0; i < 8; i++) poser(taille - 1 - i, 8, bit(b, i));
    for (let i = 8; i < 15; i++) poser(8, taille - 15 + i, bit(b, i));
    poser(8, taille - 8, true);   // module toujours sombre
  };
  format(0);
  if (ver >= 7) {
    let r = ver;
    for (let i = 0; i < 12; i++) r = (r << 1) ^ ((r >>> 11) * 0x1f25);
    const b = (ver << 12) | r;
    for (let i = 0; i < 18; i++) {
      const a = taille - 11 + (i % 3), c = Math.floor(i / 3);
      poser(a, c, bit(b, i)); poser(c, a, bit(b, i));
    }
  }

  // Données en zigzag, colonnes de deux modules, de droite à gauche.
  const flux = avecCorrection(donnees, ver);
  let i = 0;
  for (let droite = taille - 1; droite >= 1; droite -= 2) {
    if (droite === 6) droite = 5;
    for (let v = 0; v < taille; v++) for (let j = 0; j < 2; j++) {
      const x = droite - j, montant = ((droite + 1) & 2) === 0, y = montant ? taille - 1 - v : v;
      if (!fixe[y][x] && i < flux.length * 8) { m[y][x] = bit(flux[i >>> 3], 7 - (i & 7)); i++; }
    }
  }

  const masquer = (k) => {
    for (let y = 0; y < taille; y++) for (let x = 0; x < taille; x++) {
      let inv;
      switch (k) {
        case 0: inv = (x + y) % 2 === 0; break;
        case 1: inv = y % 2 === 0; break;
        case 2: inv = x % 3 === 0; break;
        case 3: inv = (x + y) % 3 === 0; break;
        case 4: inv = (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0; break;
        case 5: inv = ((x * y) % 2) + ((x * y) % 3) === 0; break;
        case 6: inv = (((x * y) % 2) + ((x * y) % 3)) % 2 === 0; break;
        default: inv = (((x + y) % 2) + ((x * y) % 3)) % 2 === 0;
      }
      if (!fixe[y][x] && inv) m[y][x] = !m[y][x];
    }
  };

  let meilleur = 0, min = Infinity;
  for (let k = 0; k < 8; k++) {
    masquer(k); format(k);
    const p = penalite(m, taille);
    if (p < min) { min = p; meilleur = k; }
    masquer(k);   // le masque est un ou exclusif : le réappliquer l'annule
  }
  masquer(meilleur); format(meilleur);
  return { version: ver, taille, masque: meilleur, modules: m };
}

// Pénalités de la norme (§7.8.3) : séries de 5 et plus, carrés 2×2, motifs proches des repères, déséquilibre clair/sombre.
function penalite(m, taille) {
  let r = 0;
  const ajouterHisto = (n, h) => { if (h[0] === 0) n += taille; h.pop(); h.unshift(n); };
  const motifs = (h) => {
    const n = h[1];
    const coeur = n > 0 && h[2] === n && h[3] === n * 3 && h[4] === n && h[5] === n;
    return (coeur && h[0] >= n * 4 && h[6] >= n ? 1 : 0) + (coeur && h[6] >= n * 4 && h[0] >= n ? 1 : 0);
  };
  const terminer = (couleur, n, h) => { if (couleur) { ajouterHisto(n, h); n = 0; } ajouterHisto(n + taille, h); return motifs(h); };
  for (const lire of [(a, b) => m[a][b], (a, b) => m[b][a]]) {
    for (let a = 0; a < taille; a++) {
      let couleur = false, n = 0;
      const h = [0, 0, 0, 0, 0, 0, 0];
      for (let b = 0; b < taille; b++) {
        if (lire(a, b) === couleur) {
          n++;
          if (n === 5) r += 3; else if (n > 5) r++;
        } else {
          ajouterHisto(n, h);
          if (!couleur) r += motifs(h) * 40;
          couleur = lire(a, b);
          n = 1;
        }
      }
      r += terminer(couleur, n, h) * 40;
    }
  }
  let sombres = 0;
  for (let y = 0; y < taille; y++) for (let x = 0; x < taille; x++) {
    if (m[y][x]) sombres++;
    if (y < taille - 1 && x < taille - 1) {
      const c = m[y][x];
      if (c === m[y][x + 1] && c === m[y + 1][x] && c === m[y + 1][x + 1]) r += 3;
    }
  }
  const total = taille * taille;
  r += (Math.ceil(Math.abs(sombres * 20 - total * 10) / total) - 1) * 10;
  return r;
}

/** Forme servie par GET /sync : une chaîne de « 0 » et « 1 » par ligne (1 = sombre), sans zone de silence. */
export function qrEnLignes(texte) {
  const q = encoderQr(texte);
  return { taille: q.taille, version: q.version, modules: q.modules.map((l) => l.map((c) => (c ? '1' : '0')).join('')) };
}
