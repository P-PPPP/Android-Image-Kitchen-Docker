FROM ubuntu:24.04

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

WORKDIR /work

CMD ["bash"]
