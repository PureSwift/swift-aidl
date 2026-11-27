#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
corpus="$repo_root/.build/aosp-aidl"

usage() {
    printf 'Usage: %s [--ref <branch-or-tag> | --revisions <file>]\n' "$0"
}

ref=refs/heads/main
revisions=
case ${1:-} in
    "")
        ;;
    --ref)
        if [[ $# != 2 || -z $2 || $2 == -* ]]; then usage >&2; exit 2; fi
        ref=$2
        ;;
    --revisions)
        if [[ $# != 2 || ! -r $2 ]]; then usage >&2; exit 2; fi
        revisions=$2
        ;;
    --help|-h)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

projects=(
    frameworks/base
    frameworks/libs/modules-utils
    packages/modules/Wifi
    packages/modules/Bluetooth
    packages/modules/Connectivity
    prebuilts/sdk
)

if [[ -n $revisions ]]; then
    if ! awk -v projects="${projects[*]}" '
        BEGIN {
            count = split(projects, names)
            for (i = 1; i <= count; i++) expected[names[i]] = 1
        }
        NF != 2 || !($1 in expected) || seen[$1]++ || length($2) != 40 || $2 ~ /[^[:xdigit:]]/ {
            invalid = 1
        }
        END {
            for (project in expected) if (!(project in seen)) invalid = 1
            exit invalid
        }
    ' "$revisions"; then
        printf 'Expected one project and commit pair per AOSP repository in %s\n' "$revisions" >&2
        exit 2
    fi
fi

fetch() {
    local project=$1
    shift
    local checkout="$corpus/$project"
    local revision="$ref"
    if [[ -n $revisions ]]; then
        revision=$(awk -v project="$project" '$1 == project { print $2 }' "$revisions")
    fi

    mkdir -p "$checkout"
    git -C "$checkout" init --quiet
    git -C "$checkout" config remote.origin.url "https://android.googlesource.com/platform/$project"
    git -C "$checkout" config remote.origin.promisor true
    git -C "$checkout" config remote.origin.partialclonefilter blob:none
    git -C "$checkout" sparse-checkout set --no-cone "$@"
    git -C "$checkout" fetch --depth=1 --filter=blob:none --no-tags origin "$revision"
    git -C "$checkout" checkout --quiet --detach FETCH_HEAD
    printf '%s %s\n' "$project" "$(git -C "$checkout" rev-parse HEAD)"
}

fetch frameworks/base '/core/java/**/*.aidl'
fetch frameworks/libs/modules-utils '/java/**/*.aidl'
fetch packages/modules/Wifi '/framework/java/**/*.aidl' '/framework/aidl-export/**/*.aidl' '/aidl/**/*.aidl'
fetch packages/modules/Bluetooth '/android/app/aidl/**/*.aidl' '/framework/aidl-export/**/*.aidl' '/service/aidl/**/*.aidl'
fetch packages/modules/Connectivity '/framework/aidl-export/**/*.aidl'
fetch prebuilts/sdk '/current/public/framework.aidl'
