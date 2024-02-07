FROM scratch
COPY --from=qemux/qemu-docker:latest / /

ARG DEBCONF_NOWARNINGS="yes"
ARG DEBIAN_FRONTEND "noninteractive"
ARG DEBCONF_NONINTERACTIVE_SEEN "true"

RUN apt-get update \
    && apt-get --no-install-recommends -y install \
        curl \
        7zip \
        wsdd \
        samba \
        wimtools \
        dos2unix \
        cabextract \
        genisoimage \
        libxml2-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY ./src /run/
COPY ./assets /run/assets
ADD https://github.com/qemus/virtiso/releases/download/v0.1.240/virtio-win-0.1.240.iso /run/drivers.iso
RUN chmod +x /run/*.sh

EXPOSE 8006 3389
VOLUME /storage

ENV RAM_SIZE "4G"
ENV CPU_CORES "2"
ENV DISK_SIZE "64G"
ENV VERSION "win11"

ARG VERSION_ARG "0.0"
RUN echo "$VERSION_ARG" > /run/version

ENTRYPOINT ["/usr/bin/tini", "-s", "/run/entry.sh"]
