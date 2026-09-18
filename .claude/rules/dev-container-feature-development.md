---
paths:
  - 'plugins/dev-container-feature-development/**'
---
# dev-container-feature-development

Dev Container Features 開発用のエージェント プラグイン。

## 対象 Linux ディストリビューション

Feature 実行環境となる Dev Container の OS について。

- Ubuntu の最新および 1 つ前の LTS リリースと、Debian の stable および oldstable は必ずサポートする。非 root ユーザーでのテストには、サポート対象の各 Ubuntu LTS について、`mcr.microsoft.com/devcontainers/base` のその版の variant を持つ最新メジャー バージョンを使う。
- その他の Linux ディストリビューションについては、パッケージ マネージャーの分岐を足す程度で済む場合のみサポートする。
- 具体的なリリースとイメージ名は `plugins/dev-container-feature-development/skills/feature-authoring/references/supported-distributions.md` を正本とする。プラグイン内でリリース番号やイメージ名を書く箇所は、正本と一致させる。
  - 一致しているかは `bash .github/scripts/check-supported-distributions.sh consistency` で検査する（CI の validate ワークフローでも実行される）。
  - 上流で新しいリリースが出たかは `bash .github/scripts/check-supported-distributions.sh upstream` で検査する。毎月 1 日にワークフローがこれを実行し、更新が必要なら issue を立てる。
    - Ubuntu と Debian のリリースの差分は「Supported distributions need updating」の issue で知らせる。
    - 新しい Ubuntu LTS が出た場合は、それとは別に「Check mcr.microsoft.com/devcontainers/base for Ubuntu <version>」の issue を立てる。`devcontainers/base` の対応版は数週間遅れて公開されるので、レジストリは自動では調べず、公開を人が確認してから Non-root test images に加える。
    - `devcontainers/base` の新しいメジャー バージョンは自動では検出しない。気づいたら手動で更新する。
  - issue への対応は `/update-supported-distributions` スキルで行える。正本の書き換えからプル リクエストの作成までを行う。
  - 更新するときは、正本の表、確認日、Non-root test images と CI base images の一覧を書き換えてから、`consistency` の検査が通るように他の箇所を合わせる。サポート対象から外れた Ubuntu の Non-root test images は、リリースの表と同時に外す。

## 開発方針

Feature に含まれるスクリプトの書き方について。

- 依存パッケージのインストールには `apt-get` を使用してよい。`apt-get` がないディストリビューションで使用する場合は、ユーザーがあらかじめ依存パッケージをインストールしておく必要がある。
  - `apt-get` がない環境で、必須依存関係がインストールされていない場合は、エラーメッセージを出して、終了コード 1 で終了する。
- Feature が必要とする依存関係は `src/<feature>/NOTES.md` に明記する。
- テストは必須サポート対象のディストリビューションで行う。その他のディストリビューションではテストしていないことを `src/<feature>/NOTES.md` に明記する。
- [nanolayer](https://github.com/devcontainers-extra/nanolayer) は使わない。

## 参考実装

- `aetos382/devcontainer-features` は初期のサンプルとして参照してよいが、規範ではない。このプラグインの方針と食い違う場合はこのプラグインが正であり、devcontainer-features 側を合わせる。

## 参考資料

- [Dev Container Features reference](https://containers.dev/implementors/features/)
- [Best Practices: Authoring a Dev Container Feature](https://containers.dev/guide/feature-authoring-best-practices)
- [Feature Starter](https://github.com/devcontainers/feature-starter)
