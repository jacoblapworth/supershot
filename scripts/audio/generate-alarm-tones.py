#!/usr/bin/env python3
"""Reproduce Supershot's four original tones. No samples or third-party audio."""
import math
from pathlib import Path
import struct
import subprocess
import tempfile
import wave

RATE = 44100
ROOT = Path(__file__).resolve().parents[2]


def envelope(t, duration, attack=0.025, release=0.09):
    return max(0, min(1, t / attack, (duration - t) / release))


def whistle(t):
    duration = 1.6
    phase = 2 * math.pi * 2850 * t - (100 / 24) * math.cos(2 * math.pi * 24 * t)
    return math.sin(phase) * envelope(t, duration)


def horn(t):
    return sum(math.sin(2 * math.pi * f * h * t) / h**1.4
               for f in (220, 277.18, 329.63) for h in range(1, 7)) * envelope(t, 2.1)


def chime(t):
    return sum(math.sin(2 * math.pi * f * t) * math.exp(-t * decay)
               for f, decay in ((880, 2.4), (1320, 3.3), (1760, 4.2))) * envelope(t, 2.8, 0.008, 0.2)


def pulse(t):
    beat = t % 0.5
    return (math.sin(2 * math.pi * 660 * t) + 0.3 * math.sin(2 * math.pi * 1320 * t)) * envelope(beat, 0.25) * envelope(t, 1.8)


for name, duration, synth in (
    ('whistle', 1.6, whistle), ('airHorn', 2.1, horn),
    ('softChime', 2.8, chime), ('electronicPulse', 1.8, pulse),
):
    samples = [synth(i / RATE) for i in range(int(RATE * duration))]
    scale = 0.78 * 32767 / max(abs(value) for value in samples)
    with tempfile.TemporaryDirectory() as temp:
        source = Path(temp) / 'tone.wav'
        with wave.open(str(source), 'wb') as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(RATE)
            output.writeframes(b''.join(struct.pack('<h', round(value * scale)) for value in samples))
        subprocess.run(['afconvert', '-f', 'caff', '-d', 'LEI16', str(source),
                        str(ROOT / 'Supershot' / 'AlarmSounds' / f'alarm-{name}.caf')], check=True)
