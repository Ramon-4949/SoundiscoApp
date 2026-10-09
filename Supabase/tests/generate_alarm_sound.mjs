import { writeFileSync } from 'node:fs';

const rate = 22050;
const duration = 6;
const samples = rate * duration;
const wav = Buffer.alloc(44 + samples * 2);
wav.write('RIFF', 0);
wav.writeUInt32LE(wav.length - 8, 4);
wav.write('WAVEfmt ', 8);
wav.writeUInt32LE(16, 16);
wav.writeUInt16LE(1, 20);
wav.writeUInt16LE(1, 22);
wav.writeUInt32LE(rate, 24);
wav.writeUInt32LE(rate * 2, 28);
wav.writeUInt16LE(2, 32);
wav.writeUInt16LE(16, 34);
wav.write('data', 36);
wav.writeUInt32LE(samples * 2, 40);
for (let i = 0; i < samples; i++) {
  const t = i / rate;
  const pulse = t % 1;
  const envelope = pulse < 0.65 ? Math.min(1, pulse / 0.025, (0.65 - pulse) / 0.1) : 0;
  const frequency = Math.floor(t) % 2 === 0 ? 660 : 880;
  const sample = envelope * 0.65 * (0.8 * Math.sin(2 * Math.PI * frequency * t)
    + 0.2 * Math.sin(4 * Math.PI * frequency * t));
  wav.writeInt16LE(Math.round(sample * 32767), 44 + i * 2);
}
writeFileSync(new URL('../../SoundiscoApp/milestone_alarm.wav', import.meta.url), wav);
