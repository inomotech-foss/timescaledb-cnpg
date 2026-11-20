"""Typed JSON boundaries shared by the CI scripts."""

import json
from typing import TypedDict, cast

type JSON = None | bool | int | float | str | list[JSON] | dict[str, JSON]


class Image(TypedDict):
    name: str
    suite: str
    image: str
    tag: str


def parse_json(text: str) -> JSON:
    # The decoder returns only the JSON types above.
    return cast(JSON, json.loads(text))


def object_value(value: JSON) -> dict[str, JSON]:
    if not isinstance(value, dict):
        raise ValueError("expected a JSON object")
    return value


def string_value(value: JSON) -> str:
    if not isinstance(value, str):
        raise ValueError("expected a JSON string")
    return value


def image_list(text: str) -> list[Image]:
    values = parse_json(text)
    if not isinstance(values, list):
        raise ValueError("expected an image list")
    result: list[Image] = []
    for value in values:
        record = object_value(value)
        result.append(Image(
            name=string_value(record["name"]), suite=string_value(record["suite"]),
            image=string_value(record["image"]), tag=string_value(record["tag"]),
        ))
    return result
