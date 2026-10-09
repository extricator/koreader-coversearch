#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Called only after validation, tests, and packaging succeed.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source tools/release-common.sh
release_context "${RELEASE_SHA:?Missing release commit}"
main_sha=$(gh api 'repos/{owner}/{repo}/git/ref/heads/main' --jq .object.sha)
if [[ "$main_sha" != "$RELEASE_SHA" ]]; then
    [[ "$main_sha" == "$GITHUB_SHA" &&
       $(git rev-list --parents -n 1 "$RELEASE_SHA") == "$RELEASE_SHA $GITHUB_SHA" &&
       $(git diff --name-only "$GITHUB_SHA" "$RELEASE_SHA") == coversearch.koplugin/_meta.lua ]] || {
        echo 'Main changed during preparation. Start a new workflow run.' >&2; exit 1;
    }
    release_git push origin "$RELEASE_SHA:refs/heads/main"
fi
