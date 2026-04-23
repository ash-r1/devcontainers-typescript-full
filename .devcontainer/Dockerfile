# ═══════════════════════════════════════════════════════════
# Stage: base — Core development tools
# ═══════════════════════════════════════════════════════════
FROM mcr.microsoft.com/devcontainers/typescript-node:latest AS base

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

# Claude Code — native installer (latest). Binary goes to ~/.local/bin/claude.
# Codex CLI — latest via npm.
# Pre-create ~/.claude and ~/.codex so named volume mounts inherit node ownership,
# and symlink ~/.claude.json into ~/.claude/ so that file is persisted too.
RUN su node -c "curl -fsSL https://claude.ai/install.sh | bash" \
    && test -x /home/node/.local/bin/claude \
    && su node -c "npm install -g @openai/codex@latest" \
    && su node -c "npm cache clean --force" \
    && su node -c "mkdir -p /home/node/.claude /home/node/.codex" \
    && su node -c "touch /home/node/.claude/_claude.json" \
    && su node -c "ln -sf /home/node/.claude/_claude.json /home/node/.claude.json"

# Ensure the native claude binary is on PATH for login and non-login shells.
ENV PATH=/home/node/.local/bin:$PATH

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
