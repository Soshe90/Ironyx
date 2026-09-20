#!/usr/bin/env python3
"""Synthesize the timer's audio cues into assets/audio/.

The three cues are plain sine tones (with a touch of second harmonic and a
short envelope so they read as a soft "ping" rather than a raw beep). They
are generated here, from nothing, rather than taken from a sound library —
that is what makes them ours outright (see ASSETS-LICENSE.md) and what makes
the files reproducible: the output is deterministic, so re-running this
script leaves the repository unchanged.

    countdown.wav   one short tick, played on each of the last three seconds
    transition.wav  two rising notes, played when a work/rest phase changes
    complete.wav    three rising notes, played when the whole session ends

Usage (from the repository root):

    python3 scripts/build_timer_cues.py

Standard library only. Output is 16-bit mono PCM at 44.1 kHz.
"""

from __future__ import annotations

import math
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44_100
PEAK = 0.7  # of full scale; leaves headroom so ducked music is not clipped
OUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "audio"

ATTACK_S = 0.006
GAP_S = 0.025


def note(freq_hz: float, length_s: float) -> list[float]:
    """One enveloped note: fast attack, smooth cosine decay to silence."""
    n = int(SAMPLE_RATE * length_s)
    attack = max(1, int(SAMPLE_RATE * ATTACK_S))
    samples: list[float] = []
    for i in range(n):
        t = i / SAMPLE_RATE
        tone = math.sin(2 * math.pi * freq_hz * t) + 0.25 * math.sin(
            2 * math.pi * 2 * freq_hz * t
        )
        tone /= 1.25  # keep the sum within [-1, 1]
        rise = min(1.0, i / attack)
        fall = 0.5 * (1 + math.cos(math.pi * i / n))  # 1 -> 0 over the note
        samples.append(tone * rise * fall)
    return samples


def silence(length_s: float) -> list[float]:
    return [0.0] * int(SAMPLE_RATE * length_s)


def write_wav(name: str, samples: list[float]) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / name
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s)) * PEAK * 32767))
        for s in samples
    )
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(frames)
    print(f"{path.relative_to(OUT_DIR.parent.parent)}  "
          f"{len(samples) / SAMPLE_RATE:.2f}s  {path.stat().st_size} bytes")


def main() -> None:
    write_wav("countdown.wav", note(880.0, 0.12))
    write_wav(
        "transition.wav",
        note(660.0, 0.11) + silence(GAP_S) + note(990.0, 0.20),
    )
    write_wav(
        "complete.wav",
        note(660.0, 0.14)
        + silence(GAP_S)
        + note(880.0, 0.14)
        + silence(GAP_S)
        + note(1320.0, 0.34),
    )


if __name__ == "__main__":
    main()
