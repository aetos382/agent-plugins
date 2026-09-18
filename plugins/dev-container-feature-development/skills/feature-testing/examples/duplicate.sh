#!/bin/bash
# Ensures that installing mytool twice, once with default options and once with other values, still
# leaves a single working binary, so that the Feature can be pulled in both directly and through
# another Feature's dependsOn.
#
# The CLI exposes the second installation's options as VERSION and the defaults as VERSION__DEFAULT.
#
# shellcheck disable=SC2016
set -e

# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

check 'both option sets were passed in' bash -c '[ -n "${VERSION}" ] && [ -n "${VERSION__DEFAULT}" ]'
check 'mytool runs after the second installation' mytool --version
check 'exactly one mytool is on PATH' bash -c '[ "$(type -ap mytool | wc -l)" -eq 1 ]'

reportResults
