#!/bin/bash
# Ensures that mytool is installed with the default options as a runnable binary on PATH, at the
# documented path with the documented ownership.
#
# The command strings passed to 'bash -c' are single-quoted because their '$' has to reach the nested
# shell unexpanded, which is what SC2016 warns about and is exactly what is wanted here.
# shellcheck disable=SC2016
set -e

# dev-container-features-test-lib is provided by the devcontainer CLI inside the test container, so
# ShellCheck has nothing to follow here.
# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

check 'mytool is on PATH' bash -c 'command -v mytool'
check 'mytool is installed at /usr/local/bin/mytool' test -x '/usr/local/bin/mytool'
check 'mytool runs' mytool --version
check 'mytool is owned by root, mode 755' bash -c '[ "$(stat -c "%U %G %a" "/usr/local/bin/mytool")" = "root root 755" ]'
reportResults
