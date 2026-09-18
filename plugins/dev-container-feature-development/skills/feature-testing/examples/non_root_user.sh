#!/bin/bash
# Ensures that a non-root remote user can find and run mytool without sudo. install.sh runs as root,
# so a binary installed with a restrictive mode or into a directory only on root's PATH would pass
# every test that runs as root and still be unusable in a typical dev container.
#
# shellcheck disable=SC2016
set -e

# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

check 'the test runs as the non-root remote user' bash -c '[ "$(id -un)" = "vscode" ]'
check 'mytool is on PATH for the remote user' bash -c 'command -v mytool'
check 'mytool runs as the remote user' mytool --version

reportResults
