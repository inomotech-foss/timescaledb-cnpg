"""Select test suites from changed paths and emit GitHub Actions matrices."""

import json
import os
from pathlib import Path
import re
import subprocess


RUNNERS = {"amd64": "ubuntu-26.04", "arm64": "ubuntu-26.04-arm"}
NAME = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")


def images(root):
    result = []
    for dockerfile in sorted((root / "images").glob("*/Dockerfile")):
        name = dockerfile.parent.name
        metadata = json.loads(dockerfile.with_name("image.json").read_text())
        suite = metadata["suite"]
        if not NAME.fullmatch(name) or not NAME.fullmatch(suite):
            raise ValueError(f"invalid image/suite name: {name}/{suite}")
        if not (root / "tests" / suite / "run.sh").is_file():
            raise ValueError(f"missing test entry point for {name}: {suite}")
        if not re.fullmatch(r"ghcr\.io/[a-z0-9][a-z0-9._/-]+", metadata["image"]):
            raise ValueError(f"invalid GHCR destination: {metadata['image']}")
        args = dict(re.findall(r"^ARG (\w+)=(\S+)$", dockerfile.read_text(), re.M))
        tag = metadata["tag"].format_map(args)
        if not re.fullmatch(r"[\w][\w.-]{0,127}", tag, re.ASCII):
            raise ValueError(f"invalid tag for {name}: {tag}")
        result.append({"name": name, "suite": suite, "image": metadata["image"], "tag": tag})
    destinations = [record["image"] for record in result]
    if len(destinations) != len(set(destinations)):
        raise ValueError("each extension must have its own image destination")
    return result


def plan(root, changed=None):
    records = images(root)
    all_suites = {record["suite"] for record in records}
    selected = set()
    if changed is None or any(
        path.startswith("ci/") or path in {".github/workflows/build.yaml", ".hadolint.yaml", "renovate.json"}
        for path in changed
    ):
        selected = all_suites
    else:
        for path in changed:
            parts = Path(path).parts
            if len(parts) >= 2 and parts[0] == "images":
                selected.update(record["suite"] for record in records if record["name"] == parts[1])
            elif len(parts) >= 2 and parts[0] == "tests" and parts[1] in all_suites:
                selected.add(parts[1])
    records = [record for record in records if record["suite"] in selected]
    build = [
        {"suite": suite, "arch": arch, "platform": f"linux/{arch}", "runner": runner,
         "images": [record for record in records if record["suite"] == suite]}
        for suite in sorted(selected) for arch, runner in RUNNERS.items()
    ]
    return {"has_changes": bool(build), "build": {"include": build}, "publish": {"include": records}}


def changed_paths(event_name, event):
    if event_name == "pull_request":
        base = event["pull_request"]["base"]["sha"]
    elif event_name == "push":
        base = event["before"]
        if set(base) == {"0"}:
            return None
    else:
        return None
    return subprocess.check_output(
        ["git", "diff", "--no-renames", "--name-only", "-z", base, "HEAD"], text=True,
    ).rstrip("\0").split("\0")


if __name__ == "__main__":
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    result = plan(Path("."), changed_paths(os.environ["GITHUB_EVENT_NAME"], event))
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        for key, value in result.items():
            output.write(f"{key}={json.dumps(value, separators=(',', ':'))}\n")
    print(json.dumps(result, indent=2))
