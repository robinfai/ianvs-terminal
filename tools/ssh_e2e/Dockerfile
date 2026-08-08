ARG SOURCE_DATE_EPOCH=1785542400

FROM ubuntu:24.04@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea AS pam-builder

RUN printf '%s\n' \
        'Types: deb' \
        'URIs: http://snapshot.ubuntu.com/ubuntu/20260801T000000Z/' \
        'Suites: noble noble-updates noble-security' \
        'Components: main universe' \
        'Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg' \
        > /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get -o Acquire::https::Verify-Peer=false update \
    && DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::https::Verify-Peer=false install --yes --no-install-recommends \
        gcc=4:13.2.0-7ubuntu1 \
        libc6-dev=2.39-0ubuntu8.8 \
        libpam0g-dev=1.5.3-5ubuntu5.6

COPY pam_ianvs_otp.c /src/pam_ianvs_otp.c

RUN gcc -std=c17 -Wall -Wextra -Werror -fPIC -shared \
        -Wl,-z,relro,-z,now \
        -o /pam_ianvs_otp.so /src/pam_ianvs_otp.c -lpam

FROM ubuntu:24.04@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea

ARG SOURCE_DATE_EPOCH

# Use the same immutable Ubuntu snapshot and OpenSSH package version as the
# existing ZMODEM fixture. Host and client keys are generated outside the image
# so the checked fixture contains no reusable credentials.
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
        openssh-server=1:9.6p1-3ubuntu13.18 \
        socat=1.8.0.0-4ubuntu0.1 \
        xauth=1:1.1.2-1build1 \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/ssh/ssh_host_* /var/cache/ldconfig/aux-cache /var/log/dpkg.log /var/log/apt/* \
    && mkdir -p /run/sshd /fixture \
    && find /etc /run /usr /var \
        ! -path /etc/hosts \
        ! -path /etc/hostname \
        ! -path /etc/resolv.conf \
        -newermt "@${SOURCE_DATE_EPOCH}" \
        -exec touch -h -d "@${SOURCE_DATE_EPOCH}" {} +

COPY --chmod=0755 entrypoint.sh /usr/local/bin/ianvs-ssh-e2e-entrypoint
COPY --from=pam-builder /pam_ianvs_otp.so /usr/lib/security/pam_ianvs_otp.so

EXPOSE 22

ENTRYPOINT ["/usr/local/bin/ianvs-ssh-e2e-entrypoint"]
