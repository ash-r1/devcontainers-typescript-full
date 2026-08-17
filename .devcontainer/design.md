# Devcontainer Design Notes

このファイルは `.devcontainer` の設計意図を残すためのメモです。
README は使い方中心、こちらは判断理由と変更時の注意点をまとめます。

## 目的

この devcontainer は、単に開発ツールを入れたコンテナではなく、以下を両立することを目的にしています。

- VS Code Dev Containers と `devcontainer` CLI の両方で扱いやすいこと
- Git や API キーなどの初期設定を自動適用できること
- `docker compose down` 後も、AI CLI の状態や認証が不用意に消えないこと
- Claude Code / Codex の自己更新や状態保存が、非 root の `node` ユーザーで破綻しないこと

## 前提

この構成では、作業ディレクトリそのものは `..:/workspace` で bind mount しています。
一方で、CLI の設定・セッション・ログ・認証・自己更新後の実体は、主に `/home/node` 配下に作られます。

ここを永続化しないと、コンテナを作り直した時点で以下が失われます。

- Codex の設定、過去ログ、セッション
- Claude Code のユーザー設定、認証、許可状態、MCP 設定
- GitHub CLI / AWS CLI の認証状態
- `npm install -g` で更新された CLI バイナリ

つまり、`/workspace` だけ bind mount しても、AI CLI の実運用には不十分です。

## 永続化方針

永続化は Docker named volume ではなく、host 側の gitignore 済みディレクトリ `.devcontainer-data/` への bind mount を採用しています。

理由:

- どのデータが残るかをリポジトリ利用者が把握しやすい
- `docker compose down` や devcontainer の再作成で消えない
- バックアップや削除を host 側から直接扱える
- named volume より、状態の所在が見えやすい

現時点の対応表:

- `.devcontainer-data/npm-global` -> `/home/node/.npm-global`
- `.devcontainer-data/codex` -> `/home/node/.codex`
- `.devcontainer-data/claude` -> `/home/node/.claude`
- `.devcontainer-data/claude-root` -> `/home/node/.claude-root`
- `.devcontainer-data/gh` -> `/home/node/.config/gh`
- `.devcontainer-data/aws` -> `/home/node/.aws`

## Git LFS

ベースイメージには `git-lfs` が含まれていないため、LFS を使うリポジトリを clone / checkout すると、実体ではなくポインタファイルだけが手元に来ます。
これは「ファイルは存在するのに中身が壊れている」ように見えるため、原因が分かりにくい種類の事故です。

そのため `Dockerfile` の `base` ステージで `git-lfs` を導入し、続けて次を実行しています。

```
git lfs install --system --skip-repo
```

`--global` ではなく `--system` を選んでいるのは、書き込み先が `/etc/gitconfig` になり、`root`（entrypoint）と `node`（実作業）のどちらから git を叩いても LFS filter が有効になるためです。
`--global` にすると実行ユーザーのホームにしか設定が入らず、ユーザーが変わった瞬間に smudge filter が効かなくなります。

`--skip-repo` は、build 時にリポジトリ外で実行するため、リポジトリ側の hook 設定を試みないようにするためのものです。

## Codex / Claude の自己更新

### 問題

当初は `Dockerfile` の build 時に `npm install -g @anthropic-ai/claude-code @openai/codex` を実行していました。
この形だと、CLI はイメージ層に入るため、実行時の `node` ユーザーから自己更新しづらくなります。

特に次の問題が起きやすくなります。

- install 先が root 管理領域になり、更新時に権限不足になる
- 更新できても、コンテナ再作成で build 時点の版に戻る
- 更新結果がどこに残るのか見えづらい

### 採用した方針

`NPM_CONFIG_PREFIX=/home/node/.npm-global` を使い、CLI 本体を writable なユーザー領域へ置きます。
このディレクトリは host 側の `.devcontainer-data/npm-global` に bind mount されるため、更新後の CLI 実体も保持されます。

また、`entrypoint.sh` で次を行います。

- `PATH` に `/home/node/.npm-global/bin` を追加
- 永続化対象ディレクトリを起動時に作成
- `claude` / `codex` が未導入なら `node` ユーザーで `npm install -g` する

この構成により、初回起動時は自動導入、2 回目以降は永続化済みの実体をそのまま使う、という動作になります。

## Claude 固有の考慮

Claude Code は `~/.claude` だけ見れば十分、ではありません。
ユーザー設定や skills などは `~/.claude` にありますが、OAuth セッション、MCP 設定、許可状態、各種キャッシュは `~/.claude.json` に保存されます。

そのため、`~/.claude` だけ永続化すると次の半端な状態が起こります。

- settings や skills は残る
- しかしログイン状態や許可状態が再作成で消える

これを避けるため、`/home/node/.claude.json` 自体を永続化したいのですが、単一ファイル bind mount よりディレクトリ管理の方が扱いやすいため、次の構成にしています。

- `/home/node/.claude-root/.claude.json` を永続化
- `/home/node/.claude.json` はそのファイルへの symlink とする

この symlink は `entrypoint.sh` で起動時に補います。

## Codex 固有の考慮

Codex の設定、セッション、ログは主に `~/.codex` に保存されます。
したがって、`/home/node/.codex` をそのまま host 側へ bind mount しています。

この永続化により、少なくとも以下が `docker compose down` 後も保持されます。

- 設定
- 過去ログ
- セッション履歴
- モデル情報などのキャッシュ

## entrypoint の責務

`scripts/entrypoint.sh` は単なる起動ラッパーではなく、現在は以下を担っています。

- `.devcontainer/config.toml` の読み込み
- Git 設定の適用
- API キーなどの環境変数の export
- GitHub CLI 認証
- AWS CLI 環境変数設定
- DB ソケット関連環境変数の設定
- 永続化対象ディレクトリの作成
- Claude / Codex の導入確認と不足時のインストール
- Claude の `~/.claude.json` symlink 補完

つまり、`Dockerfile` はベース環境を用意し、実行時に変化する個人設定や CLI 状態は `entrypoint.sh` 側で収束させる、という責務分離です。

## root と node の役割分担

この構成では、entrypoint は **root** で動き、実作業は **node**（`remoteUser`）で行われます。
ここを意識せずに設定を書くと、「entrypoint のログ上は成功しているのに、実際に使うユーザーからは何も見えない」という壊れ方をします。
実際に次の 3 つが同じ原因で壊れていました。

- `git config --global` が `/root/.gitconfig` に書かれ、node からは Git の名前・メールが見えない
- `gh auth login` の結果が `/root/.config/gh` に入り、永続化対象の `/home/node/.config/gh` に残らない
- `hooks.post_start` が root で実行され、生成物が root 所有になって後から node で触れない

判断基準は「その設定が誰のものか」です。

- **全ユーザー共通の設定** -> system スコープに置く（`/etc/gitconfig`、`/etc/profile.d/`）
  - Git の LFS filter、Git のユーザー設定、環境変数がこれにあたります
  - Git のユーザー設定を `--system` に置くのは一般には珍しいですが、この devcontainer は 1 人の開発者が root と node を行き来する前提なので、両方から同じ値が見えることを優先しています
- **node のホーム配下に状態を作るもの** -> `run_as_node` を通して node で実行する
  - `gh auth login`、`npm install -g`、`hooks.post_start` がこれにあたります

`hooks.post_start` を node で実行するのは、VS Code の `postStartCommand` が `remoteUser` で動くことに合わせた挙動でもあります。
root 権限が必要なフックを書く場合は、フック側で `sudo` を使ってください。

## 起動完了の目印

entrypoint はコンテナ起動と非同期に走り、CLI の導入まで含めると数十秒かかります。
その間に接続すると、Git 設定も環境変数もまだ当たっていない状態を踏みます。

そのため、すべての初期化が終わった時点で `/run/devcontainer-ready` を作ります。
起動完了を待ちたい側（CI やスクリプト）はこれを見れば済み、個別の設定項目をポーリングする必要がありません。

## CI での継続的な確認

ベースイメージを `:latest` で参照しているため、この構成はリポジトリ側を変更していなくても壊れることがあります。
実際に Git LFS の欠落もこの形で表面化しました。upstream 側の変化に気づける仕組みがないと、同じ種類の事故が繰り返されます。

そこで `.github/workflows/devcontainer.yml` で次を回しています。
push / PR に加えて週次でも実行するのは、こちらを変更していなくても upstream の変化で壊れるためです。

### `image` ジョブ: イメージに何が入っているか

`base` / `full` の両ターゲットをビルドし、`scripts/smoke-test.sh` を **root と node の両方** で実行します。
2 ユーザーで回しているのは、この構成の壊れ方が「root では動くが node では動かない」形を取りやすいためです。

確認はツールの存在確認だけでなく、LFS については実際に track -> commit -> checkout まで通し、ポインタ化と実体復元の両方を見ています。
`git lfs version` が通ることと、LFS が実際に機能することは別だからです。

### `runtime` ジョブ: 起動後に期待した状態になっているか

`devcontainer up` で実際にコンテナを起動し、`/run/devcontainer-ready` を待ってから `scripts/runtime-test.sh` を **`devcontainer exec` 経由（= remoteUser の node）** で実行します。
イメージが正しくても entrypoint の適用先を間違えれば環境は壊れるので、こちらは「config.toml に書いた設定が node から見えるか」を確認します。

- Git の名前・メールが config.toml の値と一致すること
- API キーなどが login shell で参照できること、PATH に npm prefix が入っていること
- 永続化対象ディレクトリが node で書き込めること、`~/.claude.json` が symlink であること
- `claude` / `codex` がイメージ層ではなく書き込み可能な npm prefix にあること
- `hooks.post_start` が root ではなく node で実行されること

### `config` ジョブ: 設定ファイルが妥当か

`example.config.toml` から `config.toml` を生成した上で、`docker-compose.yml` と `devcontainer.json` を検証します。

## 変更時に守りたいこと

今後この構成を変更する場合は、少なくとも以下を崩さない方がよいです。

- `node` ユーザーで CLI が実行・更新できること
- entrypoint が適用する設定が、root ではなく `node` から見えること
- 更新後の CLI 実体がコンテナ再作成後も残ること
- Claude の `~/.claude` と `~/.claude.json` の両方が失われないこと
- Codex の `~/.codex` が失われないこと
- `.devcontainer-data/` は git 管理対象にしないこと
- `config.toml` は読み取り専用 mount のままにすること

## トレードオフ

この構成には意図的なトレードオフがあります。

- 初回起動時は `claude` / `codex` の導入分だけ起動が少し重い
- host 側に `.devcontainer-data/` が増える
- CLI のバージョンが image build と完全一致しない場合がある

ただし、これらは次の利点のために受け入れています。

- 自己更新が壊れにくい
- 再作成で認証や履歴が消えにくい
- AI CLI を日常運用しやすい

## 既知の注意点

- この設計は `node` ユーザーのホーム配下を状態保存先として使う前提です。ベースイメージや `remoteUser` を変える場合は見直しが必要です。
- `docker` 自体をこの開発環境から直接叩けない場合、実コンテナでの動作確認は host 側で行う必要があります。
- Claude / Codex 側の将来の保存先変更があれば、bind mount 対象も追従が必要です。

## 関連ファイル

- `Dockerfile`: ベース環境と writable な npm prefix の定義
- `docker-compose.yml`: 永続化用 bind mount の定義
- `scripts/entrypoint.sh`: 実行時初期化と CLI 状態の収束
- `README.md`: 利用者向けセットアップ手順
