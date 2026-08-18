# syntax=docker/dockerfile:1

ARG VERSION_ARG="latest"
FROM scratch AS build-amd64

COPY --from=qemux/qemu:7.47 / /

ARG TARGETARCH

ARG VERSION_UDF="1.2.0"
ARG VERSION_WSDD="1.26"
ARG VERSION_VIRTIO="1.9.60"
ARG VERSION_BLINTER="1.0.112"

ARG DEBCONF_NOWARNINGS="yes"
ARG DEBIAN_FRONTEND="noninteractive"
ARG DEBCONF_NONINTERACTIVE_SEEN="true"

RUN <<EOF
  set -eu

  apt-get update
  apt-get --no-install-recommends -y install \
    gcab \
    samba \
    mtools \
    wimtools \
    dos2unix \
    cabextract \
    xmlstarlet \
    icu-devtools \
    libxml2-utils \
    libarchive-tools

  # Install Blinter
  python3 -m pip install --break-system-packages --root-user-action=ignore --no-cache-dir "Blinter==${VERSION_BLINTER}"

  # Install wsddn package
  wget "https://github.com/gershnik/wsdd-native/releases/download/v${VERSION_WSDD}/wsddn_${VERSION_WSDD}_${TARGETARCH}.deb" -O /tmp/wsddn.deb -q --timeout=10
  dpkg -i /tmp/wsddn.deb

  # Install UDFread package
  wget "https://github.com/qemus/udfread/releases/download/v${VERSION_UDF}/udfread_${VERSION_UDF}_${TARGETARCH}.deb" -O /tmp/udfread.deb -q --timeout=10
  dpkg -i /tmp/udfread.deb

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
