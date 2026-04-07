# devcontainers-typescript-full

TypeScript フルスタック開発用の汎用 devcontainer テンプレート。

## 使い方

1. `.devcontainer/` ディレクトリをプロジェクトにコピー
2. `.devcontainer/devcontainer.json` の `name` をプロジェクト名に変更
3. `cp .devcontainer/example.config.toml .devcontainer/config.toml` で設定ファイルを作成し、Git の名前・メールと必要な API キーを記入
4. `.devcontainer/config.toml` を `.gitignore` に追加
5. VS Code「Dev Containers: Reopen in Container」または `devcontainer up` で起動
6. 停止するときは `bin/devcontainer-down` を実行

詳細は [.devcontainer/README.md](.devcontainer/README.md) を参照。
