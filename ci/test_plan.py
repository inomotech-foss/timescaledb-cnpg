import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

import plan


class PlanTest(unittest.TestCase):
    def setUp(self):
        self.directory = TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for name, suite in [("timescaledb", "timescaledb"), ("toolkit", "timescaledb"), ("tpm", "openbao")]:
            folder = self.root / "images" / name
            folder.mkdir(parents=True)
            (folder / "Dockerfile").write_text("ARG VERSION=1.2.3\nFROM scratch\n")
            (folder / "image.json").write_text(json.dumps({
                "image": f"ghcr.io/example/{name}", "tag": "{VERSION}-test", "suite": suite,
            }))
            test = self.root / "tests" / suite / "run.sh"
            test.parent.mkdir(parents=True, exist_ok=True)
            test.touch()

    def names(self, changed):
        return [image["name"] for image in plan.plan(self.root, changed)["publish"]["include"]]

    def test_documentation_only_skips_builds(self):
        result = plan.plan(self.root, ["README.md"])
        self.assertFalse(result["has_changes"])
        self.assertEqual(result["build"], {"include": []})

    def test_companion_images_are_tested_together(self):
        self.assertEqual(self.names(["images/toolkit/Dockerfile"]), ["timescaledb", "toolkit"])

    def test_unrelated_image_selects_only_its_suite(self):
        self.assertEqual(self.names(["images/tpm/Dockerfile"]), ["tpm"])

    def test_suite_changes_select_its_images(self):
        self.assertEqual(self.names(["tests/openbao/run.sh"]), ["tpm"])

    def test_shared_changes_and_scheduled_runs_select_all(self):
        for changed in [["ci/plan.py"], [".github/workflows/build.yaml"], ["renovate.json"], None]:
            self.assertEqual(len(self.names(changed)), 3)

    def test_both_architectures_and_resolved_tags(self):
        result = plan.plan(self.root, ["images/tpm/image.json"])
        self.assertEqual([job["arch"] for job in result["build"]["include"]], ["amd64", "arm64"])
        self.assertEqual(result["publish"]["include"][0]["tag"], "1.2.3-test")

    def test_missing_version_or_test_fails_closed(self):
        (self.root / "images/tpm/Dockerfile").write_text("FROM scratch\n")
        with self.assertRaises(KeyError):
            plan.plan(self.root)
        (self.root / "tests/openbao/run.sh").unlink()
        with self.assertRaises(ValueError):
            plan.plan(self.root)

    def test_git_diff_covers_deleted_paths_without_rename_detection(self):
        with patch.object(plan.subprocess, "check_output", return_value="images/tpm/old-file\0") as diff:
            self.assertEqual(plan.changed_paths("push", {"before": "abc"}), ["images/tpm/old-file"])
            self.assertEqual(diff.call_args.args[0], ["git", "diff", "--no-renames", "--name-only", "-z", "abc", "HEAD"])

    def test_initial_push_selects_all(self):
        self.assertIsNone(plan.changed_paths("push", {"before": "0" * 40}))
