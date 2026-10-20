ARG BASE_IMAGE=debian:bookworm-slim
FROM ${BASE_IMAGE}

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        openssh-server zsh bash coreutils procps vim-tiny ca-certificates \
    && rm -rf /var/lib/apt/lists/* /etc/ssh/ssh_host_* \
    && useradd --create-home --uid 1000 --shell /bin/zsh lab \
    && printf 'lab:trail-mobile-lab\n' | chpasswd

COPY --chmod=0755 ssh_entrypoint.sh /usr/local/bin/mobile-prd-sshd
COPY --chmod=0755 trail-fixture /usr/local/bin/trail-fixture
EXPOSE 22
ENTRYPOINT ["/usr/local/bin/mobile-prd-sshd"]
