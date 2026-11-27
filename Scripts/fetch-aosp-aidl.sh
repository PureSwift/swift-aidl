#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
corpus="$repo_root/.build/aosp-aidl"

fetch() {
    local project=$1
    shift
    local checkout="$corpus/$project"

    mkdir -p "$checkout"
    git -C "$checkout" init --quiet
    git -C "$checkout" config remote.origin.url "https://android.googlesource.com/platform/$project"
    git -C "$checkout" config remote.origin.promisor true
    git -C "$checkout" config remote.origin.partialclonefilter blob:none
    git -C "$checkout" sparse-checkout set --no-cone "$@"
    git -C "$checkout" fetch --depth=1 --filter=blob:none origin refs/heads/main
    git -C "$checkout" checkout --quiet --detach FETCH_HEAD
    printf '%s %s\n' "$project" "$(git -C "$checkout" rev-parse HEAD)"
}

fetch frameworks/base '/core/java/**/*.aidl'
fetch frameworks/libs/modules-utils '/java/**/*.aidl'
fetch packages/modules/Wifi '/framework/java/**/*.aidl' '/framework/aidl-export/**/*.aidl' '/aidl/**/*.aidl'
fetch packages/modules/Bluetooth '/android/app/aidl/**/*.aidl' '/framework/aidl-export/**/*.aidl' '/service/aidl/**/*.aidl'
fetch packages/modules/Connectivity '/framework/aidl-export/**/*.aidl'
fetch prebuilts/sdk '/current/public/framework.aidl'
