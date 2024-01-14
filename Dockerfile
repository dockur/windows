FROM qemux/qemu-docker:latest

ARG DEBCONF_NOWARNINGS="yes"
ARG DEBIAN_FRONTEND "noninteractive"
ARG DEBCONF_NONINTERACTIVE_SEEN "true"

RUN apt-get update \
    && apt-get --no-install-recommends -y install \
        curl \
        novnc \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY ./src /run/
RUN chmod +x /run/*.sh

EXPOSE 8006
VOLUME /storage

ENV CPU_CORES "1"
ENV RAM_SIZE "4G"
ENV DISK_SIZE "64G"

ARG VERSION_ARG "0.0"
RUN echo "$VERSION_ARG" > /run/version

ENTRYPOINT ["/usr/bin/tini", "-s", "/run/entry.sh"]
