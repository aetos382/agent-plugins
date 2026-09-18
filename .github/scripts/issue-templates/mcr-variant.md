Ubuntu __VERSION__ が、dev-container-feature-development のサポート対象になった（または、なる予定である）。非 root ユーザーでのテストに使う `mcr.microsoft.com/devcontainers/base` に、Ubuntu __VERSION__ 版が公開されているかを確認する。

このイメージは Ubuntu のリリースから数週間遅れて公開されるので、自動では確認していない。公開されるまで、この issue は開いたままにしておく。

## 対応方法

このリポジトリで Claude Code を開き、`/update-supported-distributions mcr __VERSION__ <この issue の番号>` を実行する。タグの確認から、見つかった場合のプル リクエストの作成までを行う。まだ公開されていなければ、その旨を報告して終わる。

手作業で対応する場合は、以下の手順に従う。

## 確認方法

https://mcr.microsoft.com/en-us/artifact/mar/devcontainers/base の Tags で、`-ubuntu__VERSION__` で終わるタグを探す。コマンドで確かめる場合は次のとおり。

```bash
curl -fsS https://mcr.microsoft.com/v2/devcontainers/base/tags/list | jq -r '.tags[]' | grep -E '^[0-9]+-ubuntu__VERSION__$'
```

- **見つからない場合**: 何もせず、この issue を開いたままにする。月に 1 回程度、確認し直す。
- **見つかった場合**: 先頭の数字（メジャー バージョン）が最も大きいタグを使い、下の手順で追加する。

## 追加の手順

1. 「Supported distributions need updating」の issue が開いていれば、先にそちらを対応してマージする。正本のリリースの表に Ubuntu __VERSION__ がないと、下の手順 5 の検査が通らない。
2. `main` から、トピック ブランチ（例: `chore/add-devcontainers-base-ubuntu__VERSION__`）を作る。
3. 正本 `plugins/dev-container-feature-development/skills/feature-authoring/references/supported-distributions.md` を更新する。
   - 「Non-root test images」に `mcr.microsoft.com/devcontainers/base:<メジャー バージョン>-ubuntu__VERSION__` を追加する。
   - 「CI base images」にも同じイメージを追加する。並びは、`mcr.microsoft.com/devcontainers/base` のイメージの中でバージョンの昇順とする。
4. Feature リポジトリ用のワークフロー雛形 `plugins/dev-container-feature-development/skills/init-repository/assets/workflows/test.yaml` の `baseImage` にも、同じ位置に追加する。
5. `bash .github/scripts/check-supported-distributions.sh consistency` を実行し、報告された箇所をすべて直す。
6. `claude plugin validate --strict plugins/dev-container-feature-development` を実行する。
7. `plugins/dev-container-feature-development/.claude-plugin/plugin.json` の `version` のマイナー バージョンを上げる。
8. プル リクエストを出す。本文に `Closes #<この issue の番号>` を書く。

## マージ後に Feature リポジトリで行うこと

各 Feature リポジトリで `/dev-container-feature-development:init-repository` を実行してテスト ワークフローの `baseImage` を更新し、`/dev-container-feature-development:run-feature-tests` で全 Feature をテストする。
