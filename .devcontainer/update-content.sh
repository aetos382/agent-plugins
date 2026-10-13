#!/usr/bin/env bash
# 開発ツールの導入。
# - devcontainer CLI: `devcontainer features test` で Dev Container Features をテストするのに使う。
# postCreateCommand ではなく updateContentCommand で入れるのは、Codespaces の
# prebuild にこの結果を含めるため。
set -euo pipefail

npm install -g '@devcontainers/cli'
devcontainer --version
