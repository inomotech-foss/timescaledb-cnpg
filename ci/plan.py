"""Select test suites from changed paths and emit GitHub Actions matrices."""

import json
import os
import re
import subprocess
from pathlib import Path

from data import Image, object_value, parse_json, string_value

RUNNERS = {"amd64": "ubuntu-26.04", "arm64": "ubuntu-26.04-arm"}
NAME = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")


def images(root: Path) -> list[Image]:
    result: list[Image] = []
    for dockerfile in sorted((root / "images").glob("*/Dockerfile")):
        name = dockerfile.parent.name
        metadata = object_value(
            parse_json(dockerfile.with_name("image.json").read_text())
        )
        suite = string_value(metadata["suite"])
        image = string_value(metadata["image"])
        if not NAME.fullmatch(name) or not NAME.fullmatch(suite):
            raise ValueError(f"invalid image/suite name: {name}/{suite}")
        if not (root / "tests" / suite / "run.sh").is_file():
            raise ValueError(f"missing test entry point for {name}: {suite}")
        if not re.fullmatch(r"ghcr\.io/[a-z0-9][a-z0-9._/-]+", image):
            raise ValueError(f"invalid GHCR destination: {image}")
        args = {
            match[1]: match[2]
            for match in re.finditer(r"^ARG (\w+)=(\S+)$", dockerfile.read_text(), re.M)
        }
        tag = string_value(metadata["tag"]).format_map(args)
        if not re.fullmatch(r"[\w][\w.-]{0,127}", tag, re.ASCII):
            raise ValueError(f"invalid tag for {name}: {tag}")
        result.append(Image(name=name, suite=suite, image=image, tag=tag))
    destinations = [record["image"] for record in result]
    if len(destinations) != len(set(destinations)):
        raise ValueError("each extension must have its own image destination")
    return result


def plan(root: Path, changed: list[str] | None = None) -> dict[str, object]:
    records = images(root)
    all_suites = {record["suite"] for record in records}
    if changed is None or any(
        path.startswith("ci/")
        or path in {".github/workflows/build.yaml", ".hadolint.yaml", "renovate.json"}
        for path in changed
    ):
        selected = all_suites
    else:
        selected = {
            record["suite"]
            for record in records
            if any(
                path.startswith(
                    (f"images/{record['name']}/", f"tests/{record['suite']}/")
                )
                for path in changed
            )
        }
    records = [record for record in records if record["suite"] in selected]
    build = [
        {
            "suite": suite,
            "arch": arch,
            "platform": f"linux/{arch}",
            "runner": runner,
            "images": [record for record in records if record["suite"] == suite],
        }
        for suite in sorted(selected)
        for arch, runner in RUNNERS.items()
    ]
    return {
        "has_changes": bool(build),
        "build": {"include": build},
        "publish": {"include": records},
    }


if __name__ == "__main__":
    base = os.environ.get("BASE_SHA", "")
    changed = None
    if base and set(base) != {"0"}:
        changed = subprocess.check_output(
            ["git", "diff", "--no-renames", "--name-only", "-z", base, "HEAD"],
            text=True,
        ).split("\0")
    result = plan(Path("."), changed)
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        for key, value in result.items():
            output.write(f"{key}={json.dumps(value, separators=(',', ':'))}\n")
    print(json.dumps(result, indent=2))
