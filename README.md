# datasets-tooling

Tooling for converting open Philippine datasets into [PMTiles](https://docs.protomaps.com/pmtiles/), a single-file
vector tile format that can be hosted on static storage and read with HTTP range requests.

## Projects

| Project | Output | Layers | Source | Hugging Face |
|---|---|---|---|---|
| [`project-noah-hazard-maps-pmtiles`](project-noah-hazard-maps-pmtiles/) | `noah_hazard_maps.pmtiles` | 9 | Project NOAH hazard map shapefiles (~575 ZIPs, ~95 GB) | [project-noah-hazard-maps](https://huggingface.co/datasets/bettergovph/project-noah-hazard-maps) |
| [`ph-osm-pmtiles`](ph-osm-pmtiles/) | `ph_osm.pmtiles` | 12 | HOT OpenStreetMap exports for the Philippines (12 PMTiles, ~939 MB) | [ph-osm-pmtiles](https://huggingface.co/datasets/bettergovph/ph-osm-pmtiles) |

### project-noah-hazard-maps-pmtiles

Flood, landslide, debris flow and storm surge hazard maps.

- **Input:** shapefiles from the
  [Project NOAH Hazard Maps](https://drive.google.com/drive/folders/1ALE4-E9c-4AGjm1fqiPprWHrLUskeY9o?usp=drive_link)
- **Method:** shapefiles are streamed through `ogr2ogr` into `tippecanoe`, one process per layer, then merged with
  `tile-join`
- **Image:** `ghcr.io/osgeo/gdal` with `tippecanoe` compiled from source and the `pmtiles` CLI
- **Dataset:** [bettergovph/project-noah-hazard-maps](https://huggingface.co/datasets/bettergovph/project-noah-hazard-maps)
  on Hugging Face

### ph-osm-pmtiles

Airports, buildings, roads, health facilities and 8 other OpenStreetMap themes.

- **Input:** ready-made PMTiles from [HOT on HDX](https://data.humdata.org/organization/hot?groups=phl)
- **Method:** download, validate, then merge into one file with `tile-join` (`pmtiles merge` cannot combine overlapping
  archives)
- **Image:** `alpine` with tippecanoe built in a throwaway stage and the `pmtiles` CLI
- **Dataset:** [bettergovph/ph-osm-pmtiles](https://huggingface.co/datasets/bettergovph/ph-osm-pmtiles) on Hugging Face

## Common layout

Each project is self-contained and follows the same pattern:

- `Dockerfile` — all dependencies, so nothing is installed on the host
- a conversion script (`shp_to_pmtiles.sh`, `osm_to_pmtiles.sh`) — run inside the container
- `README.md` — layers, attributes, usage examples, how the conversion works

Run any project from its own directory with the project root mounted at `/data`:

```bash
cd <project>
docker build -t <image-name> .
docker run --rm -v $(pwd):/data <image-name> <script>.sh
```

The exact image name and script are in each project's README.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- Free disk space for the source data plus the output (see each project's README)

## License

### Code

The code in this repository is released under the [MIT License](https://opensource.org/license/mit).

### Data

The converted datasets keep the license of their original source. It is stated in each project's README.
