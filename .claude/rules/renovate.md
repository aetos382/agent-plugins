---
paths:
  - renovate.json
  - .github/workflows/**
  - .devcontainer/*.sh
  - .devcontainer/devcontainer.json
---

# Renovate

- Renovate が更新するのは、リポジトリ自身の依存関係（`.github/workflows/` の action、devcontainer のベース イメージ、`.devcontainer/*.sh` のツール）である。`plugins/` 以下の、プラグインがプラグイン利用者のリポジトリに書き出す雛形（`assets/` のワークフローや `devcontainer.json`）は、どの manager のファイル パターンにも一致しないので対象にならない（2026-10-13 にローカルの dry-run で確認）。雛形のバージョンは、プラグインのスキルが決める。
