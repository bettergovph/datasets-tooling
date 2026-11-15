# Project NOAH Hazard Maps PMTiles

Converts ~575 ZIP archives of [Project NOAH Hazard Maps shapefiles](https://huggingface.co/datasets/bettergovph/project-noah-hazard-maps)
(~95 GB) into a single PMTiles file with 9 named vector tile layers.

| Layer | Hazard | Attribute | Values |
|---|---|---|---|
| `flood_5yr` | Flood 5-year return period | `Var` | 1 / 2 / 3 |
| `flood_25yr` | Flood 25-year return period | `Var` | 1 / 2 / 3 |
| `flood_100yr` | Flood 100-year return period | `Var` | 1 / 2 / 3 |
| `landslide` | Landslide hazard zones | `HAZ` | 1 / 2 / 3 |
| `debris_flow` | Debris flow and alluvial fan | `HAZ` | 1 / 2 / 3 |
| `storm_surge_ssa1` | Storm surge advisory 1 (up to 2 m) | `HAZ` | 1 / 2 / 3 |
| `storm_surge_ssa2` | Storm surge advisory 2 (up to 3 m) | `HAZ` | 1 / 2 / 3 |
| `storm_surge_ssa3` | Storm surge advisory 3 (up to 4 m) | `HAZ` | 1 / 2 / 3 |
| `storm_surge_ssa4` | Storm surge advisory 4 (above 4 m) | `HAZ` | 1 / 2 / 3 |

The _Values_ correspond to the following hazard levels _1=Low_, _2=Medium_, _3=High_.

## PMTiles usage

The PMTiles file is available for download on [HuggingFace](https://huggingface.co/datasets/bettergovph/project-noah-hazard-maps/tree/main/PMTiles) or for viewing using the [PMTiles viewer](https://pmtiles.io/#map=5.44/11.447/123.548&url=https%3A%2F%2Fhuggingface.co%2Fdatasets%2Fbettergovph%2Fproject-noah-hazard-maps%2Fresolve%2Fmain%2FPMTiles%2Fnoah_hazard_maps.pmtiles).

### MapLibre GL JS

Load the file directly from HuggingFace using the [pmtiles](https://www.npmjs.com/package/pmtiles) protocol plugin for [MapLibre GL JS](https://maplibre.org/maplibre-gl-js/docs/).

```html
<script src="https://unpkg.com/maplibre-gl/dist/maplibre-gl.js"></script>
<script src="https://unpkg.com/pmtiles/dist/pmtiles.js"></script>
```

```js
const protocol = new pmtiles.Protocol();
maplibregl.addProtocol("pmtiles", protocol.tile);

const map = new maplibregl.Map({ container: "map", /* ... */ });

const PMTILES_URL =
  "pmtiles://https://huggingface.co/datasets/bettergovph/project-noah-hazard-maps/resolve/main/PMTiles/noah_hazard_maps.pmtiles";

map.on("load", () => {
  map.addSource("noah", { type: "vector", url: PMTILES_URL });

  // Flood attribute: Var (1=Low, 2=Medium, 3=High)
  // source-layer options: flood_5yr, flood_25yr, flood_100yr
  map.addLayer({
    id: "flood-100yr",
    type: "fill",
    source: "noah",
    "source-layer": "flood_100yr",
    paint: {
      "fill-color": ["match", ["get", "Var"], 1, "#93c5fd", 2, "#3b82f6", 3, "#1d4ed8", "transparent"],
      "fill-opacity": 0.65
    }
  });

  // Landslide / debris flow attribute: HAZ (1=Low, 2=Medium, 3=High)
  // source-layer options: landslide, debris_flow
  map.addLayer({
    id: "landslide",
    type: "fill",
    source: "noah",
    "source-layer": "landslide",
    paint: {
      "fill-color": ["match", ["get", "HAZ"], 1, "#fde68a", 2, "#f59e0b", 3, "#b45309", "transparent"],
      "fill-opacity": 0.65
    }
  });

  // Storm surge attribute: HAZ (1=Low, 2=Medium, 3=High)
  // source-layer options: storm_surge_ssa1, storm_surge_ssa2, storm_surge_ssa3, storm_surge_ssa4
  map.addLayer({
    id: "storm-surge-ssa1",
    type: "fill",
    source: "noah",
    "source-layer": "storm_surge_ssa1",
    paint: {
      "fill-color": ["match", ["get", "HAZ"], 1, "#99f6e4", 2, "#2dd4bf", 3, "#0f766e", "transparent"],
      "fill-opacity": 0.65
    }
  });
});
```

## Conversion process

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- ~6 GB free disk space beyond the source data
- The Project NOAH Hazard Maps dataset (in the current directory)

### Running the conversion process

```bash
# Build the image
docker build -t noah-pmtiles .

# Run the conversion
docker run --rm -v $(pwd):/data noah-pmtiles shp_to_pmtiles.sh
```

The conversion process takes several hours and generates individual PMTiles files
for each "layer" which is then merged into `noah_hazard_maps.pmtiles` as the final
step.

### Stage 1: Parallel tippecanoe runs

Each of the 9 hazard maps gets its own tippecanoe process, all running in
parallel. Shapefiles are streamed from ZIP archives through a named FIFO directly
into tippecanoe, no intermediate GeoJSON files are written to disk. Only one
unzipped shapefile lives on disk at a time per layer.

Processing layers separately means each tile contains features from only one layer,
keeping individual tile sizes manageable.

Landslide shapefiles use inconsistent field names across provinces (`GRIDCODE`,
`GRID`, `ALLUVIAL`, etc.). The script uses a 3-tier fallback via `ogrinfo` to
detect the hazard field per file and aliases it to a normalised output name via
ogr2ogr SQL:

1. **Tier 1** — known candidate names: `HAZ`, `GRIDCODE`, `GRID`, `ALLUVIAL`, `HAZARD`
2. **Tier 2** — first `Real` or `Integer` typed field
3. **Tier 3** — first non-geometry field of any type

Each completed layer is saved as `layers/<layer>.pmtiles` and acts as a
checkpoint, re-running skips any layer whose file already exists.

### Stage 2: tile-join merge

`tile-join -pk` merges all 9 per-layer PMTiles into `hazard_maps.pmtiles`.
The `-pk` flag bypasses tile-join's default 500 KB tile size limit.

### Stage 3: Verify

`pmtiles show` runs automatically after the merge and prints the tile type,
bounds, zoom range, and layer names of the output file.

## Resuming an interrupted run

Delete the checkpoint for any layer you want to regenerate, then re-run:

```bash
rm layers/landslide.pmtiles
docker run --rm -v $(pwd):/data noah-pmtiles shp_to_pmtiles.sh
```

## Verifying the output

Verification runs automatically at the end of the conversion script (Stage 3).
To run it manually against an existing output file:

```bash
docker run --rm -v $(pwd):/data noah-pmtiles -c "pmtiles show /data/noah_hazard_maps.pmtiles"
```

Expected output includes tile type `Vector Protobuf (MVT)`, bounds covering the
Philippines (~116–127°E, 4–21°N), zoom range 0–14, and all 9 layer names.

## Known Data Gaps

`Flood/100yr/TawiTawi.zip` is present in the dataset but is an empty ZIP archive (22 bytes, no files inside). No flood
hazard data is available for Tawi-Tawi province at the 100-year return period.

## License

Code is released under the [MIT License](LICENSE).

Data is derived from the [Project NOAH Hazard Maps](https://huggingface.co/datasets/bettergovph/project-noah-hazard-maps) dataset and is made available under the [Open Database License (ODbL) 1.0](https://opendatacommons.org/licenses/odbl/1-0/).
