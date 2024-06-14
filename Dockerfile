FROM scratch
COPY --from=qemux/qemu-docker:5.16 / /

ARG VERSION_ARG="0.0"
ARG DEBCONF_NOWARNINGS="yes"
ARG DEBIAN_FRONTEND="noninteractive"
ARG DEBCONF_NONINTERACTIVE_SEEN="true"

RUN set -eu && \
    apt-get update && \
    apt-get --no-install-recommends -y install \
        bc \
        curl \
        7zip \
        wsdd \
        samba \
        xz-utils \
        wimtools \
        dos2unix \
        cabextract \
        genisoimage \
        libxml2-utils && \
    apt-get clean && \
    echo "$VERSION_ARG" > /run/version && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --chmod=755 ./src /run/
COPY --chmod=755 ./assets /run/assets

ADD --chmod=755 https://raw.githubusercontent.com/christgau/wsdd/v0.8/src/wsdd.py /usr/sbin/wsdd
ADD --chmod=664 https://github.com/qemus/virtiso/releases/download/v0.1.248/virtio-win-0.1.248.tar.xz /drivers.txz

EXPOSE 8006 3389
VOLUME /storage

ENV RAM_SIZE "4G"
ENV CPU_CORES "2"
ENV DISK_SIZE "64G"
ENV VERSION "win11"

ENTRYPOINT ["/usr/bin/tini", "-s", "/run/entry.sh"]
