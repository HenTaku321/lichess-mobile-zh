#!/usr/bin/env bash
#
# Moves the Pikafish network to a new one, or checks that the one in hand is what the repository
# says it is. Run locally; it is not part of CI.
#
# The upgrade this automates is:
#
#   want to upgrade -> download the new dated network -> verify its hash -> verify its architecture
#   -> rewrite the constants -> recalibrate the difficulty -> release (zero engine changes)
#
# Two of those steps are mechanical and are done here. Two are not:
#
#   * `scripts/pikafish-net.json` is rewritten, because it is the one place the network is described
#     and everything else reads it.
#   * `lib/src/model/engine/engine_utils.dart` and `.github/workflows/build-linux.yml` are NOT
#     rewritten. The tool prints the lines that need to change instead. The anchors in those two
#     files are fragile — a comment drifts, the formatter reflows, and the build-linux one sits
#     inside a `run: |` block where a wrong indent only explodes at dispatch time — and a fragile
#     anchor that stops matching fails *silently*, turning the edit into a no-op. A printed diff
#     that a person applies, with CI red until they do, is worth more than a rewrite that might
#     quietly do nothing.
#   * Recalibrating the six difficulty levels is a person's judgement, not a tool's output. A new
#     network plays differently, so the curve has to be re-tuned by hand; see the plan's section on
#     it. (Swapping to a network of the same generation, as the first release did, changes nothing
#     about strength and needs no recalibration.)
#
# Usage:
#   ./scripts/update-pikafish-net.sh --check <file>    verify a local file against the manifest
#   ./scripts/update-pikafish-net.sh --check           verify the asset already in the tree
#   ./scripts/update-pikafish-net.sh <url>             download and verify, then print the edits
#   ./scripts/update-pikafish-net.sh <url> --write     ... and rewrite the manifest
#
# The architecture check is the one that matters most and the one CI cannot do: it needs zstd, which
# no runner has. A network whose architecture hash does not match the vendored engine is not
# refused with a message — `Network::verify` prints five ERROR lines and calls `exit(EXIT_FAILURE)`,
# which beside a Dart VM deadlocks the threads waiting on the search. So a network is only accepted
# here after its header has been read and compared to what the headers compute.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$REPO_DIR/scripts/pikafish-net.json"
ASSET="$REPO_DIR/assets/pikafish/pikafish.nnue"

die() {
  echo "::error::$*" >&2
  exit 1
}

manifest_field() {
  python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' \
    "$MANIFEST" "$1"
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
# The header is `u32 version, u32 hashValue, u32 descLength`, then the description — but only
# *after* decompression. The file is zstd-compressed and the first block is a compressed one, not a
# raw one, so the header is not at a fixed offset in the file: reading bytes 4..8 of the compressed
# file gives `0b be fc 9f…` where the decompressed header has `fa 8a 44 6a a6 0f c7 40`. It has to
# be decompressed.
#
# Decompressed to a file rather than piped through `head`: under `set -euo pipefail` a `zstd -dc f |
# head -c 12` exits 141, because head closes the pipe and zstd dies of SIGPIPE.
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
# Upper-cased to match the spelling the header script uses, so the comparison does not fail on
# case alone.
print('0x%08X 0x%08X %d' % (version, hash_value, desc_length))
PY
}

# The architecture hash the vendored engine expects, from the headers themselves.
#
# Uppercased to match the header's spelling. The two are printed in different cases — the script
# writes `0x40C70FA6` from the headers, the network's own header is read in lowercase — and a
# comparison that failed on case alone would reject a network that is in fact correct.
expected_architecture_hash() {
  dart run "$REPO_DIR/scripts/pikafish_net_hash.dart" 2>/dev/null \
    | awk '/architecture hash/ { print $NF }' \
    | sed 's/^0x/0x/; s/\(0x\)\(.*\)/\1\U\2/'
}

verify_file() {
  local file="$1" label="$2"
  [ -f "$file" ] || die "$label does not exist: $file"

  # The manifest's own archHash is deliberately not read here: the architecture is checked against
  # the vendored headers below, so a manifest hand-edited to a wrong archHash cannot make this
  # agree with itself.
  local want_size want_sha
  want_size="$(manifest_field size)"
  want_sha="$(manifest_field sha256)"

  local size sha
  size="$(size_of "$file")"
  sha="$(sha256_of "$file")"

  echo "$label"
  echo "  size     $size (manifest: $want_size)"
  echo "  sha256   $sha"
  echo "           (manifest: $want_sha)"

  [ "$size" = "$want_size" ] || die "$label is $size bytes, the manifest says $want_size"
  [ "$sha" = "$want_sha" ] || die "$label does not have the manifest's sha256"

  local header version arch desc
  header="$(header_architecture_hash "$file")"
  read -r version arch desc <<<"$header"

  local expected
  expected="$(expected_architecture_hash)"

  echo "  header   version $version, archHash $arch, description $desc bytes"
  echo "           (the vendored headers expect $expected)"

  [ "$arch" = "$expected" ] || die "$label carries architecture hash $arch, but the vendored \
engine computes $expected. The engine would refuse this network, and would do it by exiting from \
inside the first search — a hang with no message. Do not ship it."

  echo "  OK — the file is the one the manifest describes, and the engine can load it"
}

# The lines a person has to change after the manifest moves, printed rather than applied.
print_manual_edits() {
  local size sha
  size="$(manifest_field size)"
  sha="$(manifest_field sha256)"

  cat <<EOF

The manifest is updated. Three places hold a copy of these numbers and are NOT rewritten by this
tool — the anchors are fragile, and an anchor that stops matching fails silently. Change them by
hand, then let CI confirm:

  lib/src/model/engine/engine_utils.dart
      const kPikafishNnueSize = $size;
      const kPikafishNnueSha256 = '$sha';

  .github/workflows/build-linux.yml — the size comes from the manifest now, so only the comment
  above it needs a look; nothing numeric is left to update there.

  HenTaku321/dart-multistockfish — outside this repository, and it will go stale silently:
      pkgs/multistockfish_pikafish/README.md    the size, the sha256 and the decompressed size
      pkgs/multistockfish_pikafish/CHANGELOG.md the sha256

Then run the gates, none of which this tool runs for you:

  flutter test test/model/engine/pikafish_net_manifest_test.dart
  dart run scripts/pikafish_net_hash.dart --check

And if the new network is a different generation, recalibrate the six difficulty levels by hand:
the curve is depth and movetime, it must stay monotonic, and both ends stay pinned.
EOF
}

write_manifest() {
  local url="$1" size="$2" sha="$3" arch="$4" version="$5"
  python3 - "$MANIFEST" "$url" "$size" "$sha" "$arch" "$version" <<'PY'
import json, sys
path, url, size, sha, arch, version = sys.argv[1:7]
with open(path) as f:
    manifest = json.load(f)
manifest['url'] = url
manifest['size'] = int(size)
manifest['sha256'] = sha
manifest['archHash'] = arch
with open(path, 'w') as f:
    json.dump(manifest, f, indent=2)
    f.write('\n')
PY
  echo "Rewrote $MANIFEST"
  echo "  url      $url"
  echo "  size     $size"
  echo "  sha256   $sha"
  echo "  archHash $arch"
  echo "  (network format version $version, unchanged in the manifest)"
}

main() {
  local mode='' url='' write=false
  for argument in "$@"; do
    case "$argument" in
      --check) mode=check ;;
      --write) write=true ;;
      -*) die "unknown option: $argument" ;;
      *) url="$argument" ;;
    esac
  done

  if [ "$mode" = check ]; then
    verify_file "${url:-$ASSET}" "${url:-the asset already in the tree}"
    return
  fi

  [ -n "$url" ] || die "give a URL to download, or --check to verify what is here"

  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/pikafish-net-download.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT

  echo "Downloading $url"
  curl --fail --location --retry 3 --retry-delay 5 --output "$tmp" "$url"

  # Verified against the *downloaded* bytes before anything in the tree is touched, and the
  # architecture is checked against the headers rather than against the manifest: a manifest that
  # was hand-edited to a wrong archHash would otherwise make this agree with itself.
  local size sha header version arch expected
  size="$(size_of "$tmp")"
  sha="$(sha256_of "$tmp")"
  header="$(header_architecture_hash "$tmp")"
  read -r version arch desc <<<"$header"
  expected="$(expected_architecture_hash)"

  echo "  size     $size"
  echo "  sha256   $sha"
  echo "  header   version $version, archHash $arch, description $desc bytes"

  [ "$arch" = "$expected" ] || die "the downloaded network carries architecture hash $arch, but \
the vendored engine computes $expected. This network belongs to a different Pikafish: the engine \
would refuse it, and would do it by exiting from inside the first search — a hang with no message. \
Bump the vendored snapshot first, or pick the network that pairs with the one already vendored."

  if [ "$write" = true ]; then
    write_manifest "$url" "$size" "$sha" "$arch" "$version"
  else
    echo
    echo "Verified. Re-run with --write to rewrite the manifest to:"
    echo "  url      $url"
    echo "  size     $size"
    echo "  sha256   $sha"
    echo "  archHash $arch"
  fi

  print_manual_edits
}

main "$@"
