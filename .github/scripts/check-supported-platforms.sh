#!/usr/bin/env bash
# Checks that the dev-container-feature-development plugin and its development rules (.claude/rules)
# agree with their source of truth, skills/feature-authoring/references/supported-platforms.md.
# Release numbers and image names are checked wherever they appear. Architectures are checked only
# in RUNNERS of the test-feature.yaml template and in "architectures:" lines whose value is in
# single quotes, wherever those appear in the plugin or the rules (such as the example test jobs in
# the test.yaml template and in the feature-testing skill); prose that lists them is not.
# Needs no network access; run on every pull request.
#
# Usage: check-supported-platforms.sh
#
# Exit status: 0 when everything agrees, 1 when differences were found (reported on stdout as a
# Markdown list), 2 on any other error.
#
# Backquotes in single-quoted strings below are Markdown code spans and awk patterns, not command
# substitutions, which is what SC2016 warns about.
# shellcheck disable=SC2016
set -Eeuo pipefail

die() {
  echo "check-supported-platforms.sh: $*" >&2
  exit 2
}

# set -e alone would exit with the failed command's own status, which may be 1 and read as
# "differences found", so any unexpected failure exits 2 instead. -E makes functions and subshells
# inherit this.
trap 'echo "check-supported-platforms.sh: unexpected failure at line ${LINENO}." >&2; exit 2' ERR

# Sets MATCHES to the output of grep with the given arguments. Unlike "|| true", this accepts only
# "no match" (status 1), so an unreadable file or an invalid pattern still fails. The result is
# returned in a variable because a failure inside a process substitution would not stop the script.
grep_matches() {
  local status=0
  MATCHES="$(grep "$@")" || status=$?
  [ "${status}" -le 1 ] || die "grep failed with status ${status}: grep $*"
}

for command in git awk jq; do
  command -v "${command}" >/dev/null 2>&1 || die "'${command}' is required but not installed."
done

[ "$#" -eq 0 ] || die 'usage: check-supported-platforms.sh'
repo_root="$(git rev-parse --show-toplevel)"
plugin_dir="${repo_root}/plugins/dev-container-feature-development"
source_file="${plugin_dir}/skills/feature-authoring/references/supported-platforms.md"
workflow_template="${plugin_dir}/skills/init-repository/assets/workflows/test-feature.yaml"
rules_file="${repo_root}/.claude/rules/dev-container-feature-development.md"
source_display="${source_file#"${repo_root}/"}"

[ -f "${source_file}" ] || die "source of truth not found: ${source_file}"

# --- Source of truth -------------------------------------------------------------------------------

# Rows of the "Current releases" table as "<Distribution> <Release> <Codename> <image>".
source_rows="$(awk -F'|' '
  /^\| (Ubuntu|Debian) \|/ {
    for (i = 2; i <= 5; i++) { gsub(/[ `]/, "", $i) }
    print $2, $3, $4, $5
  }' "${source_file}")"
[ -n "${source_rows}" ] || die "no release rows found in ${source_display}"

# The bullet list under "## Non-root test images", one image per line.
non_root_images="$(awk '
  /^## / { section = ($0 == "## Non-root test images"); next }
  section && /^- `[^`]*`$/ { gsub(/^- `|`$/, ""); print }
' "${source_file}")"
[ -n "${non_root_images}" ] || die "no non-root test images found in ${source_display}"

# The code block under "## CI base images", one image per line.
ci_images="$(awk '
  /^## CI base images/ { section = 1; next }
  section && /^```/ { if (fence) exit; fence = 1; next }
  section && fence && NF { print }
' "${source_file}")"
[ -n "${ci_images}" ] || die "no CI base images found in ${source_display}"

# Rows of the "Architectures" table as "<architecture> <runner>". The `uname -m` column is not
# checked against anything; the uname -m patterns in the install.sh examples are kept in step by hand.
architecture_rows="$(awk -F'|' '
  /^## / { section = ($0 == "## Architectures"); next }
  section && /^\| [a-z0-9_]+ \|/ {
    for (i = 2; i <= 4; i++) { gsub(/[ `]/, "", $i) }
    print $2, $4
  }' "${source_file}")"
[ -n "${architecture_rows}" ] || die "no architecture rows found in ${source_display}"
architectures="$(printf '%s\n' "${architecture_rows}" | awk '{ print $1 }')"

table_images="$(printf '%s\n' "${source_rows}" | awk '{ print $4 }')"
ubuntu_releases="$(printf '%s\n' "${source_rows}" | awk '$1 == "Ubuntu" { print $2 }')"
debian_releases="$(printf '%s\n' "${source_rows}" | awk '$1 == "Debian" { print $2 }')"

# $1: newline-separated list, $2: value. Succeeds when the value is an element of the list.
contains() {
  printf '%s\n' "$1" | grep -qxF -- "$2"
}

# --- consistency ---------------------------------------------------------------------------------

check_consistency() {
  local problems=''
  add_problem() {
    problems="${problems}- $1"$'\n'
  }

  # Each row's image must be derived from its distribution and release.
  while read -r distribution release _codename image; do
    expected="$(printf '%s' "${distribution}" | tr '[:upper:]' '[:lower:]'):${release}"
    if [ "${image}" != "${expected}" ]; then
      add_problem "\`${source_display}\`: the ${distribution} ${release} row names \`${image}\`, expected \`${expected}\`."
    fi
  done <<< "${source_rows}"

  # Each non-root image is a base image variant of a supported Ubuntu release.
  while IFS= read -r image; do
    release="${image##*-ubuntu}"
    case "${image}" in
      mcr.microsoft.com/devcontainers/base:[0-9]*-ubuntu*) ;;
      *) release='' ;;
    esac
    if [ -z "${release}" ] || ! contains "${ubuntu_releases}" "${release}"; then
      add_problem "\`${source_display}\`: the non-root test image \`${image}\` is not a devcontainers/base variant of a supported Ubuntu release."
    fi
  done <<< "${non_root_images}"

  # The CI list is exactly the table's images plus the non-root images.
  expected_ci="$(printf '%s\n%s\n' "${table_images}" "${non_root_images}" | sort)"
  if [ "$(printf '%s\n' "${ci_images}" | sort)" != "${expected_ci}" ]; then
    add_problem "\`${source_display}\`: the CI base images differ from the release table plus the non-root test images."
  fi

  # The workflow template's matrix equals the CI list, in the same order.
  template_images="$(awk '
    /^ *baseImage:/ { section = 1; next }
    section && /^ *- / { sub(/^ *- /, ""); print; next }
    section && /^ *#/ { next }
    section { exit }
  ' "${workflow_template}")"
  if [ "${template_images}" != "${ci_images}" ]; then
    add_problem "\`${workflow_template#"${repo_root}/"}\`: the \`baseImage\` matrix differs from the CI base images in \`${source_display}\`."
  fi

  # The workflow template maps the same architectures to the same runners, in the same order.
  # RUNNERS is a YAML block scalar holding a JSON object: the lines after the key that are blank or
  # indented deeper than it. The object is parsed as JSON rather than matched line by line, so that
  # no way of formatting an entry lets it slip past the comparison.
  local template_display runners_json template_runners
  template_display="${workflow_template#"${repo_root}/"}"
  runners_json="$(awk '
    section && NF && match($0, /^ */) && RLENGTH <= indent { exit }
    section { print; next }
    /^ *RUNNERS: \|$/ { section = 1; match($0, /^ */); indent = RLENGTH }
  ' "${workflow_template}")"
  if template_runners="$(jq -r 'to_entries[] | "\(.key) \(.value)"' <<< "${runners_json}" 2>/dev/null)" &&
    [ -n "${template_runners}" ]; then
    if [ "${template_runners}" != "${architecture_rows}" ]; then
      add_problem "\`${template_display}\`: the runners in \`RUNNERS\` differ from the architectures in \`${source_display}\`."
    fi
  else
    add_problem "\`${template_display}\`: \`RUNNERS\` is missing or is not a JSON object that maps architectures to runners."
  fi

  # Every release number or image named anywhere else must be a supported one.
  local files
  files="$(git -C "${repo_root}" ls-files --cached --others --exclude-standard -- "${plugin_dir}" "${rules_file}")"
  [ -n "${files}" ] || die "no files found under ${plugin_dir}"
  while IFS= read -r file; do
    [ "${file}" != "${source_display}" ] || continue
    path="${repo_root}/${file}"
    [ -f "${path}" ] || continue

    # A here-string of an empty MATCHES yields one empty line, hence the -n checks.
    grep_matches -noE '\b(ubuntu:[0-9]{2}\.[0-9]{2}|debian:[0-9]+)\b' "${path}"
    while IFS=: read -r line match; do
      [ -n "${line}" ] || continue
      contains "${table_images}" "${match}" ||
        add_problem "\`${file}:${line}\`: \`${match}\` is not a supported image."
    done <<< "${MATCHES}"

    grep_matches -noE 'mcr\.microsoft\.com/devcontainers/base:[A-Za-z0-9._-]+' "${path}"
    while IFS=: read -r line match; do
      [ -n "${line}" ] || continue
      contains "${non_root_images}" "${match}" ||
        add_problem "\`${file}:${line}\`: \`${match}\` is not one of the non-root test images."
    done <<< "${MATCHES}"

    grep_matches -noE '\bUbuntu [0-9]{2}\.[0-9]{2}\b' "${path}"
    while IFS=: read -r line match; do
      [ -n "${line}" ] || continue
      contains "${ubuntu_releases}" "${match#Ubuntu }" ||
        add_problem "\`${file}:${line}\`: \`${match}\` is not a supported Ubuntu release."
    done <<< "${MATCHES}"

    grep_matches -noE '\bDebian [0-9]{1,2}\b' "${path}"
    while IFS=: read -r line match; do
      [ -n "${line}" ] || continue
      contains "${debian_releases}" "${match#Debian }" ||
        add_problem "\`${file}:${line}\`: \`${match}\` is not a supported Debian release."
    done <<< "${MATCHES}"

    # The architectures of an example test job, in the workflow template or the skills, are supported
    # ones. Only values in single quotes are checked; among them, one that test-feature.yaml would
    # reject is reported rather than skipped.
    grep_matches -noE "architectures: '[^']*'" "${path}"
    while IFS=: read -r line match; do
      [ -n "${line}" ] || continue
      value="${match#*\'}"
      value="${value%\'}"
      # Slurped, so that an empty value or several JSON values in a row are rejected.
      if ! listed="$(jq -r -s 'if length == 1 and (.[0] | type == "array" and length > 0 and all(type == "string") and length == (unique | length)) then .[0][] else error end' <<< "${value}" 2>/dev/null)"; then
        add_problem "\`${file}:${line}\`: \`${value}\` is not a non-empty JSON array of distinct architectures."
        continue
      fi
      while IFS= read -r arch; do
        [ -n "${arch}" ] || continue
        contains "${architectures}" "${arch}" ||
          add_problem "\`${file}:${line}\`: \`${arch}\` is not a supported architecture."
      done <<< "${listed}"
    done <<< "${MATCHES}"
  done <<< "${files}"

  if [ -n "${problems}" ]; then
    printf '## Supported platforms are inconsistent\n\n%s' "${problems}"
    # exit rather than return: a function returning nonzero would fire the ERR trap.
    exit 1
  fi
  echo "Supported platforms are consistent with ${source_display}."
}

check_consistency
