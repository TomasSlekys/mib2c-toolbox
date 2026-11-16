#!/bin/sh
# Runs the off-unit tests for mib2cfg.sh in Docker: tests/run.sh [shell], shell = mksh (default), pdksh (the unit's PD KSH 5.2.14) or busybox.
# Needs only Docker. The repo is mounted read only; each case builds its own fake unit and card in /tmp.
set -e
here=$(cd "$(dirname "$0")" && pwd)
repo=$(dirname "$here")
image=mib2cfg-test
# Build every time (cached layers make it quick) so a changed Dockerfile is never skipped.
docker build -q -t $image "$here" >/dev/null 2>&1 || docker build -t $image "$here"
docker run --rm -v "$repo:/repo:ro" -e SH="${1:-mksh}" $image sh /repo/tests/cases.sh
