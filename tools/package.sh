#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Usage: bash tools/package.sh [vX.Y.Z] [output-directory]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export LC_ALL=C TZ=UTC
version=$(luajit tools/version.lua "${1:-}")
output_dir=${2:-dist}
mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
source_epoch=$(git log -1 --format=%ct)
archive="koreader-coversearch-v$version.zip"

# Only tracked runtime files belong in the installable plugin. No developer
# documents, screenshots, tests, untracked files, or previous archives.
git ls-files -z -- coversearch.koplugin > "$staging/tracked-files"
while IFS= read -r -d '' source_file; do
    if [[ ! -f "$source_file" || -L "$source_file" ]]; then
        printf 'Not a regular runtime file: %s\n' "$source_file" >&2
        exit 1
    fi
    install -D -m 0644 "$source_file" "$staging/payload/$source_file"
done < "$staging/tracked-files"
install -D -m 0644 LICENSE "$staging/payload/coversearch.koplugin/LICENSE"
find "$staging/payload" -type f -exec touch -d "@$source_epoch" {} +

# Normalize ordering, permissions, timestamps, and ZIP extra fields so the same
# commit and Info-ZIP version produce the same bytes on repeated builds.
(
    cd "$staging/payload"
    find coversearch.koplugin -type f | sort | zip -q -9 -X "$staging/$archive" -@
)
unzip -tq "$staging/$archive"
mv "$staging/$archive" "$output_dir/$archive"
(
    cd "$output_dir"
    sha256sum "$archive" > "$archive.sha256"
    cat "$archive.sha256"
    unzip -l "$archive"
)
