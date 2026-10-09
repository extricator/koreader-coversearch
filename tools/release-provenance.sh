#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# A workflow can create a metadata commit after dispatch. Record both commits,
# rather than describing the initial workflow commit as the ZIP's source.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ $(git rev-parse HEAD) == "${RELEASE_SHA:?Missing release commit}" ]]
mkdir -p dist
jq -n --arg server "${GITHUB_SERVER_URL:?}" --arg repo "${GH_REPO:?}" \
    --arg source "$RELEASE_SHA" --arg workflow_source "${GITHUB_SHA:?}" \
    --arg tag "${RELEASE_TAG:?}" --arg run "${GITHUB_RUN_ID:?}" --arg attempt "${GITHUB_RUN_ATTEMPT:-1}" '
    ($server + "/" + $repo) as $repository |
    ($repository + "/actions/runs/" + $run + "/attempts/" + $attempt) as $invocation |
    {
      buildDefinition: {
        buildType: ($repository + "/blob/" + $workflow_source + "/.github/workflows/prepare-release.yml"),
        externalParameters: {repository: $repository, ref: "refs/heads/main", tag: $tag},
        resolvedDependencies: [
          {uri: ("git+" + $repository + "@" + $tag), digest: {gitCommit: $source}},
          {uri: ("git+" + $repository + "@refs/heads/main"), digest: {gitCommit: $workflow_source}}
        ]
      },
      runDetails: {
        builder: {id: ($server + "/actions/runner/github-hosted")},
        metadata: {invocationId: $invocation}
      }
    }' > dist/provenance.json
