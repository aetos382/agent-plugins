---
name: update-supported-distributions
description: dev-container-feature-development の対象ディストリビューション（Ubuntu LTS、Debian stable/oldstable、mcr.microsoft.com/devcontainers/base の非 root テスト イメージ）の更新を、正本の書き換えから PR 作成まで行う。「Supported distributions need updating」や「Check mcr.microsoft.com/devcontainers/base for Ubuntu <version>」の issue に対応するとき、またはユーザーが対象ディストリビューションの更新を求めたときに使う。
argument-hint: "[mcr <ubuntu-version>] [issue-number]"
---

# 対象ディストリビューションの更新

dev-container-feature-development の対象ディストリビューションを更新し、プル リクエストを作成する。正本は `plugins/dev-container-feature-development/skills/feature-authoring/references/supported-distributions.md`、照合と上流チェックは `.github/scripts/check-supported-distributions.sh` で行う。

このスキルの起動は、ブランチの作成、コミット、プッシュ、プル リクエストの作成までの指示として扱う。ただし、各手順で想定外の結果になった場合や、判断に迷う置き換えがある場合は、先へ進まずにユーザーに報告する。

## 引数

| 引数 | モード |
|---|---|
| なし、または `<issue-number>` | **distributions**: 上流の Ubuntu LTS と Debian のリリースに正本を合わせる |
| `mcr <ubuntu-version> [<issue-number>]` | **mcr**: 指定の Ubuntu 版の `devcontainers/base` イメージを非 root テスト イメージに加える |

issue 番号が与えられたら、`gh issue view <番号>` で内容を確かめ、プル リクエスト本文に `Closes #<番号>` を書く。与えられなければ、`gh issue list --state open --search "in:title <題名>"` で対応する issue を探し、見つかればそれを使う。

## 1. 準備

- `git status --porcelain` が空であること。空でなければ中断して報告する。
- `git fetch origin` の後、`origin/main` からトピック ブランチを作る。名前は distributions モードなら `chore/update-supported-distributions-<YYYYMM>`、mcr モードなら `chore/add-devcontainers-base-ubuntu<version>`。

## 2a. distributions モード

1. 上流の状態を取り直す。issue の本文は作成時点のものなので、それには頼らない。

   ```bash
   mkdir -p Temp
   bash .github/scripts/check-supported-distributions.sh upstream --new-ubuntu-releases Temp/new-ubuntu-releases.txt
   ```

   - 終了コード 0: 更新は不要。ブランチを削除し、issue があれば閉じてよいかをユーザーに確認して終わる。
   - 終了コード 2: 通信などのエラー。中断して報告する。
   - 終了コード 1: 出力の「上流の最新」の表を使って、次に進む。

2. 正本を書き換える。
   - 「Current releases」の表を、上流の最新の表に置き換える。
   - 「Last checked against upstream release information」の日付を今日にする。
   - 「Non-root test images」から、対象から外れた Ubuntu 版のイメージを削除する。新しい Ubuntu 版のイメージはここでは追加しない（mcr モードで扱う）。
   - 「CI base images」を、表のイメージと Non-root test images を合わせた一覧にする。並びは `debian`、`ubuntu`、`mcr.microsoft.com/devcontainers/base` の順で、それぞれバージョンの昇順。

3. 手順 3 の「他の箇所を合わせる」へ進む。

## 2b. mcr モード

1. 正本のリリースの表に、指定の Ubuntu 版があることを確かめる。なければ、先に distributions モードで対応が必要なので、中断して報告する。
2. レジストリでタグを確かめる。

   ```bash
   curl -fsS https://mcr.microsoft.com/v2/devcontainers/base/tags/list | jq -r '.tags[]' | grep -E '^[0-9]+-ubuntu<version>$'
   ```

   - 見つからない: まだ公開されていない。ブランチを削除し、issue は開いたままにして、その旨を報告して終わる。
   - 見つかった: 先頭の数字が最も大きいタグを使う。
3. 正本の「Non-root test images」と「CI base images」に `mcr.microsoft.com/devcontainers/base:<major>-ubuntu<version>` を追加する。並びは手順 2a と同じ規則に従う。

## 3. 他の箇所を合わせる

1. `bash .github/scripts/check-supported-distributions.sh consistency` を実行し、報告された箇所を直す。報告が出なくなるまで繰り返す。置き換えの規則は次のとおり。

   | 箇所 | 置き換え方 |
   |---|---|
   | Feature リポジトリ用のワークフロー雛形 `skills/init-repository/assets/workflows/test.yaml` の `baseImage` | 正本の「CI base images」と同じ内容、同じ並びにする |
   | README や `feature-reviewer` エージェントなど、対象リリースを列挙した文 | 正本の表のとおりに列挙し直す |
   | サンプルや説明の中で、対象から外れたリリースを 1 つ使っている箇所 | 同じディストリビューションのサポート対象のうち、最も古いリリースに置き換える（例: `debian:12` → `debian:13`）。説明の内容がそのリリース固有の事情に依存していれば、置き換えずにユーザーに報告する |
   | 対象から外れた非 root テスト イメージ | 残っている非 root テスト イメージのうち、最も新しいものに置き換える |

2. 照合スクリプトはリリース番号とイメージ名しか見ないので、コードネームの取り残しを別に探す。対象から外れたリリースのコードネーム（例: `Bookworm`）で `plugins/dev-container-feature-development` と `.claude/rules` を検索し、見つかれば直す。
3. `claude plugin validate --strict plugins/dev-container-feature-development` を実行する。変更したシェル スクリプトがあれば `shellcheck` も実行する。
4. `plugins/dev-container-feature-development/.claude-plugin/plugin.json` の `version` のマイナー バージョンを上げる（パッチは 0 に戻す）。ただし、このブランチで既に `origin/main` より上がっていれば、そのままにする。

## 4. コミットとレビュー

1. 変更を 1 つのコミットにまとめる。コミット メッセージは日本語で、distributions モードなら「対象ディストリビューションを更新（<追加・削除の要約>）」、mcr モードなら「devcontainers/base の Ubuntu <version> 版を非 root テスト イメージに追加」とする。
2. `/review-pr-isolated` を実行する。重大な指摘があれば、プル リクエストを作らずに報告し、ユーザーの指示を待つ。

## 5. プル リクエスト

1. ブランチをプッシュし、`gh pr create` でプル リクエストを作る。題名はコミット メッセージと同じにする。本文には次を書く。
   - 変更の要約（追加・削除されたリリースやイメージ）
   - 手順 3 で行った置き換えのうち、機械的でないもの
   - `Closes #<issue の番号>`（issue がある場合）
   - distributions モードで新しい Ubuntu 版があった場合は、mcr の対応版が別の issue で扱われること
2. プル リクエストの URL を報告する。あわせて、マージ後に各 Feature リポジトリで行うこと（`/dev-container-feature-development:init-repository` の再実行、`/dev-container-feature-development:run-feature-tests` での全 Feature のテスト、`NOTES.md` の更新）を伝える。
