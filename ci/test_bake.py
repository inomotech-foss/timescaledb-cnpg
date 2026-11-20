from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from bake import record_digests
from data import JSON


class DigestTest(unittest.TestCase):
    def test_missing_or_invalid_digest_never_reaches_publication(self) -> None:
        bad_records: list[JSON] = [{}, {"containerimage.digest": "not-a-digest"}]
        for bad in bad_records:
            with TemporaryDirectory() as directory:
                output = Path(directory) / "digests"
                with self.assertRaises((KeyError, ValueError)):
                    record_digests(["one", "two"], "amd64", {
                        "push-one": {"containerimage.digest": "sha256:" + "a" * 64},
                        "push-two": bad,
                    }, output)
                self.assertFalse(output.exists())

    def test_architecture_digests_are_kept_separate(self) -> None:
        with TemporaryDirectory() as directory:
            output = Path(directory)
            for arch, value in [("amd64", "a"), ("arm64", "b")]:
                record_digests(["one"], arch, {
                    "push-one": {"containerimage.digest": "sha256:" + value * 64},
                }, output)
            self.assertNotEqual((output / "one/amd64").read_text(), (output / "one/arm64").read_text())
