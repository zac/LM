import tempfile
import unittest
from pathlib import Path

from SummarizeMoonExplorerProfile import capture


class ExplorerProfileTests(unittest.TestCase):
    def report(self, messages, cycles=1, receipt=False):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            (directory / "stages.tsv").write_text("stage\tpid\tsha256\nglobe\t42\tunused\n")
            (directory / "launch-arguments.txt").write_text(f"--lunar-explorer-profile-soak-cycles={cycles}\n")
            if receipt:
                with (directory / "launch-arguments.txt").open("a") as stream:
                    stream.write("--lunar-explorer-profile-capture-token=unique-run\n")
                (directory / "completion.txt").write_text("passed")
            messages = [(42, "Explorer performance preset=journey p95=16.67ms p99=16.67ms max=16.67ms missed=0 physical=100.0MiB")] + messages
            (directory / "performance.log").write_text("\n".join(
                f"2026-09-06 07:00:00.000000-0700 0x1 Info 0x0 {pid} 0 LM: {message}"
                for pid, message in messages))
            return capture(directory)

    @staticmethod
    def checkpoint(stage):
        return (42, f"Terrain memory phase=soak-1-{stage} physical=104857600 peak=209715200 metal=0 resources=0")

    def test_stale_pid_cannot_complete_capture(self):
        result = self.report([(99, "Moon experience stage=passed")], cycles=0)
        self.assertFalse(result["complete"])

    def test_acknowledged_receipt_can_precede_buffered_pass_log(self):
        self.assertTrue(self.report([], cycles=0, receipt=True)["complete"])
        self.assertFalse(self.report([], cycles=1, receipt=True)["complete"])

    def test_missing_checkpoint_is_incomplete_even_with_pass_marker(self):
        result = self.report([(42, "Moon experience stage=passed"),
                              (42, "Moon experience cycle=1 cameraAndSunlightExact=true"),
                              self.checkpoint("surface")])
        self.assertFalse(result["complete"])

    def test_complete_soak_keeps_lifetime_peak_separate(self):
        result = self.report([(42, "Moon experience stage=passed"),
                              (42, "Moon experience cycle=1 cameraAndSunlightExact=true"),
                              self.checkpoint("surface"), self.checkpoint("returned")])
        self.assertTrue(result["complete"])
        self.assertEqual(result["soak"]["returnedDriftMiB"], 0)
        self.assertEqual(result["timing"]["memory"]["lifetimePeakMiB"], 200)
        self.assertIsNone(result["timing"]["memory"]["maxMetalAllocatedMiB"])

    def test_failure_marker_overrides_pass_marker(self):
        result = self.report([(42, "Moon experience stage=failed"),
                              (42, "Moon experience stage=passed")], cycles=0)
        self.assertFalse(result["complete"])


if __name__ == "__main__":
    unittest.main()
