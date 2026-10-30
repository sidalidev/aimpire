// ElevenLabs voices of the villagers: 5 premade English voices (Adam, Antoni, Arnold, Rachel, Domi).
// Clé : ELEVENLABS_API_KEY dans l'environnement ou dans <données>/.env. Jamais dans le dépôt, jamais journalisée.
// Les voix détaillées envoient du texte de session à un tiers : désactivées tant que AIMPIRE_VOIX=1 n'est pas posé (env ou .env).
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { file, readEnvFile } from './paths.js';

const env = { ...readEnvFile(), ...process.env };
export const KEY = env.ELEVENLABS_API_KEY || '';
export const voicesEnabled = () => !!KEY && env.AIMPIRE_VOIX === '1';
export const VOICES = [
  'pNInz6obpgDQGcFmaJgB', // Adam, grave
  'ErXwobaYiN019PkySvjV', // Antoni, chaleureux
  'VR6AewLTigWG4xSOukaG', // Arnold, solennel
  '21m00Tcm4TlvDq8ikWAM', // Rachel, posée
  'AZnzlk1XvdvUeBnXmlld', // Domi, vive
];

// Synthèse à la demande, cache disque (nom = sha256, jamais le texte), plafond quotidien (AIMPIRE_TTS_MAX_JOUR, 4000), 50 Mo max.
const CACHE = file('voix-cache');
fs.mkdirSync(CACHE, { recursive: true });
const MAX = Number(env.AIMPIRE_TTS_MAX_JOUR || 4000);
const CACHE_MAX = 50 << 20;
let day = '', used = 0;

function purge() {
  let files = [];
  try { files = fs.readdirSync(CACHE).map((f) => { const p = path.join(CACHE, f); const st = fs.statSync(p); return { p, size: st.size, t: st.mtimeMs }; }); } catch { return; }
  let total = files.reduce((a, f) => a + f.size, 0);
  for (const f of files.sort((a, b) => a.t - b.t)) { if (total <= CACHE_MAX) break; try { fs.unlinkSync(f.p); total -= f.size; } catch {} }
}

export async function speak(text, v) {
  const clean = String(text).slice(0, 120);
  const voice = VOICES[Math.abs(Number(v) || 0) % VOICES.length];
  const f = path.join(CACHE, crypto.createHash('sha256').update(voice + '|' + clean).digest('hex') + '.mp3');
  if (fs.existsSync(f)) return fs.readFileSync(f);
  if (!voicesEnabled()) return null;
  const today = new Date().toLocaleDateString('sv');
  if (today !== day) { day = today; used = 0; }
  if (used + clean.length > MAX) return null;
  used += clean.length;
  const r = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voice}?output_format=mp3_44100_64`, {
    method: 'POST',
    headers: { 'xi-api-key': KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ text: clean, model_id: 'eleven_multilingual_v2', voice_settings: { stability: 0.4, similarity_boost: 0.8, style: 0.5 } }),
  });
  if (!r.ok) return null;
  const buf = Buffer.from(await r.arrayBuffer());
  fs.writeFileSync(f, buf);
  purge();
  return buf;
}
