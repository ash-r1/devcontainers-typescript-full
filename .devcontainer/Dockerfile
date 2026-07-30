# ═══════════════════════════════════════════════════════════
# Stage: base — Core development tools
# ═══════════════════════════════════════════════════════════
FROM mcr.microsoft.com/devcontainers/typescript-node:latest AS base

ENV NPM_CONFIG_PREFIX=/home/node/.npm-global
ENV PATH=/home/node/.npm-global/bin:${PATH}

# System packages: DB clients, redis, utilities
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        default-mysql-client \
        postgresql-client \
        redis-tools \
        curl \
        unzip \
        gnupg \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# AWS CLI v2
RUN ARCH=$(uname -m) \
    && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o /tmp/awscli.zip \
    && unzip -q /tmp/awscli.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscli.zip /tmp/aws

# dasel — TOML parser for entrypoint config
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL "https://github.com/TomWright/dasel/releases/latest/download/dasel_linux_${ARCH}" -o /usr/local/bin/dasel \
    && chmod +x /usr/local/bin/dasel

# Writable global npm prefix for self-updating CLIs
RUN mkdir -p /home/node/.npm-global \
    && chown -R node:node /home/node/.npm-global

# Socket directories for DB connections
RUN mkdir -p /var/run/mysqld /var/run/postgresql \
    && chmod 777 /var/run/mysqld /var/run/postgresql

# Entrypoint script
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]

# ═══════════════════════════════════════════════════════════
# Stage: full — Base + media processing tools
# ═══════════════════════════════════════════════════════════
FROM base AS full

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ffmpeg \
        imagemagick \
    && rm -rf /var/lib/apt/lists/*
