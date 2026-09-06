FROM ubuntu:26.04 AS base

WORKDIR /ansible-workspace

FROM base AS builder

ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
# Only use the managed Python version
ENV UV_PYTHON_PREFERENCE=only-managed

# Cache for binary python
ENV UV_PYTHON_CACHE_DIR=/opt/uv-cache/python
# Cache for python library
ENV UV_CACHE_DIR=/opt/uv-cache/packages

# Configure the Python directory so it is consistent
ENV UV_PYTHON_INSTALL_DIR=/opt/python

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && apt-get install --no-install-recommends -y git ca-certificates build-essential \
    && update-ca-certificates

RUN --mount=from=ghcr.io/astral-sh/uv:latest,source=/uv,target=/bin/uv \
    --mount=type=cache,target=/opt/uv-cache/python \
    --mount=type=cache,target=/opt/uv-cache/packages \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=.python-version,target=.python-version \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --no-install-project --no-dev

FROM base AS finish

ENV LANG=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1

ENV PATH="/ansible-workspace/.venv/bin:$PATH"

WORKDIR /ansible-workspace

# hadolint ignore=DL3008
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update -q \
    && apt-get install -yq --no-install-recommends \
    vim \
    git \
    openssh-client \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/log/* \
    && update-ca-certificates

COPY --from=builder --chown=$USER:$USER --chmod=500 /opt/python /opt/python
COPY --from=builder --chown=$USER:$USER --chmod=500 /ansible-workspace/.venv ./.venv

RUN --mount=type=bind,source=requirements.yml,target=requirements.yml \
    ansible-galaxy install -r requirements.yml

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY playbook/* .
COPY roles roles

#RUN OS_ARCHITECTURE=$(dpkg --print-architecture) \
#    && curl -L "https://dl.k8s.io/release/v1.36.4/bin/linux/${OS_ARCHITECTURE}/kubectl" -o /usr/local/bin/kubectl \
#    && echo "$(curl -L "https://dl.k8s.io/release/v1.36.4/bin/linux/${OS_ARCHITECTURE}/kubectl.sha256")" /usr/local/bin/kubectl | sha256sum --check \
#    && chmod a+x /usr/local/bin/kubectl

