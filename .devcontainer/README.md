# .devcontainer

TypeScript フルスタック開発用の汎用 devcontainer テンプレート。
このディレクトリをプロジェクトにコピーし、`devcontainer.json` の `name` を書き換えるだけで使えます。

設計意図や永続化・自己更新まわりの判断理由は `design.md` を参照してください。

## 特徴

- **ベースイメージ**: `mcr.microsoft.com/devcontainers/typescript-node:latest`
- **マルチステージビルド**: `base`（コア開発ツール）と `full`（+ ffmpeg / imagemagick）を `docker-compose.yml` の `target` で切替
- **TOML 一元管理**: `.devcontainer/config.toml` に Git / API キー / DB ソケット等の設定を集約し、entrypoint で自動適用
- **CLI 永続化**: `.devcontainer-data/` を host bind mount し、Codex/Claude/GitHub/AWS の設定・セッション・ログ・npm グローバルパッケージを保持
- **DB サイドカー**: MySQL・PostgreSQL を Unix ソケット経由で接続（docker-compose.yml 内にコメントアウトで用意）

## 含まれるツール

| ツール | 用途 |
|--------|------|
| GitHub CLI (`gh`) | GitHub 操作 |
| Git LFS (`git lfs`) | 大容量ファイルを含むリポジトリの clone / checkout |
| AWS CLI v2 | AWS リソース操作 |
| dasel | TOML パーサ（entrypoint 用） |
| Claude Code CLI | Anthropic AI コーディングアシスタント（初回起動時に writable な npm prefix へ自動導入） |
| OpenAI Codex CLI | OpenAI コーディングアシスタント（初回起動時に writable な npm prefix へ自動導入） |
| mysql-client / psql | DB クライアント |
| redis-tools | Redis クライアント |
| ffmpeg / imagemagick | メディア処理（`full` ステージのみ） |

## セットアップ

1. 設定ファイルを作成:

   ```bash
   cp example.config.toml config.toml
   ```

2. `config.toml` を編集し、Git の名前・メールアドレス（必須）と各種 API キーを設定

3. VS Code で「Dev Containers: Reopen in Container」を実行

初回起動時に `claude` / `codex` は `/home/node/.npm-global` へ自動インストールされます。自己更新後のバージョンも `.devcontainer-data/npm-global/` に保存されるため、`docker compose down` 後も維持されます。

## ファイル構成

```
.devcontainer/
  devcontainer.json                 # VS Code devcontainer 設定
  docker-compose.yml                # サービス定義（devcontainer + オプションの DB サイドカー）
  Dockerfile                        # マルチステージビルド（base / full）
  example.config.toml               # 設定テンプレート（コピーして使用）
  scripts/
    entrypoint.sh                   # コンテナ起動時に TOML 設定を読み込み環境を構成
    smoke-test.sh                   # ビルド済みイメージの動作確認（CI から実行）
    runtime-test.sh                 # 起動後の状態確認（CI から remoteUser で実行）
.devcontainer-data/                 # host 側に残る CLI の設定・履歴・ログ・npm グローバル領域
```

## 設定項目 (config.toml)

| セクション | 項目 | 必須 | 説明 |
|-----------|------|------|------|
| `[git]` | name, email | Yes | Git のユーザー名・メールアドレス |
| `[claude]` | api_key | - | Claude Code 用 Anthropic API キー |
| `[codex]` | api_key | - | Codex CLI 用 OpenAI API キー |
| `[github]` | token | - | GitHub CLI 認証トークン |
| `[aws]` | access_key_id, secret_access_key, region | - | AWS CLI 認証情報 |
| `[mysql]` | socket | - | MySQL Unix ソケットパス |
| `[postgresql]` | socket | - | PostgreSQL Unix ソケットディレクトリ |
| `[hooks]` | post_start | - | コンテナ起動後に実行するカスタムスクリプト |

## devcontainer CLI での使い方

VS Code を使わずに、[devcontainer CLI](https://github.com/devcontainers/cli) からコンテナを操作できます。

```bash
# インストール
npm install -g @devcontainers/cli

# コンテナの起動
devcontainer up

# コンテナの停止
bin/devcontainer-down

# コマンド実行
devcontainer exec node --version
devcontainer exec bash
devcontainer exec claude
devcontainer exec codex

# ビルドのみ
devcontainer build
```

## 永続化されるデータ

`docker compose down` 後も、以下は host 側の `.devcontainer-data/` に残ります。

- `npm-global/`: `claude` / `codex` 本体。自己更新後のバージョンも保持
- `codex/`: Codex の設定、セッション、過去ログ
- `claude/`: Claude Code のユーザー設定、skills、commands、plugins、認証情報
- `claude-root/`: Claude Code の `~/.claude.json`。OAuth セッション、MCP 設定、許可状態、各種キャッシュ
- `gh/`: GitHub CLI の認証状態
- `aws/`: AWS CLI の認証・設定

## DB サイドカーの有効化

`docker-compose.yml` 内の MySQL / PostgreSQL セクションのコメントを解除してください。DB には Unix ソケット経由で接続します（TCP ポートのホスト公開不要）。

## 動作確認

`.github/workflows/devcontainer.yml` が push / PR / 週次で以下を確認します。

| ジョブ | 内容 |
|--------|------|
| `image` | `base` / `full` をビルドし、`smoke-test.sh` を root と node の両方で実行 |
| `runtime` | `devcontainer up` で起動し、`runtime-test.sh` を remoteUser (node) で実行 |
| `config` | `docker-compose.yml` と `devcontainer.json` を検証 |

### イメージの確認 (smoke-test.sh)

手元で同じ確認をする場合:

```bash
docker build --target full -t devcontainer-smoke:full .devcontainer

docker run --rm -e SMOKE_TARGET=full \
  -v "$PWD/.devcontainer/scripts:/smoke:ro" \
  --entrypoint bash devcontainer-smoke:full /smoke/smoke-test.sh

# 実作業ユーザーでも同じ結果になること
docker run --rm --user node -e HOME=/home/node -e SMOKE_TARGET=full \
  -v "$PWD/.devcontainer/scripts:/smoke:ro" \
  --entrypoint bash devcontainer-smoke:full /smoke/smoke-test.sh
```

確認内容:

- 各 CLI が PATH に存在すること（`full` では ffmpeg / imagemagick も）
- Git LFS の filter が `/etc/gitconfig` にあり、root / node の双方から見えること
- LFS 追跡ファイルがポインタとしてコミットされ、checkout で実体が復元されること

### 起動後の状態の確認 (runtime-test.sh)

`config.toml` に書いた設定が、実際に作業するユーザー (`node`) から見えているかを確認します。
entrypoint は root で動くため、ここがズレると「ログ上は成功しているのに設定が効かない」状態になります。

```bash
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . bash .devcontainer/scripts/runtime-test.sh
```

entrypoint は起動と非同期に走るので、初期化の完了は `/run/devcontainer-ready` の有無で判断できます。

```bash
devcontainer exec --workspace-folder . bash -c 'test -f /run/devcontainer-ready && echo ready'
```

## ビルドターゲットの切替

`docker-compose.yml` の `target` を変更:

```yaml
build:
  target: base  # ffmpeg/imagemagick が不要な場合
  # target: full  # デフォルト（ffmpeg/imagemagick 込み）
```
