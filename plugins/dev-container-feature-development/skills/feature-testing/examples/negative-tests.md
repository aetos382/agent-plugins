# Manual negative tests for `install.sh`

`install.sh` rejects a malformed or nonexistent `version`, an unsupported architecture, and missing dependencies on an image without `apt-get`. None of that can be covered by `devcontainer features test`: the harness treats a failed build as a failed test, so a case that is supposed to fail cannot be expressed. Run the cases below whenever the option validation, version resolution, architecture detection, or dependency handling in `install.sh` changes.

## Setup

```sh
docker run --rm -it -v "$PWD/src/mytool:/mnt/f:ro" debian:12 sh
```

## Case A: a version with characters that could escape the download path

```sh
VERSION='../1.2.3' sh /mnt/f/install.sh; echo "exit status: $?"
```

Expected: exit status 1, before anything is downloaded, and `/usr/local/bin/mytool` does not exist.

```
mytool: invalid version '../1.2.3'; expected something like 1.2.3.
```

## Case B: a version that was never released

Requires an x86_64 host, since the expected message names the architecture.

```sh
VERSION=0.0.0-nonexistent sh /mnt/f/install.sh; echo "exit status: $?"
```

Expected: exit status 1, and `/usr/local/bin/mytool` does not exist.

```
mytool: failed to download mytool_0.0.0-nonexistent_linux_amd64.tar.gz (see curl's message above).
mytool: if that was a 404, version '0.0.0-nonexistent' may not be published for amd64.
```

## Case C: an unsupported architecture

Requires an x86_64 host. `linux32` (from util-linux) makes `uname -m` report `i686`, which exercises the architecture check without emulating another CPU.

```sh
linux32 sh /mnt/f/install.sh; echo "exit status: $?"
```

Expected: exit status 1, before any package is installed or anything is downloaded.

```
mytool: unsupported architecture 'i686'.
```

## Case D: a required tool is missing and apt-get is unavailable

```sh
mv /usr/bin/apt-get /usr/bin/apt-get.disabled
VERSION=latest sh /mnt/f/install.sh; echo "exit status: $?"
```

Expected: exit status 1, and nothing is installed. `debian:12` lacks `curl`, so the message names at least `curl`.

```
mytool: the following are required but missing, and apt-get is unavailable to install them:
mytool: install them in your base image, or use a Debian/Ubuntu-based image.
```
