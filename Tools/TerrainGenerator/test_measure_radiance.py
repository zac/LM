import colorsys
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

from measure_radiance import measure, ownership_masks


class GlobalOwnershipTests(unittest.TestCase):
    def test_simulator_color_conversion_keeps_the_two_green_levels_separate(self):
        # Dominant RGB values from the unlit highland capture, including all
        # three L1 parity brightnesses. L5 is also green but is not landing.
        colors = [(150, 126, 46), (44, 97, 38), (72, 153, 60), (99, 208, 83),
                  (40, 82, 150), (132, 35, 150), (144, 67, 34), (90, 153, 50)]
        pixels = np.repeat(np.array([colors], dtype=np.uint8), 64, axis=0)
        pixels = np.repeat(pixels, 64, axis=1)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "simulator-palette.png"
            Image.fromarray(pixels).save(path)
            terminal, landing = ownership_masks(path, global_levels=True)
        self.assertEqual(int(terminal.sum()), 64 * 64)
        self.assertEqual(int(landing.sum()), 3 * 64 * 64)
        self.assertFalse(landing[:, 4 * 64:].any())

    def test_empty_measurement_interior_is_an_error(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "empty.png"
            Image.new("RGB", (64, 64)).save(path)
            empty = np.zeros((64, 64), dtype=bool)
            with self.assertRaisesRegex(ValueError, "no interior"):
                measure(path, empty, ~empty)

    def test_distant_regions_are_not_an_adjacent_boundary(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "separated.png"
            Image.new("RGB", (512, 128), color=(80, 80, 80)).save(path)
            terminal = np.zeros((128, 512), dtype=bool)
            landing = np.zeros_like(terminal)
            terminal[:, :128] = True
            landing[:, -128:] = True
            with self.assertRaisesRegex(ValueError, "no adjacent boundary"):
                measure(path, terminal, landing)

    def test_distant_global_bands_cannot_contaminate_landing_boundary(self):
        colors = [tuple(round(channel * 255) for channel in
                        colorsys.hsv_to_rgb((0.13 + level * 0.23) % 1, 0.85, 0.7))
                  for level in range(7)]
        pixels = np.zeros((32, 7 * 32, 3), dtype=np.uint8)
        for level, color in enumerate(colors):
            pixels[:, level * 32:(level + 1) * 32] = color
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "palette.png"
            Image.fromarray(pixels).save(path)
            terminal, landing = ownership_masks(path, global_levels=True)
        self.assertEqual(int(terminal.sum()), 32 * 32)
        self.assertEqual(int(landing.sum()), 32 * 32)
        self.assertTrue(terminal[:, :32].all())
        self.assertTrue(landing[:, 32:64].all())
        self.assertFalse(terminal[:, 64:].any())
        self.assertFalse(landing[:, 64:].any())


if __name__ == "__main__":
    unittest.main()
