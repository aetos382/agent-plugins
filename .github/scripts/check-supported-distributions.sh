#!/usr/bin/env bash
# Checks that every release number and image name in the dev-container-feature-development plugin
# agrees with its source of truth, skills/feature-authoring/references/supported-distributions.md.
# Needs no network access; run on every pull request.
#
# Usage: check-supported-distributions.sh
#
# Exit status: 0 when everything agrees, 1 when differences were found (reported on stdout as a
# Markdown list), 2 on any other error.
#
# Backquotes in single-quoted strings below are Markdown code spans and awk patterns, not command
# substitutions, which is what SC2016 warns about.
# shellcheck disable=SC2016
set -Eeuo pipefail

die() {
  echo "check-supported-distributions.sh: $*" >&2
  exit 2
}

# set -e alone would exit with the failed command's own status, which may be 1 and read as
# "differences found", so any unexpected failure exits 2 instead. -E makes functions and subshells
# inherit this.
trap 'echo "check-supported-distributions.sh: unexpected failure at line ${LINENO}." >&2; exit 2' ERR

for command in git awk; do
  command -v "${command}" >/dev/null 2>&1 || die "'${command}' is required but not installed."
done

[ "$#" -eq 0 ] || die 'usage: check-supported-distributions.sh'
repo_root="$(git rev-parse --show-toplevel)"
plugin_dir="${repo_root}/plugins/dev-container-feature-development"
source_file="${plugin_dir}/skills/feature-authoring/references/supported-distributions.md"
workflow_template="${plugin_dir}/skills/init-repository/assets/workflows/test.yaml"
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

  # Every release number or image named anywhere else must be a supported one.
  local files
  files="$(git -C "${repo_root}" ls-files --cached --others --exclude-standard -- "${plugin_dir}" "${rules_file}")"
  [ -n "${files}" ] || die "no files found under ${plugin_dir}"
  while IFS= read -r file; do
    [ "${file}" != "${source_display}" ] || continue
    path="${repo_root}/${file}"
    [ -f "${path}" ] || continue

    while IFS=: read -r line match; do
      contains "${table_images}" "${match}" ||
        add_problem "\`${file}:${line}\`: \`${match}\` is not a supported image."
    done < <(grep -noE '\b(ubuntu:[0-9]{2}\.[0-9]{2}|debian:[0-9]+)\b' "${path}" || true)

    while IFS=: read -r line match; do
      contains "${non_root_images}" "${match}" ||
        add_problem "\`${file}:${line}\`: \`${match}\` is not one of the non-root test images."
    done < <(grep -noE 'mcr\.microsoft\.com/devcontainers/base:[A-Za-z0-9._-]+' "${path}" || true)

    while IFS=: read -r line match; do
      contains "${ubuntu_releases}" "${match#Ubuntu }" ||
        add_problem "\`${file}:${line}\`: \`${match}\` is not a supported Ubuntu release."
    done < <(grep -noE '\bUbuntu [0-9]{2}\.[0-9]{2}\b' "${path}" || true)

    while IFS=: read -r line match; do
      contains "${debian_releases}" "${match#Debian }" ||
        add_problem "\`${file}:${line}\`: \`${match}\` is not a supported Debian release."
    done < <(grep -noE '\bDebian [0-9]{1,2}\b' "${path}" || true)
  done <<< "${files}"

  if [ -n "${problems}" ]; then
    printf '## Supported distributions are inconsistent\n\n%s' "${problems}"
    # exit rather than return: a function returning nonzero would fire the ERR trap.
    exit 1
  fi
  echo "Supported distributions are consistent with ${source_display}."
}

check_consistency
