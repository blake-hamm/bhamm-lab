# Sops sync (used in forgejo webhook - ci)
#  - syncs on changes to sops file
FROM harbor.bhamm-lab.com/dockerhub/debian:trixie-slim

# Install base dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    wget \
    gpg \
    lsb-release \
    ca-certificates \
    gnupg \
    ssh-client && \
    rm -rf /var/lib/apt/lists/*

# Add HashiCorp repository
RUN wget -O - https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list

# Install remaining packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git \
    curl \
    jq \
    vault && \
    rm -rf /var/lib/apt/lists/*

# Install SOPS
RUN curl -LO https://github.com/getsops/sops/releases/download/v3.10.2/sops-v3.10.2.linux.amd64 && \
    mv sops-v3.10.2.linux.amd64 /usr/local/bin/sops && \
    chmod +x /usr/local/bin/sops

WORKDIR /workspace