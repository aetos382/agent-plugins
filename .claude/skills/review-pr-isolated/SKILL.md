---
name: review-pr-isolated
description: プル リクエストを作成する前に、開発とは別のセッションで /pr-review-toolkit:review-pr を実行し、その結果を報告する。PR を作る直前、またはユーザーが「PR 前のレビュー」「別コンテキストでレビュー」を求めたときに使う。
---

# 別セッションでの PR レビュー

開発時の前提や意図がレビューに持ち込まれないよう、`claude -p` で新しいセッションを起動して `/pr-review-toolkit:review-pr` を実行する。開発セッションは、レビューの起動、結果の判定、報告だけを行う。

各手順で想定外の結果になったら、先へ進まずにユーザーに報告する。

## 1. 前提の確認

- `command -v claude jq` の結果で、両方のパスが出力されること（`command -v` は、どれか 1 つでも見つかれば成功を返すので、終了コードでは判定しない）。
- `git status --porcelain` が空であること。レビューの対象はコミット済みの `origin/main...HEAD` なので、未コミットの変更はレビューされない。空でなければ、コミットするかどうかをユーザーに確認する。
- `git fetch origin main` を実行し、比較の基準となる `origin/main` を最新にしておく。

## 2. 実行前の状態を記録

レビュー側が Bash 経由で作業ツリーを変更していないかを後で確かめるため、次の 2 つを記録する。

```bash
git rev-parse HEAD
git status --porcelain
```

## 3. レビューの実行

次のコマンドを、1 回の Bash 呼び出しとしてバックグラウンドで実行する。時間がかかるので、完了の通知を待つ。

```bash
mkdir -p Temp
claude -p '/pr-review-toolkit:review-pr code comments tests errors types. Review the changes in origin/main...HEAD.' \
  --output-format json \
  --allowedTools 'Read' 'Glob' 'Grep' 'Agent' \
    'Bash(git diff *)' 'Bash(git log *)' 'Bash(git show *)' 'Bash(git status *)' \
    'Bash(gh pr view *)' 'Bash(gh pr diff *)' 'Bash(shellcheck *)' 'Bash(claude plugin validate *)' \
  --disallowedTools 'Edit' 'Write' 'NotebookEdit' \
  > "Temp/review-$(git rev-parse --short HEAD).json"
```

- レビュー側にコードを変更させないため、編集系ツールを禁止し、コードを書き換える `simplify` 観点は指定しない。
- 結果の JSON ファイルは、レビュー側のセッションではなく、開発セッションのシェルがリダイレクトで書き込む。レビュー側への編集の禁止とは両立するので、レビュー側に書き込みを許可したり、禁止を緩めたりしない。
- `Temp/` は `.gitignore` で除外してあるので、結果のファイルは手順 4 の比較に現れない。

## 4. 実行後の状態を確認

手順 2 と同じコマンドを実行し、記録と比べる。`review-pr` 自身の `allowed-tools` が制限なしの `Bash` を含むため、`--disallowedTools` だけでは Bash 経由の変更を防げない。

違いがあれば、プル リクエストの作成に進まず、`git diff` や `git log` で変更の内容を確かめてユーザーに報告する。変更を勝手に戻さない。

## 5. 結果の判定

結果の JSON を `jq` で読む。

| 確認項目 | 対応 |
|---|---|
| `is_error` が `true`、または `subtype` が `success` でない | レビューが完了していないものとして、ユーザーに報告する |
| `permission_denials` が空でない | 拒否されたツール呼び出しを添えて、レビューが不完全である可能性を報告する |
| 上記のフィールドがない | JSON の構造が想定と違う。推測で判定せず、トップ レベルのキー一覧（`jq 'keys'`）を示してユーザーに報告し、このスキルの修正を提案する |

指摘事項の本文は `.result` にある。

## 6. 報告

`.result` の指摘事項を、重要度に関わらず通し番号を振り直して報告する。手順 5 で見つかった問題（未完了、拒否されたツール呼び出し）も併せて報告する。

指摘への対応は、ユーザーの指示を受けてから行う。対応後にもう一度レビューする場合は、コミットしてからこのスキルを最初から実行する。
