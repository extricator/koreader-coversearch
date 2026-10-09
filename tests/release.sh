#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Exercise release operations with a fake GitHub CLI; no network or remote writes.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/bin"
cat > "$scratch/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
missing() { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
case "$1 $2" in
    'api repos/{owner}/{repo}/releases/tags/'*)
        echo READ_RELEASE >> "$MOCK_LOG"
        case "$MOCK_SCENARIO" in
            auth) echo 'gh: Bad credentials (HTTP 401)' >&2; exit 1 ;;
            draft|draft_conflict|draft_without_tag) echo true ;;
            published) echo false ;;
            *) missing ;;
        esac ;;
    'api repos/{owner}/{repo}/git/ref/tags/'*)
        echo READ_TAG >> "$MOCK_LOG"
        case "$MOCK_SCENARIO" in
            new|draft_without_tag) missing ;;
            conflict|draft_conflict) echo 'commit 0000000000000000000000000000000000000000' ;;
            annotated) echo 'tag 1111111111111111111111111111111111111111' ;;
            tag_error) echo 'gh: Service Unavailable (HTTP 503)' >&2; exit 1 ;;
            *) echo "commit $GITHUB_SHA" ;;
        esac ;;
    'api repos/{owner}/{repo}/git/tags/'*)
        echo READ_ANNOTATED_TAG >> "$MOCK_LOG"
        echo "commit $GITHUB_SHA" ;;
    'api repos/{owner}/{repo}/git/refs')
        [[ " $* " == *" ref=refs/tags/$MOCK_TAG "* && " $* " == *" sha=$GITHUB_SHA "* ]]
        echo CREATE_TAG >> "$MOCK_LOG" ;;
    'release create')
        [[ "$3" == "$MOCK_TAG" ]]
        [[ " $* " == *' --draft '* && " $* " == *' --generate-notes '* && " $* " == *' --verify-tag '* ]]
        [[ "$4" == "dist/koreader-coversearch-$MOCK_TAG.zip" && "$5" == "$4.sha256" ]]
        while (($#)); do
            if [[ "$1" == --notes-file ]]; then
                grep -Fq "$GITHUB_SHA" "$2"
                grep -Fq 'Build log' "$2"
                break
            fi
            shift
        done
        (($#))
        echo CREATE_DRAFT_WITH_GENERATED_NOTES >> "$MOCK_LOG" ;;
    'release upload')
        [[ "$MOCK_SCENARIO" == draft && " $* " == *' --clobber '* ]]
        [[ "$4" == "dist/koreader-coversearch-$MOCK_TAG.zip" && "$5" == "$4.sha256" ]]
        echo REFRESH_ASSETS >> "$MOCK_LOG" ;;
    'release view')
        echo "https://github.com/$GH_REPO/releases/tag/$MOCK_TAG" ;;
    *) echo "Unexpected GitHub command: $*" >&2; exit 1 ;;
esac
MOCK
chmod +x "$scratch/bin/gh"
export PATH="$scratch/bin:$PATH"
export GITHUB_EVENT_NAME=workflow_dispatch GITHUB_REF=refs/heads/main
export GITHUB_SHA GH_REPO=example/coversearch GITHUB_SERVER_URL=https://github.com GITHUB_RUN_ID=123
GITHUB_SHA=$(git rev-parse HEAD)
export MOCK_TAG="v$(luajit tools/version.lua)" MOCK_LOG="$scratch/operations"
export GITHUB_STEP_SUMMARY="$scratch/summary"
bash tools/package.sh "$MOCK_TAG" > "$scratch/build.log"
check() {
    local scenario=$1 expected=$2
    export MOCK_SCENARIO="$scenario"
    : > "$MOCK_LOG"; : > "$GITHUB_STEP_SUMMARY"
    if bash tools/prepare-release.sh "$MOCK_TAG" > "$scratch/output" 2>&1; then
        [[ "$expected" == pass ]] || { cat "$scratch/output"; exit 1; }
        grep -Fq 'Review draft release' "$GITHUB_STEP_SUMMARY"
    else
        [[ "$expected" == fail ]] || { cat "$scratch/output"; exit 1; }
        if grep -Eq 'CREATE_TAG|CREATE_DRAFT|REFRESH_ASSETS' "$MOCK_LOG"; then
            echo "Failed scenario performed a remote mutation: $scenario" >&2; exit 1
        fi
    fi
    printf 'PASS release preparation: %s\n' "$scenario"
}
check new pass
grep -Fxq CREATE_TAG "$MOCK_LOG"
grep -Fxq CREATE_DRAFT_WITH_GENERATED_NOTES "$MOCK_LOG"
check draft pass
grep -Fxq REFRESH_ASSETS "$MOCK_LOG"
! grep -Eq 'CREATE_TAG|CREATE_DRAFT' "$MOCK_LOG"
check existing_tag pass
! grep -Fxq CREATE_TAG "$MOCK_LOG"
check annotated pass
grep -Fxq READ_ANNOTATED_TAG "$MOCK_LOG"
for scenario in published conflict draft_conflict draft_without_tag auth tag_error; do
    check "$scenario" fail
done
GITHUB_REF=refs/heads/feature
check wrong_branch fail
[[ ! -s "$MOCK_LOG" ]]
GITHUB_REF=refs/heads/main
GITHUB_SHA=0000000000000000000000000000000000000000
check wrong_checkout fail
[[ ! -s "$MOCK_LOG" ]]
printf '%s\n' 'All draft-release checks passed without network access'
