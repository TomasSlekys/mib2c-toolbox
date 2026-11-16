# Test image for mib2cfg.sh: mksh (a pdksh descendant, close to the unit's PD KSH 5.2.14) and busybox sh.
FROM debian:bookworm-slim
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends mksh busybox >/dev/null \
	&& rm -rf /var/lib/apt/lists/* && useradd -m tester
USER tester
