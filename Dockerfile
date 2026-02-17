FROM ubuntu:24.04 AS tools-builder

ARG http_proxy
ARG https_proxy
ARG all_proxy
ENV http_proxy=${http_proxy} \
    https_proxy=${https_proxy} \
    all_proxy=${all_proxy}
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    make \
    gcc \
    g++ \
    libc6-dev \
  && rm -rf /var/lib/apt/lists/*

RUN git clone --depth=1 https://github.com/osm0sis/unpackelf.git /tmp/unpackelf \
  && make -C /tmp/unpackelf \
  && cp /tmp/unpackelf/unpackelf /tmp/unpackelf.bin \
  && git clone --depth=1 https://github.com/osm0sis/elftool.git /tmp/elftool \
  && make -C /tmp/elftool \
  && cp /tmp/elftool/elftool /tmp/elftool.bin

FROM ubuntu:24.04

ARG http_proxy
ARG https_proxy
ARG all_proxy
ENV http_proxy=${http_proxy} \
    https_proxy=${https_proxy} \
    all_proxy=${all_proxy}
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    binutils \
    cpio \
    coreutils \
    file \
    gzip \
    lz4 \
    lzop \
    mkbootimg \
    perl \
    u-boot-tools \
    xz-utils \
    default-jre-headless \
    python3 \
  && mkdir -p /usr/lib/python3/dist-packages/gki \
  && printf '%s\n' 'def generate_gki_certificate(*args, **kwargs):' '    return None' > /usr/lib/python3/dist-packages/gki/generate_gki_certificate.py \
  && touch /usr/lib/python3/dist-packages/gki/__init__.py \
  && rm -rf /var/lib/apt/lists/*

COPY --from=tools-builder /tmp/unpackelf.bin /usr/local/bin/unpackelf
COPY --from=tools-builder /tmp/elftool.bin /usr/local/bin/elftool
RUN chmod 755 /usr/local/bin/unpackelf /usr/local/bin/elftool

WORKDIR /work

CMD ["bash"]
