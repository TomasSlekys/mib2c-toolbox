# Test image for mib2cfg.sh: pdksh 5.2.14 (the unit's own shell, PD KSH v5.2.14), mksh (a pdksh descendant) and
# busybox sh. pdksh comes from Debian's archive, pinned by URL and sha256.
FROM debian:bookworm-slim
ARG PDKSH_URL=https://snapshot.debian.org/archive/debian/20120101T000000Z/pool/main/p/pdksh/pdksh_5.2.14-25_amd64.deb
ARG PDKSH_SHA256=0145ed739e9b0951f58edfe98807986c2efecece6ef44359b61b643836a74578
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends mksh busybox curl ca-certificates >/dev/null \
	&& curl -sfL -o /tmp/pdksh.deb "$PDKSH_URL" \
	&& echo "$PDKSH_SHA256  /tmp/pdksh.deb" | sha256sum -c - >/dev/null \
	&& dpkg-deb -x /tmp/pdksh.deb /tmp/pdksh && install -m 755 /tmp/pdksh/bin/pdksh /usr/local/bin/pdksh \
	&& rm -rf /tmp/pdksh /tmp/pdksh.deb \
	&& apt-get purge -y -qq --auto-remove curl ca-certificates >/dev/null \
	&& rm -rf /var/lib/apt/lists/* && useradd -m tester
USER tester
