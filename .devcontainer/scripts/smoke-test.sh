#!/usr/bin/env bash
# ビルド済み devcontainer イメージの動作確認スクリプト。
# root と node の両方で実行し、ユーザー差で壊れる設定を検知する。
#
#   docker build --target full -t devcontainer-smoke:full .devcontainer
#   docker run --rm -e SMOKE_TARGET=full \
#       -v "$PWD/.devcontainer/scripts:/smoke:ro" \
#       --entrypoint bash devcontainer-smoke:full /smoke/smoke-test.sh
set -uo pipefail

TARGET="${SMOKE_TARGET:-full}"
FAILURES=0

SMOKE_TMP=$(mktemp -d)
trap 'rm -rf "$SMOKE_TMP"' EXIT

# ── Helper: run a check, print its output only when it fails ──
check() {
    local desc="$1"
    shift
    local output
    if output=$("$@" 2>&1); then
        echo "  ok    $desc"
    else
        echo "  FAIL  $desc"
        [ -n "$output" ] && echo "$output" | sed 's/^/          | /'
        FAILURES=$((FAILURES + 1))
    fi
}

has_imagemagick() {
    command -v magick || command -v convert
}

# ── Git LFS: clean フィルタでポインタ化され、checkout で実体が戻ること ──
lfs_roundtrip() {
    local repo="$SMOKE_TMP/lfs-repo" before after
    mkdir -p "$repo"
    cd "$repo" || return 1

    git init -q .
    git config user.name "smoke test"
    git config user.email "smoke@example.invalid"
    git lfs track '*.bin' || return 1

    head -c 4096 /dev/urandom > payload.bin
    before=$(sha256sum payload.bin | cut -d ' ' -f 1)
    git add .gitattributes payload.bin
    git commit -qm "add payload" || return 1

    # コミットされた blob は実体ではなく LFS ポインタであるはず
    git cat-file -p HEAD:payload.bin | head -n 1 | grep -q '^version https://git-lfs' || return 1

    # checkout で LFS のローカルストアから実体が復元されるはず
    rm payload.bin
    git checkout -q -- payload.bin || return 1
    after=$(sha256sum payload.bin | cut -d ' ' -f 1)
    [ "$before" = "$after" ]
}

echo "[smoke] user=$(id -un) target=$TARGET"

echo "[smoke] core tools"
for bin in node npm git git-lfs gh aws dasel mysql psql redis-cli; do
    check "$bin is on PATH" command -v "$bin"
done

if [ "$TARGET" = "full" ]; then
    echo "[smoke] full stage tools"
    check "ffmpeg is on PATH" command -v ffmpeg
    check "imagemagick is on PATH" has_imagemagick
fi

echo "[smoke] git lfs ($(git lfs version 2>/dev/null || echo unavailable))"
# --global ではなく --system に入れているので、root でも node でも同じ設定が見える
for key in clean smudge process; do
    check "filter.lfs.$key is set in /etc/gitconfig" git config --system --get "filter.lfs.$key"
done
check "filter.lfs.clean is visible to $(id -un)" git config --get filter.lfs.clean
check "clean/smudge round-trip preserves file contents" lfs_roundtrip

if [ "$FAILURES" -gt 0 ]; then
    echo "[smoke] $FAILURES check(s) failed"
    exit 1
fi

echo "[smoke] all checks passed"
