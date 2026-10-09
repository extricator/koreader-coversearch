#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Real temporary Git repositories and a fake GitHub API; no network writes.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
project=$(pwd)
luajit tests/release-version.lua
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/bin"
cat > "$scratch/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ ${MOCK_API_ERROR:-false} == false ]] || { echo 'gh: Bad credentials (HTTP 401)' >&2; exit 1; }
case "$1 $2" in
    'api repos/{owner}/{repo}/git/ref/heads/main') git --git-dir="$MOCK_ORIGIN" rev-parse refs/heads/main ;;
    'api repos/{owner}/{repo}/releases?per_page=100') cat "$MOCK_PUBLISHED" ;;
    'api repos/{owner}/{repo}/releases/tags/'*)
        if [[ ${MOCK_PUBLISHED_TARGET:-false} == true ]]; then echo false
        else echo 'gh: Not Found (HTTP 404)' >&2; exit 1; fi ;;
    'api repos/{owner}/{repo}/git/ref/tags/'*)
        if [[ ${MOCK_TAG_CONFLICT:-false} == true ]]; then echo 'commit 0000000000000000000000000000000000000000'
        else echo 'gh: Not Found (HTTP 404)' >&2; exit 1; fi ;;
    *) echo "Unexpected GitHub command: $*" >&2; exit 1 ;;
esac
MOCK
chmod +x "$scratch/bin/gh"
export PATH="$scratch/bin:$PATH"
export GITHUB_EVENT_NAME=workflow_dispatch GITHUB_REF=refs/heads/main GITHUB_RUN_ID=123
export GH_REPO=example/coversearch GITHUB_SERVER_URL=https://github.com
export MOCK_ORIGIN MOCK_PUBLISHED GITHUB_ENV GITHUB_STEP_SUMMARY GITHUB_SHA RELEASE_SHA RELEASE_TAG
export VERSION_SELECTION CUSTOM_VERSION PRERELEASE RELEASE_RESULT

fixture() {
    cd "$project"
    mkdir "$scratch/$1"
    cp -R tools coversearch.koplugin "$scratch/$1/"
    cp LICENSE .gitignore "$scratch/$1/"
    cd "$scratch/$1"
    git init -q -b main
    git config user.name 'Release test'
    git config user.email 'test@example.invalid'
    git add .
    git commit -qm 'Fixture'
    MOCK_ORIGIN="$scratch/$1-origin.git"
    git init -q --bare "$MOCK_ORIGIN"
    git remote add origin "$MOCK_ORIGIN"
    git push -q origin HEAD:refs/heads/main
    GITHUB_SHA=$(git rev-parse HEAD)
    GITHUB_ENV="$scratch/$1-env"
    GITHUB_STEP_SUMMARY="$scratch/$1-summary"
    MOCK_PUBLISHED="$scratch/$1-published"
    : > "$MOCK_PUBLISHED"; : > "$GITHUB_ENV"; : > "$GITHUB_STEP_SUMMARY"
    VERSION_SELECTION=automatic CUSTOM_VERSION= PRERELEASE=false RELEASE_RESULT=draft
    unset RELEASE_SHA RELEASE_TAG MOCK_API_ERROR MOCK_TAG_CONFLICT MOCK_PUBLISHED_TARGET
}
resolve() {
    bash tools/resolve-release.sh > "$scratch/resolve.log" 2>&1 || { cat "$scratch/resolve.log"; exit 1; }
    # Only validated numeric version/SHA assignments are written by the script.
    source "$GITHUB_ENV"
    export RELEASE_TAG RELEASE_SHA
    [[ "$RELEASE_TAG" == "$1" && $(luajit tools/version.lua) == "${1#v}" ]]
    [[ $(git rev-parse HEAD) == "$RELEASE_SHA" && -z $(git status --porcelain) ]]
}
fails() {
    local command=$1 expected=$2
    if bash "$command" > "$scratch/failure.log" 2>&1; then echo "Unexpected success: $command" >&2; exit 1; fi
    grep -Fq "$expected" "$scratch/failure.log" || { cat "$scratch/failure.log"; exit 1; }
}

fixture first
resolve v0.1.16
[[ "$RELEASE_SHA" == "$GITHUB_SHA" ]]
bash tools/push-release-version.sh
printf '%s\n' 'PASS first release uses code version without a commit'

fixture automatic
printf 'v0.1.16\n' > "$MOCK_PUBLISHED"
resolve v0.1.17
[[ $(git diff --name-only "$GITHUB_SHA" HEAD) == coversearch.koplugin/_meta.lua ]]
[[ $(git --git-dir="$MOCK_ORIGIN" rev-parse refs/heads/main) == "$GITHUB_SHA" ]]
bash tools/package.sh "$RELEASE_TAG" > "$scratch/package.log"
bash tools/push-release-version.sh > "$scratch/push.log" 2>&1
[[ $(git --git-dir="$MOCK_ORIGIN" rev-parse refs/heads/main) == "$RELEASE_SHA" ]]
bash tools/release-provenance.sh
jq -e --arg source "$RELEASE_SHA" --arg original "$GITHUB_SHA" '
    .buildDefinition.resolvedDependencies[0].digest.gitCommit == $source and
    .buildDefinition.resolvedDependencies[1].digest.gitCommit == $original and
    .buildDefinition.externalParameters.tag == "v0.1.17"' dist/provenance.json > /dev/null
unzip -p dist/koreader-coversearch-v0.1.17.zip coversearch.koplugin/_meta.lua | grep -Fq 'version = "0.1.17"'
git checkout -q --detach "$GITHUB_SHA"
previous_sha=$RELEASE_SHA
resolve v0.1.17
[[ "$RELEASE_SHA" == "$previous_sha" ]]
bash tools/push-release-version.sh
export MOCK_PUBLISHED_TARGET=true
git checkout -q --detach "$GITHUB_SHA"
fails tools/resolve-release.sh 'already has a published release'
printf '%s\n' 'PASS automatic bump, delayed push, exact ZIP/provenance, same-run retry, published retry rejection'

for selection in patch minor major; do
    fixture "$selection"
    VERSION_SELECTION=$selection
    case "$selection" in patch) expected=v0.1.17 ;; minor) expected=v0.2.0 ;; major) expected=v1.0.0 ;; esac
    resolve "$expected"
done
printf '%s\n' 'PASS patch, minor, and major selectors'

fixture custom
VERSION_SELECTION=major CUSTOM_VERSION=0.3.2
resolve v0.3.2
printf '%s\n' 'PASS custom override wins over selector and commits metadata'

fixture conflicts
export MOCK_TAG_CONFLICT=true
fails tools/resolve-release.sh 'Existing version tag does not point'
[[ $(git rev-parse HEAD) == "$GITHUB_SHA" ]]
unset MOCK_TAG_CONFLICT
CUSTOM_VERSION='0.2.0;echo broken'
fails tools/resolve-release.sh 'Version must be X.Y.Z'
CUSTOM_VERSION=
export MOCK_API_ERROR=true
fails tools/resolve-release.sh 'HTTP 401'
unset MOCK_API_ERROR
RELEASE_RESULT=invalid
fails tools/resolve-release.sh 'Release result must be draft or publish'
RELEASE_RESULT=draft PRERELEASE=invalid
fails tools/resolve-release.sh 'Prerelease must be true or false'
printf '%s\n' 'PASS reservation conflicts, unsafe inputs, and API errors stop before metadata changes'

fixture race
CUSTOM_VERSION=0.2.0
resolve v0.2.0
git checkout -q main
printf 'Another edit\n' > another.txt
git add another.txt
git commit -qm 'Concurrent edit'
git push -q origin HEAD:refs/heads/main
other_sha=$(git rev-parse HEAD)
git checkout -q --detach "$RELEASE_SHA"
fails tools/push-release-version.sh 'Main changed during preparation'
[[ $(git --git-dir="$MOCK_ORIGIN" rev-parse refs/heads/main) == "$other_sha" ]]
git checkout -q --detach "$GITHUB_SHA"
fails tools/resolve-release.sh 'Main changed since this run started'
printf '%s\n' 'PASS concurrent changes are preserved without force pushes'
printf '%s\n' 'All version automation checks passed without network access'
