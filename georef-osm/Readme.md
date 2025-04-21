# Georef-OSM
This directory contains tooling to assist with "georeferencing" traced technical drawings with actual geographic features
using [OpenStreetMap](https://www.openstreetmap.org/) data. This uses a combination of Bash, Node.JS, and PostgreSQL scripts; 
as such it's recommended to be performed in a Linux or WSL environment.

## Concepts
### Georeference Points
Fixed locations along the guideway that can be mapped between a geographic location and a track node. 
Some examples are switches, most substations, most electrical switches, some reentry point signs, building/tunnel entrances.

## Georeference Lines
A continuous, unbranching line between 2 georeference points both on OSM ways and traced track fragments. Only nodes 
which are either a georef point or contained on a georef line can be automatically placed.

## Map scale groups
Traced maps which all have the same scale. While most of the traced drawings are not to scale, one can reasonably assume 
that multiple maps traced from the same drawing are at least roughly to the same scale. A georef line that spans multiple 
scale groups can't be automatically georeferenced without additional information.

- - -

## Process Overview
### Download OSM Data
Bash script `download.sh` will use the [Overpass API](https://overpass-api.de/) to run the query contained in 
`overpass-query.txt` & output it in `work/raw-osm.json`. To avoid unnecessary load on the OSM & overpass servers, try 
to run this script only when necessary to refresh the cached OSM data.

### Fix & Import OSM Data
Bash script `import-data.sh` does several steps:
1. Runs NodeJS script `index.js`. This will take `work/raw-osm.json` & output `nodes.geojson`, `ways.geojson` & 
`way_nodes.sql`. The former 2 are just the OSM data in GeoJSON form (I'm currently unaware of a clean way to output 
GeoJSON from Overpass); the latter is a PGSQL `COPY FROM` command to load data into the as-yet-created 
`osm.osm_raw_way_nodes` table.
2. Uses GDAL's [`ogr2ogr`](https://gdal.org/en/stable/programs/ogr2ogr.html) to convert these GeoJSON files to PGSQL 
scripts `nodes.sql` & `ways.sql`. I chose this method as it was the easiest way to import all OSM data without me having 
to reinvent the wheel in terms of importing the data.
3. Runs `import.sql` using `psql`. The user should have configured PostgreSQL's [environment variables](https://www.postgresql.org/docs/current/libpq-envars.html) 
prior to running the script to ensure a connection can be made. This script is responsible for the remaining steps.
4. `DROP` & re-`CREATE` schema `osm`, and loads the data from `nodes.sql`, `ways.sql`, and `way_nodes.sql` into it.
5. Runs script `pre-osm-parse.sql`. This file contains any dataset-specific fixes that are required.
6. Creates type `osm.switch_type`, view `osm.switches`, and materialized view `osm.node_pairs`

### Manually Georeference Points
The `georef-schema.sql` schema contains various tables to allow specifying "georef points"; track locations that map to 
features contained in the traced drawings. This is mainly performed by hand.

### Run Georeferencing Script
Once satisfied with the georeferencing, `georef.sql` may be ran. This will delete all nodes & fragments from the `geo` map. 
Nodes specified in a georeferencing point will be placed at the georef point. Remaining nodes will be mapped along the 
OSM way between 2 georef points, placing them at intervals according to their respective percentage between the georef 
points on the traced map. Any fragments unable to be placed will currently silently fail.

- - -

## Schema `georef`
Many of these tables reference tables from other schemas. To allow editing `track`, or re-run the OSM import script 
without running into foreign key issues, these tables do not have foreign keys on any other schema.

The materialized views contained in this schema are currently considered implementation details and are thus not documented.

### Table `georef.map_scale_groups`
Defines map scale groups.

| Field       | Type                        | Description                                                       |
|-------------|-----------------------------|-------------------------------------------------------------------|
| `scale_key` | `TEXT NOT NULL PRIMARY KEY` | The scale key                                                     |
| `maps`      | `TEXT[] NOT NULL`           | An array of `maps.maps (map_id)`s which are all of the same scale |

### Table `georef.loops_linked_nodes`
A couple of georef line pairs both start and end on the same georef point, and have no other georef points along them to 
differentiate them. Adding an entry to this table for each line will tell the pathfinding algorithm that they are distinct 
georef lines.

`PRIMARY KEY (track_node, osm_node)`

| Field        | Type                                                              | Description            |
|--------------|-------------------------------------------------------------------|------------------------|
| `track_node` | `UUID NOT NULL UNIQUE` "`REFERENCES track.track_nodes (node_id)`" | Track node on the loop |
| `osm_node`   | `TEXT NOT NULL UNIQUE` "`REFERENCES osm.osm_raw_nodes (id)`"      | OSM node on the loop   |

### Table `georef.georef_nodes`
Declares georef points which are directly OSM nodes (i.e. switches).

`PRIMARY KEY (track_node, osm_node)`

| Field        | Type                                                              | Description                     |
|--------------|-------------------------------------------------------------------|---------------------------------|
| `track_node` | `UUID NOT NULL UNIQUE` "`REFERENCES track.track_nodes (node_id)`" | Track node for the georef point |
| `osm_node`   | `TEXT NOT NULL UNIQUE` "`REFERENCES osm.osm_raw_nodes (id)`"      | OSM node for the georef point   |

### Table `georef.intersection_lines`
Declares "intersection lines"; georef points can be specified at the intersection of these lines and a specific OSM 
node_pair.

| Field                  | Type                                  | Description           |
|------------------------|---------------------------------------|-----------------------|
| `intersection_line_id` | `TEXT NOT NULL PRIMARY KEY`           | Intersection line ID  |
| `geom`                 | `geometry(LINESTRING, 3857) NOT NULL` | The intersection line |

### Table `georef.intersection_cross_node_pairs`
Specifies a georef point node at the intersection of a line and OSM node_pair.

`PRIMARY KEY (intersection_line_id, node_pair_id)`

| Field                  | Type                                                                        | Description                     |
|------------------------|-----------------------------------------------------------------------------|---------------------------------|
| `intersection_line_id` | `TEXT NOT NULL REFERENCES georef.intersection_lines (intersection_line_id)` | Intersection line ID            |
| `node_pair_id`         | `TEXT NOT NULL` "`REFERENCES osm.node_pairs (node_pair_id)`"                | Intersected node_pair           |
| `track_node`           | `UUID NOT NULL UNIQUE` "`REFERENCES track.track_nodes (node_id)`"           | Track node for the georef point |

### Table `georef.closest_point`
Declares a georef point at the point along the node_pair which is closest to the specified OSM node.

`PRIMARY KEY (osm_node, node_pair_id)`

| Field          | Type                                                              | Description                               |
|----------------|-------------------------------------------------------------------|-------------------------------------------|
| `osm_node`     | `TEXT NOT NULL UNIQUE` "`REFERENCES osm.osm_raw_nodes (id)`"      | OSM which the georef point is closest to  |
| `node_pair_id` | `TEXT NOT NULL` "`REFERENCES osm.node_pairs (node_pair_id)`"      | Node pair to place the georef point along |
| `track_node`   | `UUID NOT NULL UNIQUE` "`REFERENCES track.track_nodes (node_id)`" | Track node for the georef point           |

### Table `georef.force_auto_node_percentage_map_source`
Force's the percentage finder algorithm to pull the specified fragment's length from the specified map. Useful if a 
fragment appears on multiple map scales.

| Field         | Type                                                                           | Description                                  |
|---------------|--------------------------------------------------------------------------------|----------------------------------------------|
| `fragment_id` | `UUID NOT NULL PRIMARY KEY` "`REFERENCES track.track_fragments (fragment_id)`" | Fragment ID                                  |
| `map_id`      | `TEXT NOT NULL` "`REFERENCES maps.maps (map_id)`"                              | The map to source the fragment's length from |

### Table `georef.force_fragment_trace_length`
Overrides the length of the fragment on the traced map.

| Field             | Type                                                                           | Description                                                  |
|-------------------|--------------------------------------------------------------------------------|--------------------------------------------------------------|
| `fragment_id`     | `UUID NOT NULL PRIMARY KEY` "`REFERENCES track.track_fragments (fragment_id)`" | Fragment ID                                                  |
| `length_override` | `DOUBLE PERCISION NOT NULL`                                                    | The length (in map units of the traced map) for the fragment |
