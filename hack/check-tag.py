"""Check a GHCR tag without treating authentication or network errors as absence."""

import base64
import json
import os
import urllib.error
import urllib.parse
import urllib.request


def tag_exists(image, tag, actor, password):
    if not image.startswith("ghcr.io/"):
        raise ValueError("only ghcr.io images are supported")
    repository = image.removeprefix("ghcr.io/")
    scope = urllib.parse.urlencode(
        {"service": "ghcr.io", "scope": f"repository:{repository}:pull"}
    )
    credentials = base64.b64encode(f"{actor}:{password}".encode()).decode()
    request = urllib.request.Request(
        f"https://ghcr.io/token?{scope}",
        headers={"Authorization": f"Basic {credentials}"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        token = json.load(response)["token"]
    request = urllib.request.Request(
        f"https://ghcr.io/v2/{repository}/manifests/{urllib.parse.quote(tag, safe='')}",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": ", ".join(
                [
                    "application/vnd.oci.image.index.v1+json",
                    "application/vnd.docker.distribution.manifest.list.v2+json",
                    "application/vnd.oci.image.manifest.v1+json",
                    "application/vnd.docker.distribution.manifest.v2+json",
                ]
            ),
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            if response.status != 200:
                raise RuntimeError(f"unexpected registry status: {response.status}")
            return True
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        errors = json.load(error).get("errors", [])
        if not errors or any(item.get("code") != "MANIFEST_UNKNOWN" for item in errors):
            raise
        return False


if __name__ == "__main__":
    image, tag = os.environ["IMAGE"], os.environ["TAG"]
    exists = tag_exists(image, tag, os.environ["GITHUB_ACTOR"], os.environ["GITHUB_TOKEN"])
    print(f"{image}:{tag}: {'already published' if exists else 'not published'}")
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        output.write(f"published={str(exists).lower()}\n")
