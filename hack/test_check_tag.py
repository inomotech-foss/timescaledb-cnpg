import importlib.util
import io
import json
from pathlib import Path
import unittest
import urllib.error
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("check_tag", Path(__file__).with_name("check-tag.py"))
check_tag = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check_tag)


class Response(io.BytesIO):
    status = 200


def http_error(status, code):
    return urllib.error.HTTPError(
        "https://ghcr.io/v2/example/image/manifests/1.0.0-pg18",
        status,
        "registry error",
        {},
        io.BytesIO(json.dumps({"errors": [{"code": code}]}).encode()),
    )


class CheckTagTest(unittest.TestCase):
    def check(self, result):
        with patch.object(
            check_tag.urllib.request,
            "urlopen",
            side_effect=[Response(b'{"token":"test-token"}'), result],
        ):
            return check_tag.tag_exists("ghcr.io/example/image", "1.0.0-pg18", "actor", "secret")

    def test_existing_tag(self):
        self.assertTrue(self.check(Response(b"{}")))

    def test_missing_manifest(self):
        self.assertFalse(self.check(http_error(404, "MANIFEST_UNKNOWN")))

    def test_registry_failures_do_not_allow_publishing(self):
        for status, code in [(401, "UNAUTHORIZED"), (403, "DENIED"), (404, "NAME_UNKNOWN"),
                             (429, "TOOMANYREQUESTS"), (500, "UNKNOWN")]:
            with self.subTest(status=status, code=code):
                with self.assertRaises(urllib.error.HTTPError):
                    self.check(http_error(status, code))

    def test_network_failure_does_not_allow_publishing(self):
        with self.assertRaises(urllib.error.URLError):
            self.check(urllib.error.URLError("connection reset"))

    def test_token_failure_does_not_allow_publishing(self):
        with patch.object(check_tag.urllib.request, "urlopen", side_effect=http_error(403, "DENIED")):
            with self.assertRaises(urllib.error.HTTPError):
                check_tag.tag_exists("ghcr.io/example/image", "1.0.0-pg18", "actor", "secret")
