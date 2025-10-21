# syntax=docker/dockerfile:1

ARG VERSION_ARG="latest"
FROM scratch AS build-amd64

COPY --from=qemux/qemu:7.27 / /

ARG TARGETARCH
ARG DEBCONF_NOWARNINGS="yes"
ARG DEBIAN_FRONTEND="noninteractive"
ARG DEBCONF_NONINTERACTIVE_SEEN="true"

RUN set -eu && \
    apt-get update && \
    apt-get --no-install-recommends -y install \
        samba \
        wimtools \
        dos2unix \
        cabextract \
        libxml2-utils \
        libarchive-tools && \
    wget "https://github.com/gershnik/wsdd-native/releases/download/v1.22/wsddn_1.22_${TARGETARCH}.deb" -O /tmp/wsddn.deb -q && \
    dpkg -i /tmp/wsddn.deb && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --chmod=755 ./src /run/
COPY --chmod=755 ./assets /run/assets

ADD --chmod=664 https://github.com/qemus/virtiso-whql/releases/download/v1.9.48-0/virtio-win-1.9.48.tar.xz /var/drivers.txz

FROM dockurr/windows-arm:${VERSION_ARG} AS build-arm64
FROM build-${TARGETARCH}

ARG VERSION_ARG="0.00"
RUN echo "$VERSION_ARG" > /run/version

VOLUME /storage
EXPOSE 3389 8006

ENV VERSION="11"
ENV RAM_SIZE="4G"
ENV CPU_CORES="2"
ENV DISK_SIZE="64G"

ENTRYPOINT ["/usr/bin/tini", "-s", "/run/entry.sh"]
