"""Deterministic source-asset and read-only verification contract."""

import subprocess
import sys
import tempfile
import unittest
import wave
from pathlib import Path


GAME = Path(__file__).resolve().parents[1]
GENERATOR = GAME / "tools/generate_audio.py"


class AudioAssets(unittest.TestCase):
    def test_generator_reproducible_and_check_rejects_corruption(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            def run(*args):
                return subprocess.run(
                    [sys.executable, str(GENERATOR), "--output", str(output), *args],
                    capture_output=True, text=True,
                )

            self.assertEqual(run().returncode, 0)
            original = {path.name: path.read_bytes() for path in output.glob("*.wav")}
            self.assertEqual(set(original), {"cannon.wav", "impact.wav", "splash.wav", "sea.wav"})
            self.assertLess(sum(map(len, original.values())), 512 * 1024)
            self.assertIn("audio assets: 4 verified", run("--check").stdout)
            for name, seconds in {"cannon": .65, "impact": .30, "splash": .55, "sea": 8}.items():
                with wave.open(str(output / (name + ".wav"))) as wav:
                    self.assertEqual((wav.getnchannels(), wav.getsampwidth(), wav.getframerate(), wav.getnframes()),
                                     (1, 2, 22050, round(seconds * 22050)))
            self.assertEqual(run().returncode, 0)
            self.assertEqual({path.name: path.read_bytes() for path in output.glob("*.wav")}, original)
            (output / "sea.wav").write_bytes(original["sea.wav"][:-2] + b"\0\0")
            failure = run("--check")
            self.assertNotEqual(failure.returncode, 0)
            self.assertIn("sea.wav", failure.stderr)


if __name__ == "__main__":
    unittest.main()
