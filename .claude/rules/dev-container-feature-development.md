---
paths:
  - 'plugins/dev-container-feature-development/**'
---
# dev-container-feature-development

Dev Container Features 開発用のエージェント プラグイン。

## 利用の前提

- このプラグインで作る Feature リポジトリは、AI エージェントだけが編集すると想定する。スクリプトは想定した文脈（CI のワークフローや、スキルからの呼び出し）でのみ実行され、単体で手動実行されることはないと想定する。
- エージェントの誤りは、スキルとエージェント（`feature-reviewer` など）の指示で防ぐ。レビューでは、エージェントが指示に従えば正しく作業できるかを基準にし、人が手で編集した場合や手動で実行した場合の問題は扱わない。
- ワークフロー雛形のスクリプト（`targets` ジョブや `tests-passed` の判定など）の実行時の振る舞いを検査する CI ハーネスは設けない。壊れ方は無数に考えられ、一部だけを検査しても守れないため。

## 対象 Linux ディストリビューション

Feature 実行環境となる Dev Container の OS について。

- Ubuntu の最新および 1 つ前の LTS リリースと、Debian の stable および oldstable は必ずサポートする。非 root ユーザーでのテストには、サポート対象の各 Ubuntu LTS について、`mcr.microsoft.com/devcontainers/base` のその版の variant を持つ最新メジャー バージョンを使う。
  - `devcontainers/base` の Ubuntu 版と Debian 版は別々のイメージ定義からビルドされ、バージョン番号も別々に付く。メジャー バージョンは片方の系列にしか当てはまらない（例：`3` は Ubuntu 版のメジャー バージョンで、Debian の variant はない）。
- その他の Linux ディストリビューションについては、パッケージ マネージャーの分岐を足す程度で済む場合のみサポートする。
- 目的が一部のディストリビューションでしか意味を持たない Feature（Ubuntu の apt ソースを書き換えるものなど）は、他のディストリビューションで働かなくてよい。既定のオプションでは何もせず、対象外のディストリビューションでオプションを有効にしたら失敗させる。ベース イメージは `devcontainer.json` で決まり、誰がビルドしても同じ結果になるので、止めてよい。
- 具体的なリリース、イメージ名、アーキテクチャは `plugins/dev-container-feature-development/skills/feature-authoring/references/supported-platforms.md` を正本とする。プラグイン内でリリース番号、イメージ名、アーキテクチャを書く箇所は、正本と一致させる。
  - 一致しているかは `bash .github/scripts/check-supported-platforms.sh` で検査する（CI の validate ワークフローでも実行される）。
    - リリース番号とイメージ名は、プラグイン内のどこに書いても検査される。
    - アーキテクチャは、ワークフロー雛形 `test-feature.yaml` の `RUNNERS` と、値を単一引用符で囲んだ `architectures:` の行（`test.yaml` 雛形のコメントやスキル中のテスト ジョブの例）だけが検査される。本文中の列挙（「amd64 と arm64」など）は検査されないので、正本を変えたら手で合わせる。
    - CI ランナー名は正本と `RUNNERS` 以外に書かない。
  - 上流の新しいリリース（Ubuntu LTS、Debian stable、`devcontainers/base` の新しいイメージやメジャー バージョン、GitHub ホステッド ランナーの新しい Ubuntu 版）は自動では検出しない。気づいたら `/update-supported-distributions` スキルで更新する。

## 対象アーキテクチャ

- amd64 と arm64 をサポートし、CI でそれぞれのネイティブ ランナーでテストする。CI でテストできないアーキテクチャはサポートしない。
- 各 Feature は対象アーキテクチャを、テスト ワークフロー `test.yaml` の `test-<id>` ジョブの `architectures` に明示する。再利用可能ワークフロー `test-feature.yaml` の `architectures` 入力は必須とし、既定値は設けない。正本にアーキテクチャを足したときに、upstream にビルドがない Feature まで黙ってテスト対象に広がるのを防ぐため。
- テスト ワークフローは Feature ごとのジョブを YAML に書き並べる。`src/` から Feature を列挙して matrix に展開する方式は採らない。matrix には 1 つあたり 256 ジョブの上限があり、Feature 数 × アーキテクチャ数 × baseImage 数ですぐに達するため。ジョブや `tests-passed` の `needs` の書き漏れは CI では検出せず、`feature-reviewer` エージェントで検出する（「利用の前提」を参照）。
- upstream がビルドを公開していないアーキテクチャに限り、Feature の対象から外してよい。そのアーキテクチャでは失敗させる。何もせずに成功させると、ツールが入っていないコンテナーができ、利用者は後からコマンドが無いことで気づくためである。
- Feature のすることがそのアーキテクチャでは意味を持たない場合（書き換える対象が無いなど）は、失敗させずに、警告を出して何もしない。同じ `devcontainer.json` を複数のアーキテクチャでビルドするので、失敗させると片方の利用者だけがビルドできなくなるためである。この経路も CI でテストする。
  - 2 つの場合は、何もしなくても利用者が期待する状態と変わらないかどうかで見分ける。
- 「テストされている」とは CI でテストされていることを指す。開発者の手元でのテストは、そのマシンのアーキテクチャしか確認できないので、根拠にしない。

## 開発方針

Feature に含まれるスクリプトの書き方について。

- 依存パッケージのインストールには `apt-get` を使用してよい。`apt-get` がないディストリビューションで使用する場合は、ユーザーがあらかじめ依存パッケージをインストールしておく必要がある。
  - `apt-get` がない環境で、必須依存関係がインストールされていない場合は、エラーメッセージを出して、終了コード 1 で終了する。
- Feature が必要とする依存関係は `src/<feature>/NOTES.md` に明記する。
- テストは必須サポート対象のディストリビューションで行う。その他のディストリビューションではテストしていないことを `src/<feature>/NOTES.md` に明記する。
- [nanolayer](https://github.com/devcontainers-extra/nanolayer) は使わない。
- Feature が同じイメージで 2 回実行されることは、起こるものとして扱う。事前ビルドしたイメージに同じ Feature を書いた場合と、`dependsOn` で取り込まれたものと利用者が書いたものとでオプションや版が違う場合に、実際に 2 回実行される（devcontainer CLI 0.89.0 で確認）。
  - 2 回目の結果は、Feature が何を触るかで決める。自分で作る設定やファイルは後勝ち、一覧への追加は積み上げ、オプションから再現できないものは残す、とする。
  - すでにある設定をその場で書き換える Feature は、期待した入力が無ければ、警告を出して何もしない。原因が以前の自分の実行か、別の手段での設定かは見分けさせない。どちらでも利用者に見えるのは警告で、見分けるには以前の実行を記録する仕組みが要るためである。
  - 指定したオプションが効かないのに、何も言わずに成功することだけは認めない。
  - `dependsOn` の経路では、どちらが後に実行されるかを Feature も利用者も決められない。これは Feature の側では直せないので、規則の対象にしない。

## 参考実装

- `aetos382/devcontainer-features` は初期のサンプルとして参照してよいが、規範ではない。このプラグインの方針と食い違う場合はこのプラグインが正であり、devcontainer-features 側を合わせる。

## 参考資料

- [Dev Container Features reference](https://containers.dev/implementors/features/)
- [Best Practices: Authoring a Dev Container Feature](https://containers.dev/guide/feature-authoring-best-practices)
- [Feature Starter](https://github.com/devcontainers/feature-starter)
