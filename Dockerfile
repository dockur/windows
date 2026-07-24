# syntax=docker/dockerfile:1

ARG VERSION_ARG="latest"
FROM scratch AS build-amd64

COPY --from=qemux/qemu:7.39 / /

ARG TARGETARCH
ARG VERSION_WSDD="1.26"
ARG VERSION_VIRTIO="1.9.58"

ARG DEBCONF_NOWARNINGS="yes"
ARG DEBIAN_FRONTEND="noninteractive"
ARG DEBCONF_NONINTERACTIVE_SEEN="true"

RUN <<EOF
  set -eu

  apt-get update
  apt-get --no-install-recommends -y install \
    samba \
    wimtools \
    dos2unix \
    cabextract \
    icu-devtools \
    libxml2-utils \
    libarchive-tools

  # Install wsdd
  wget "https://github.com/gershnik/wsdd-native/releases/download/v${VERSION_WSDD}/wsddn_${VERSION_WSDD}_${TARGETARCH}.deb" -O /tmp/wsddn.deb -q --timeout=10
  dpkg -i /tmp/wsddn.deb

  apt-get clean
  rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOF

COPY --chmod=755 ./src /run/
COPY --chmod=755 ./assets /run/assets

ADD --chmod=664 https://github.com/qemus/virtiso-whql/releases/download/v${VERSION_VIRTIO}-0/virtio-win-${VERSION_VIRTIO}.tar.xz /var/drivers.txz

FROM dockurr/windows-arm:${VERSION_ARG} AS build-arm64
FROM build-${TARGETARCH}

ARG VERSION_ARG="0.00"
RUN echo "$VERSION_ARG" > /etc/version

VOLUME /storage
EXPOSE 3389 8006

ENV VERSION="11"
ENV RAM_SIZE="4G"
ENV CPU_CORES="2"
ENV DISK_SIZE="64G"

ENTRYPOINT ["/usr/bin/tini", "-s", "/run/entry.sh"]
