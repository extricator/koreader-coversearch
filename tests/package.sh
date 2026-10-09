#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export LC_ALL=C
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
version=$(luajit tools/version.lua)
archive="koreader-coversearch-v$version.zip"
bash tools/package.sh "v$version" "$scratch/first" > "$scratch/build.log"
bash tools/package.sh "v$version" "$scratch/second" >> "$scratch/build.log"
cmp "$scratch/first/$archive" "$scratch/second/$archive"
(
    cd "$scratch/first"
    sha256sum --check "$archive.sha256"
)
{ git ls-files -- coversearch.koplugin; printf '%s\n' coversearch.koplugin/LICENSE; } | sort > "$scratch/expected"
unzip -Z1 "$scratch/first/$archive" | sort > "$scratch/actual"
diff -u "$scratch/expected" "$scratch/actual"
unzip -q "$scratch/first/$archive" -d "$scratch/extracted"
while IFS= read -r source_file; do
    cmp "$source_file" "$scratch/extracted/$source_file"
done < <(git ls-files -- coversearch.koplugin)
cmp LICENSE "$scratch/extracted/coversearch.koplugin/LICENSE"
for bad_tag in v999.999.999 v01.1.16 0.1.16 'v0.1.16;echo unexpected'; do
    if bash tools/package.sh "$bad_tag" "$scratch/rejected" > "$scratch/rejected.log" 2>&1; then
        printf 'Accepted an invalid tag: %s\n' "$bad_tag" >&2
        exit 1
    fi
    [[ ! -e "$scratch/rejected" ]]
done
printf '%s\n' 'PASS repeatable ZIP, SHA-256, exact runtime contents, extraction, and tag/version validation'
