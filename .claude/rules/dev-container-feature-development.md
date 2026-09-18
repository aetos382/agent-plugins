---
paths:
  - 'plugins/dev-container-feature-development/**'
---
# dev-container-feature-development

Dev Container Features 開発用のエージェント プラグイン。

## 対象 Linux ディストリビューション

Feature 実行環境となる Dev Container の OS について。

- Ubuntu および Debian の最新および 1 バージョン前の LTS リリースは必ずサポートする。
  - 2026-09-18 現在、以下のリリースがサポート対象である。このリストは適宜書き換えること。
    - Ubuntu 26.04 LTS (Resolute)
    - Ubuntu 24.04 LTS (Noble)
    - Debian 13 (Trixie)
    - Debian 12 (Bookworm)
- その他の Linux ディストリビューションについては、パッケージ マネージャーの分岐を足す程度で済む場合のみサポートする。

## 開発方針

Feature に含まれるスクリプトについて。

- 依存パッケージのインストールには `apt-get` を使用してよい。`apt-get` がないディストリビューションで使用する場合は、ユーザーがあらかじめ依存パッケージをインストールしておく必要がある。
  - `apt-get` がない環境で、必須依存関係がインストールされていない場合は、エラーメッセージを出して、終了コード 1 で終了する。
- Feature が必要とする依存関係は `src/<feature>/NOTES.md` に明記する。
- テストは必須サポート対象のディストリビューションで行う。その他のディストリビューションではテストしていないことを `src/<feature>/NOTES.md` に明記する。
- [nanolayer](https://github.com/devcontainers-extra/nanolayer) は使わない。

## 参考資料

- [Dev Container Features reference](https://containers.dev/implementors/features/)
- [Best Practices: Authoring a Dev Container Feature](https://containers.dev/guide/feature-authoring-best-practices)
- [Feature Starter](https://github.com/devcontainers/feature-starter)
