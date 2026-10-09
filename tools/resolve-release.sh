#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Select a version and commit metadata locally; no remote mutations before tests.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source tools/release-common.sh
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
release_context "${GITHUB_SHA:?Missing workflow source commit}"
: "${GITHUB_RUN_ID:?Missing workflow run}"
: "${GITHUB_ENV:?Missing workflow environment file}"
metadata=coversearch.koplugin/_meta.lua
current=$(luajit tools/version.lua)
main_sha=$(gh api 'repos/{owner}/{repo}/git/ref/heads/main' --jq .object.sha)

if [[ "$main_sha" != "$GITHUB_SHA" ]]; then
    # A rerun may reuse the metadata commit created by this same workflow run.
    # Any other advance of main requires a fresh run, never a rebase/force push.
    release_git fetch --no-tags origin "$main_sha"
    [[ $(git rev-list --parents -n 1 "$main_sha") == "$main_sha $GITHUB_SHA" &&
       $(git show -s --format=%B "$main_sha" | git interpret-trailers --parse) == "Release-Run: $GITHUB_RUN_ID" &&
       $(git diff --name-only "$GITHUB_SHA" "$main_sha") == "$metadata" ]] || {
        echo 'Main changed since this run started. Start a new workflow run.' >&2; exit 1;
    }
    git show "$main_sha:$metadata" > "$scratch/remote-meta"
    version=$(sed -n 's/^[[:space:]]*version = "\([^"]*\)",$/\1/p' "$scratch/remote-meta")
    git show "$GITHUB_SHA:$metadata" > "$scratch/expected-meta"
    luajit tools/select-version.lua write "$scratch/expected-meta" "$version"
    cmp "$scratch/expected-meta" "$scratch/remote-meta"
    git checkout --detach "$main_sha"
else
    gh api 'repos/{owner}/{repo}/releases?per_page=100' --paginate \
        --jq '.[] | select(.draft == false) | .tag_name' > "$scratch/published"
    version=$(luajit tools/select-version.lua "$current" "${VERSION_SELECTION:-automatic}" \
        "${CUSTOM_VERSION:-}" "$scratch/published")
    # Check reservation conflicts before modifying the checkout.
    release_target "v$version" "$GITHUB_SHA"
    if [[ "$version" != "$current" ]]; then
        [[ "$release_tag_exists" == false ]] || {
            echo 'Existing version tag cannot be used for a metadata update.' >&2; exit 1;
        }
        luajit tools/select-version.lua write "$metadata" "$version"
        git add -- "$metadata"
        git -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
            commit -m "chore: release v$version" -m "Release-Run: $GITHUB_RUN_ID"
    fi
fi
release_sha=$(git rev-parse HEAD)
luajit tools/version.lua "v$version"
release_target "v$version" "$release_sha"
printf 'RELEASE_TAG=v%s\nRELEASE_SHA=%s\n' "$version" "$release_sha" >> "$GITHUB_ENV"
if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
    printf '## Release v%s\n\nSource commit: `%s`\n\nVersion selection: `%s`; custom override: `%s`\n\nResult: `%s`; prerelease: `%s`\n\n' \
        "$version" "$release_sha" "${VERSION_SELECTION:-automatic}" "${CUSTOM_VERSION:-none}" \
        "${RELEASE_RESULT:-draft}" "${PRERELEASE:-false}" >> "$GITHUB_STEP_SUMMARY"
fi
