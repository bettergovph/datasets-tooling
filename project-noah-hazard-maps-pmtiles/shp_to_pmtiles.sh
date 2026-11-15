#!/usr/bin/env bash
#
# Convert Project NOAH shapefiles to a single PMTiles file with 9 named layers.
#
# Architecture:
#   Stage 1: 9 parallel tippecanoe runs, one per hazard map. Each run streams
#   shapefiles from ZIP archives through a named FIFO directly into tippecanoe
#   with no intermediate GeoJSON files written to disk.
#
#   Stage 2: tile-join merges all 9 per-layer PMTiles into one file.
#
#   Stage 3: Verify the output with the pmtiles CLI.
#
# Per-layer processing means each tile holds only one layer's features, which
# keeps individual tile sizes manageable. Each layer file in layers/ is a
# checkpoint; re-running the script skips any layer whose file already exists.
#
# Run inside the noah-pmtiles Docker container with the project root at /data:
# `docker run --rm -v $(pwd):/data noah-pmtiles shp_to_pmtiles.sh`

set -euo pipefail

WORKDIR="/data"
FIFODIR="$WORKDIR/pipes"
LAYERDIR="$WORKDIR/layers"
OUTPUT="$WORKDIR/noah_hazard_maps.pmtiles"

cd "$WORKDIR"
mkdir -p "$FIFODIR" "$LAYERDIR"

trap 'rm -f "$FIFODIR"/*.geojsonl' EXIT

# Prints the name of the hazard attribute field in the shapefile, or returns
# 1 if none can be found.
#
# Tier 1: known candidate names (HAZ, GRIDCODE, GRID, ALLUVIAL, HAZARD).
# Tier 2: first Real or Integer typed field.
# Tier 3: first non-geometry field of any type.
#
# Landslide shapefiles use inconsistent field names across provinces
# (GRIDCODE, GRID, ALLUVIAL, etc.) so the 3-tier fallback ensures all
# provinces are processed. Flood and storm surge layers have consistent
# field names and are caught by tier 1 or 2.
detect_haz_field() {
  local shp="$1"
  local info
  info=$(ogrinfo -al -so "$shp" 2>/dev/null)

  # Tier 1 — known candidate names
  for candidate in HAZ GRIDCODE GRID ALLUVIAL HAZARD; do
    if echo "$info" | grep -qiE "^[[:space:]]*${candidate}[[:space:]]*:"; then
      echo "$candidate"
      return 0
    fi
  done

  # Tier 2 — first Real or Integer field
  local field
  field=$(echo "$info" \
    | grep -E '^[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*(Real|Integer)' \
    | head -1 | cut -d: -f1 | tr -d ' ')
  if [ -n "$field" ]; then
    echo "$field"
    return 0
  fi

  # Tier 3 — first non-geometry field of any type
  field=$(echo "$info" \
    | grep -E '^[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*' \
    | grep -vE '(Geometry|SRS WKT|Extent|Feature Count|Layer name)' \
    | head -1 | cut -d: -f1 | tr -d ' ')
  if [ -n "$field" ]; then
    echo "$field"
    return 0
  fi

  return 1
}

# Iterates all ZIPs in src_dir, extracts each to a tmpdir, and streams the
# contained shapefile into the named pipe as GeoJSONSeq.
#
# Uses detect_haz_field to find the hazard attribute and ogr2ogr aliases it
# to out_field so all features share a consistent attribute name downstream.
#
# The ZIP loop runs inside a subshell redirected to the FIFO. This keeps the
# FIFO write-end open for all ZIPs; closing it only when the subshell exits,
# which signals EOF to the tippecanoe reader.
stream_hazard_maps_shapefiles() {
  local src_dir="$1"
  local fifo="$2"
  local out_field="$3"

  (
    local processed=0 skipped=0 total=0
    for zip in "$src_dir"/*.zip; do
      [ -f "$zip" ] || { echo "[warn] no ZIPs in $src_dir" >&2; break; }
      total=$((total + 1))
      local zipname
      zipname=$(basename "$zip")

      local tmpdir
      tmpdir=$(mktemp -d)
      unzip -q "$zip" -d "$tmpdir" 2>/dev/null
      local shp
      shp=$(find "$tmpdir" -name "*.shp" | head -1)

      if [ -z "$shp" ]; then
        echo "[warn] $zipname — no .shp found, skipping" >&2
        skipped=$((skipped + 1))
        rm -rf "$tmpdir"
        continue
      fi

      local layer actual_field tier
      layer=$(basename "$shp" .shp)
      actual_field=$(detect_haz_field "$shp") || true

      if [ -z "$actual_field" ]; then
        echo "[warn] $zipname — no hazard field detected, skipping" >&2
        skipped=$((skipped + 1))
        rm -rf "$tmpdir"
        continue
      fi

      case "$actual_field" in
        HAZ|GRIDCODE|GRID|ALLUVIAL|HAZARD) tier="tier1" ;;
        *) tier="tier2/3" ;;
      esac

      echo "[ok]   $zipname → field=$actual_field ($tier)" >&2

      ogr2ogr -f GeoJSONSeq /vsistdout/ "$shp" \
        -sql "SELECT CAST(\"$actual_field\" AS INTEGER) AS $out_field FROM \"$layer\""

      processed=$((processed + 1))
      rm -rf "$tmpdir"
    done

    echo "" >&2
    echo "[summary] $src_dir: processed=$processed skipped=$skipped total=$total" >&2
  ) > "$fifo"
}

# Skips if layers/<layer_name>.pmtiles already exists (checkpoint).
# Otherwise creates a FIFO, streams hazard maps shapefiles and writes into
# it in the background, then runs tippecanoe reading from it in the foreground.
#
# --drop-densest-as-needed: culls the densest features when a tile exceeds
#   the size limit, preserving lower-density features at the cost of detail.
# --maximum-tile-bytes 2500000: raised from the default 500 KB to 2.5 MB to
#   accommodate dense multi-polygon flood/landslide tiles.
process_layer() {
  local name="$1"
  local src_dir="$2"
  local field="$3"
  local out="$LAYERDIR/$name.pmtiles"

  if [ -f "$out" ]; then
    echo "[skip] $name (already exists: $out)" >&2
    return
  fi

  local fifo="$FIFODIR/$name.geojsonl"
  mkfifo "$fifo"

  # Start writer in background — blocks at FIFO open until tippecanoe connects
  stream_hazard_maps_shapefiles "$src_dir" "$fifo" "$field" &

  echo "[start] $name" >&2
  tippecanoe -o "$out" \
    --force \
    -z14 \
    --drop-densest-as-needed \
    --maximum-tile-bytes 2500000 \
    -l "$name" \
    -y "$field" \
    "$fifo"

  rm -f "$fifo"
  echo "[done] $name → $out" >&2
}

# Stage 1: Process all 9 layers in parallel
echo "[stage1] Processing layers in parallel..."

process_layer "flood_5yr"        "Flood/5yr"                        "Var" &
process_layer "flood_25yr"       "Flood/25yr"                       "Var" &
process_layer "flood_100yr"      "Flood/100yr"                      "Var" &
process_layer "landslide"        "Landslide/LandslideHazards"       "HAZ" &
process_layer "debris_flow"      "Landslide/DebrisFlowAlluvialFan"  "HAZ" &
process_layer "storm_surge_ssa1" "Storm Surge/StormSurgeAdvisory1"  "HAZ" &
process_layer "storm_surge_ssa2" "Storm Surge/StormSurgeAdvisory2"  "HAZ" &
process_layer "storm_surge_ssa3" "Storm Surge/StormSurgeAdvisory3"  "HAZ" &
process_layer "storm_surge_ssa4" "Storm Surge/StormSurgeAdvisory4"  "HAZ" &

wait
echo "[stage1] All layers complete."

# Stage 2: Merge individual hazard maps PMTiles into a single file
#
# -pk skips tile-join's default 500 KB size limit.
echo "[stage2] Merging layers with tile-join..."

tile-join -o "$OUTPUT" --force -pk "$LAYERDIR"/*.pmtiles

echo ""
echo "[done] Output: $OUTPUT"

# Stage 3: Verify the output
echo "[stage3] Verifying output..."
pmtiles show "$OUTPUT"
