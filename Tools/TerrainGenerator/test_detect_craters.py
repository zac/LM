#!/usr/bin/env python3

import argparse
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from detect_craters import Candidate, crater_template, scale_candidates, write_catalog


class CraterDetectorTests(unittest.TestCase):
    def arguments(self) -> argparse.Namespace:
        return argparse.Namespace(
            catalog_id="apollo11-crater-detector-test",
            meters_per_pixel=0.5,
            minimum_diameter=2.0,
            maximum_diameter=8.0,
            diameter_steps=9,
            minimum_score=0.60,
            coverage_radius=40.0,
            max_candidates=1200,
            sun_elevation=27.4,
            sun_azimuth=92.0,
            source_ids=None,
        )

    def test_exact_template_is_recovered_at_its_center(self) -> None:
        arguments = self.arguments()
        diameter = 4.0
        template = crater_template(
            diameter,
            arguments.meters_per_pixel,
            arguments.sun_elevation,
            arguments.sun_azimuth,
        )
        image = np.zeros((101, 101), dtype=np.float32)
        half = template.shape[0] // 2
        image[50 - half : 51 + half, 50 - half : 51 + half] = template

        candidates = scale_candidates(image, diameter, arguments)

        self.assertTrue(
            any(candidate.row == 50 and candidate.column == 50 for candidate in candidates)
        )

    def test_catalog_records_detection_parameters(self) -> None:
        arguments = self.arguments()
        candidate = Candidate(column=50, row=50, diameter_meters=4.0, score=0.9)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "catalog.json"
            write_catalog(output, [candidate], (101, 101), arguments)
            payload = json.loads(output.read_text())

        self.assertEqual(payload["detectionParameters"]["sunElevationDegrees"], 27.4)
        self.assertEqual(payload["catalogID"], "apollo11-crater-detector-test")
        self.assertEqual(
            payload["detectionParameters"]["sunAzimuthDegreesClockwiseFromNorth"],
            92.0,
        )
        self.assertEqual(payload["entries"][0]["eastMeters"], 0.0)
        self.assertEqual(payload["entries"][0]["northMeters"], 0.0)


if __name__ == "__main__":
    unittest.main()
