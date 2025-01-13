ARG TARGETARCH
ARG OS=linux



FROM --platform=$OS/$TARGETARCH ubuntu:noble-20241118.1 AS base
ARG TARGETARCH
ARG OS


ENV TARGETARCH=$TARGETARCH
ENV OS=$OS

WORKDIR /app
    
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    net-tools \
    iputils-ping \
    ca-certificates \
    wget \
    unzip \
    zip \
    libgl1 \
    libpng16-16 \
    libqt6core6 \
    libqt6gui6 \
    libqt6network6 \
    libqt6widgets6 \
    libxml2 \
    libvirt0 \
    dnsmasq-base \
    dnsmasq-utils \
    qemu-system \
    qemu-utils \
    libslang2 \
    iproute2 \
    iptables \
    iputils-ping \
    libatm1 \
    libxtables12 \
    xterm \
    expect \
    nano \
    ovmf \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY multipass.tar /app

COPY *.sh /app

RUN tar xvf multipass.tar && rm multipass.tar \
    && chmod +x /app/*.sh /app/multipass/multipassd /app/multipass/multipass \
    && ln -s /app/multipass/multipass /usr/local/bin/multipass \
    && ln -s /app/data/agent/apps/qiniu-unix/install-qiniu.sh /app

ENV MULTIPASS_PASSPHRASE=default^^p@ssw0rd
ENV WORKSPACE=/app/data/agent
ENV AGENT_PATH=/app/agent
ENV MULTIPASS_PATH=/app/multipass
ENV SERVER_URL=https://test4-api.titannet.io
ENV DATA_DIR=/app/data
ENV MULTIPASS_SOCKET_PATH=/run/multipass_socket
ENV LOG_FILE=$WORKSPACE/agent.log
ENV MULTIPASS_STORAGE=$DATA_DIR/multipass
ENV MULTIPASS_SERVER_ADDRESS=unix:$MULTIPASS_SOCKET_PATH
ENV MULTIPASS_LOG_FILE=$DATA_DIR/multipass/multipass.log

HEALTHCHECK --interval=30s --timeout=30s --start-period=90s --retries=10 \
  CMD /app/install-qiniu.sh info | grep "BOX_ID:" || exit 1


ENTRYPOINT [ "./run.sh" ]