FROM ghcr.io/osgeo/gdal:ubuntu-full-latest

# Build dependencies
RUN set -x \
  && apt-get update \
  && apt-get install -y \
    build-essential \
    libsqlite3-dev \
    zlib1g-dev \
    git \
    wget \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Compile tippecanoe from source
WORKDIR /tmp/tippecanoe
RUN git clone https://github.com/felt/tippecanoe.git . \
  && make -j$(nproc) \
  && make install \
  && rm -rf /tmp/tippecanoe

# Install pmtiles CLI
RUN wget -qO- https://github.com/protomaps/go-pmtiles/releases/download/v1.22.3/go-pmtiles_1.22.3_Linux_x86_64.tar.gz \
  | tar -xz -C /usr/local/bin pmtiles

WORKDIR /data
ENTRYPOINT ["/bin/bash"]
