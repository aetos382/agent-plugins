#!/usr/bin/env bash
# 開発ツールの導入。
# - devcontainer CLI: `devcontainer features test` で Dev Container Features をテストするのに使う。
# - Renovate: pre-commit hook で renovate.json を renovate-config-validator で検証するのに使う。
# postCreateCommand ではなく updateContentCommand で入れるのは、Codespaces の
# prebuild にこの結果を含めるため。
set -euo pipefail

# renovate: datasource=npm depName=renovate
RENOVATE_VERSION='44.149.1'

npm install -g '@devcontainers/cli'
devcontainer --version

npm install -g "renovate@${RENOVATE_VERSION}"
renovate --version
