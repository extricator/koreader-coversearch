#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Shared validation; callers provide a disposable $scratch directory.
release_context() {
    case ${RELEASE_RESULT:-draft} in
        'Draft release') RELEASE_RESULT=draft ;;
        'Publish immediately') RELEASE_RESULT=publish ;;
    esac
    [[ ${GITHUB_EVENT_NAME:-} == workflow_dispatch && ${GITHUB_REF:-} == refs/heads/main ]] || {
        echo 'Prepare release must be run manually on main.' >&2; return 1;
    }
    [[ ${PRERELEASE:-false} == true || ${PRERELEASE:-false} == false ]] || {
        echo 'Prerelease must be true or false.' >&2; return 1;
    }
    [[ ${RELEASE_RESULT:-draft} == draft || ${RELEASE_RESULT:-draft} == publish ]] || {
        echo 'Release result must be draft or publish.' >&2; return 1;
    }
    : "${GITHUB_SHA:?Missing workflow source commit}"
    : "${GH_REPO:?Missing release repository}"
    [[ $(git rev-parse HEAD) == "$1" ]] || {
        echo 'Checkout does not match the requested source commit.' >&2; return 1;
    }
    git diff --exit-code HEAD -- coversearch.koplugin LICENSE
}

# Only a 404 means absence. Authentication and network errors stop preparation.
release_lookup() {
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

release_target() {
    local tag=$1 expected_sha=$2 object object_type object_sha depth
    release_draft=$(release_lookup "repos/{owner}/{repo}/releases/tags/$tag" '.draft')
    if [[ -n "$release_draft" && "$release_draft" != true ]]; then
        echo 'This version already has a published release. Use a new version.' >&2
        return 1
    fi
    object=$(release_lookup "repos/{owner}/{repo}/git/ref/tags/$tag" '.object.type + " " + .object.sha')
    release_tag_exists=false
    if [[ -z "$object" ]]; then
        [[ "$release_draft" != true ]] || {
            echo 'Existing draft has no tag identifying its source. Resolve it before retrying.' >&2; return 1;
        }
    else
        release_tag_exists=true
        read -r object_type object_sha <<< "$object"
        for ((depth=0; depth<10; depth++)); do
            [[ "$object_type" == tag ]] || break
            object=$(gh api "repos/{owner}/{repo}/git/tags/$object_sha" --jq '.object.type + " " + .object.sha')
            read -r object_type object_sha <<< "$object"
        done
        [[ "$object_type" == commit && "$object_sha" == "$expected_sha" ]] || {
            echo 'Existing version tag does not point to this source commit.' >&2; return 1;
        }
    fi
}

release_git() {
    git -c credential.helper= -c 'credential.helper=!gh auth git-credential' -c push.followTags=false "$@"
}
