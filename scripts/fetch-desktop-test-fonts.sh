#!/usr/bin/env bash
# Fixed real fonts for desktop screenshots; never shipped in the production bundle.
set -euo pipefail
dest=${1:?usage: fetch-desktop-test-fonts.sh DEST}
mkdir -p "$dest"
manifest="$(dirname "$0")/desktop-test-fonts.json"
while IFS=$'\t' read -r file url digest; do
  if [ ! -f "$dest/$file" ] || ! printf '%s  %s\n' "$digest" "$dest/$file" | sha256sum --check --status; then
    curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 --max-time 180 \
      "$url" -o "$dest/$file.download"
    printf '%s  %s\n' "$digest" "$dest/$file.download" | sha256sum --check
    mv "$dest/$file.download" "$dest/$file"
  fi
  printf '%s  %s\n' "$digest" "$dest/$file" | sha256sum --check
done < <(python3 -c 'import json,sys; print("\n".join("\t".join(f[k] for k in ("file","url","sha256")) for f in json.load(open(sys.argv[1]))["fonts"]))' "$manifest")
