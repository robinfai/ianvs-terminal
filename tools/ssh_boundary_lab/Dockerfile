# Reuse the repository's pinned Ubuntu/OpenSSH acceptance image.
# Build it with tools/ssh_e2e/run.sh first if it is not cached locally.
ARG BASE_IMAGE=ianvs-ssh-e2e:20260808
FROM ${BASE_IMAGE}
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      zsh fish tmux strace python3 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -s /bin/bash lab \
    && passwd -d lab \
    && mkdir -p /home/lab/.ssh /run/sshd /fixture \
    && chmod 700 /home/lab/.ssh
COPY entrypoint.sh /usr/local/bin/ianvs-boundary-entrypoint
ENTRYPOINT ["/bin/bash", "/usr/local/bin/ianvs-boundary-entrypoint"]
