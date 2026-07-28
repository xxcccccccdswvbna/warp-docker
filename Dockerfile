ARG BASE_IMAGE=debian:bookworm-slim


FROM ${BASE_IMAGE}

ARG WARP_VERSION
ARG GOST_VERSION
ARG COMMIT_SHA
ARG TARGETPLATFORM

LABEL org.opencontainers.image.authors="cmj2002"
LABEL org.opencontainers.image.url="https://github.com/cmj2002/warp-docker"
LABEL WARP_VERSION=${WARP_VERSION}
LABEL GOST_VERSION=${GOST_VERSION}
LABEL COMMIT_SHA=${COMMIT_SHA}

COPY entrypoint.sh /entrypoint.sh
COPY ./healthcheck /healthcheck

RUN case ${TARGETPLATFORM} in \
      "linux/amd64") ARCH="amd64" ;; \
      "linux/arm64") ARCH="armv8" ;; \
      *) echo "Unsupported TARGETPLATFORM: ${TARGETPLATFORM}" && exit 1 ;; \
    esac && \
    echo "Building for ${TARGETPLATFORM} with GOST ${GOST_VERSION}" && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        sudo \
        jq \
        ipcalc && \
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
        | gpg --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/cloudflare-client.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends cloudflare-warp && \
    MAJOR_VERSION=$(echo ${GOST_VERSION} | cut -d. -f1) && \
    MINOR_VERSION=$(echo ${GOST_VERSION} | cut -d. -f2) && \
    if [ "${MAJOR_VERSION}" -ge 3 ] || [ "${MAJOR_VERSION}" -eq 2 -a "${MINOR_VERSION}" -ge 12 ]; then \
        if [ "${TARGETPLATFORM}" = "linux/arm64" ]; then ARCH="arm64"; fi && \
        FILE_NAME="gost_${GOST_VERSION}_linux_${ARCH}.tar.gz" && \
        curl -fsSLO https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/${FILE_NAME} && \
        tar -xzf ${FILE_NAME} -C /usr/bin gost && \
        rm -f ${FILE_NAME}; \
    else \
        FILE_NAME="gost-linux-${ARCH}-${GOST_VERSION}.gz" && \
        curl -fsSLO https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/${FILE_NAME} && \
        gunzip ${FILE_NAME} && \
        mv gost-linux-${ARCH}-${GOST_VERSION} /usr/bin/gost; \
    fi && \
    chmod +x /usr/bin/gost && \
    chmod +x /entrypoint.sh && \
    chmod +x /healthcheck/index.sh && \
    useradd -m -s /bin/bash warp && \
    echo "warp ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/warp && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

USER warp

RUN mkdir -p /home/warp/.local/share/warp && \
    echo -n "yes" > /home/warp/.local/share/warp/accepted-tos.txt

ENV GOST_ARGS="-L :1080"
ENV WARP_SLEEP=2
ENV REGISTER_WHEN_MDM_EXISTS=
ENV WARP_LICENSE_KEY=
ENV BETA_FIX_HOST_CONNECTIVITY=
ENV WARP_ENABLE_NAT=

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD /healthcheck/index.sh

ENTRYPOINT ["/entrypoint.sh"]
