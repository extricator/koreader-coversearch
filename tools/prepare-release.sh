#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Called after validation, packaging, and attestation by Prepare release.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
version=$(luajit tools/version.lua "${1:?Provide the release tag}")
tag="v$version"
archive="koreader-coversearch-$tag.zip"
[[ ${GITHUB_EVENT_NAME:-} == workflow_dispatch && ${GITHUB_REF:-} == refs/heads/main ]] || {
    echo 'Prepare release must be run manually on main.' >&2; exit 1;
}
[[ $(git rev-parse HEAD) == "${GITHUB_SHA:?Missing source commit}" ]] || {
    echo 'Checkout does not match the requested source commit.' >&2; exit 1;
}
git diff --exit-code HEAD -- coversearch.koplugin LICENSE
(cd dist && sha256sum --check "$archive.sha256")
: "${GH_REPO:?Missing release repository}"
: "${GITHUB_SERVER_URL:?Missing GitHub URL}"
: "${GITHUB_RUN_ID:?Missing workflow run}"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

# Treat only an explicit 404 as absent. Authentication/network errors stop the
# workflow instead of being mistaken for permission to create a release or tag.
lookup() {
    local result
    if result=$(gh api "$1" --jq "$2" 2> "$scratch/api-error"); then
        printf '%s' "$result"
    elif [[ $(< "$scratch/api-error") == *'(HTTP 404)'* ]]; then
        return 0
    else
        cat "$scratch/api-error" >&2
        return 1
    fi
}
draft=$(lookup "repos/{owner}/{repo}/releases/tags/$tag" '.draft')
if [[ -n "$draft" && "$draft" != true ]]; then
    echo 'This version already has a published release. Use a new version.' >&2
    exit 1
fi
object=$(lookup "repos/{owner}/{repo}/git/ref/tags/$tag" '.object.type + " " + .object.sha')
if [[ -z "$object" ]]; then
    if [[ "$draft" == true ]]; then
        echo 'Existing draft has no tag identifying its source. Resolve it before retrying.' >&2
        exit 1
    fi
    gh api 'repos/{owner}/{repo}/git/refs' --method POST \
        -f "ref=refs/tags/$tag" -f "sha=$GITHUB_SHA" > /dev/null
else
    # Resolve annotated tags as well as lightweight tags; never move a version
    # tag or replace a draft's assets with a build from a different commit.
    read -r object_type object_sha <<< "$object"
    for ((depth=0; depth<10; depth++)); do
        [[ "$object_type" == tag ]] || break
        object=$(gh api "repos/{owner}/{repo}/git/tags/$object_sha" --jq '.object.type + " " + .object.sha')
        read -r object_type object_sha <<< "$object"
    done
    [[ "$object_type" == commit && "$object_sha" == "$GITHUB_SHA" ]] || {
        echo 'Existing version tag does not point to this source commit.' >&2; exit 1;
    }
fi

if [[ "$draft" == true ]]; then
    # Keep any release-note edits made during review.
    gh release upload "$tag" "dist/$archive" "dist/$archive.sha256" --clobber
else
    notes_file="$scratch/release-notes.md"
    printf 'Install `%s` by extracting it into KOReader’s `plugins` directory.\n\n[Build log](%s/%s/actions/runs/%s) · [Source commit](%s/%s/commit/%s)\n' \
        "$archive" "$GITHUB_SERVER_URL" "$GH_REPO" "$GITHUB_RUN_ID" \
        "$GITHUB_SERVER_URL" "$GH_REPO" "$GITHUB_SHA" > "$notes_file"
    gh release create "$tag" "dist/$archive" "dist/$archive.sha256" \
        --verify-tag --draft --title "Cover Search $tag" \
        --generate-notes --notes-file "$notes_file"
fi
release_url=$(gh release view "$tag" --json url --jq .url)
printf 'Draft ready for review: %s\n' "$release_url"
if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
    printf '\n[Review draft release](%s). Edit the notes as needed, then click **Publish release**.\n' \
        "$release_url" >> "$GITHUB_STEP_SUMMARY"
fi
