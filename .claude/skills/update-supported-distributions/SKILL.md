---
name: update-supported-distributions
description: dev-container-feature-development の対象ディストリビューション（Ubuntu LTS、Debian stable/oldstable、mcr.microsoft.com/devcontainers/base の非 root テスト イメージ）を上流の最新に合わせて更新する。Ubuntu や Debian の新しいリリース、devcontainers/base の新しいイメージやメジャー バージョンが出たとき、またはユーザーが対象ディストリビューションの確認や更新を求めたときに使う。
---

# 対象ディストリビューションの更新

dev-container-feature-development の対象ディストリビューションを上流の最新に合わせる。正本は `plugins/dev-container-feature-development/skills/feature-authoring/references/supported-distributions.md` で、方針は同ファイルの「Policy」節に従う。

このスキルは作業ツリーの変更と検証までを行う。コミット、プッシュ、プル リクエストの作成は、ユーザーの指示を待つ。各手順で想定外の結果になった場合や、判断に迷う置き換えがある場合は、先へ進まずに報告する。

## 1. 上流の最新を調べる

取得や解析の失敗を「新しい版がない」と取り違えないよう、コマンドはパイプでつながず 1 つずつ実行し、`curl` や `jq` が失敗したら中断して報告する。取得したファイルは `Temp/` に置く（`mkdir -p Temp`）。

1. **Ubuntu LTS**

   ```bash
   curl -fsS --retry 3 -o Temp/meta-release-lts https://changelogs.ubuntu.com/meta-release-lts
   awk '/^Dist:/ { dist = $2 } /^Version:/ && /LTS/ { split($2, p, "."); print p[1] "." p[2], dist }' Temp/meta-release-lts
   ```

   最後の 2 行が最新と 1 つ前の LTS（版とコードネーム）。`Supported:` フィールドはアップグレードの提供可否であり、リリース済みかどうかではないので判断に使わない。

2. **Debian stable と oldstable**（`<suite>` を `stable`、`oldstable` にしてそれぞれ実行）

   ```bash
   curl -fsS --retry 3 -o Temp/debian-<suite>-Release https://deb.debian.org/debian/dists/<suite>/Release
   grep -E '^(Version|Codename):' Temp/debian-<suite>-Release
   ```

   `Version` のメジャー番号（`13.1` なら `13`）とコードネームを使う。

3. **devcontainers/base のタグ**

   ```bash
   curl -fsS --retry 3 -o Temp/mcr-base-tags.json https://mcr.microsoft.com/v2/devcontainers/base/tags/list
   jq -r '.tags[]' Temp/mcr-base-tags.json > Temp/mcr-base-tags.txt
   grep -E '^[0-9]+-ubuntu[0-9]+\.[0-9]+$' Temp/mcr-base-tags.txt
   ```

   手順 1 の Ubuntu 版それぞれについて、`<major>-ubuntu<version>` があるもののうち `<major>` が最大のタグを選ぶ。該当するタグがない Ubuntu 版（リリース直後で未公開）は非 root テスト イメージに含めず、その旨を最後に報告する。

4. 結果を正本と比べる。リリースの表と非 root テスト イメージのどちらも一致していれば、更新は不要と報告して終わる。

## 2. ブランチを作る

- `git status --porcelain` が空であること。空でなければ中断して報告する。
- `git fetch origin` の後、`origin/main` から `chore/update-supported-distributions-<YYYYMMDD>` を作る。

## 3. 正本を書き換える

- 「Current releases」の表を、手順 1 の結果（Ubuntu は新しい順、次に Debian を新しい順）にする。コードネームは先頭だけ大文字にし（`resolute` → `Resolute`）、イメージ名は `ubuntu:<version>`、`debian:<major>` とする。
- 「Last checked against upstream release information」の日付を今日にする。
- 「Non-root test images」を、手順 1.3 で選んだタグの一覧にする（Ubuntu の新しい順）。
- 「CI base images」を、表のイメージと Non-root test images を合わせた一覧にする。並びは `debian`、`ubuntu`、`mcr.microsoft.com/devcontainers/base` の順で、それぞれバージョンの昇順。

## 4. 他の箇所を合わせる

1. `bash .github/scripts/check-supported-distributions.sh` を実行し、報告された箇所を直す。報告が出なくなるまで繰り返す。置き換えの規則は次のとおり。

   | 箇所 | 置き換え方 |
   |---|---|
   | Feature リポジトリ用のワークフロー雛形 `skills/init-repository/assets/workflows/test.yaml` の `baseImage` | 正本の「CI base images」と同じ内容、同じ並びにする |
   | 対象リリースや非 root テスト イメージを列挙した文 | 正本のとおりに列挙し直す |
   | サンプルや説明の中で、対象から外れたリリースを 1 つ使っている箇所 | 同じディストリビューションのサポート対象のうち、最も古いリリースに置き換える（例: `debian:12` → `debian:13`）。説明の内容がそのリリース固有の事情に依存していれば、置き換えずに報告する |
   | 対象から外れた非 root テスト イメージ | 残っている非 root テスト イメージのうち、最も新しいものに置き換える |

2. 照合スクリプトは、書かれた名前が対象内かどうかしか見ず、列挙の漏れは検出しない。次の列挙は報告の有無にかかわらず正本と突き合わせ、追加された版が漏れていれば直す。
   - `plugins/dev-container-feature-development/README.md` の Conventions 節
   - `plugins/dev-container-feature-development/agents/feature-reviewer.md` の Supported distributions と非 root シナリオの例
   - `plugins/dev-container-feature-development/skills/feature-authoring/examples/NOTES.md` の Limitations 節
3. 照合スクリプトはコードネームも見ない。対象から外れたリリースのコードネーム（例: `Bookworm`）で `plugins/dev-container-feature-development` と `.claude/rules` を検索し、見つかれば直す。

## 5. 検証とバージョン

1. `claude plugin validate --strict plugins/dev-container-feature-development` を実行する。変更したシェル スクリプトがあれば `shellcheck` も実行する。
2. `plugins/dev-container-feature-development/.claude-plugin/plugin.json` の `version` のマイナー バージョンを上げる（パッチは 0 に戻す）。ただし、このブランチで既に `origin/main` より上がっていれば、そのままにする。

## 6. 報告

次を報告する。

- 追加・削除したリリースとイメージ
- 手順 4 で行った置き換えのうち、機械的でないもの
- まだ devcontainers/base に variant がなく、非 root テスト イメージに入れられなかった Ubuntu 版（公開後にこのスキルを再実行すれば追加される）
- 次に行うこと: コミットとプル リクエストの作成（指示があれば行う）。マージ後、各 Feature リポジトリで `/dev-container-feature-development:init-repository` を再実行してテスト ワークフローの `baseImage` を更新し、`/dev-container-feature-development:run-feature-tests` で全 Feature をテストし、各 Feature の `NOTES.md` のテスト済みディストリビューションを更新する。
