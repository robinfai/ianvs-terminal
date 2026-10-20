# Small fixture for rollback acceptance; no credentials are baked into the image.
ARG BASE_IMAGE=php:8.2-cli
FROM ${BASE_IMAGE}
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server openssh-client zsh fish strace \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -s /bin/bash lab && passwd -d lab \
    && mkdir -p /home/lab/.ssh /run/sshd /fixture && chmod 700 /home/lab/.ssh
COPY entrypoint.sh /usr/local/bin/entrypoint
ENTRYPOINT ["/bin/bash", "/usr/local/bin/entrypoint"]
