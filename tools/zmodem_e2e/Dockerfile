ARG SOURCE_DATE_EPOCH=1785542400

FROM ubuntu:24.04@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea

ARG SOURCE_DATE_EPOCH

# snapshot.ubuntu.com redirects the HTTP bootstrap URI to HTTPS, while the
# pinned base has no CA bundle yet. APT signatures and hashes still
# authenticate the pinned archive until ca-certificates is installed.
RUN printf '%s\n' \
        'Types: deb' \
        'URIs: http://snapshot.ubuntu.com/ubuntu/20260801T000000Z/' \
        'Suites: noble noble-updates noble-security' \
        'Components: main universe' \
        'Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg' \
        > /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get -o Acquire::https::Verify-Peer=false update \
    && DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::https::Verify-Peer=false install --yes --no-install-recommends \
        ca-certificates=20260601~24.04.1 \
        lrzsz=0.12.21-11build1 \
        openssh-server=1:9.6p1-3ubuntu13.18 \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/ssh/ssh_host_* /var/cache/ldconfig/aux-cache /var/log/dpkg.log /var/log/apt/* \
    && mkdir -p /run/sshd /root/.ssh \
    && chmod 0700 /root/.ssh \
    && printf '%s\n' 'snapshot=20260801T000000Z;lrzsz=0.12.21-11build1;openssh-server=1:9.6p1-3ubuntu13.18' > /etc/ianvs-zmodem-e2e-fixture \
    && printf '%s\n' \
        'PermitRootLogin prohibit-password' \
        'PasswordAuthentication no' \
        'KbdInteractiveAuthentication no' \
        'PubkeyAuthentication yes' \
        'UsePAM no' \
        > /etc/ssh/sshd_config.d/ianvs-zmodem.conf \
    && find /etc /root /run /usr /var \
        ! -path /etc/hosts \
        ! -path /etc/hostname \
        ! -path /etc/resolv.conf \
        -newermt "@${SOURCE_DATE_EPOCH}" \
        -exec touch -h -d "@${SOURCE_DATE_EPOCH}" {} +

CMD ["/bin/sh", "-c", "ssh-keygen -A >/dev/null 2>&1 && exec /usr/sbin/sshd -D -e"]
