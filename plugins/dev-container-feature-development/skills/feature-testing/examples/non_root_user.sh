#!/bin/bash
# Ensures that a non-root remote user can find and run mytool without sudo. install.sh runs as root,
# so a binary installed with a restrictive mode or into a directory only on root's PATH would pass
# every test that runs as root and still be unusable in a typical dev container.
#
# The command strings passed to 'bash -c' are single-quoted so that '$' reaches the nested shell
# unexpanded, which is what SC2016 warns about.
# shellcheck disable=SC2016
set -e

# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

check 'the test runs as the non-root remote user' bash -c '[ "$(id -un)" = "vscode" ]'
check 'mytool is on PATH for the remote user' bash -c 'command -v mytool'
check 'mytool runs as the remote user' mytool --version

reportResults
