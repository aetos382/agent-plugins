# CLAUDE.md

## このリポジトリ

Claude Code のプラグインを配布するマーケットプレイス。

- `.claude-plugin/marketplace.json`: マーケットプレイスの定義。プラグインを追加したら、ここに登録する（ファイルがなければ作成する）。
- `plugins/<name>/`: 各プラグイン。マニフェストは `plugins/<name>/.claude-plugin/plugin.json`。
- プラグイン固有の開発方針は `.claude/rules/<name>.md` に `paths` 付きで書く。`plugins/<name>/` 以下は丸ごと配布されるため、そこに `CLAUDE.md` を置かない。

## 対象エージェント

- 最新版の Claude Code をターゲットとし、古いバージョンとの互換性は考慮しない。
- 他エージェントや [Agent Plugins](https://agent-plugins.org/) への対応は、実装の大部分を共有できる場合のみ考慮する。
- プラグインの機能は Claude Code 向けをフルセットとし、他エージェント向けはサブセットとする。他エージェント専用の機能は設けない。

## 対象環境

- プラグインを実行する環境に Git がインストールされていることは必須要件としてよい。

## プラグインの開発

- プラグイン全般の開発には `plugin-dev` プラグイン、プラグインに内蔵するスキルの開発には `skill-creator` プラグインを使う。作成後のレビューには `plugin-dev:plugin-validator` と `plugin-dev:skill-reviewer` を使う。
- `plugin.json` には `version` を SemVer で書き、利用者に届けたい変更をしたら上げる。`marketplace.json` のエントリには `version` を書かない。
- プラグイン実行環境の OS に依存するコードは避ける。
- プラグインを構成するスクリプトは Bash 用のシェル スクリプトで書く。
  - Python、JavaScript、PowerShell 等は、特別な理由がない限り使用しない。使う場合は事前にユーザーに確認する。
  - プラグイン利用者が実行しない、本リポジトリの開発用スクリプト（`.claude/install-plugins.ps1` 等）はこの限りでない。
  - macOS の `/bin/bash` は 3.2 なので、連想配列や `mapfile` など Bash 4 以降の機能は使わない。`sed -i`、`readlink -f`、`date -d` など GNU 固有の挙動にも依存しない。
  - フック等からスクリプトを呼ぶときは `bash "${CLAUDE_PLUGIN_ROOT}/..."` の形にし、実行ビットに頼らない。
  - `jq` 等、Git に同梱されないコマンドに依存する場合は、スクリプトの冒頭で存在を確認し、必須要件としてユーザー向けドキュメントに書く。
- コード中のコメントはアメリカ英語で書く。
- `*-lock.json` は手で編集せず、生成ツールで再生成する。

## プラグインのチェックおよびレビュー

- プラグインやマーケットプレイスの構成要素を変更したら `claude plugin validate --strict` で検証する。マーケットプレイスはリポジトリのルートを、プラグインは `plugins/<name>` を渡す。
- シェル スクリプトを変更したら `shellcheck` を実行する。
- プル リクエストを出す前には `/pr-review-toolkit:review-pr` でレビューする。

## ドキュメント

- `README.md` や `SKILL.md` 等のプラグインに同梱して配布される文書はアメリカ英語で書く。
- `CLAUDE.md` 等、プラグイン開発時にエージェントが読むための文書は日本語で書く。
- 対象エージェントおよび必須要件は、各プラグインの `README.md` の Requirements 節に明記する。

## ソース管理

本リポジトリのソース管理について。

- `main` ブランチにはコミットしない。機能開発は適当なトピック ブランチで行う。
- コミット メッセージやプル リクエストのサマリーは日本語で書く。
