#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Called after validation, packaging, version push, and attestation.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source tools/release-common.sh
release_sha=${RELEASE_SHA:-${GITHUB_SHA:?Missing source commit}}
release_context "$release_sha"
version=$(luajit tools/version.lua "${1:?Provide the release tag}")
tag="v$version"
archive="koreader-coversearch-$tag.zip"
(cd dist && sha256sum --check "$archive.sha256")
: "${GITHUB_SERVER_URL:?Missing GitHub URL}"
: "${GITHUB_RUN_ID:?Missing workflow run}"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

release_target "$tag" "$release_sha"
if [[ "$release_tag_exists" == false ]]; then
    gh api 'repos/{owner}/{repo}/git/refs' --method POST \
        -f "ref=refs/tags/$tag" -f "sha=$release_sha" > /dev/null
fi

if [[ "$release_draft" == true ]]; then
    # Keep any release-note edits made during review.
    gh release upload "$tag" "dist/$archive" "dist/$archive.sha256" --clobber
    gh release edit "$tag" --title "$tag" --prerelease="${PRERELEASE:-false}" --draft=true
else
    notes_file="$scratch/release-notes.md"
    printf 'Install `%s` by extracting it into KOReader’s `plugins` directory.\n\n[Build log](%s/%s/actions/runs/%s) · [Source commit](%s/%s/commit/%s)\n' \
        "$archive" "$GITHUB_SERVER_URL" "$GH_REPO" "$GITHUB_RUN_ID" \
        "$GITHUB_SERVER_URL" "$GH_REPO" "$release_sha" > "$notes_file"
    gh release create "$tag" "dist/$archive" "dist/$archive.sha256" \
        --verify-tag --draft --title "$tag" --prerelease="${PRERELEASE:-false}" \
        --generate-notes --notes-file "$notes_file"
fi
if [[ ${RELEASE_RESULT:-draft} == publish ]]; then
    # Always attach assets to a draft first, including when publishing immediately.
    # A prerelease must never displace the latest ordinary release.
    latest=true
    [[ ${PRERELEASE:-false} == false ]] || latest=false
    gh release edit "$tag" --draft=false --latest="$latest"
fi
release_url=$(gh release view "$tag" --json url --jq .url)
printf 'Release result (%s): %s\n' "${RELEASE_RESULT:-draft}" "$release_url"
if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
    if [[ ${RELEASE_RESULT:-draft} == draft ]]; then
        printf '\n[Review draft release](%s). Edit the notes as needed, then click **Publish release**.\n' \
            "$release_url" >> "$GITHUB_STEP_SUMMARY"
    else
        printf '\n[Published release](%s).\n' "$release_url" >> "$GITHUB_STEP_SUMMARY"
    fi
fi
