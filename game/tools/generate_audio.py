"""Generate four compact, original, reproducible mono PCM combat sounds."""

import argparse
import hashlib
import math
import random
import struct
import sys
import wave
from pathlib import Path


RATE = 22050
SOUNDS = {"cannon": (.65, 707, .8), "impact": (.30, 708, .8),
          "splash": (.55, 709, .8), "sea": (8.0, 710, .25)}


def samples(name, duration, seed, peak):
    rng = random.Random(seed)
    count = round(duration * RATE)
    sea = name == "sea"
    values = []
    lp = 0.0
    body = 0.0
    rumble = 0.0
    for i in range(count + (round(.25 * RATE) if sea else 0)):
        t = i / RATE
        u = t / duration
        n = rng.uniform(-1.0, 1.0)
        lp += .08 * (n - lp)
        if name == "cannon":
            # Broadband ignition crack, turbulent low body, falling resonances,
            # and two diffuse reflections; no sampled third-party material.
            body += .025 * (n - body)
            rumble += .004 * (n - rumble)
            attack = (n - lp) * math.exp(-95 * t) * .9
            pressure = body * math.exp(-8 * t) * 5.0
            low = rumble * math.exp(-6 * t) * 4.0
            resonances = (.13 * math.sin(2 * math.pi * (82*t - 24*t*t))
                          + .08 * math.sin(2 * math.pi * (47*t - 8*t*t))) * math.exp(-13*t)
            reflections = sum(.08 * math.sin(2*math.pi*113*(t-delay))
                              * math.exp(-24*(t-delay)) if t >= delay else 0
                              for delay in (.038, .081))
            value = attack + pressure + low + resonances + reflections
        elif name == "impact":
            value = (.5 * math.sin(2 * math.pi * 170 * t) + .3 * math.sin(2 * math.pi * 310 * t) + .2 * n) * math.exp(-22 * t)
        elif name == "splash":
            value = (n - lp) * math.sin(math.pi * u) ** 2
        else:
            value = lp * (.65 + .2 * math.sin(2 * math.pi * t / 8) + .15 * math.sin(4 * math.pi * t / 8))
        values.append(value)

    if name == "cannon":
        dc = sum(values) / len(values)
        values = [value - dc for value in values]

    if sea:
        # Blend the extra tail into the original head; the wrap then joins the
        # final retained sample to the beginning of that tail.
        fade = len(values) - count
        for i in range(fade):
            weight = i / (fade - 1)
            values[i] = (1 - weight) * values[count + i] + weight * values[i]
        values = values[:count]
    else:
        fade = round(.005 * RATE)
        for i in range(fade):
            values[i] *= i / fade
            values[-1 - i] *= i / fade

    mean = 0.0 if name == "cannon" else sum(values) / len(values)
    values = [value - mean for value in values]
    scale = peak / max(abs(value) for value in values)
    return struct.pack("<%dh" % len(values), *(round(max(-1, min(1, value * scale)) * 32767)
                                                  for value in values))


def expected_wav(name, duration, seed, peak):
    # wave writes a standard 44-byte header for this one-channel PCM format.
    import io
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as wav:
        wav.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        wav.writeframes(samples(name, duration, seed, peak))
    return buffer.getvalue()


def verify(path, expected, duration, peak, sea=False):
    if not path.is_file():
        raise ValueError(f"{path.name}: missing file")
    data = path.read_bytes()
    try:
        with wave.open(str(path), "rb") as wav:
            if (wav.getnchannels(), wav.getsampwidth(), wav.getframerate(), wav.getnframes()) != (1, 2, RATE, round(duration * RATE)):
                raise ValueError(f"{path.name}: format/duration mismatch")
            pcm = wav.readframes(wav.getnframes())
    except (wave.Error, EOFError) as error:
        raise ValueError(f"{path.name}: invalid WAV: {error}") from error
    values = struct.unpack("<%dh" % (len(pcm) // 2), pcm)
    rms = math.sqrt(sum(value * value for value in values) / len(values)) / 32768
    maximum = max(map(abs, values)) / 32768
    if rms < .001 or maximum > peak + .001 or maximum < peak - .01:
        raise ValueError(f"{path.name}: RMS/peak outside bounds ({rms:.4f}/{maximum:.4f})")
    if sea and abs(values[-1] - values[0]) / 32768 >= .02:
        raise ValueError(f"{path.name}: loop seam jump exceeds .02")
    if data != expected:
        raise ValueError(f"{path.name}: regeneration mismatch (expected SHA-256 {hashlib.sha256(expected).hexdigest()})")
    return len(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify existing WAVs without writing")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "assets/audio")
    args = parser.parse_args()
    total = 0
    for name, (duration, seed, peak) in SOUNDS.items():
        path = args.output / f"{name}.wav"
        expected = expected_wav(name, duration, seed, peak)
        if not args.check:
            args.output.mkdir(parents=True, exist_ok=True)
            path.write_bytes(expected)
        try:
            total += verify(path, expected, duration, peak, name == "sea")
        except (ValueError, OSError) as error:
            parser.exit(1, f"audio check failed: {error}\n")
    if total >= 512 * 1024:
        parser.exit(1, f"audio check failed: total {total} bytes exceeds 512KiB\n")
    print("audio assets: 4 verified")


if __name__ == "__main__":
    main()
