# syntax=docker/dockerfile:1.6

ARG VERSION_ARG="latest"
ARG TARGETARCH

# === Build for amd64 ===
FROM debian:bookworm-slim AS build-amd64
COPY --from=qemux/qemu:7.2.8 / /usr/bin/

RUN set -eux; \
apt-get update; \
apt-get install -y --no-install-recommends \
samba \
wimtools \
dos2unix \
cabextract \
libxml2-utils \
libarchive-tools \
wget \
ca-certificates; \
wget -qO /tmp/wsddn.deb "https://github.com/gershnik/wsdd-native/releases/download/v1.22/wsddn_1.22_amd64.deb"; \
dpkg -i /tmp/wsddn.deb; \
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --chmod=755 ./src /run/
COPY --chmod=755 ./assets /run/assets
RUN wget -qO /var/drivers.txz \
"https://github.com/qemus/virtiso-whql/releases/download/v1.9.48-0/virtio-win-1.9.48.tar.xz"

# === Build for arm64 ===
FROM dockurr/windows-arm:${VERSION_ARG} AS build-arm64

# === Final image ===
FROM build-${TARGETARCH}

ARG VERSION_ARG="0.00"
RUN echo "$VERSION_ARG" > /run/version

ENV VERSION="11" \
RAM_SIZE="4G" \
CPU_CORES="2" \
DISK_SIZE="64G" \
DEBIAN_FRONTEND="noninteractive"

VOLUME ["/storage"]
EXPOSE 3389 8006

ENTRYPOINT ["/usr/bin/tini", "-s", "/run/entry.sh"]
