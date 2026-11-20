"""Generate shared Bake targets; record tested per-architecture push digests."""

import json
import os
from pathlib import Path
import re
import sys


def definition(images, arch, platform):
    targets = {}
    for image in images:
        name = image["name"]
        scope = f"{name}-{arch}"
        targets[f"build-{name}"] = {
            "context": f"images/{name}",
            "dockerfile": "Dockerfile",
            "platforms": [platform],
            "cache-from": [f"type=gha,scope={scope}"],
            "cache-to": [f"type=gha,mode=max,scope={scope}"],
            "output": [f"type=local,dest=extension/{name}"],
        }
        targets[f"push-{name}"] = {
            "inherits": [f"build-{name}"],
            "output": [f"type=image,name={image['image']},push-by-digest=true,name-canonical=true,push=true"],
        }
    return {"group": {
        "build": {"targets": [f"build-{image['name']}" for image in images]},
        "push": {"targets": [f"push-{image['name']}" for image in images]},
    }, "target": targets}


def record_digests(images, arch, metadata, destination):
    # Validate all targets before writing any files consumed by publication.
    digests = {image["name"]: metadata[f"push-{image['name']}"]["containerimage.digest"] for image in images}
    if not all(re.fullmatch(r"sha256:[0-9a-f]{64}", digest) for digest in digests.values()):
        raise ValueError("invalid pushed image digest")
    for name, digest in digests.items():
        path = destination / name / arch
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(digest + "\n")


if __name__ == "__main__":
    images = json.loads(os.environ["IMAGES"])
    arch = os.environ["ARCH"]
    if sys.argv[1:] == ["digests"]:
        record_digests(images, arch, json.loads(os.environ["METADATA"]), Path("digests"))
    else:
        print(json.dumps(definition(images, arch, os.environ["PLATFORM"]), indent=2))
