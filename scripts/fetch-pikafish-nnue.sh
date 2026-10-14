#!/usr/bin/env bash
#
# Fetches the Pikafish network into the asset tree.
#
# Pikafish embeds no network: it loads one from disk through its `EvalFile` option, and an engine
# started without one does not fail — it evaluates every position to noise, which on a board looks
# like a computer that plays at random rather than like a missing file. So the file has to be in
# the app, and it is fetched here rather than committed: 48 MB of binary in git, for a file that is
# one HTTP request away, is a cost every clone would pay for the rest of the project's life.
#
# Every workflow that builds the app runs this before `flutter build`, and so does a local build —
# once. The size and the hash are checked because the file decides how strong the opponent is and
# the app has no way to tell a truncated download from a complete one.
#
# The URL and the two values it is checked against come from `scripts/pikafish-net.json`, which is
# the one place the network is described. The URL is a fixed release on the fork that also carries
# the vendored Pikafish snapshot, and deliberately not the `master-net` release of
# official-pikafish/Networks: that one is a rolling release whose asset is replaced in place, so a
# build pinned to it breaks the day upstream ships a new network, which is what happened on
# 2026-10-14. A network from a different Pikafish is not rejected with a message, it is rejected
# deep inside the first search — so if the vendored commit is ever bumped, the manifest's URL, hash
# and archHash, and the constants in `lib/src/model/engine/engine_utils.dart`, all move together.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$REPO_DIR/assets/pikafish/pikafish.nnue"
MANIFEST="$REPO_DIR/scripts/pikafish-net.json"

# Read with python3 rather than jq: python3 is on both the ubuntu and the macOS runners and is
# already a dependency of scripts/update-pikafish-net.sh, while jq is not guaranteed to be there.
# Three bare values on three lines, so SIZE stays an integer the arithmetic below can use.
if [ ! -f "$MANIFEST" ]; then
  echo "::error::$MANIFEST is missing — it is the source of the URL and the checks below" >&2
  exit 1
fi
{ read -r URL; read -r SIZE; read -r SHA256; } < <(
  python3 -c 'import json, sys
m = json.load(open(sys.argv[1]))
print(m["url"])
print(m["size"])
print(m["sha256"])' "$MANIFEST"
)

# The digest of $1, printed alone. Both spellings are asked for rather than one: the macOS runner's
# sha256sum is the BSD one, which computes a digest but has no `-c`, and the workflows run on it as
# well as on Linux — a check that silently cannot run there would have failed the build on a file
# that was in fact correct. Both forms take the file as an argument and print `<digest>  <name>`.
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

if [ -f "$DEST" ]; then
  actual_size=$(stat -c%s "$DEST" 2>/dev/null || stat -f%z "$DEST")
  if [ "$actual_size" = "$SIZE" ] && [ "$(sha256_of "$DEST")" = "$SHA256" ]; then
    echo "pikafish.nnue is already there and intact ($SIZE bytes)"
    exit 0
  fi
  echo "pikafish.nnue is there but not the file this build wants; fetching it again" >&2
fi

mkdir -p "$(dirname "$DEST")"
tmp="$DEST.part"
trap 'rm -f "$tmp"' EXIT

echo "Downloading pikafish.nnue ($((SIZE / 1024 / 1024)) MB) from $URL"
curl --fail --location --retry 3 --retry-delay 5 --output "$tmp" "$URL"

actual_size=$(stat -c%s "$tmp" 2>/dev/null || stat -f%z "$tmp")
if [ "$actual_size" != "$SIZE" ]; then
  echo "::error::pikafish.nnue is $actual_size bytes, expected $SIZE" >&2
  exit 1
fi
actual_digest=$(sha256_of "$tmp")
if [ "$actual_digest" != "$SHA256" ]; then
  echo "::error::pikafish.nnue does not have the expected sha256" >&2
  echo "expected: $SHA256" >&2
  echo "actual:   $actual_digest" >&2
  exit 1
fi

mv "$tmp" "$DEST"
trap - EXIT
echo "Wrote $DEST ($actual_size bytes, sha256 verified)"
