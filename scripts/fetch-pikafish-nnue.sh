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
# The URL is the `master-net` release of official-pikafish/Networks, which is the network the
# vendored Pikafish snapshot in the `multistockfish_pikafish` package is paired with. A network
# from a different Pikafish is not rejected with a message, it is rejected deep inside the first
# search — so if the vendored commit is ever bumped, this URL, the hash below, and the constants in
# `lib/src/model/engine/engine_utils.dart` all move together.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$REPO_DIR/assets/pikafish/pikafish.nnue"

URL='https://github.com/official-pikafish/Networks/releases/download/master-net/pikafish.nnue'
SIZE=50244700
SHA256='10b84dd80bb4e324aa389cab327feeb7b4c44578e35a86105d4fcd5f840c3ac7'

if [ -f "$DEST" ]; then
  actual_size=$(stat -c%s "$DEST" 2>/dev/null || stat -f%z "$DEST")
  if [ "$actual_size" = "$SIZE" ] && echo "$SHA256  $DEST" | sha256sum -c --status; then
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
if ! echo "$SHA256  $tmp" | sha256sum -c --status; then
  echo "::error::pikafish.nnue does not have the expected sha256" >&2
  echo "expected: $SHA256" >&2
  echo "actual:   $(sha256sum "$tmp" | cut -d' ' -f1)" >&2
  exit 1
fi

mv "$tmp" "$DEST"
trap - EXIT
echo "Wrote $DEST ($actual_size bytes, sha256 verified)"
