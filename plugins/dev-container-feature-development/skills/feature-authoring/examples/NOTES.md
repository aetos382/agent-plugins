## How it works

- Downloads `mytool_<version>_linux_<arch>.tar.gz` from the [mytool releases](https://github.com/example-org/mytool/releases), verifies it against the release's `checksums.txt`, and installs the binary to `/usr/local/bin/mytool` (owned by root, mode 755).
- mytool publishes checksums but no signatures, and `checksums.txt` comes from the same release as the archive. The check therefore catches corrupted or truncated downloads, but not a release that was tampered with at the source.
- When `version` names an exact version, the installed binary has to report that version or the install fails.
- Installing the Feature again on the same image, for example on top of a prebuilt image or through another Feature's `dependsOn`, replaces the binary: the version of the later installation is the one left.
- `version: latest` is resolved by following the redirect of the releases/latest page rather than the GitHub API, so builds are not subject to the API's rate limit.

## Requirements

- `curl`, `ca-certificates`, `tar`, `gzip`, and `sha256sum` (coreutils). The missing ones are installed automatically with `apt-get`.

## Limitations

- Debian and Ubuntu only. Tested on Ubuntu 26.04, Ubuntu 24.04, Debian 13, and Debian 12, the distributions CI runs. Other distributions are not supported; on an image without `apt-get`, the Feature fails when it has a dependency to install.
- Linux only. Tested on `amd64` and `arm64`, the architectures CI runs; other architectures are not supported.
- Pin an exact version for reproducible builds; `latest` changes whenever upstream releases.
