# Philippines OpenStreetMap Vector Tiles (PMTiles): 12 Layers

Merges the 12 [Humanitarian OpenStreetMap Team (HOT)](https://data.humdata.org/organization/hot?groups=phl)
OpenStreetMap exports for the Philippines into a single PMTiles file, with each dataset in its own named vector tile
layer.

- **Input:** 12 PMTiles files (~939 MB), listed in [`hot_pmtiles_urls.txt`](hot_pmtiles_urls.txt)
- **Output:** `ph_osm.pmtiles` (~946 MB), z0–z15, 12 layers

| Layer | Dataset | Source size | Max zoom |
|---|---|---|---|
| `airports` | Airports | 1.0 MB | 12 |
| `buildings` | Buildings | 644.1 MB | 15 |
| `cultural_places` | Cultural places | 5.3 MB | 12 |
| `education_facilities` | Education facilities | 24.9 MB | 12 |
| `financial_services` | Financial services | 1.5 MB | 12 |
| `health_facilities` | Health facilities | 3.2 MB | 12 |
| `points_of_interest` | Points of interest | 38.8 MB | 12 |
| `populated_places` | Populated places | 23.9 MB | 12 |
| `railways` | Railways | 0.2 MB | 12 |
| `roads` | Roads | 158.7 MB | 13 |
| `sea_ports` | Sea ports | 0.6 MB | 12 |
| `waterways` | Waterways | 58.7 MB | 12 |

Layer names match the dataset name in each source filename (`hotosm_phl_<layer>_osm.pmtiles`).

## Layer attributes

Every layer carries the same administrative attributes, plus dataset-specific OSM tags.

**Shared by all layers**

- `id` — OSM feature id, e.g. `way/1382563216`
- `name`, `name_en`, `name_fil`, `name_latin` — names (not every layer has all four)
- `adm0_name`/`adm0_pcode` … `adm4_name`/`adm4_pcode` — country down to barangay, with PSGC-style codes

**Dataset-specific (examples)**

- `roads` — `highway`, `surface`, `lanes`, `oneway`, `bridge`, `width`, `smoothness`
- `buildings` — `building`, `building_levels`, `addr_*`
- `waterways` — `waterway`, `water`, `tunnel`, `width`
- `health_facilities` — `amenity`, `healthcare`, `healthcare_speciality`, `capacity_persons`
- `populated_places` — `place`, `population`, `is_in`

List every field per layer with:

```bash
docker run --rm -v $(pwd):/data ph-osm-pmtiles -c "pmtiles show --metadata /data/ph_osm.pmtiles"
```

Most layers contain **mixed geometry types** (for example `points_of_interest` has points and polygons). Filter by
`$type` when styling (see below).

## PMTiles usage

View the file with the [PMTiles viewer](https://pmtiles.io/) (drag in the file or paste a hosted URL), or load it in
MapLibre GL JS with the [pmtiles](https://www.npmjs.com/package/pmtiles) protocol plugin.

### MapLibre GL JS

Replace `PMTILES_URL` with wherever you host `ph_osm.pmtiles`. The host must support HTTP range requests.

```html
<script src="https://unpkg.com/maplibre-gl/dist/maplibre-gl.js"></script>
<script src="https://unpkg.com/pmtiles/dist/pmtiles.js"></script>
```

```js
const protocol = new pmtiles.Protocol();
maplibregl.addProtocol("pmtiles", protocol.tile);

const map = new maplibregl.Map({ container: "map", center: [121.0, 14.6], zoom: 9, /* ... */ });

const PMTILES_URL = "pmtiles://https://example.com/ph_osm.pmtiles";

map.on("load", () => {
  map.addSource("osm", { type: "vector", url: PMTILES_URL });

  // source-layer options: airports, buildings, cultural_places, education_facilities,
  // financial_services, health_facilities, points_of_interest, populated_places,
  // railways, roads, sea_ports, waterways
  map.addLayer({
    id: "buildings",
    type: "fill",
    source: "osm",
    "source-layer": "buildings",
    filter: ["==", "$type", "Polygon"],
    paint: { "fill-color": "#9ca3af", "fill-opacity": 0.7 }
  });

  map.addLayer({
    id: "roads",
    type: "line",
    source: "osm",
    "source-layer": "roads",
    filter: ["==", "$type", "LineString"],
    paint: { "line-color": "#f59e0b", "line-width": 1 }
  });

  map.addLayer({
    id: "health-facilities",
    type: "circle",
    source: "osm",
    "source-layer": "health_facilities",
    filter: ["==", "$type", "Point"],
    paint: { "circle-color": "#dc2626", "circle-radius": 4 }
  });
});
```

Layers have different max zooms (see table). MapLibre overzooms automatically, so `roads` (z13) and the other layers
(z12) stay visible when you zoom past their max zoom, while `buildings` continues to z15.

## Conversion process

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- ~2 GB free disk space (939 MB of source files + 946 MB output)
- ~2 GB RAM available to Docker (the container used ~1 GB when sampled mid-merge)

### Running the conversion process

```bash
# Build the image
docker build -t ph-osm-pmtiles .

# Download, validate, merge and verify
docker run --rm -v $(pwd):/data ph-osm-pmtiles osm_to_pmtiles.sh
```

Download time depends on your connection. The merge took about 10 minutes on an Apple Silicon laptop running Docker.

The script writes:

- `source/` — the 12 downloaded PMTiles files
- `ph_osm.pmtiles` — the merged output

### Stage 1: Download

Reads every URL in `hot_pmtiles_urls.txt` and downloads it into `source/`.

- Files that already exist are skipped (checkpoint)
- Downloads go to `<file>.part` and are renamed on success, so an interrupted run never leaves a truncated file that
  looks complete
- `curl -C -` resumes a partial `.part` file

### Stage 2: Validate

For each source file, the script:

- runs `pmtiles verify` to check the archive structure
- checks that the layer id in the metadata equals the dataset name in the filename

`tile-join` keeps source layer ids unchanged, so this check guarantees the output layer names match the table above.

### Stage 3: tile-join merge

`tile-join` decodes the tiles from all 12 archives and writes one tile per z/x/y containing every source layer present
at that address.

Flags:

- `-pk` — skip the default 500 KB tile size limit
- `-f` — overwrite an existing output file
- `-n`, `-N`, `-A` — set output name, description and attribution metadata

### Stage 4: Verify

`pmtiles verify` and `pmtiles show` run on the output and print tile type, bounds, zoom range and tile counts.

## Why tile-join and not `pmtiles merge`?

The `pmtiles` CLI has a `merge` command, but it only merges **disjoint** archives. All 12 sources cover the same tile
addresses, so it fails:

```
Failed to merge, hotosm_phl_railways_osm.pmtiles: 97 overlapping tiles, starting with 0 0 0. Inputs must be disjoint
```

Combining layers means decoding each tile and re-encoding the union, which is what `tile-join` from
[tippecanoe](https://github.com/felt/tippecanoe) does. It is the same approach used in
[project-noah-hazard-maps-pmtiles](../project-noah-hazard-maps-pmtiles/).

## Docker image

[`Dockerfile`](Dockerfile) is a two-stage build on `alpine`:

**Stage 1 — build tippecanoe**

- Installs `build-base git sqlite-dev zlib-dev bash`
- Compiles tippecanoe `2.79.0` from source
- Discarded after the build, so the compiler toolchain is not in the final image

**Stage 2 — runtime (~190 MB)**

- Installs `bash curl libstdc++ sqlite-libs zlib`
- Copies `tile-join` and other tippecanoe binaries from stage 1
- Downloads the prebuilt `pmtiles` CLI `1.31.2` (picks `x86_64` or `arm64` automatically)

Versions are build arguments:

```bash
docker build -t ph-osm-pmtiles \
  --build-arg PMTILES_VERSION=1.31.2 \
  --build-arg TIPPECANOE_VERSION=2.79.0 .
```

## Resuming an interrupted run

Re-run the same command. Completed downloads are skipped and the merge starts again from the files in `source/`. To
re-download one file, delete it first:

```bash
rm source/hotosm_phl_roads_osm.pmtiles
docker run --rm -v $(pwd):/data ph-osm-pmtiles osm_to_pmtiles.sh
```

## Verifying the output

Verification runs automatically at the end of the script. To run it manually:

```bash
docker run --rm -v $(pwd):/data ph-osm-pmtiles -c "pmtiles verify /data/ph_osm.pmtiles && pmtiles show /data/ph_osm.pmtiles"
```

Expected output:

- tile type `mvt`
- bounds ~114.3–126.6°E, 4.6–21.1°N
- zoom range 0–15
- 155,269 tiles (as of the 2026-10-13 HOT export)

Check which layers a tile contains:

```bash
docker run --rm -v $(pwd):/data ph-osm-pmtiles -c \
  "tippecanoe-decode /data/ph_osm.pmtiles 8 214 120 | grep -o '\"layer\": \"[a-z_]*\"' | sort -u"
```

## Known quirks

- **Warnings during merge** — `Warning: mismatched maxzooms: 13 in …roads… vs previous 12` and the same for `buildings`
  are expected. Layers have different max zooms (12, 13, 15) by design.
- **Large tiles** — `-pk` removes the tile size limit, so low-zoom tiles can be large (tile 5/26/14 is ~1.3 MB gzipped).
  The source files were already thinned by tippecanoe at each zoom.
- **Inherited metadata** — the output `generator_options` metadata is concatenated from the sources and contains the HOT
  exporter's local build paths. It is harmless but not meaningful.
- **Mixed geometry** — most layers hold points and polygons together. Use a `$type` filter when styling.

## Data source and license

Original data: [Humanitarian OpenStreetMap Team on HDX —
Philippines](https://data.humdata.org/organization/hot?groups=phl). Direct file URLs are in
[`hot_pmtiles_urls.txt`](hot_pmtiles_urls.txt) (HOT raw-data API exports on S3, last modified 2026-10-13).

Data is © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright) and available under the [Open Database
License (ODbL) 1.0](https://opendatacommons.org/licenses/odbl/1-0/). Attribute OpenStreetMap contributors and HOT when
you use it.
