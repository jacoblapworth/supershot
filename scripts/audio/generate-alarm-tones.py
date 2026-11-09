#!/usr/bin/env python3
"""Original, insistent alarm tones; no Apple recordings or melodies.

Pass --buzzer-source path/to/the-supplied.mp3 to regenerate the edited buzzer.
Without it, regenerate the four synthesized sounds and leave Buzzer intact.
"""
import argparse
import math
from pathlib import Path
import struct
import subprocess
import tempfile
import wave

RATE = 44100
DURATION = 4.5
ROOT = Path(__file__).resolve().parents[2]
# Three brisk groups with a longer final accent, separated by breathing space.
PULSES = ((0.0, 0.16), (0.23, 0.16), (0.46, 0.20), (0.82, 0.40))


def envelope(t, duration, attack=0.004, release=0.018):
    return max(0, min(1, t / attack, (duration - t) / release))


def active_pulse(t):
    beat = t % 1.5
    for index, (start, duration) in enumerate(PULSES):
        if start <= beat < start + duration:
            return index, beat - start, duration
    return None


def whistle(t):
    hit = active_pulse(t)
    if hit is None:
        return 0
    _, local, duration = hit
    phase = 2 * math.pi * 2600 * local - (85 / 32) * math.cos(2 * math.pi * 32 * local)
    return (math.sin(phase) + 0.18 * math.sin(phase * 2)) * envelope(local, duration)


def horn(t):
    hit = active_pulse(t)
    if hit is None:
        return 0
    _, local, duration = hit
    # Bright, slightly beating horn partials retain the sports-signal character.
    return sum(math.sin(2 * math.pi * f * h * local) / h**1.15
               for f in (311.13, 392.0) for h in range(1, 9)) * envelope(local, duration)


def chime(t):
    # A repeating, rising bell figure; shorter tails keep each strike distinct.
    beat = t % 1.5
    result = 0
    for start, frequency in ((0, 987.77), (0.22, 1244.51), (0.44, 1479.98), (0.82, 1244.51)):
        local = beat - start
        if 0 <= local < 0.5:
            tone = sum(math.sin(2 * math.pi * frequency * ratio * local) * weight
                       for ratio, weight in ((1, 1), (2.76, 0.35), (4.08, 0.12)))
            result += tone * math.exp(-local * 9) * envelope(local, 0.5, 0.002, 0.04)
    return result


def pulse(t):
    hit = active_pulse(t)
    if hit is None:
        return 0
    index, local, duration = hit
    # Alternating registers and a longer high accent give a clock-alarm urgency.
    frequency = (880, 1174.66, 880, 1760)[index]
    tone = sum(math.sin(2 * math.pi * frequency * harmonic * local) / harmonic**1.6
               for harmonic in (1, 3, 5, 7))
    return tone * envelope(local, duration)


def buzzer_from_source(source, directory):
    decoded = directory / 'source.wav'
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(source), '-ac', '1',
                    '-ar', str(RATE), '-c:a', 'pcm_s16le', str(decoded)], check=True)
    with wave.open(str(decoded), 'rb') as audio:
        frames = audio.readframes(audio.getnframes())
    samples = struct.unpack(f'<{len(frames) // 2}h', frames)
    # Find a stable audible section instead of repeating the clip's leading silence.
    size = int(0.44 * RATE)
    starts = range(0, len(samples) - size + 1, int(0.02 * RATE))
    offset = max(starts, key=lambda start: sum(value * value for value in samples[start:start + size:32]))
    fragment = samples[offset:offset + size]

    def buzzer(t):
        hit = active_pulse(t)
        if hit is None:
            return 0
        _, local, duration = hit
        return fragment[min(int(local * RATE), len(fragment) - 1)] * envelope(local, duration)

    return buzzer


def write_sound(name, synth, directory):
    samples = [synth(i / RATE) for i in range(int(RATE * DURATION))]
    peak = max(abs(value) for value in samples)
    scale = 0.86 * 32767 / peak
    source = directory / f'{name}.wav'
    with wave.open(str(source), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(b''.join(struct.pack('<h', round(value * scale)) for value in samples))
    subprocess.run(['afconvert', '-f', 'caff', '-d', 'LEI16', str(source),
                    str(ROOT / 'Supershot' / 'AlarmSounds' / f'alarm-{name}.caf')], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--buzzer-source', type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        tones = [('whistle', whistle), ('airHorn', horn), ('softChime', chime), ('electronicPulse', pulse)]
        if args.buzzer_source:
            tones.append(('buzzer', buzzer_from_source(args.buzzer_source, directory)))
        for name, synth in tones:
            write_sound(name, synth, directory)


if __name__ == '__main__':
    main()
