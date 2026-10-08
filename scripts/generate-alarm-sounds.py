#!/usr/bin/env python3
"""Generates the six bundled wake-up sounds (App/ZANO/Sounds/alarm-<id>.wav).

Mono, 16-bit linear PCM at 16 kHz, 20 seconds each (a local notification sound must be under 30s).
Each tone's volume rises over the clip, so it wakes you gently and then insistently. Pure standard
library: no numpy. Run from the repo root:  python3 scripts/generate-alarm-sounds.py
"""
import math
import struct
import wave
from pathlib import Path

RATE = 16000
SECONDS = 20
OUT = Path("App/ZANO/Sounds")

# Note frequencies (Hz)
C5, D5, E5, G5, A5, C6, D6, E6, G6 = 523.25, 587.33, 659.25, 783.99, 880.00, 1046.50, 1174.66, 1318.51, 1567.98
G4, A4, C4, E4 = 392.00, 440.00, 261.63, 329.63


def new_buffer():
    return [0.0] * (RATE * SECONDS)


def add(buf, start, samples, gain=1.0):
    i0 = int(start * RATE)
    for k, v in enumerate(samples):
        j = i0 + k
        if j >= len(buf):
            break
        buf[j] += v * gain


def pluck(freq, dur, decay, harmonics=((1, 1.0),)):
    n = int(dur * RATE)
    out = []
    for k in range(n):
        t = k / RATE
        env = math.exp(-t * decay) * min(1.0, t / 0.004)
        v = sum(a * math.sin(2 * math.pi * freq * h * t) for h, a in harmonics)
        out.append(v * env)
    return out


def bell(freq, dur, decay, index=3.0, ratio=3.5):
    n = int(dur * RATE)
    out = []
    for k in range(n):
        t = k / RATE
        env = math.exp(-t * decay) * min(1.0, t / 0.003)
        mod = index * math.exp(-t * decay * 1.5) * math.sin(2 * math.pi * freq * ratio * t)
        out.append(math.sin(2 * math.pi * freq * t + mod) * env)
    return out


def beep(freq, dur):
    n = int(dur * RATE)
    out = []
    for k in range(n):
        t = k / RATE
        env = min(1.0, t / 0.01, (dur - t) / 0.01)
        v = math.sin(2 * math.pi * freq * t) + 0.3 * math.sin(2 * math.pi * freq * 3 * t)
        out.append(v * env)
    return out


def finish(buf, name):
    total = len(buf)
    peak = max(abs(v) for v in buf) or 1.0
    frames = bytearray()
    for i, v in enumerate(buf):
        progress = i / total
        ramp = 0.25 + 0.75 * (progress ** 0.7)  # soft start, loud finish
        s = max(-1.0, min(1.0, v / peak * 0.9 * ramp))
        frames += struct.pack("<h", int(s * 32767))
    path = OUT / f"alarm-{name}.wav"
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))
    print(path, f"{path.stat().st_size / 1024:.0f} KB")


def daybreak():
    buf = new_buffer()
    phrase = [(C5, 0.0), (E5, 0.5), (G5, 1.0), (C6, 1.5), (G5, 2.4), (E5, 2.9)]
    for rep in range(5):
        for f, t in phrase:
            add(buf, rep * 4.0 + t, pluck(f, 1.6, 2.2, ((1, 1.0), (2, 0.25), (3, 0.08))))
    finish(buf, "daybreak")


def chimes():
    buf = new_buffer()
    seq = [C6, G5, E6, D6, G6, E5, A5, C6]
    for i in range(24):
        add(buf, i * 0.8, bell(seq[i % len(seq)], 2.4, 1.6, index=1.6, ratio=2.76))
    finish(buf, "chimes")


def marimba():
    buf = new_buffer()
    melody = [C5, E5, G5, E5, A5, G5, E5, D5]
    for i in range(60):
        add(buf, i * 0.33, pluck(melody[i % len(melody)], 0.6, 9.0, ((1, 1.0), (4, 0.35), (10, 0.1))))
    finish(buf, "marimba")


def pulse():
    buf = new_buffer()
    for rep in range(14):
        base = rep * 1.4
        for k in range(3):
            add(buf, base + k * 0.22, beep(880.0, 0.14))
    finish(buf, "pulse")


def bells():
    buf = new_buffer()
    for rep in range(8):
        base = rep * 2.5
        add(buf, base, bell(A4, 2.2, 1.3, index=4.0, ratio=1.4))
        add(buf, base + 1.1, bell(E5, 2.2, 1.3, index=4.0, ratio=1.4))
    finish(buf, "bells")


def ripple():
    buf = new_buffer()
    notes = [C5, D5, E5, G5, A5, C6, A5, G5, E5, D5]
    for i in range(120):
        add(buf, i * 0.16, pluck(notes[i % len(notes)], 0.45, 8.0, ((1, 1.0), (2, 0.3))))
    finish(buf, "ripple")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for fn in (daybreak, chimes, marimba, pulse, bells, ripple):
        fn()
