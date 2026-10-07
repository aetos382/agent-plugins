#!/bin/bash
# Ensures that installing mytool twice on one image still leaves a single working binary, so that
# the Feature can be pulled in both directly and through another Feature's dependsOn.
#
# The CLI installs first with the option values it picks (VERSION, the first value of 'proposals'
# other than the default) and last with the defaults (VERSION__DEFAULT). mytool's binary follows the
# later run, so the binary left behind is the one the defaults install. That is not asserted here:
# the default is 'latest', which may resolve to the very version the first installation pinned, so
# the two results cannot be told apart. A Feature whose defaults give a fixed result asserts it.
#
# The command strings passed to 'bash -c' are single-quoted so that '$' reaches the nested shell
# unexpanded, which is what SC2016 warns about.
# shellcheck disable=SC2016
set -e

# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

# Guards the premise of this test: when the CLI finds no value other than the default to pick, both
# installations are the same and it runs install.sh only once, so everything below would pass
# without a second run having happened.
check 'the two installations used different options' bash -c '[ -n "${VERSION}" ] && [ "${VERSION}" != "${VERSION__DEFAULT}" ]'
check 'mytool runs after the second installation' mytool --version
check 'exactly one mytool is on PATH' bash -c 'set -o pipefail; [ "$(type -ap mytool | wc -l)" -eq 1 ]'

reportResults
