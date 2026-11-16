#!/bin/sh
# Runs the off-unit tests for mib2cfg.sh in Docker: tests/run.sh [shell], shell = mksh (default) or busybox.
# Needs only Docker. The repo is mounted read only; each case builds its own fake unit and card in /tmp.
set -e
here=$(cd "$(dirname "$0")" && pwd)
repo=$(dirname "$here")
image=mib2cfg-test
if ! docker image inspect $image >/dev/null 2>&1; then
	docker build -q -t $image "$here" >/dev/null
fi
docker run --rm -v "$repo:/repo:ro" -e SH="${1:-mksh}" $image sh /repo/tests/cases.sh
