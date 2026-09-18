#!/usr/bin/env bash
# ShellCheck の導入。eng/*.sh 等の静的解析に使う。
# postCreateCommand ではなく updateContentCommand で入れるのは、Codespaces の
# prebuild にこの結果を含めるため。
set -euo pipefail

bash "$(dirname "$0")/install-shellcheck.sh"
