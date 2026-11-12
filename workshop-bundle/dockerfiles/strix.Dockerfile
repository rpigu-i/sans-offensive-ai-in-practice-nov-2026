# syntax=docker/dockerfile:1
#
# Workshop image for Strix (https://github.com/usestrix/strix), the optional
# 5th tool.
#
# Strix is two parts:
#   1. The `strix` CLI / agent controller (this image). Upstream publishes it to
#      PyPI as `strix-agent`, with per-platform wheels (linux amd64 + arm64) that
#      already bundle the compiled Go TUI and the prebuilt web dashboard, so we
#      install the pinned wheel instead of building from source.
#   2. The sandbox image (ghcr.io/usestrix/strix-sandbox), where the agents
#      actually run their tools (Caido proxy, browser, nmap, ...). The CLI
#      starts it on demand through the Docker socket that docker-compose.yml
#      mounts into this container, and joins it to the `strix-net` network so it
#      can reach Juice Shop. The tag is pinned by STRIX_IMAGE in
#      docker-compose.yml.
#
# docker compose builds this with context ./dockerfiles (see the `strix`
# service). Bump STRIX_VERSION, and STRIX_IMAGE in docker-compose.yml to the
# sandbox tag that release defaults to, to move to a newer Strix.

FROM python:3.12-slim-bookworm

ARG STRIX_VERSION=1.7.0

# git: Strix clones repository targets (e.g. https://github.com/org/repo).
# docker-cli: Strix shells out to the `docker` CLI to start its sandbox
#   container through the mounted socket, so the binary must be in PATH (the
#   socket alone is not enough).
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates curl gnupg \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg \
        -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli \
    && apt-get purge -y gnupg \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir "strix-agent==${STRIX_VERSION}" \
    && strix --version

# Runs live in ./strix_runs relative to the working directory, which
# docker-compose.yml bind-mounts to ./out/strix on the host.
WORKDIR /work

ENTRYPOINT ["strix"]
CMD ["--help"]
