## 対応方法

このリポジトリで Claude Code を開き、`/update-supported-distributions <この issue の番号>` を実行する。以下の手順を、正本の書き換えからプル リクエストの作成まで行う。

手作業で対応する場合は、以下の手順に従う。

## 対応手順

1. `main` から、トピック ブランチ（例: `chore/update-supported-distributions`）を作る。
2. 正本 `plugins/dev-container-feature-development/skills/feature-authoring/references/supported-distributions.md` を更新する。
   - 「Current releases」の表を、上の「上流の最新」の表に置き換える。
   - 「Last checked against upstream release information」の日付を今日にする。
   - 「Non-root test images」から、サポート対象から外れた Ubuntu 版のイメージを削除する。新しい Ubuntu LTS 版のイメージは、ここでは追加しない（別の issue で扱う。後述）。
   - 「CI base images」を、表のイメージと Non-root test images を合わせた一覧にする。並びは、`debian` のイメージ、`ubuntu` のイメージ、`mcr.microsoft.com/devcontainers/base` のイメージの順で、それぞれバージョンの昇順とする。
3. `bash .github/scripts/check-supported-distributions.sh consistency` を実行し、報告された箇所をすべて直す。報告が出なくなるまで繰り返す。
   - Feature リポジトリ用のワークフロー雛形 `skills/init-repository/assets/workflows/test.yaml` の `baseImage` は、「CI base images」と同じ並びにする。
   - README、`feature-reviewer` エージェント、サンプル（`examples/`）の中で、サポート対象から外れたリリースを使っている箇所は、サポート対象のリリースに置き換える。
4. `claude plugin validate --strict plugins/dev-container-feature-development` と、変更したシェル スクリプトへの `shellcheck` を実行する。
5. `plugins/dev-container-feature-development/.claude-plugin/plugin.json` の `version` のマイナー バージョンを上げる。テスト対象の変更は、プラグインの利用者に届けるべき変更なので。
6. プル リクエストを出す。本文に `Closes #<この issue の番号>` を書く。validate ワークフローの `distributions` ジョブが通ればマージしてよい。

## 新しい Ubuntu LTS がある場合

新しく対象になった Ubuntu LTS 版ごとに、「Check mcr.microsoft.com/devcontainers/base for Ubuntu <バージョン>」という issue が別に立つ。`mcr.microsoft.com/devcontainers/base` の対応版は数週間遅れて公開されるので、Non-root test images への追加はそちらで扱う。この issue の対応は、それを待たずに進めてよい。

## マージ後に Feature リポジトリで行うこと

プラグインを更新しても、既存の Feature リポジトリのワークフローは自動では変わらない。各 Feature リポジトリで次を行う。

1. `/dev-container-feature-development:init-repository` を実行し、テスト ワークフローの `baseImage` を更新する。
2. `/dev-container-feature-development:run-feature-tests` で全 Feature をテストし、新しいリリースで壊れていないか確かめる。
3. 各 Feature の `NOTES.md` にある、テスト済みディストリビューションの記述を更新する。
