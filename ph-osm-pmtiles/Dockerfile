# syntax=docker/dockerfile:1

ARG ALPINE_VERSION=3.22

# ---------------------------------------------------------------------------
# Stage 1: compile tippecanoe (provides `tile-join`, used to merge layers).
# Throwaway stage: the compiler toolchain never reaches the final image.
# ---------------------------------------------------------------------------
FROM alpine:${ALPINE_VERSION} AS tippecanoe-build

ARG TIPPECANOE_VERSION=2.79.0

RUN apk add --no-cache build-base git sqlite-dev zlib-dev bash

WORKDIR /tmp/tippecanoe
RUN git clone --depth 1 --branch "${TIPPECANOE_VERSION}" https://github.com/felt/tippecanoe.git . \
  && make -j"$(nproc)" \
  && make install PREFIX=/opt/tippecanoe

# ---------------------------------------------------------------------------
# Stage 2: runtime image.
# ---------------------------------------------------------------------------
FROM alpine:${ALPINE_VERSION}

ARG PMTILES_VERSION=1.31.2
# Set automatically by BuildKit: amd64 | arm64
ARG TARGETARCH

# Runtime libraries for tippecanoe, plus bash for the conversion script
# and curl to download the source PMTiles.
RUN apk add --no-cache bash curl libstdc++ sqlite-libs zlib

# tile-join (and tippecanoe) built in stage 1
COPY --from=tippecanoe-build /opt/tippecanoe/bin/ /usr/local/bin/

# pmtiles CLI (prebuilt Go binary)
RUN case "${TARGETARCH:-$(uname -m)}" in \
      amd64|x86_64)  ARCH=x86_64 ;; \
      arm64|aarch64) ARCH=arm64 ;; \
      *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
  && curl -fsSL "https://github.com/protomaps/go-pmtiles/releases/download/v${PMTILES_VERSION}/go-pmtiles_${PMTILES_VERSION}_Linux_${ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin pmtiles \
  && pmtiles version

WORKDIR /data
ENTRYPOINT ["/bin/bash"]
