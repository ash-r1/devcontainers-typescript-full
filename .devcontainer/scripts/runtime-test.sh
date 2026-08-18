#!/usr/bin/env bash
# 起動後の devcontainer が期待した状態になっているかを確認する。
# entrypoint は root で動くが、実作業は remoteUser (node) なので、
# 「node から見て設定が効いているか」を確認するのがこのスクリプトの目的。
#
# entrypoint の完了後（/run/devcontainer-ready ができた後）に実行すること:
#
#   devcontainer exec --workspace-folder . bash .devcontainer/scripts/runtime-test.sh
#
# イメージに何が入っているかの確認は smoke-test.sh を参照。
set -uo pipefail

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
CONFIG_FILE="${DEVCONTAINER_CONFIG:-$WORKSPACE_DIR/.devcontainer/config.toml}"
READY_MARKER="/run/devcontainer-ready"
EXPECT_USER="${EXPECT_USER:-node}"
NODE_HOME="/home/node"
NPM_GLOBAL_PREFIX="$NODE_HOME/.npm-global"
FAILURES=0

RUNTIME_TMP=$(mktemp -d)
trap 'rm -rf "$RUNTIME_TMP"' EXIT
# ユーザー設定を見たいので、リポジトリの外から確認する
cd "$RUNTIME_TMP" || exit 1

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

# ── Helper: compare two values (両方ログに出るので、秘匿値には check を使う) ──
expect_equal() {
    local desc="$1" actual="$2" expected="$3"
    if [ "$actual" = "$expected" ]; then
        echo "  ok    $desc"
    else
        echo "  FAIL  $desc"
        echo "          | expected: $expected"
        echo "          | actual:   $actual"
        FAILURES=$((FAILURES + 1))
    fi
}

# ── Helper: read a TOML value (entrypoint と同じ読み方) ──
toml_get() {
    local result
    result=$(cat "$CONFIG_FILE" | dasel -i toml "$1" 2>/dev/null | sed "s/^'//;s/'$//") || result=""
    echo "$result"
}

# ── Helper: 設定は /etc/profile.d 経由で配るので、login shell で確認する ──
login_env() {
    bash -lc "printf '%s' \"\${$1-}\"" 2>/dev/null
}

login_path_has_npm_global() {
    local path
    path=$(bash -lc 'printf "%s" "$PATH"')
    case ":$path:" in
        *":$NPM_GLOBAL_PREFIX/bin:"*) return 0 ;;
    esac
    echo "PATH=$path"
    return 1
}

echo "[runtime] user=$(id -un) config=$CONFIG_FILE"

echo "[runtime] entrypoint"
check "entrypoint finished (ready marker exists)" test -f "$READY_MARKER"
expect_equal "running as the expected remote user" "$(id -un)" "$EXPECT_USER"

echo "[runtime] git identity from config.toml"
# entrypoint は root なので、--global に書くと node からは見えない
expect_equal "git user.name is visible" "$(git config --get user.name)" "$(toml_get git.name)"
expect_equal "git user.email is visible" "$(git config --get user.email)" "$(toml_get git.email)"

echo "[runtime] environment from config.toml"
check "npm global bin is on PATH in a login shell" login_path_has_npm_global
for pair in "claude.api_key:ANTHROPIC_API_KEY" "codex.api_key:OPENAI_API_KEY" "github.token:GITHUB_TOKEN"; do
    key="${pair%%:*}"
    var="${pair##*:}"
    value=$(toml_get "$key")
    [ -n "$value" ] || continue
    # 値そのものは出さない
    check "$var matches config.toml in a login shell" test "$(login_env "$var")" = "$value"
done

echo "[runtime] persisted state is owned by $(id -un)"
for dir in \
    "$NPM_GLOBAL_PREFIX" \
    "$NODE_HOME/.codex" \
    "$NODE_HOME/.claude" \
    "$NODE_HOME/.claude-root" \
    "$NODE_HOME/.config/gh" \
    "$NODE_HOME/.aws"; do
    check "$dir is writable" test -w "$dir"
done

check "~/.claude.json is a symlink" test -L "$NODE_HOME/.claude.json"
expect_equal "~/.claude.json points at the persisted file" \
    "$(readlink "$NODE_HOME/.claude.json")" \
    "$NODE_HOME/.claude-root/.claude.json"

echo "[runtime] self-updatable CLIs"
# イメージ層ではなく、書き込み可能な npm prefix に入っていること
check "claude is in the writable npm prefix" test -x "$NPM_GLOBAL_PREFIX/bin/claude"
check "codex is in the writable npm prefix" test -x "$NPM_GLOBAL_PREFIX/bin/codex"

if [ "$FAILURES" -gt 0 ]; then
    echo "[runtime] $FAILURES check(s) failed"
    exit 1
fi

echo "[runtime] all checks passed"
