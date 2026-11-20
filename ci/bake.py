"""Generate shared Bake targets; record tested per-architecture push digests."""

import json
import os
from pathlib import Path
import re
import sys
from collections.abc import Sequence

from data import Image, JSON, image_list, object_value, parse_json, string_value


def definition(images: Sequence[Image], arch: str, platform: str) -> dict[str, object]:
    targets: dict[str, dict[str, str | list[str]]] = {}
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


def record_digests(names: Sequence[str], arch: str, metadata: JSON, destination: Path) -> None:
    # Validate all targets before writing any files consumed by publication.
    records = object_value(metadata)
    digests = {name: string_value(object_value(records[f"push-{name}"])["containerimage.digest"])
               for name in names}
    if not all(re.fullmatch(r"sha256:[0-9a-f]{64}", digest) for digest in digests.values()):
        raise ValueError("invalid pushed image digest")
    for name, digest in digests.items():
        path = destination / name / arch
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(digest + "\n")


if __name__ == "__main__":
    images = image_list(os.environ["IMAGES"])
    arch = os.environ["ARCH"]
    if sys.argv[1:] == ["digests"]:
        record_digests([image["name"] for image in images], arch,
                       parse_json(os.environ["METADATA"]), Path("digests"))
    else:
        print(json.dumps(definition(images, arch, os.environ["PLATFORM"]), indent=2))
