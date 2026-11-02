"""Exact lazy full-product planning; this never renders, downloads or schedules another batch.

Indexes/counts are decimal strings at JSON boundaries, not rounded GitHub/Dart/JavaScript numbers.
"""
import argparse
import copy
import hashlib
import json
import math
import re
import struct
import zlib
from datetime import datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def digest(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def resolve_registry(registry, catalogue=None):
    value = copy.deepcopy(registry)
    if value.get("schema") != 1:
        raise ValueError("Unknown registry schema")
    catalogue = catalogue or {}
    axes = value.get("axes", {})
    for name, choices in axes.items():
        if isinstance(choices, str) and choices.startswith("@"):
            choices = catalogue.get("axes", catalogue).get(choices[1:])
            axes[name] = choices
        if not isinstance(choices, list) or not choices:
            raise ValueError(f"Empty/unresolved axis: {name}")
        if len({canonical(choice) for choice in choices}) != len(choices):
            raise ValueError(f"Duplicate axis values: {name}")
    environment = value.get("environment", {})
    for name in ("size", "locale", "mode", "textScale", "dpi"):
        choices = environment.get(name)
        if not isinstance(choices, list) or not choices:
            raise ValueError(f"Missing environment axis: {name}")
        if len({canonical(choice) for choice in choices}) != len(choices):
            raise ValueError(f"Duplicate environment values: {name}")
    role_ids = set()
    for role in value.get("roles", []):
        if not role.get("id") or role["id"] in role_ids:
            raise ValueError("Missing/duplicate role identity")
        role_ids.add(role["id"])
        inherited = []
        for profile in role.get("profiles", []):
            if profile not in value.get("profiles", {}):
                raise ValueError(f"Unknown preference profile: {profile}")
            for axis in value["profiles"][profile]:
                if axis not in inherited:
                    inherited.append(axis)
        if "states" not in role:
            state_set = role.get("stateSet")
            if state_set not in value.get("stateSets", {}):
                raise ValueError(f"Unknown state set: {state_set}")
            role["states"] = [{"id": name} for name in value["stateSets"][state_set]]
        state_ids = set()
        for state in role["states"]:
            if not state.get("id") or state["id"] in state_ids:
                raise ValueError("Missing/duplicate state identity")
            state_ids.add(state["id"])
            state.update(role.get("stateOverrides", {}).get(state["id"], {}))
            state.setdefault("axes", inherited)
            names = state["axes"]
            if len(names) != len(set(names)) or any(name not in axes for name in names):
                raise ValueError(f"Unknown/duplicate axes for {role['id']}/{state['id']}")
            for field, default in [("driver", "unimplemented"), ("requiredRoles", ["appbar", "viewport"]),
                                   ("pixelRoles", []), ("allowedDifferences", [])]:
                state.setdefault(field, role.get(field, default))
            if not set(state["pixelRoles"]).issubset(state["requiredRoles"]):
                raise ValueError("Pixel roles require geometric evidence")
            if "differences" in value and any(key not in value["differences"] for key in state["allowedDifferences"]):
                raise ValueError("Unregistered intentional difference")
    if not role_ids:
        raise ValueError("Registry has no roles")
    return value


def spans(registry):
    value = resolve_registry(registry)
    start = 0
    for role in value["roles"]:
        for state in role["states"]:
            axes = [("preferences", name, value["axes"][name]) for name in state["axes"]]
            # Environment is innermost: DPI=2 is tested independently of text scaling immediately.
            axes += [("environment", name, choices) for name, choices in value["environment"].items()]
            count = math.prod(len(choices) for _, _, choices in axes)
            yield start, count, role, state, axes
            start += count


def count_cases(registry):
    return sum(count for _, count, _, _, _ in spans(registry))


def case_at(registry, ordinal):
    if not isinstance(ordinal, int) or isinstance(ordinal, bool) or ordinal < 0:
        raise ValueError("Invalid case ordinal")
    for start, count, role, state, axes in spans(registry):
        if ordinal >= start + count:
            continue
        rank = ordinal - start
        configuration = {"environment": {}, "preferences": {}}
        for kind, name, choices in reversed(axes):
            rank, index = divmod(rank, len(choices))
            configuration[kind][name] = choices[index]
        return {
            "index": str(ordinal), "role": role["id"], "state": state["id"], "driver": state["driver"],
            "sources": role["sources"], "configuration": configuration,
            "requiredRoles": state["requiredRoles"], "pixelRoles": state["pixelRoles"],
            "allowedDifferences": state["allowedDifferences"],
            "differenceDefinitions": {key: registry.get("differences", {}).get(key, {}) for key in state["allowedDifferences"]},
        }
    raise ValueError("Case ordinal outside the complete matrix")


def plan_batch(registry, offset, limit, role=None, state=None):
    if any(not isinstance(n, int) or isinstance(n, bool) for n in (offset, limit)) or offset < 0 or not 1 <= limit <= 1024:
        raise ValueError("Manual batches require a nonnegative offset and 1..1024 pairs")
    selected = [(start, count) for start, count, entry, stage, _ in spans(registry)
                if (role is None or entry["id"] == role) and (state is None or stage["id"] == state)]
    total = sum(count for _, count in selected)
    if offset + limit > total:
        raise ValueError("Batch exceeds matrix scope; refusing to silently clamp")
    indexes = []
    skip = offset
    for start, count in selected:
        if skip >= count:
            skip -= count
            continue
        take = min(limit - len(indexes), count - skip)
        indexes.extend(range(start + skip, start + skip + take))
        skip = 0
        if len(indexes) == limit:
            break
    return [{"shard": part // 64, "cases": [case_at(registry, index) for index in indexes[part:part + 64]]}
            for part in range(0, limit, 64)]


def fingerprint(source_sha, registry, runtime):
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        raise ValueError("Candidate must be an exact full Git SHA")
    return digest({"sourceSha": source_sha, "registry": registry, "runtime": runtime})


def timestamp(value):
    result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if result.tzinfo is None:
        raise ValueError("Evidence timestamp requires a UTC offset")
    return result.astimezone(timezone.utc)


def equal_preference(expected, actual):
    if isinstance(expected, str) and isinstance(actual, (int, float)) and not isinstance(actual, bool):
        try:
            return Decimal(expected) == Decimal(str(actual))
        except InvalidOperation:
            return False
    return canonical(expected) == canonical(actual)


def checked_png(root, record, expected_size=None, decode=False):
    path = (root / record["path"]).resolve()
    if not path.is_relative_to(root.resolve()) or not path.is_file():
        raise ValueError("Missing image or path outside evidence root")
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != record["sha256"] or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("Corrupt/mismatched PNG")
    at = 8
    width = height = channels = None
    compressed = bytearray()
    ended = False
    while at + 12 <= len(data):
        length = struct.unpack(">I", data[at:at + 4])[0]
        kind = data[at + 4:at + 8]
        chunk = data[at + 8:at + 8 + length]
        crc = data[at + 8 + length:at + 12 + length]
        if len(chunk) != length or len(crc) != 4 or zlib.crc32(kind + chunk) != struct.unpack(">I", crc)[0]:
            raise ValueError("Invalid PNG chunk")
        if kind == b"IHDR":
            width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", chunk)
            if depth != 8 or color not in (0, 2, 4, 6) or compression or filtering or interlace:
                raise ValueError("Unsupported screenshot PNG encoding")
            channels = {0: 1, 2: 3, 4: 2, 6: 4}[color]
            if expected_size is not None and [width, height] != expected_size:
                raise ValueError("PNG does not represent the requested true DPI")
            if not 0 < width <= 3840 or not 0 < height <= 2160:
                raise ValueError("Screenshot outside locked resource bounds")
        elif kind == b"IDAT":
            compressed.extend(chunk)
        elif kind == b"IEND":
            ended = True
            break
        at += length + 12
    if not ended or channels is None:
        raise ValueError("Truncated PNG")
    size = height * (width * channels + 1)
    decoder = zlib.decompressobj()
    pixels = decoder.decompress(bytes(compressed), size + 1)
    if len(pixels) != size or not decoder.eof or decoder.unconsumed_tail:
        raise ValueError("Truncated/oversized screenshot pixels")
    if not decode:
        return width, height
    stride = width * channels
    decoded = bytearray(height * stride)
    previous = bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        filtering = pixels[start]
        row = bytearray(pixels[start + 1:start + stride + 1])
        if filtering in (2, 4) and row.count(0) == stride:
            row = previous.copy()
        elif filtering == 1 and row[channels:].count(0) == stride - channels:
            row = row[:channels] * width
        elif filtering == 2:
            row = bytearray((a + b) & 255 for a, b in zip(row, previous))
        elif filtering in (1, 3, 4):
            for index in range(stride):
                left = row[index - channels] if index >= channels else 0
                up = previous[index]
                upper_left = previous[index - channels] if index >= channels else 0
                if filtering == 1:
                    prediction = left
                elif filtering == 3:
                    prediction = (left + up) // 2
                else:
                    p = left + up - upper_left
                    distances = (abs(p - left), abs(p - up), abs(p - upper_left))
                    prediction = (left if distances[0] <= min(distances[1:])
                                  else up if distances[1] <= distances[2] else upper_left)
                row[index] = (row[index] + prediction) & 255
        elif filtering != 0:
            raise ValueError("Unknown PNG filter")
        decoded[y * stride:(y + 1) * stride] = row
        previous = row
    return width, height, channels, decoded


def crop_row(image, rect, y, width):
    image_width, image_height, channels, pixels = image
    left, top, crop_width, crop_height = rect
    result = bytearray(width * 4)
    if y >= crop_height or not 0 <= top + y < image_height:
        return result
    start = max(left, 0)
    end = min(left + crop_width, image_width)
    if end <= start:
        return result
    first = ((top + y) * image_width + start) * channels
    row = pixels[first:first + (end - start) * channels]
    destination = (start - left) * 4
    if channels == 4:
        result[destination:destination + len(row)] = row
    else:
        for index in range(end - start):
            sample = row[index * channels:(index + 1) * channels]
            result[destination + index * 4:destination + (index + 1) * 4] = (
                sample + b'\xff' if channels == 3 else sample[:1] * 3 + (sample[1:] if channels == 2 else b'\xff'))
    return result


def verify_difference(root, record, images, rects, dpi):
    def rounded(number):
        return math.floor(number + 0.5) if number >= 0 else math.ceil(number - 0.5)
    crops = [tuple(rounded(number * dpi) for number in rect) for rect in rects]
    width, height = max(rect[2] for rect in crops), max(rect[3] for rect in crops)
    diff = checked_png(root, record['image'], [width, height], decode=True)
    changed = 0
    for y in range(height):
        rows = [crop_row(image, rect, y, width) for image, rect in zip(images, crops)]
        expected = bytearray(b'\x00\x00\x00\xff' * width)
        if rows[0] != rows[1]:
            for x in range(width):
                index = x * 4
                different = False
                for channel in range(3):
                    delta = abs(rows[0][index + channel] - rows[1][index + channel])
                    expected[index + channel] = delta
                    different |= delta != 0
                changed += different
        actual = crop_row(diff, (0, 0, width, height), y, width)
        if actual != expected:
            raise ValueError('Role difference image is not derived from the supplied originals')
    if isinstance(record.get('changedPixels'), bool) or record.get('changedPixels') != changed:
        raise ValueError('Role difference pixel count is not derived from its image')
    return changed


def evaluate_case(case, report, root, now):
    try:
        for field in ("caseId", "sourceSha", "registryHash", "renderFingerprint", "configuration", "state"):
            if field not in case or report.get(field) != case[field]:
                raise ValueError(f"Missing/stale/mismatched evidence: {field}")
        if report.get("status") in ("not_run", "blocked"):
            if not report.get("reason"):
                raise ValueError("Unrun evidence requires a reason")
            return {"status": report["status"], "reason": report["reason"]}
        age = timestamp(now) - timestamp(report["generatedAt"])
        if age < timedelta(minutes=-5) or age >= timedelta(days=90):
            raise ValueError("Future/expired evidence")
        if report.get("allowedDifferences") != case["allowedDifferences"]:
            raise ValueError("Intentional differences cannot be added after a failing render")
        environment = case["configuration"]["environment"]
        physical = [int(number * environment["dpi"]) for number in environment["size"]]
        failures = []
        images = []
        for side in ("lichess", "xiangqi"):
            result = report["sides"][side]
            if result["stage"] != case["state"] or result.get("realRatingPreferences") is not True:
                raise ValueError("Wrong phase/fixed test rating override")
            if result["environment"] != environment or result["physicalSize"] != physical:
                raise ValueError("Environment/text scale/DPI projection mismatch")
            if not result.get("driverProof") or not result.get("controllerProof"):
                raise ValueError("Missing real input/controller evidence")
            if not isinstance(result.get("requests"), list):
                raise ValueError("Missing boundary request trace")
            prefs = result["preferences"]
            if set(prefs) != set(case["configuration"]["preferences"]) or any(
                not equal_preference(expected, prefs[name])
                for name, expected in case["configuration"]["preferences"].items()
            ):
                raise ValueError("Requested preference was overridden or did not take effect")
            images.append(checked_png(root, result["original"], physical, decode=True))
            for role in case["requiredRoles"]:
                rect = result["roles"][role]["rect"]
                if len(rect) != 4 or any(isinstance(n, bool) or not isinstance(n, (int, float)) or not math.isfinite(n) for n in rect) or min(rect[2:]) <= 0:
                    raise ValueError("Invalid/missing comparable layout role")
        for role in case["requiredRoles"]:
            left = report["sides"]["lichess"]["roles"][role]["rect"]
            right = report["sides"]["xiangqi"]["roles"][role]["rect"]
            intentional = any(definition.get("kind") == "geometry" and role in definition.get("roles", [])
                              for definition in case.get("differenceDefinitions", {}).values())
            if not intentional and max(abs(a - b) for a, b in zip(left, right)) > 1:
                failures.append(f"{role}: geometry differs by more than one logical pixel")
            difference = report["differences"][role]
            changed = verify_difference(root, difference, images, [left, right], environment['dpi'])
            if role in case["pixelRoles"] and changed != 0:
                failures.append(f"{role}: shared-role pixels differ")
        return {"status": "failed" if failures else "passed", "reason": "; ".join(failures)}
    except (KeyError, TypeError, ValueError, OSError, struct.error, zlib.error) as error:
        return {"status": "invalid", "reason": str(error)}


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".partial")
    temporary.write_text(canonical(value) + "\n")
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    plan = commands.add_parser("plan")
    for name in ("registry", "catalogue", "runtime", "sha", "offset", "limit", "out"):
        plan.add_argument(f"--{name}", required=True)
    plan.add_argument("--role")
    plan.add_argument("--state")
    plan.add_argument("--github-output")
    verify = commands.add_parser("verify")
    verify.add_argument("--plan", required=True)
    verify.add_argument("--evidence", required=True)
    verify.add_argument("--out", required=True)
    args = parser.parse_args()
    if args.command == "plan":
        raw = json.loads(Path(args.registry).read_text())
        catalogue = json.loads(Path(args.catalogue).read_text())
        registry = resolve_registry(raw, catalogue)
        runtime = {"catalogue": catalogue, "renderer": json.loads(Path(args.runtime).read_text())}
        context = {"sourceSha": args.sha, "registryHash": digest(raw),
                   "renderFingerprint": fingerprint(args.sha, registry, runtime)}
        shards = plan_batch(registry, int(args.offset), int(args.limit), args.role, args.state)
        for shard in shards:
            for case in shard["cases"]:
                case.update(context)
                case["caseId"] = digest(case)
            write_json(Path(args.out) / f"shard-{shard['shard']}.json", {**context, "cases": shard["cases"]})
        summary = {**context, "totalPairs": str(count_cases(registry)), "requestedPairs": args.limit,
                   "scope": {"role": args.role, "state": args.state, "offset": args.offset},
                   "shards": len(shards), "concurrency": 4, "shardMinutes": 30, "complete": False,
                   "nonVisualAcceptance": raw.get("nonVisualAcceptance", {})}
        write_json(Path(args.out) / "registry-resolved.json", registry)
        write_json(Path(args.out) / "manifest.json", summary)
        matrix = {"include": [{"shard": shard["shard"]} for shard in shards]}
        if args.github_output:
            with Path(args.github_output).open("a") as output:
                output.write("matrix=" + canonical(matrix) + "\n")
        print(canonical(summary))
    else:
        plan_dir = Path(args.plan)
        manifest = json.loads((plan_dir / "manifest.json").read_text())
        now = datetime.now(timezone.utc).isoformat()
        records = []
        for shard in sorted(plan_dir.glob("shard-*.json")):
            for case in json.loads(shard.read_text())["cases"]:
                root = Path(args.evidence) / case["caseId"]
                path = root / "report.json"
                try:
                    report = json.loads(path.read_text()) if path.is_file() else {}
                except (OSError, ValueError):
                    report = {}
                records.append({"index": case["index"], "caseId": case["caseId"],
                                **evaluate_case(case, report, root, now)})
        counts = {status: sum(record["status"] == status for record in records)
                  for status in ("passed", "failed", "invalid", "not_run", "blocked")}
        summary = {**manifest, "batch": counts,
                   "unrunPairs": str(int(manifest["totalPairs"]) - counts["passed"] - counts["failed"] - counts["blocked"]),
                   "complete": counts["passed"] == int(manifest["totalPairs"]), "records": records}
        write_json(Path(args.out), summary)
        print(canonical({key: value for key, value in summary.items() if key != "records"}))
        if counts["passed"] != len(records):
            raise SystemExit(1)


if __name__ == "__main__":
    main()
