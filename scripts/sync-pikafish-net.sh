#!/usr/bin/env bash
#
# Keeps the Pikafish network current, unattended. Run by
# `.github/workflows/sync-pikafish-net.yml` on a schedule; runnable by hand too.
#
# The problem this exists for. Pikafish ships no network inside the engine: it loads one from disk
# through `EvalFile`, and an engine started without one does not fail — it evaluates every position
# to noise, which on a board looks like an opponent playing at random. So the network is an asset
# the app has to carry, and it is fetched at build time (scripts/fetch-pikafish-nnue.sh) rather than
# committed. Which network is right is not a free choice: the engine refuses one whose architecture
# hash is not the one its own headers compute, and it refuses it by calling exit(EXIT_FAILURE) from
# inside the first search, which beside a Dart VM deadlocks the waiting threads instead of reporting
# anything. Nothing in the test suite can catch that.
#
# What went wrong once already. The network used to be fetched from official-pikafish/Networks'
# `master-net` release, whose single asset is replaced in place. On 2026-10-14 upstream replaced it,
# every build broke on a size mismatch, and the replacement turned out to be architecture-
# incompatible with the engine we vendored. A URL whose content can change is not a pin.
#
# So the network is now pinned twice over: `scripts/pikafish-net.json` records the bytes, and the
# bytes are hosted on a fixed release tag of our own fork. This script is what moves the pin
# forward, and it moves it only when doing so is provably safe:
#
#   resolve -> download -> verify size and sha256 -> verify the architecture against the vendored
#   headers -> republish under a tag derived from the bytes -> rewrite the manifest -> rewrite the
#   app's constants -> hand off to the builds
#
# Two things it deliberately does NOT do:
#
#   * It does not recalibrate the six difficulty levels. A different network plays differently, so
#     the curve has to be re-tuned by hand; the script prints that and stamps the manifest with the
#     network it was last calibrated against, so the drift is visible rather than silent.
#   * It does not follow `master-net`. That is the rolling release described above. The source is
#     the engine repository's *dated* releases, whose tags and digests cannot move.
#
# The floor. Our vendored engine is a snapshot of a particular upstream commit, and the dated
# releases are tagged earlier than it (2026-09-06 against a 2026-10-11 snapshot). Taking the newest
# release unconditionally would therefore *downgrade* the network on the first run — a silent
# strength regression in shipped builds. `source.notBefore` is that commit's date, and nothing
# published before it is ever considered. Today the script finds nothing to do, which is correct.
#
# Usage:
#   ./scripts/sync-pikafish-net.sh --dry-run    report what it would do, touch nothing
#   ./scripts/sync-pikafish-net.sh              do it
#
# Environment:
#   GH_TOKEN   required to read the upstream release list and to publish the asset

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$REPO_DIR/scripts/pikafish-net.json"
CONSTANTS="$REPO_DIR/lib/src/model/engine/engine_utils.dart"

# The scratch directory, and the cleanup that removes it.
#
# `work` is a global and the trap is installed here, at the top, rather than next to the code that
# fills it. A trap that references a `local` is not a trap: the EXIT handler runs after the
# function that declared the variable has returned, so under `set -u` the handler itself aborts
# with "unbound variable" and the directory is left behind. Moving the declaration out of `main`
# was not enough either — the handler still ran against a variable that no longer existed, and the
# run ended in exit 1 *after* doing all of its actual work.
work=''
trap 'if [ -n "$work" ]; then rm -rf "$work"; fi' EXIT

dry_run=false
for argument in "$@"; do
  case "$argument" in
    --dry-run) dry_run=true ;;
    -*) echo "::error::unknown option: $argument" >&2; exit 1 ;;
    *) echo "::error::unexpected argument: $argument" >&2; exit 1 ;;
  esac
done

die() {
  echo "::error::$*" >&2
  exit 1
}

note() {
  echo "  $*"
}

# One field of the manifest, as a bare string. python3 rather than jq: python3 is on both the ubuntu
# and the macOS runners, jq is not guaranteed, and python3 is already needed to rewrite the file.
manifest_field() {
  python3 -c 'import json, sys
m = json.load(open(sys.argv[1]))
for key in sys.argv[2].split("."):
    if m is None:
        break
    m = m.get(key) if isinstance(m, dict) else None
print("" if m is None else m)' "$MANIFEST" "$1"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

size_of() {
  stat -c%s "$1" 2>/dev/null || stat -f%z "$1"
}

# The architecture hash in a network file's header.
#
# The header is `u32 version, u32 hashValue, u32 descLength` then the description — but only *after*
# decompression. The file is zstd-compressed and its first block is a compressed one, not a raw one,
# so the header is not at a fixed offset in the file: the bytes at offset 12 are `0b be fc 9f…`
# where the decompressed header has `fa 8a 44 6a a6 0f c7 40`. Decompression is genuinely required.
#
# Decompressed to a file rather than piped through `head`: under `set -euo pipefail` a
# `zstd -dc f | head -c 12` exits 141, because head closes the pipe and zstd dies of SIGPIPE.
header_architecture_hash() {
  local source="$1" decompressed
  decompressed="$(mktemp "${TMPDIR:-/tmp}/pikafish-net-header.XXXXXX")"
  trap 'rm -f "$decompressed"' RETURN

  if command -v zstd >/dev/null 2>&1; then
    zstd -dc "$source" > "$decompressed" 2>/dev/null || die "could not decompress $source"
  elif command -v unzstd >/dev/null 2>&1; then
    unzstd -c "$source" > "$decompressed" 2>/dev/null || die "could not decompress $source"
  else
    die "no zstd on PATH — the network header cannot be read without it"
  fi

  python3 - "$decompressed" <<'PY'
import struct, sys
with open(sys.argv[1], 'rb') as f:
    head = f.read(12)
if len(head) < 12:
    sys.exit('the decompressed network is shorter than its header')
version, hash_value, desc_length = struct.unpack('<III', head)
print('0x%08X 0x%08X %d' % (version, hash_value, desc_length))
PY
}

# The architecture hash the vendored engine expects, computed from its own headers. This is the
# check that matters most and the one CI cannot do on its own: it needs zstd, which no runner has.
expected_architecture_hash() {
  dart run "$REPO_DIR/scripts/pikafish_net_hash.dart" 2>/dev/null \
    | awk '/architecture hash/ { print $NF }' \
    | sed 's/^0x/0x/; s/\(0x\)\(.*\)/\1\U\2/'
}

# The newest upstream release worth considering, as `<tag> <published_at> <asset_name> <asset_size>
# <asset_digest>`. "Worth considering" means: published at or after source.notBefore, and carrying
# an asset whose name matches source.assetPattern. A release before the floor is not considered at
# all — see the note at the top about the downgrade it would otherwise cause.
resolve_source() {
  local repo="$1" pattern="$2" not_before="$3"
  python3 - "$repo" "$pattern" "$not_before" <<'PY'
import json, os, re, subprocess, sys
repo, pattern, not_before = sys.argv[1:4]

token = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
env = dict(os.environ)
if token:
    env['GH_TOKEN'] = token

raw = subprocess.run(
    ['gh', 'api', '--paginate', 'repos/%s/releases' % repo],
    capture_output=True, text=True, env=env, check=True).stdout
# `--paginate` concatenates one JSON array per page, so they are decoded one after another rather
# than parsed as a single document.
releases = []
decoder = json.JSONDecoder()
position = 0
while position < len(raw):
    while position < len(raw) and raw[position] in ' \t\r\n':
        position += 1
    if position >= len(raw):
        break
    page, position = decoder.raw_decode(raw, position)
    releases.extend(page)

matcher = re.compile(pattern)
candidates = []
for release in releases:
    if release.get('draft') or release.get('prerelease'):
        continue
    published = release.get('published_at') or ''
    if published < not_before:
        continue
    for asset in release.get('assets') or []:
        if not matcher.fullmatch(asset.get('name') or ''):
            continue
        digest = asset.get('digest') or ''
        candidates.append((published, release['tag_name'], asset['name'],
                           asset['size'], digest.split(':', 1)[-1]))
        break

if not candidates:
    sys.exit(0)
candidates.sort()
published, tag, name, size, digest = candidates[-1]
print('%s %s %s %s %s' % (tag, published, name, size, digest))
PY
}

# Rewrite the manifest in place. A no-op rewrite is byte-identical — json.dump with the same indent
# and a trailing newline reproduces the file exactly — so the diff after a real change is only the
# fields that moved.
write_manifest() {
  local url="$1" size="$2" sha="$3" arch="$4" tag="$5"
  python3 - "$MANIFEST" "$url" "$size" "$sha" "$arch" "$tag" <<'PY'
import json, sys
path, url, size, sha, arch, tag = sys.argv[1:7]
with open(path) as f:
    manifest = json.load(f)
manifest['url'] = url
manifest['size'] = int(size)
manifest['sha256'] = sha
manifest['archHash'] = arch
manifest.setdefault('source', {})['tag'] = tag
with open(path, 'w') as f:
    json.dump(manifest, f, indent=2)
    f.write('\n')
PY
}

# Rewrite the two constants the app compiles in. The anchors are the whole point: the match counts
# are asserted to be exactly one each, so a comment drifting or the formatter reflowing turns this
# into a loud failure rather than a silent no-op that leaves the app verifying a network nobody
# fetched.
#
# The check is the count, and only the count. An earlier version also compared the file's digest
# before and after and treated "unchanged" as "the anchors matched nothing" — which is wrong, and
# wrong in the direction that matters: syncing to a network the constants already describe is a
# legitimate no-op, and that version failed the run for it.
rewrite_constants() {
  local size="$1" sha="$2"
  python3 - "$CONSTANTS" "$size" "$sha" <<'PY'
import re, sys
path, size, sha = sys.argv[1:4]
with open(path) as f:
    text = f.read()
text, count_size = re.subn(r'(const kPikafishNnueSize = )\d+;', r'\g<1>' + size + ';', text)
text, count_sha = re.subn(
    r"(const kPikafishNnueSha256 = ')[0-9a-f]{64}(';)", r'\g<1>' + sha + r'\g<2>', text)
if count_size != 1 or count_sha != 1:
    sys.exit('expected exactly one of each constant in %s, found %d and %d'
             % (path, count_size, count_sha))
with open(path, 'w') as f:
    f.write(text)
PY
}

# Say so when the six levels were tuned against a different network than the one now pinned.
#
# A warning rather than a failure, and deliberately so: the build is correct, the levels are merely
# untuned, and a red run would be read as "the network is broken" when it is not. It is checked on
# every path out of main, not only on the run that swapped the bytes — a re-run of a swap that left
# the curve uncalibrated has to keep saying so, or the one run that mattered is the only one that
# ever mentions it.
check_calibration() {
  local calibrated_for current_sha
  calibrated_for="$(manifest_field difficultyCalibratedFor)"
  current_sha="$(manifest_field sha256)"
  [ "$calibrated_for" = "$current_sha" ] && return 0
  echo "::warning title=Difficulty not recalibrated::The six levels in \
lib/src/model/xiangqi/xiangqi_game_controller.dart were tuned against network \
${calibrated_for:-unknown}, and the pinned network is now $current_sha. Re-tune them by hand — both \
columns strictly increasing, both ends pinned — then set difficultyCalibratedFor in \
scripts/pikafish-net.json to $current_sha."
}

# Publish the bytes under a tag derived from the bytes. This is the property `master-net` lacks:
# the tag cannot point at anything else later, so a build pinned to it cannot break underneath it.
publish_asset() {
  local file="$1" tag="$2" repo="$3" sha="$4"
  gh release view "$tag" --repo "$repo" >/dev/null 2>&1 && {
    note "release $tag already exists; leaving it alone"
    return
  }
  gh release create "$tag" "$file" \
    --repo "$repo" \
    --title "Pikafish network $tag" \
    --notes "The Pikafish network, pinned by content. sha256 \`$sha\`. Published by scripts/sync-pikafish-net.sh; the tag is derived from the digest, so it can never point at different bytes." \
    --prerelease
}

main() {
  command -v gh >/dev/null 2>&1 || die "gh is not on PATH"
  [ -f "$MANIFEST" ] || die "$MANIFEST is missing"

  local source_repo source_pattern source_not_before current_tag
  source_repo="$(manifest_field source.repo)"
  source_pattern="$(manifest_field source.assetPattern)"
  source_not_before="$(manifest_field source.notBefore)"
  current_tag="$(manifest_field source.tag)"

  [ -n "$source_repo" ] || die "the manifest has no source.repo"
  [ -n "$source_pattern" ] || die "the manifest has no source.assetPattern"
  [ -n "$source_not_before" ] || die "the manifest has no source.notBefore"

  echo "Looking for a network newer than $source_not_before in $source_repo"
  local resolved
  resolved="$(resolve_source "$source_repo" "$source_pattern" "$source_not_before")"

  if [ -z "$resolved" ]; then
    echo "Nothing published at or after $source_not_before carries a network. Nothing to do."
    check_calibration
    return
  fi

  local tag published asset_name asset_size asset_digest
  read -r tag published asset_name asset_size asset_digest <<<"$resolved"
  echo "Newest candidate: $tag ($published), asset $asset_name"
  note "size   $asset_size"
  note "digest $asset_digest"

  if [ "$tag" = "$current_tag" ]; then
    echo "The manifest is already synced to $tag. Nothing to do."
    check_calibration
    return
  fi

  echo "The manifest is on ${current_tag:-no release yet}; $tag is newer."

  if [ "$dry_run" = true ]; then
    echo "Dry run — stopping before anything is downloaded or written."
    check_calibration
    return
  fi

  work="$(mktemp -d "${TMPDIR:-/tmp}/pikafish-sync.XXXXXX")"

  echo "Downloading $asset_name"
  curl --fail --location --retry 3 --retry-delay 5 \
    --output "$work/$asset_name" \
    "https://github.com/$source_repo/releases/download/$tag/$asset_name"

  local archive_size archive_digest
  archive_size="$(size_of "$work/$asset_name")"
  archive_digest="$(sha256_of "$work/$asset_name")"
  [ "$archive_size" = "$asset_size" ] \
    || die "$asset_name is $archive_size bytes, the release says $asset_size"
  if [ -n "$asset_digest" ]; then
    [ "$archive_digest" = "$asset_digest" ] \
      || die "$asset_name does not have the digest the release advertises"
    note "archive sha256 verified against the release's own digest"
  else
    note "the release advertises no digest; only the size was checked"
  fi

  echo "Extracting the network"
  local member
  member="$(manifest_field source.member)"
  [ -n "$member" ] || die "the manifest has no source.member"
  command -v 7z >/dev/null 2>&1 || die "7z is not on PATH — the release archive cannot be read"
  mkdir -p "$work/out"
  7z e -y -o"$work/out" "$work/$asset_name" "$member" >/dev/null \
    || die "could not extract $member from $asset_name"
  local network="$work/out/$member"
  [ -f "$network" ] || die "$asset_name does not contain $member"

  local size sha header version arch desc expected
  size="$(size_of "$network")"
  sha="$(sha256_of "$network")"
  header="$(header_architecture_hash "$network")"
  read -r version arch desc <<<"$header"
  expected="$(expected_architecture_hash)"

  echo "The extracted network"
  note "size     $size"
  note "sha256   $sha"
  note "header   version $version, archHash $arch, description $desc bytes"
  note "the vendored headers expect $expected"

  # `owner/name`, from either an https or an ssh remote. The `.git` suffix is stripped first and
  # separately: a single lazy pattern leaves it attached, because `[^/]+?` expands to satisfy the
  # whole match and the optional group then matches nothing — which produced a repo called
  # `lichess-mobile-zh.git` and a 404 on the publish.
  local fork
  fork="$(git -C "$REPO_DIR" remote get-url origin \
    | sed -E 's#\.git$##' \
    | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#')"
  [ -n "$fork" ] || die "could not work out the repository from the origin remote"

  # The network is published to the *engine* repository, not to this one, and the reason is not
  # tidiness. `scripts/fetch-pikafish-nnue.sh` downloads the asset with a plain `curl` and no
  # credentials, and this repository is private — an asset published here would be a URL every
  # build fails on, with a 404 that reads like a missing file rather than like a permission. The
  # engine repository is public, the network is a property of the engine rather than of the app,
  # and it is where the bytes already live.
  local publish_repo
  publish_repo="$(manifest_field source.publishRepo)"
  [ -n "$publish_repo" ] || die "the manifest has no source.publishRepo"

  local publish_visibility
  publish_visibility="$(gh repo view "$publish_repo" --json visibility -q .visibility 2>/dev/null || true)"
  [ "$publish_visibility" = "PUBLIC" ] || die "$publish_repo is ${publish_visibility:-unreachable}; \
the fetch script downloads the network with no credentials, so it has to be public"

  if [ "$arch" != "$expected" ]; then
    # Not a transient failure: the upstream network has moved to an architecture the vendored
    # engine does not implement, and no amount of retrying will change that. The fix is a new
    # engine snapshot, which is a different piece of work — so this is reported as an issue on our
    # own repository rather than left as a failed scheduled run nobody looks at.
    # The issue goes on *this* repository, not on the one the network is published to: bumping the
    # vendored engine is work that happens here, and an issue on the engine fork would be filed
    # where nobody is looking for it.
    local title="Pikafish network $tag is not compatible with the vendored engine"
    if ! gh issue list --repo "$fork" --state open --search "$title in:title" --json title \
        -q '.[].title' 2>/dev/null | grep -qxF "$title"; then
      gh issue create \
        --repo "$fork" \
        --title "$title" \
        --body "$(printf '%s\n' \
          "The newest Pikafish network at or after \`$source_not_before\` carries architecture hash" \
          "\`$arch\`, but the vendored engine computes \`$expected\`. The engine would refuse it, and" \
          "would do it by exiting from inside the first search — a hang with no message." \
          "" \
          "Source: \`$source_repo\` release \`$tag\`, asset \`$asset_name\`." \
          "" \
          "This is not something the sync can retry past: the vendored engine snapshot has to be" \
          "bumped first (see the plan's wave C), and the six difficulty levels recalibrated after.")" \
        || note "could not open an issue; the failed run is the report"
    fi
    die "$tag carries architecture hash $arch, the vendored engine computes $expected"
  fi

  # The tag is derived from the digest, so a re-run of the same network lands on the same release
  # and the publish below is a no-op rather than a second copy. The first release, published by
  # hand before this script existed, is named after the engine commit instead
  # (`pikafish-net-532c3ff216`); it is not renamed, because the manifest of an already-published
  # commit points at it and the bytes are verified against `sha256` either way.
  local new_tag="pikafish-net-${sha:0:12}"
  echo "Publishing the network as $publish_repo release $new_tag"
  publish_asset "$network" "$new_tag" "$publish_repo" "$sha"

  local url="https://github.com/$publish_repo/releases/download/$new_tag/$member"
  write_manifest "$url" "$size" "$sha" "$arch" "$tag"
  note "manifest rewritten: url $url"
  rewrite_constants "$size" "$sha"
  note "engine_utils.dart rewritten: $size bytes, sha256 $sha"

  cat <<EOF

The network is now $new_tag (from $source_repo $tag).

NOT done, and not doable by a script: the six difficulty levels in
lib/src/model/xiangqi/xiangqi_game_controller.dart are a curve on depth and movetime, and a
different network plays differently. The two hard constraints are that both columns stay strictly
increasing and that both ends stay pinned.
EOF

  check_calibration
}

main "$@"
