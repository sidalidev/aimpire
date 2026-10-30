// Generates the villager lines once with ElevenLabs, using your own key (ELEVENLABS_API_KEY in the environment or in
// <data folder>/.env). These audio files are not part of the repository: the game runs without them (bubbles only).
// 5 premade English voices from the ElevenLabs library (daemon/voices.js). Existing files are kept (delete the .mp3
// files to regenerate everything). The lines must match godot/audio.gd (same categories, same order).
// Output: godot/assets/voix/<category>_<voice>_<n>.mp3, then `godot --headless --path godot --import` to import them.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const OUT = path.join(path.dirname(new URL(import.meta.url).pathname), '..', 'godot/assets/voix');

import { VOICES, KEY } from '../daemon/voices.js';
export const LINES = {
  travail: ['To work!', 'Right away.', "Let's get to it!", 'Understood.', 'On my way!', 'Here we go.', "Let's go!"],
  fini: ['Done.', 'Work finished!', 'Mission accomplished.', "That's done.", 'All done, chief!'],
  attente: ['Awaiting your orders.', 'Yes?', 'Any instructions?'],
  nouveau: ['Ready to serve!', 'Here I am.', 'At your command!'],
  renfort: ["I'll handle it.", 'Sending backup!', 'On the way!'],
};

if (!KEY) {
  console.error('ELEVENLABS_API_KEY is not set (environment or <data folder>/.env). Nothing generated.');
  process.exit(1);
}
let failed = 0;
fs.mkdirSync(OUT, { recursive: true });
for (const [cat, lines] of Object.entries(LINES)) {
  for (const [v, voice] of VOICES.entries()) {
    for (const [i, text] of lines.entries()) {
      const file = path.join(OUT, `${cat}_${v}_${i}.mp3`);
      if (fs.existsSync(file)) continue;
      const r = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voice}?output_format=mp3_44100_128`, {
        method: 'POST',
        headers: { 'xi-api-key': KEY, 'Content-Type': 'application/json' },
        body: JSON.stringify({ text, model_id: 'eleven_multilingual_v2', voice_settings: { stability: 0.35, similarity_boost: 0.8, style: 0.6 } }),
      });
      if (!r.ok) { failed++; console.error(cat, v, i, r.status, (await r.text()).slice(0, 160)); continue; }
      fs.writeFileSync(file, Buffer.from(await r.arrayBuffer()));
    }
  }
  console.log('ok', cat);
}
if (failed) { console.error(`${failed} line(s) failed`); process.exit(1); }
