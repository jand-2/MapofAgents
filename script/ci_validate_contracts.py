#!/usr/bin/env python3
"""Validate repository contract fixtures with a dependency-free schema subset.

The repository schemas intentionally use a small Draft 2020-12 keyword set. This
validator implements that complete set and rejects unknown schema keywords so CI
cannot silently stop enforcing a newly added constraint.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import pathlib
import re
import sys
from typing import Any, Dict, Iterable, List, Set


class ContractError(Exception):
    """A schema, fixture, or validation error."""


def strict_json_load(path: pathlib.Path) -> Any:
    def reject_duplicates(pairs: Iterable[Any]) -> Dict[str, Any]:
        result: Dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ContractError(f"{path}: duplicate JSON key {key!r}")
            result[key] = value
        return result

    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle, object_pairs_hook=reject_duplicates)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ContractError(f"{path}: invalid JSON: {error}") from error


def instance_type(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    raise ContractError(f"unsupported JSON value type: {type(value).__name__}")


def matches_type(value: Any, expected: str) -> bool:
    actual = instance_type(value)
    return actual == expected or (expected == "number" and actual == "integer")


def json_equal(left: Any, right: Any) -> bool:
    if instance_type(left) != instance_type(right):
        return False
    return left == right


def resolve_ref(root: Any, reference: str) -> Any:
    if not reference.startswith("#/"):
        raise ContractError(f"only local JSON Pointer references are supported: {reference!r}")
    current = root
    for raw_part in reference[2:].split("/"):
        part = raw_part.replace("~1", "/").replace("~0", "~")
        if not isinstance(current, dict) or part not in current:
            raise ContractError(f"unresolved schema reference: {reference!r}")
        current = current[part]
    return current


def validate_date_time(value: str, path: str) -> None:
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = dt.datetime.fromisoformat(normalized)
    except ValueError as error:
        raise ContractError(f"{path}: expected RFC 3339 date-time") from error
    if parsed.tzinfo is None:
        raise ContractError(f"{path}: date-time must include a UTC offset")


def validate(instance: Any, schema: Any, root: Any, path: str = "$") -> Set[str]:
    if schema is True:
        return set()
    if schema is False:
        raise ContractError(f"{path}: rejected by false schema")
    if not isinstance(schema, dict):
        raise ContractError(f"{path}: schema must be an object or boolean")

    evaluated: Set[str] = set()

    if "$ref" in schema:
        evaluated |= validate(instance, resolve_ref(root, schema["$ref"]), root, path)

    if "allOf" in schema:
        for subschema in schema["allOf"]:
            evaluated |= validate(instance, subschema, root, path)

    if "anyOf" in schema:
        matches: List[Set[str]] = []
        for subschema in schema["anyOf"]:
            try:
                matches.append(validate(instance, subschema, root, path))
            except ContractError:
                pass
        if not matches:
            raise ContractError(f"{path}: did not match any anyOf branch")
        for match in matches:
            evaluated |= match

    if "oneOf" in schema:
        matches = []
        for subschema in schema["oneOf"]:
            try:
                matches.append(validate(instance, subschema, root, path))
            except ContractError:
                pass
        if len(matches) != 1:
            raise ContractError(f"{path}: matched {len(matches)} oneOf branches; expected exactly 1")
        evaluated |= matches[0]

    if "not" in schema:
        try:
            validate(instance, schema["not"], root, path)
        except ContractError:
            pass
        else:
            raise ContractError(f"{path}: matched prohibited schema")

    if "type" in schema:
        expected = schema["type"]
        expected_types = expected if isinstance(expected, list) else [expected]
        if not any(matches_type(instance, item) for item in expected_types):
            raise ContractError(
                f"{path}: expected type {expected!r}, found {instance_type(instance)!r}"
            )

    if "const" in schema and not json_equal(instance, schema["const"]):
        raise ContractError(f"{path}: expected constant {schema['const']!r}")

    if "enum" in schema and not any(json_equal(instance, item) for item in schema["enum"]):
        raise ContractError(f"{path}: value is not in the allowed enum")

    if isinstance(instance, str):
        if len(instance) < schema.get("minLength", 0):
            raise ContractError(f"{path}: string is shorter than minLength")
        if "maxLength" in schema and len(instance) > schema["maxLength"]:
            raise ContractError(f"{path}: string is longer than maxLength")
        if "pattern" in schema:
            try:
                matched = re.search(schema["pattern"], instance)
            except re.error as error:
                raise ContractError(f"invalid schema regex {schema['pattern']!r}: {error}") from error
            if matched is None:
                raise ContractError(f"{path}: string does not match {schema['pattern']!r}")
        if schema.get("format") == "date-time":
            validate_date_time(instance, path)

    if isinstance(instance, (int, float)) and not isinstance(instance, bool):
        if isinstance(instance, float) and not math.isfinite(instance):
            raise ContractError(f"{path}: number must be finite")
        if "minimum" in schema and instance < schema["minimum"]:
            raise ContractError(f"{path}: number is below minimum")
        if "maximum" in schema and instance > schema["maximum"]:
            raise ContractError(f"{path}: number is above maximum")
        if "exclusiveMinimum" in schema and instance <= schema["exclusiveMinimum"]:
            raise ContractError(f"{path}: number is not above exclusiveMinimum")
        if "exclusiveMaximum" in schema and instance >= schema["exclusiveMaximum"]:
            raise ContractError(f"{path}: number is not below exclusiveMaximum")

    if isinstance(instance, list):
        if len(instance) < schema.get("minItems", 0):
            raise ContractError(f"{path}: array is shorter than minItems")
        if "maxItems" in schema and len(instance) > schema["maxItems"]:
            raise ContractError(f"{path}: array is longer than maxItems")
        if schema.get("uniqueItems"):
            canonical = [json.dumps(item, sort_keys=True, separators=(",", ":")) for item in instance]
            if len(canonical) != len(set(canonical)):
                raise ContractError(f"{path}: array items must be unique")
        if "items" in schema:
            for index, item in enumerate(instance):
                validate(item, schema["items"], root, f"{path}[{index}]")

    if isinstance(instance, dict):
        required = schema.get("required", [])
        missing = [key for key in required if key not in instance]
        if missing:
            raise ContractError(f"{path}: missing required properties {missing!r}")

        properties = schema.get("properties", {})
        for key, subschema in properties.items():
            if key in instance:
                validate(instance[key], subschema, root, f"{path}.{key}")
                evaluated.add(key)

        pattern_properties = schema.get("patternProperties", {})
        for key, value in instance.items():
            for pattern, subschema in pattern_properties.items():
                if re.search(pattern, key):
                    validate(value, subschema, root, f"{path}.{key}")
                    evaluated.add(key)

        locally_known = set(properties)
        for key in instance:
            if any(re.search(pattern, key) for pattern in pattern_properties):
                locally_known.add(key)
        additional = set(instance) - locally_known
        if "additionalProperties" in schema:
            additional_schema = schema["additionalProperties"]
            if additional_schema is False and additional:
                raise ContractError(f"{path}: unknown properties {sorted(additional)!r}")
            if additional_schema is not False:
                for key in additional:
                    validate(instance[key], additional_schema, root, f"{path}.{key}")
                    evaluated.add(key)

        if "unevaluatedProperties" in schema:
            remaining = set(instance) - evaluated
            unevaluated_schema = schema["unevaluatedProperties"]
            if unevaluated_schema is False and remaining:
                raise ContractError(f"{path}: unevaluated properties {sorted(remaining)!r}")
            if unevaluated_schema is not False:
                for key in remaining:
                    validate(instance[key], unevaluated_schema, root, f"{path}.{key}")
                    evaluated.add(key)

    return evaluated


KNOWN_KEYWORDS = {
    "$comment",
    "$defs",
    "$id",
    "$ref",
    "$schema",
    "additionalProperties",
    "allOf",
    "anyOf",
    "const",
    "deprecated",
    "description",
    "enum",
    "examples",
    "exclusiveMaximum",
    "exclusiveMinimum",
    "format",
    "items",
    "maxItems",
    "maxLength",
    "maximum",
    "minItems",
    "minLength",
    "minimum",
    "not",
    "oneOf",
    "pattern",
    "patternProperties",
    "properties",
    "readOnly",
    "required",
    "title",
    "type",
    "unevaluatedProperties",
    "uniqueItems",
    "writeOnly",
}


def lint_schema(schema: Any, root: Any, path: str = "$") -> None:
    if isinstance(schema, bool):
        return
    if not isinstance(schema, dict):
        raise ContractError(f"{path}: schema node must be an object or boolean")
    unknown = set(schema) - KNOWN_KEYWORDS
    if unknown:
        raise ContractError(f"{path}: unsupported schema keywords {sorted(unknown)!r}")
    if "$ref" in schema:
        resolve_ref(root, schema["$ref"])
    if "type" in schema:
        values = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        allowed = {"array", "boolean", "integer", "null", "number", "object", "string"}
        if not values or any(value not in allowed for value in values):
            raise ContractError(f"{path}: invalid type declaration {schema['type']!r}")
    if schema.get("format") not in (None, "date-time"):
        raise ContractError(f"{path}: unsupported asserted format {schema['format']!r}")

    for collection_key in ("$defs", "properties", "patternProperties"):
        for key, child in schema.get(collection_key, {}).items():
            lint_schema(child, root, f"{path}.{collection_key}.{key}")
    for child_key in ("additionalProperties", "items", "not", "unevaluatedProperties"):
        if child_key in schema:
            lint_schema(schema[child_key], root, f"{path}.{child_key}")
    for list_key in ("allOf", "anyOf", "oneOf"):
        for index, child in enumerate(schema.get(list_key, [])):
            lint_schema(child, root, f"{path}.{list_key}[{index}]")


def resolved_child(base: pathlib.Path, value: str, repository_root: pathlib.Path) -> pathlib.Path:
    path = (base / value).resolve()
    try:
        path.relative_to(repository_root)
    except ValueError as error:
        raise ContractError(f"contract path escapes repository root: {value!r}") from error
    if not path.is_file():
        raise ContractError(f"contract path does not exist: {value!r}")
    return path


def run(repository_root: pathlib.Path) -> None:
    protocol_directory = repository_root / "shared" / "protocol"
    manifest_path = protocol_directory / "contract-fixtures.json"
    manifest = strict_json_load(manifest_path)
    if not isinstance(manifest, dict) or manifest.get("version") != 1:
        raise ContractError(f"{manifest_path}: expected contract manifest version 1")
    contracts = manifest.get("contracts")
    if not isinstance(contracts, list) or not contracts:
        raise ContractError(f"{manifest_path}: contracts must be a non-empty array")

    validated = 0
    rejected = 0
    listed_fixtures: Set[pathlib.Path] = set()
    for index, contract in enumerate(contracts):
        if not isinstance(contract, dict) or set(contract) != {"schema", "valid", "invalid"}:
            raise ContractError(f"contract {index}: expected schema, valid, and invalid fields")
        if not contract["valid"] or not contract["invalid"]:
            raise ContractError(f"contract {index}: valid and invalid fixture lists must be non-empty")

        schema_path = resolved_child(protocol_directory, contract["schema"], repository_root)
        schema = strict_json_load(schema_path)
        if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
            raise ContractError(f"{schema_path}: expected Draft 2020-12 declaration")
        lint_schema(schema, schema)

        for fixture_name in contract["valid"]:
            fixture_path = resolved_child(protocol_directory, fixture_name, repository_root)
            listed_fixtures.add(fixture_path)
            fixture = strict_json_load(fixture_path)
            try:
                validate(fixture, schema, schema)
            except ContractError as error:
                raise ContractError(f"{fixture_path}: expected valid fixture: {error}") from error
            validated += 1

        for fixture_name in contract["invalid"]:
            fixture_path = resolved_child(protocol_directory, fixture_name, repository_root)
            listed_fixtures.add(fixture_path)
            fixture = strict_json_load(fixture_path)
            try:
                validate(fixture, schema, schema)
            except ContractError:
                rejected += 1
            else:
                raise ContractError(f"{fixture_path}: expected fixture to be rejected")

    fixture_roots = (
        protocol_directory / "fixtures",
        repository_root / "shared" / "workflow-events" / "fixtures",
    )
    repository_fixtures = {
        path.resolve()
        for fixture_root in fixture_roots
        for path in fixture_root.rglob("*.json")
    }
    unlisted = sorted(repository_fixtures - listed_fixtures)
    stale = sorted(listed_fixtures - repository_fixtures)
    if unlisted or stale:
        details = []
        if unlisted:
            details.append(
                "unlisted fixtures: "
                + ", ".join(str(path.relative_to(repository_root)) for path in unlisted)
            )
        if stale:
            details.append(
                "manifest entries outside fixture roots: "
                + ", ".join(str(path.relative_to(repository_root)) for path in stale)
            )
        raise ContractError("; ".join(details))

    print(f"Contract validation passed: {validated} valid and {rejected} invalid fixtures.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        type=pathlib.Path,
        default=pathlib.Path(__file__).resolve().parent.parent,
        help="repository root",
    )
    arguments = parser.parse_args()
    try:
        run(arguments.root.resolve())
    except ContractError as error:
        print(f"contract validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
