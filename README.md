# devcontainers-typescript-full

TypeScript フルスタック開発用の汎用 devcontainer テンプレート。

プロジェクトのルートにこのリポジトリを配置し、VS Code の「Dev Containers: Reopen in Container」で開発環境を起動できます。

## 特徴

- **ベースイメージ**: `mcr.microsoft.com/devcontainers/typescript-node:latest`
- **マルチステージビルド**: `base`（コア開発ツール）と `full`（+ ffmpeg / imagemagick）を `docker-compose.yml` の `target` で切替
- **TOML 一元管理**: `.devcontainer.config.toml` に Git / API キー / DB ソケット等の設定を集約し、entrypoint で自動適用
- **DB サイドカー**: MySQL・PostgreSQL を Unix ソケット経由で接続（docker-compose.yml 内にコメントアウトで用意）

## 含まれるツール

| ツール | 用途 |
|--------|------|
| GitHub CLI (`gh`) | GitHub 操作 |
| AWS CLI v2 | AWS リソース操作 |
| dasel | TOML パーサ（entrypoint 用） |
| Claude Code CLI | Anthropic AI コーディングアシスタント |
| OpenAI Codex CLI | OpenAI コーディングアシスタント |
| mysql-client / psql | DB クライアント |
| redis-tools | Redis クライアント |
| ffmpeg / imagemagick | メディア処理（`full` ステージのみ） |

## セットアップ

1. 設定ファイルを作成:

   ```bash
   cp example.devcontainer.config.toml .devcontainer.config.toml
   ```

2. `.devcontainer.config.toml` を編集し、Git の名前・メールアドレス（必須）と各種 API キーを設定

3. VS Code で「Dev Containers: Reopen in Container」を実行

## ファイル構成

```
.devcontainer/
  devcontainer.json          # VS Code devcontainer 設定
docker-compose.yml           # サービス定義（devcontainer + オプションの DB サイドカー）
Dockerfile                   # マルチステージビルド（base / full）
example.devcontainer.config.toml  # 設定テンプレート（コピーして使用）
scripts/
  entrypoint.sh              # コンテナ起動時に TOML 設定を読み込み環境を構成
```

## 設定項目 (.devcontainer.config.toml)

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

### インストール

```bash
npm install -g @devcontainers/cli
```

### コンテナの起動

```bash
# プロジェクトルートで実行
devcontainer up
```

### コンテナ内でコマンドを実行

```bash
# 単発コマンド
devcontainer exec node --version

# シェルに入る
devcontainer exec bash
```

### ビルドのみ（起動しない）

```bash
devcontainer build
```

### Claude Code をコンテナ内で直接使う

```bash
devcontainer exec claude
```

## DB サイドカーの有効化

`docker-compose.yml` 内の MySQL / PostgreSQL セクションのコメントを解除してください。DB には Unix ソケット経由で接続します（TCP ポートのホスト公開不要）。

## ビルドターゲットの切替

`docker-compose.yml` の `target` を変更:

```yaml
build:
  target: base  # ffmpeg/imagemagick が不要な場合
  # target: full  # デフォルト（ffmpeg/imagemagick 込み）
```
