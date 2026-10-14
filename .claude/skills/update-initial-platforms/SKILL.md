---
name: update-initial-platforms
description: dev-container-feature-development の初期値（init-repository が新しい Features リポジトリに書く test-feature.yaml の baseImage と RUNNERS）と、プラグイン内の例のイメージ名を、上流の最新に合わせて更新する。Ubuntu や Debian の新しいリリース、devcontainers/base の新しいイメージやメジャー バージョン、GitHub ホステッド ランナーの新しい Ubuntu 版が出たとき、またはユーザーが初期値の確認や更新を求めたときに使う。既存の Features リポジトリの一覧は変えない。
---

# 初期値の更新

dev-container-feature-development の初期値を上流の最新に合わせる。初期値は、ワークフロー雛形 `plugins/dev-container-feature-development/skills/init-repository/assets/workflows/test-feature.yaml` の `baseImage` と `RUNNERS` だけに書いてある。選び方は `plugins/dev-container-feature-development/skills/feature-authoring/references/supported-platforms.md` の「Initial values」節に従う。対象アーキテクチャ（`RUNNERS` のキー）は上流のリリースに連動しないので、このスキルでは扱わない。ランナーのラベルは Ubuntu LTS の版で固定しているので、このスキルで扱う。

対象のディストリビューションは、各 Features リポジトリが自分のテスト ワークフローで決める。初期値を変えても既存のリポジトリには届かない。`init-repository` を再実行したときに、初期値との差が計画に情報として出るだけである。

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

   手順 1 の Ubuntu 版それぞれについて、`<major>-ubuntu<version>` があるもののうち `<major>` が最大のタグを選ぶ。Ubuntu 版と Debian 版はバージョン番号が別々なので、Debian の variant のタグにない `<major>` があっても、提供が打ち切られたわけではない。該当するタグがない Ubuntu 版（リリース直後で未公開）は含めず、その旨を最後に報告する。選んだタグが 1 つも無ければ、`devcontainers/base` のイメージを 1 つ以上含めるという原則を満たせないので、中断して報告する。

4. **GitHub ホステッド ランナー**

   [GitHub-hosted runners のリファレンス](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)の、標準ランナーの表（パブリック リポジトリ用とプライベート リポジトリ用）を読む。雛形の `RUNNERS` の全アーキテクチャについて、両方の表にラベルがある Ubuntu 版のうち最新のものを選ぶ（例: `ubuntu-24.04` と `ubuntu-24.04-arm`）。プレビューやベータと書かれたラベルは数えない。

5. 結果を雛形の `baseImage` と `RUNNERS` と比べる。どちらも一致していれば、更新は不要と報告して終わる。

## 2. ブランチを作る

- `git status --porcelain` が空であること。空でなければ中断して報告する。
- `git fetch origin` の後、`origin/main` から `chore/update-initial-platforms-<YYYYMMDD>` を作る。

## 3. 雛形を書き換える

- `baseImage` を、手順 1 の Debian、Ubuntu、devcontainers/base のタグを合わせた一覧にする。並びは `debian`、`ubuntu`、`mcr.microsoft.com/devcontainers/base` の順で、それぞれバージョンの昇順。イメージ名は `debian:<major>`、`ubuntu:<version>`、`mcr.microsoft.com/devcontainers/base:<major>-ubuntu<version>` とする。
- `RUNNERS` の各ランナーを、手順 1.4 で選んだラベルにする。キーとその並びは変えない。

## 4. 原則を確かめ、他の箇所を合わせる

1. 書き換えた雛形が、`plugins/dev-container-feature-development/skills/feature-authoring/references/supported-platforms.md` の「Principles」を満たすことを確かめる。`baseImage` のどのイメージもリリースのタグを持つ（`latest` やタグなしではない）こと、`mcr.microsoft.com/devcontainers/base` のイメージが 1 つ以上あること、`RUNNERS` のどのランナーも Ubuntu の版を名指しする（`ubuntu-latest` ではない）ことである。
2. プラグインと rules に書かれたイメージ名、リリース番号、ランナー名を洗い出す。

   ```bash
   git grep -n -E -e '\b(ubuntu:[0-9]{2}\.[0-9]{2}|debian:[0-9]+)\b' -e 'mcr\.microsoft\.com/devcontainers/base:[A-Za-z0-9._-]+' -e '\b(Ubuntu [0-9]{2}\.[0-9]{2}|Debian [0-9]{1,2})\b' -e '\bubuntu-[0-9]{2}\.[0-9]{2}' -- plugins/dev-container-feature-development .claude/rules
   ```

   雛形 `test-feature.yaml` 自身の行を除き、雛形の `baseImage` に無いイメージ、そこに無いリリース、`RUNNERS` 以外に書かれたランナー名を、次の規則で直す。

   | 箇所 | 置き換え方 |
   |---|---|
   | サンプルや説明の中で、外れたリリースを 1 つ使っている箇所 | 同じディストリビューションの、雛形に残っているうち最も古いリリースに置き換える（例: `debian:12` → `debian:13`）。説明の内容がそのリリース固有の事情に依存していれば、置き換えずに報告する |
   | 外れた devcontainers/base のイメージ（雛形の `devcontainer.json` を含む） | 雛形に残っている devcontainers/base のイメージのうち、最も新しいものに置き換える |
   | リリースを列挙した文 | 雛形のとおりに列挙し直す |
   | `RUNNERS` 以外に書かれたランナー名 | 消す。ランナー名は `RUNNERS` にだけ書く |

   直した後にもう一度実行し、残りが無いことを確かめる。

3. 手順 2 は書かれた名前しか見ず、列挙の漏れは見つけない。`plugins/dev-container-feature-development/skills/feature-authoring/examples/NOTES.md` の Limitations 節は雛形と突き合わせ、追加された版が漏れていれば直す。
4. 手順 2 はコードネームも見ない。外れたリリースのコードネーム（例: `Bookworm`）で `plugins/dev-container-feature-development` と `.claude/rules` を検索し、見つかれば直す。
5. `architectures: '[...]'` の形の例（`ci.yaml` 雛形のコメント、`feature-testing` のテスト ジョブの例）は、アーキテクチャを変えないこのスキルでは直す必要がない。

## 5. 検証とバージョン

1. `claude plugin validate --strict plugins/dev-container-feature-development` を実行する。変更したシェル スクリプトがあれば `shellcheck` も実行する。
2. `plugins/dev-container-feature-development/.claude-plugin/plugin.json` の `version` のマイナー バージョンを上げる（パッチは 0 に戻す）。ただし、このブランチで既に `origin/main` より上がっていれば、そのままにする。

## 6. 報告

次を報告する。

- 追加・削除したイメージと、変更したランナー
- 手順 4 で行った置き換えのうち、機械的でないもの
- まだ devcontainers/base に variant がなく、含められなかった Ubuntu 版（公開後にこのスキルを再実行すれば追加される）
- 次に行うこと: コミットとプル リクエストの作成（指示があれば行う）。既存の Features リポジトリの一覧は変わらない。各リポジトリで一覧を変えるかどうかはそのリポジトリが決める。`/dev-container-feature-development:init-repository` を再実行すれば、初期値との差が計画に出る。
