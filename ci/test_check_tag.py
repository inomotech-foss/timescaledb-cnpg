import io
import json
import unittest
import urllib.error
import urllib.request
from email.message import Message
from unittest.mock import patch

import check_tag
from data import JSON


class Response(io.BytesIO):
    status = 200


def http_error(status: int, code: str) -> urllib.error.HTTPError:
    body: JSON = {"errors": [{"code": code}]}
    return urllib.error.HTTPError(
        "https://ghcr.io/v2/example/image/manifests/1.0.0-pg18",
        status,
        "registry error",
        Message(),
        io.BytesIO(json.dumps(body).encode()),
    )


class CheckTagTest(unittest.TestCase):
    def check(self, result: Response | urllib.error.URLError) -> bool:
        responses: list[Response | urllib.error.URLError] = [
            Response(b'{"token":"test-token"}'),
            result,
        ]
        with patch.object(
            urllib.request,
            "urlopen",
            side_effect=responses,
        ):
            return check_tag.tag_exists(
                "ghcr.io/example/image", "1.0.0-pg18", "actor", "secret"
            )

    def test_existing_tag(self) -> None:
        self.assertTrue(self.check(Response(b"{}")))

    def test_missing_manifest(self) -> None:
        self.assertFalse(self.check(http_error(404, "MANIFEST_UNKNOWN")))

    def test_registry_failures_do_not_allow_publishing(self) -> None:
        for status, code in [
            (401, "UNAUTHORIZED"),
            (403, "DENIED"),
            (404, "NAME_UNKNOWN"),
            (429, "TOOMANYREQUESTS"),
            (500, "UNKNOWN"),
        ]:
            with self.subTest(status=status, code=code):
                with self.assertRaises(urllib.error.HTTPError):
                    self.check(http_error(status, code))

    def test_network_failure_does_not_allow_publishing(self) -> None:
        with self.assertRaises(urllib.error.URLError):
            self.check(urllib.error.URLError("connection reset"))

    def test_token_failure_does_not_allow_publishing(self) -> None:
        with patch.object(
            urllib.request, "urlopen", side_effect=http_error(403, "DENIED")
        ):
            with self.assertRaises(urllib.error.HTTPError):
                check_tag.tag_exists(
                    "ghcr.io/example/image", "1.0.0-pg18", "actor", "secret"
                )
