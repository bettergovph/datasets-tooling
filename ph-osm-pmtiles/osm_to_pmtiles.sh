#!/usr/bin/env bash
#
# Download the HOT OSM Philippines PMTiles and merge them into a single
# PMTiles file with one named layer per dataset.
#
# Stages:
#   1. Download: fetch every URL in hot_pmtiles_urls.txt into source/.
#      Existing files are skipped (checkpoint); partial downloads are resumed.
#   2. Validate: confirm each source archive is a vector PMTiles file whose
#      layer id matches the dataset name in its URL.
#   3. Merge: tile-join combines all archives into one. Tiles at the same
#      z/x/y are unioned, and each source keeps its own layer.
#   4. Verify: `pmtiles verify` and `pmtiles show` on the output.
#
# Run inside the ph-osm-pmtiles Docker container with the project root at /data:
# `docker run --rm -v $(pwd):/data ph-osm-pmtiles osm_to_pmtiles.sh`

set -euo pipefail

WORKDIR="/data"
URL_FILE="$WORKDIR/hot_pmtiles_urls.txt"
SRCDIR="$WORKDIR/source"
OUTPUT="$WORKDIR/ph_osm.pmtiles"

cd "$WORKDIR"
mkdir -p "$SRCDIR"

# Prints the layer name for a source URL or file path:
# .../hotosm_phl_<layer>_osm.pmtiles -> <layer>
layer_name() {
  basename "$1" | sed -E 's/^hotosm_phl_//; s/_osm\.pmtiles$//'
}

# Stage 1: Download
#
# Downloads to <file>.part and renames on success, so an interrupted run never
# leaves a truncated file that looks complete. `-C -` resumes a partial file.
echo "[stage1] Downloading source PMTiles..."

files=()
while IFS= read -r url || [ -n "$url" ]; do
  [ -n "$url" ] || continue
  file="$SRCDIR/$(basename "$url")"
  files+=("$file")

  if [ -f "$file" ]; then
    echo "[skip] $(basename "$file") (already exists)" >&2
    continue
  fi

  echo "[get]  $url" >&2
  curl -fSL --retry 3 -C - -o "$file.part" "$url"
  mv "$file.part" "$file"
done < "$URL_FILE"

[ "${#files[@]}" -gt 0 ] || { echo "[error] no URLs found in $URL_FILE" >&2; exit 1; }

# Stage 2: Validate
#
# tile-join keeps each source's layer id as-is, so the layer id inside each
# archive must already equal the dataset name. Fail early if not.
echo "[stage2] Validating source layers..."

for file in "${files[@]}"; do
  layer=$(layer_name "$file")
  pmtiles verify "$file" > /dev/null
  if ! pmtiles show --metadata "$file" | tr -d ' \n' | grep -q "\"vector_layers\":\[{\"id\":\"$layer\""; then
    echo "[error] $(basename "$file"): layer id '$layer' not found in metadata" >&2
    exit 1
  fi
  echo "[ok]   $layer" >&2
done

# Stage 3: Merge
#
# -pk  skips tile-join's default 500 KB tile size limit.
# -f   overwrites an existing output file.
# -n/-N/-A  set the output's name, description and attribution metadata.
echo "[stage3] Merging ${#files[@]} archives with tile-join..."

tile-join -o "$OUTPUT" -f -pk \
  -n "Philippines OpenStreetMap Vector Tiles (PMTiles): 12 Layers" \
  -N "Humanitarian OpenStreetMap Team (HOT) OSM exports for the Philippines, one layer per dataset" \
  -A "© OpenStreetMap contributors, ODbL 1.0. Exported by HOT." \
  "${files[@]}"

echo ""
echo "[done] Output: $OUTPUT"

# Stage 4: Verify
echo "[stage4] Verifying output..."
pmtiles verify "$OUTPUT"
pmtiles show "$OUTPUT"
