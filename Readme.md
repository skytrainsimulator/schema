# Skytrain Technical Map - Schema

This schema is intended to map out the technical details of the guideway for the Vancouver Skytrain Millennium & Expo 
line to a sufficient degree to simulate automated train operations. This schema is **not** intended as a wayfinding or 
schedule viewing tool.

This schema is written for PostgreSQL v14 with PostGIS. Entities are split across several schemas to naturally group 
them together. Each schema is defined in a separate file, named for their schema. A notable exception is 
`editing-tools.sql`, which contains add-on functions only intended for human usage to aid with data hand editing.

Most of the core data is contained within [`track`](#schema-track). This schema acts as the single point of truth for all non-rendering 
data, and should have sufficient info contained to completely simulate automatic train operations. To display this data, 
the [`maps`](#schema-maps) schema contains layout information for rendering this data. 

- - -

## Notes
Most tables contained in this database schema have column `notes TEXT DEFAULT NULL`. This column is intended for notes 
about the entity, and is only intended for human consumption. This column is not noted in table documentation in this Readme.

- - -

## Schema `track`
### Color
Many tables in this schema have a `color INT NOT NULL` column. This is the equivalent of running a graph coloring 
algorithm over the table - no entity will touch any entity of the same type with the same `color` value. The column 
typically contains ints `0 <= color <= 5`, which can then be mapped to a proper color as desired for rendering.

### Track directions & identifiers
The mainline typically has 2 tracks, defined as inbound (`IB`) & outbound (`OB`). The inbound track is defined as the 
track primarily used for train movement towards downtown (Waterfront & VCC-Clark stations), while outbound is for 
movement away. Similarly, at any point on the mainline, a vehicle may be pointed one of two directions, `0` & `1`. The 
`0` direction is defined as towards downtown, `1` away.

As the track layout is rather-infamously a "pretzel" in that a train can travel from Waterfront to VCC-Clark (or vice 
versa) without stopping, reversing, or leaving the mainline, there is a "guideway direction reversal point". This is 
located on the Sapperton side of the New Westminster tunnel & is marked with radio channel change signs. Travelling 
towards either side of the sign is travelling in the `1` direction, and at the sign the `IB` & `OB` track definitions swap.

### Enum Type `track.track_side`
*This concept is introduced by this schema, and is not an official BCRTC concept*

Possible values: `left`, `right`. Denoted when facing the `1` direction.

### Table `track.stations`
Represents a passenger station. A station must have one or more child station zones, each of which must have one or more 
station platforms.

| Field        | Type                        | Description                                                                                      |
|--------------|-----------------------------|--------------------------------------------------------------------------------------------------|
| `station_id` | `TEXT NOT NULL PRIMARY KEY` | The internal ID of the station. Typically a 2-character pneumonic.                               |
| `full_name`  | `TEXT NOT NULL`             | The full, common name of the station                                                             |
| `gtfs_id`    | `TEXT`                      | The [GTFS `stop_id`](https://gtfs.org/documentation/schedule/reference/#stopstxt) of the station |

### Table `track.station_zones`
Represents a logical "station zone" where trains can be routed to. This may be contained in a `station` with a platform, 
or a virtual-only stopping zone.

A station zone may have a parent station, and must have one or more child track fragments. These fragments must be 
contiguous and non-branching.

| Field        | Type                                          | Description                                                                                           |
|--------------|-----------------------------------------------|-------------------------------------------------------------------------------------------------------|
| `zone_id`    | `TEXT NOT NULL PRIMARY KEY`                   | The internal ID of the station zone. Typically a 3-character pneumonic                                |
| `station_id` | `TEXT REFERENCES track.stations (station_id)` | The ID of the parent station                                                                          |
| `gtfs_id`    | `TEXT`                                        | The [GTFS `stop_id`](https://gtfs.org/documentation/schedule/reference/#stopstxt) of the station zone |

### Table `track.station_platforms`
Represents a physical platform where passengers may board stopped trains. A station zone may have 0, 1, or 2 platforms. 
All station zones contained within a station must have at least 1 platform.

`PRIMARY KEY (zone_id, platform_id)`

| Field         | Type                                                     | Description                                                    |
|---------------|----------------------------------------------------------|----------------------------------------------------------------|
| `zone_id`     | `TEXT NOT NULL REFERENCES track.station_zones (zone_id)` | The parent station zone of this platform                       |
| `platform_id` | `TEXT NOT NULL`                                          | The passenger-facing ID of this platform. Typically an integer |
| `track_side`  | `track.track_side NOT NULL`                              | The side of the track this platform is located on              |

### Table `track.vccs`
Represents a VCC (Vehicle Control Computer). Each VCC is responsible for a different geographic region of tracks (noted 
in the `notes`) & has 1 or more child communication loops.

| Field    | Type                       | Description            |
|----------|----------------------------|------------------------|
| `vcc_id` | `INT NOT NULL PRIMARY KEY` | The ID of the VCC      |
| `color`  | `INT NOT NUL`              | [Entity Color](#color) |

### Table `track.comm_loops`
Represents a communication loop laid in the trackbed. Each comm loop has a parent VCC, and 1 or more child track limits. 
A loop is referred to by both it's VCC and ID, typically in format `L<V>-<I>` i.e. `L4-2` would be loop 2 in VCC 4.

`PRIMARY KEY (loop_id, vcc_id)`

| Field     | Type                                          | Description                                            |
|-----------|-----------------------------------------------|--------------------------------------------------------|
| `loop_id` | `INT NOT NULL`                                | The ID of the loop. Unique only within the parent VCC. |
| `vcc_id`  | `INT NOT NULL REFERENCES track.vccs (vcc_id)` | The ID of the parent VCC                               |
| `color`   | `INT NOT NULL`                                | [Entity Color](#color)                                 |

### Table `track.substations`
Represents a propulsion power substation (PPS). Marked on guideway signage as the ID with a `Z` suffix i.e. `LHZ` would 
be substation with ID `LH`.

A substation must have at least one child substation source, and may have child electrical connections and power blocks.

| Field           | Type                        | Description                       |
|-----------------|-----------------------------|-----------------------------------|
| `substation_id` | `TEXT NOT NULL PRIMARY KEY` | The ID of the substation          |
| `full_name`     | `TEXT`                      | The common name of the substation |

### Table `track.power_blocks`
*This concept is introduced by this schema, and is not an official BCRTC concept*

Represents an abstraction of electrical connectivity. A power block may be either physically tied to a track fragment, 
or virtually within a substation. A power block is not capable of being subdivided without significant manual work, thus 
an entire block can be taken to be either powered or unpowered. More advanced electronic properties like voltage, rated 
power, polarity, etc. are not included in this abstraction; a power block can only either be energized or de-energized.

| Field                     | Type                                                | Description                                                                                                    |
|---------------------------|-----------------------------------------------------|----------------------------------------------------------------------------------------------------------------|
| `pb_id`                   | `UUID NOT NULL PRIMARY KEY`                         | The ID of the power block                                                                                      |
| `color`                   | `INT NOT NULL`                                      | [Entity Color](#color)                                                                                         |
| `encompassing_substation` | `TEXT REFERENCES track.substations (substation_id)` | If present, this block is only contained within the referenced substation i.e. not directly tied to any tracks |

### Table `track.track_nodes`
*This concept is introduced by this schema, and is not an official BCRTC concept*

Represents a single point location on the guideway. On its own, this table contains no additional information.

A node must have at least 1 connected track fragments. If the node is also a switch, it must have exactly 3 connected 
track fragments; otherwise it must have at most 2 connected track fragments. A node may never have 4 or more connected 
track fragments.

| Field     | Type                        | Description        |
|-----------|-----------------------------|--------------------|
| `node_id` | `UUID NOT NULL PRIMARY KEY` | The ID of the node |

### Table `track.tracks`
Represents a logical track (or track limit). Sometimes referred to as `Tk <id>` i.e. `Tk 112` would be track limit 112

Control or automated safety systems may "close" tracks to prevent trains from routing into them. As trains move, they 
"scan into" or reserve tracks they currently occupy or are about to occupy. Should a track be closed, any trains 
currently scanned into the track will emergency brake.

When at least 1 train is scanned into a given track, this track has a direction assigned to it which is the only 
direction of movement permitted within the track (to prevent trains getting into head-on collisions). To reverse a track, 
all trains scanned into it must be stationary. A notable exception to this is the handful of "bidirectional" tracks 
within OMC1, within which trains can be freely routed in either direction.

A track will have exactly one parent comm loop, and one or more child track sections. A track will *mostly* be a 
straight stretch of physical rail which does not branch. However, track section border imprecision at switches means a 
track limit may branch a tiny bit at either end.

`FOREIGN KEY (vcc_id, loop_id) REFERENCES track.comm_loops (vcc_id, loop_id)`

| Field              | Type                                      | Description                                 |
|--------------------|-------------------------------------------|---------------------------------------------|
| `track_id`         | `INT NOT NULL PRIMARY KEY`                | The ID of the track limit                   |
| `vcc_id`           | `INT NOT NULL REFERENCES track.vccs (id)` | The ID of the VCC owning the comm loop      |
| `loop_id`          | `INT NOT NULL`                            | The ID of the comm loop covering this track |
| `is_bidirectional` | `BOOLEAN NOT NULL`                        | If this is a bidirectional track            |
| `color`            | `INT NOT NULL`                            | [Entity Color](#color)                      |

### Table `track.track_sections`
Represents a physical track section. A track section is a physical stretch of rail (typically several meters long) which 
trains use for approximate location. The borders of a track section will have the comm loop flip sides (trains can detect 
this polarity switch). Often referred to as `TS<id>` i.e. `TS1045` would be track section 1045.

Most track sections are a straight piece of non-branching track. However, switches are more complicated. As a track 
limit is defined by the space between comm loop polarity flips, and there's no single point where a switch branches, 
track sections may sometimes branch at switches. The layout of this will vary per switch.

Track section IDs increase in the 0 direction. While the mainline only uses simple integer track section IDs, OMC1 track 
sections appear to have 2 integer IDs. These are currently represented as `<high-int>-<low-int>`. It is suspected this 
is because of the loop structure of OMC1 making directionality unclear.

A track section will have exactly one parent track, and one or more child track fragments.

| Field       | Type                                              | Description                                                              |
|-------------|---------------------------------------------------|--------------------------------------------------------------------------|
| `ts_id`     | `TEXT NOT NULL PRIMARY KEY`                       | The ID of the track section                                              |
| `track_id`  | `INT NOT NULL REFERENCES track.tracks (track_id)` | The ID of the owning track limit                                         |
| `max_speed` | `INT NOT NULL`                                    | The maximum permitted speed in the track section, in Kilometers per hour |
| `color`     | `INT NOT NULL`                                    | [Entity Color](#color)                                                   |

### Table `track.track_fragments`
*This concept is introduced by this schema, and is not an official BCRTC concept*

Represents a physical stretch of rail. A track fragment will never branch, and has all properties contiguous for the 
fragment's entire length. A track fragment connects 2 track nodes, and has a length.

A track fragment may have a parent track section. If it does not, then the track is outside of ATC territory and only 
trains under manual control may move in it. 

A track fragment may have a parent power block. If it does not, then only vehicles with an onboard power source may 
move in it.

All track fragments with a parent track section *should* also have a parent power block. However, small power gaps (a 
few meters or less) can be bridged by trains.

A track fragment may have a parent station zone.

| Field         | Type                                                   | Description                                                          |
|---------------|--------------------------------------------------------|----------------------------------------------------------------------|
| `fragment_id` | `UUID NOT NULL PRIMARY KEY`                            | The ID of the track fragment                                         |
| `ts_id`       | `TEXT REFERENCES track.track_sections (id)`            | The ID of the parent track section                                   |
| `length`      | `FLOAT NOT NULL`                                       | The physical length of the track fragment, in meters                 |
| `node_u`      | `UUID NOT NULL REFERENCES track.track_nodes (node_id)` | The ID of 1 adjacent node. Typically the `0` side.                   |
| `node_v`      | `UUID NOT NULL REFERENCES track.track_nodes (node_id)` | The ID of another adjacent node. Typically the `1` side.             |
| `pb_id`       | `UUID REFERENCES track.power_blocks (pb_id)`           | The ID of the power block powering this track fragment's power rails |
| `zone_id`     | `TEXT REFERENCES track.station_zones (zone_id)`        | The ID of the station zone this track fragment is in                 |
| `color`       | `INT NOT NULL`                                         | [Entity Color](#color)                                               |

### Enum Type `track.switch_turnout_side`
Possible values: `left`, `right`, `wye`. Denotes which side of the switch branches off from the straight track, when 
facing the switch from the switch from the common side. `wye` means both sides of the switch diverge (i.e. the switch 
from above resembles a `Y`).

### Enum Type `track.switch_type`
Possible values: `direct`, `field`, `manual`. Denotes what kind of control system is used for the switch. Direct control 
(also sometimes called "dual control") switches are motorized and controllable from either VCCs or locally at the switch. 
Field control switches are motorized but only controllable locally at the switch, but their state is still monitorable 
from control computers. Manual control switches have no electronics or motors and can only be operated by hand locally. 
Switch types are typically abbreviated to their first initial, then suffixed by a `C` i.e. `DC` is a direct control switch. 

### Function `track.switch_type_as_display`
`track.switch_type_as_display(track.switch_type) RETURNS TEXT`

Maps the given switch type to its respective abbreviation: `direct` -> `DC`, `field` -> `FC`, `manual` -> `MC`.

### Table `track.switches`
Represents a track switch. A switch is identified by both it's type abbreviation and ID i.e. `DC45` is a `direct` 
control switch with ID 45.

A switch has a parent node where the split occurs, and 3 parent track fragments representing the 3 branches of the 
switch. The 3 parent fragments must all have the switch node as one of their fragment nodes. A node may have at most 
one switch.

`PRIMARY KEY (switch_id, switch_type)`

| Field             | Type                                                           | Description                                                               |
|-------------------|----------------------------------------------------------------|---------------------------------------------------------------------------|
| `switch_id`       | `INT NOT NULL`                                                 | The numerical ID of the switch. Unique only within the given switch type. |
| `node_id`         | `UUID NOT NULL UNIQUE REFERENCES track.track_nodes (node_id)`  | The ID of the node where this switch branches                             |
| `switch_type`     | `track.switch_type NOT NULL`                                   | The type of the switch                                                    |
| `turnout_side`    | `track.switch_turnout_side NOT NULL`                           | The turnout side of the switch                                            |
| `common_fragment` | `UUID NOT NULL REFERENCES track.track_fragments (fragment_id)` | The ID of the fragment on the common side of the switch                   |
| `left_fragment`   | `UUID NOT NULL REFERENCES track.track_fragments (fragment_id)` | The ID of the fragment on the left branch of the switch                   |
| `right_fragment`  | `UUID NOT NULL REFERENCES track.track_fragments (fragment_id)` | The ID of the fragment on the right branch of the switch                  |

### Table `track.atc_markers`
Represents an ATC marker. A marker is point location where trains may be routed, found outside of station zones. It is 
possible all ATC markers are internally station zones; this will need to be confirmed.

An ATC marker has a parent node representing its location. This node must not be a switch or the end of a physical track 
(i.e. exactly 2 fragments must reference the node).

| Field       | Type                                                               | Description                                                           |
|-------------|--------------------------------------------------------------------|-----------------------------------------------------------------------|
| `node_id`   | `UUID NOT NULL PRIMARY KEY REFERENCES track.track_nodes (node_id)` | The ID of the node for the location of this marker                    | 
| `marker_id` | `TEXT UNIQUE NOT NULL`                                             | The internal ID of the ATC marker. Typically a 3-character pneumonic. |

### Table `track.reentry_points`
Represents a reentry point. A reentry point is a point on the border of a communication loop where timed-out trains can 
be "re-entered" into automatic control. A reentry point is identified by its reentry id in format `RE <ID>` i.e. `RE 423` 
is reentry point 423. The leading digit of the reentry ID is the parent VCC i.e. `RE 423` is within VCC 4. 

Reentry points are usually found in double-sided pairs. When passing a reentry point sign with the text facing the 
vehicle, the vehicle is passing the reentry point identified on that sign.

A reentry point has a parent VCC, communication loop, track fragment, and track node. This fragment must have a track 
section whose track limit is contained within the vcc & comm loop of the reentry point. The node must be one of the 
nodes of the fragment, on the border of the comm loop, and not a switch or track end (i.e. must have exactly 2 track 
fragments connected to the node).  
The fragment is used to identify the direction of the reentry point.

`FOREIGN KEY (vcc_id, loop_id) REFERENCES track.comm_loops (vcc_id, loop_id)`

| Field         | Type                                                           | Description                                                           |
|---------------|----------------------------------------------------------------|-----------------------------------------------------------------------|
| `reentry_id`  | `INT NOT NULL PRIMARY KEY`                                     | The ID of the reentry point. Leading digit must be the VCC ID.        |
| `vcc_id`      | `INT NOT NULL REFERENCES track.vccs (vcc_id)`                  | The ID of the owning VCC                                              |
| `loop_id`     | `INT NOT NULL`                                                 | The ID of the comm loop within the VCC this reentry point enters into |
| `node_id`     | `node_id UUID NOT NULL REFERENCES track.track_nodes (node_id)` | The ID of the node where this reentry point is located                |
| `fragment_id` | `UUID NOT NULL REFERENCES track.track_fragments (fragment_id)` | The ID of the fragment containing the referenced comm loop            |

### Table `track.substation_sources`
*This concept is introduced by this schema, and is not an official BCRTC concept*

Represents an abstract power feed into a substation from the wide power grid. Sources can be assumed to be always 
energized except for grid power outages. Control has no direct ability to turn off a substation source. Like the power 
block abstraction, sources have no concept of advanced electrical concepts; they can only be energized or de-energized.

Substation sources must have a parent substation, and a child power block supplied by this source.

| Field           | Type                                                         | Description                                       |
|-----------------|--------------------------------------------------------------|---------------------------------------------------|
| `source_id`     | `UUID NOT NULL PRIMARY KEY`                                  | The ID of the substation source                   |
| `substation_id` | `TEXT NOT NULL REFERENCES track.substations (substation_id)` | The ID of the owning substation                   |
| `fed_block`     | `UUID NOT NULL REFERENCES track.power_blocks (pb_id)`        | The ID of the power block supplied by this source |

### Enum Type `track.electrical_connection_type`
Possible values: `'electrical_switch`, `transfer_switch`, `cross_connect_switch`, `breaker`, `jumper`. Denotes the type 
of electrical connection.

`electrical_switch`, `transfer_switch`, and `cross_connect_switch` are all physically similar (large, guideway-side 
electrical connections), the main difference is what they connect. `electrical_switch`es simply connect 2 power blocks 
of nearby track. `transfer_switch`es are used to supply power to an adjacent side track from a mainline track. 
`cross_connect_switch`es are used to connect inbound & outbound tracks.

`breaker`s are an abstraction for all kinds of electrical switches found within substations. `jumpers` are simple 
removable wires connecting 2 power blocks.

### Table `track.electrical_connections`
Represents a breakable connection between 2 power blocks. A connection may be normally open, and may be motorized. A 
motorized electrical connection can be remotely controlled by control computers; non-motorized connections can only be 
locally actuated by power techs.

Electrical connections of all types other than `breaker`s may only be switched when both power blocks are de-energized. 
Electrical connections of type `jumper` cannot be motorized. Since `jumper`s are wires physically bolted to power rails, 
they can only be removed when significant safety precautions have been taken. As such, they are essentially permanently 
in their default state, and only substantial incidents will warrant jumpers being (dis)connected.

An electrical connection may have an encompassing substation. If present, this connection is physically within the 
substation building.

| Field                     | Type                                                  | Description                                                                 |
|---------------------------|-------------------------------------------------------|-----------------------------------------------------------------------------|
| `connection_id`           | `TEXT NOT NULL PRIMARY KEY`                           | The ID of the electrical connection                                         |
| `block_u`                 | `UUID NOT NULL REFERENCES track.power_blocks (pb_id)` | One connected power block. Typically on the `0` side                        |
| `block_v`                 | `UUID NOT NULL REFERENCES track.power_blocks (pb_id)` | One connected power block. Typically on the `1` side                        |
| `connection_type`         | `track.electrical_connection_type NOT NULL`           | The type of the electrical connection                                       |
| `encompassing_substation` | `TEXT REFERENCES track.substations (substation_id)`   | The substation this electrical connection is contained within               |
| `normally_open`           | `BOOLEAN NOT NULL`                                    | Whether this electrical connection is normally open (normally disconnected) |
| `motorized`               | `BOOLEAN NOT NULL`                                    | Whether this electrical connection is motorized (remotely controllable)     |

- - -
## File `track_checks.sql`
This file contains a set of validation checks to ensure the `track` data meets various constraints not easily 
expressible otherwise. These checks are not all-encompassing, but they do a decent baseline.

- - -
## File `power_graphvis.sql`
This file generates a [graphvis](https://graphviz.org/) graph of the power network to STDOUT, which can then be input 
into something like [graphvis online](https://dreampuf.github.io/GraphvizOnline/?engine=neato). The `neato` engine 
appears to give the best output, `dot` is also acceptable.

Entities encompassed in a substation have a blue outline. Substation sources are represented by blue stars.

Power blocks are dots; electrical connections are labeled with their ID. Greyed-in electrical connections are motorized. 
Breakers are rectangles, electrical switches are houses, transfer switches are trapezoids, cross-connect switches are 
diamonds, and jumpers are circles. Normally open connections are dotted while normally closed connections are solid.

- - -
## Schema `maps`
**Depends on:** [`track`](#schema-track)

**Requires extension:** `postgis` 

Contains information used to render maps of the `track` data. As many maps will not be 100% to scale, the point of truth 
for fragment length remains in `track.track_fragments (length)`.

Each map has an associated `style`, a helper for mapping `track` entities' `color` attribute to an actual RGB color. 
However, much of the layer styling is still up to the rendering application to handle.

Different maps will aim to show different subsets of information & track areas; as such these tables may not contain all 
entities for all maps.

All the views in this schema will have a "qgis ID" - a unique stable ID for view rows. This is added as qGIS requires all 
entries have a single unique ID property. This ID shouldn't be used for anything else. 

### Table `maps.styles`
Represents a map style. Contains no information on its own.

A map style may have 0 or more child `line_styles`, `switch_styles`, `auto_guide_lines`. 

| Field      | Type                        | Description         |
|------------|-----------------------------|---------------------|
| `style_id` | `TEXT NOT NULL PRIMARY KEY` | The ID of the style |

### Table `maps.line_styles`
Maps a `color` of a given line type to an RGB color. Every `line_style` has a parent style, and an int `color`. Neither 
of these have any constraints.

`PRIMARY KEY (style_id, line_type, color_id)`

| Field       | Type                                              | Description                                  |
|-------------|---------------------------------------------------|----------------------------------------------|
| `style_id`  | `TEXT NOT NULL REFERENCES maps.styles (style_id)` | The ID of the owning style                   |
| `line_type` | `TEXT NOT NULL`                                   | The type of line this line_style is for      |
| `color_id`  | `INT NOT NULL`                                    | The integer `color` type to match            |
| `color`     | `TEXT NOT NULL`                                   | The RGB color to map to, in format `#RRGGBB` |

### Table `maps.switch_styles`
Maps a switch type to an RGB color. Every `switch_style` has a parent style.

`PRIMARY KEY (style_id, switch_type)`

| Field         | Type                                              | Description                                  |
|---------------|---------------------------------------------------|----------------------------------------------|
| `style_id`    | `TEXT NOT NULL REFERENCES maps.styles (style_id)` | The ID of the owning style                   |
| `switch_type` | `track.switch_type NOT NULL`                      | The type of switch this style is for         |
| `color`       | `TEXT NOT NULL`                                   | The RGB color to map to, in format `#RRGGBB` |

### Table `maps.auto_guide_lines`
An offset from `track_fragments` to automatically render a guideline for aiding in manual map drawing.

`PRIMARY KEY (style_id, guideline_id)`

| Field          | Type                                              | Description                                                                  |
|----------------|---------------------------------------------------|------------------------------------------------------------------------------|
| `style_id`     | `TEXT NOT NULL REFERENCES maps.styles (style_id)` | The ID of the owning style                                                   |
| `guideline_id` | `TEXT NOT NULL`                                   | The ID of the guideline                                                      |
| `line_offset`  | `DOUBLE PERCISION NOT NULL`                       | The offset from the fragment to render the guideline. Uses the map CRS units |

### Table `maps.maps`
Represents a map. A map has an associated coordinate reference system and a parent style.

| Field      | Type                                              | Description                                                                  |
|------------|---------------------------------------------------|------------------------------------------------------------------------------|
| `srid`     | `INT NOT NULL`                                    | The SRID of the coordinate reference system used by this map. `0` for no CRS |
| `map_id`   | `TEXT NOT NULL PRIMARY KEY`                       | The ID of the map                                                            |
| `style_id` | `TEXT NOT NULL REFERENCES maps.styles (style_id)` | The ID of the owning style                                                   |

### Table `maps.guide_lines`
A guideline. Used only for aiding in manual map drawing.

`PRIMARY KEY (map_id, guideline_id)`

| Field          | Type                                          | Description             |
|----------------|-----------------------------------------------|-------------------------|
| `map_id`       | `TEXT NOT NULL REFERENCES maps.maps (map_id)` | The owning map          |
| `guideline_id` | `TEXT NOT NULL`                               | The ID of the guideline |
| `geom`         | `geometry(LINESTRING) NOT NULL`               | The guideline           |

### Table `maps.track_nodes`
The location on the given map to render the specified track node. Track nodes without an entry for a given map will not 
be rendered on that map.

`PRIMARY KEY (map_id, node_id)`

| Field     | Type                                                   | Description    |
|-----------|--------------------------------------------------------|----------------|
| `map_id`  | `TEXT NOT NULL REFERENCES maps.maps (map_id)`          | The owning map |
| `node_id` | `UUID NOT NULL REFERENCES track.track_nodes (node_id)` | The track node |
| `geom`    | `geometry(POINT) NOT NULL`                             | The node point |

### Table `maps.track_fragments`
Track fragments to render on the specified map. Fragments will be drawn as a straight line between its 2 nodes, unless 
additional points are specified. These additional points will be joined into a linestring starting from the fragment 
`node_u`, then the point list, then `node_v`. Fragments without both it's `node_u` and `node_v` on the map will not be rendered.

`PRIMARY KEY (map_id, fragment_id)`

| Field         | Type                                                           | Description            |
|---------------|----------------------------------------------------------------|------------------------|
| `map_id`      | `TEXT NOT NULL REFERENCES maps.maps (map_id)`                  | The owning map         |
| `fragment_id` | `UUID NOT NULL REFERENCES track.track_fragments (fragment_id)` | The track fragment     |
| `geom`        | `geometry(POINT)[] NOT NULL`                                   | Additional line points |

### Table `maps.substation_markers`
A point marker for substations. On some map styles this may be the only marking for substations, on others this may be a 
text label for a cluster of substation breakers.

`PRIMARY KEY (map_id, substation_id)`

| Field           | Type                                                         | Description           |
|-----------------|--------------------------------------------------------------|-----------------------|
| `map_id`        | `TEXT NOT NULL REFERENCES maps.maps (map_id)`                | The owning map        |
| `substation_id` | `TEXT NOT NULL REFERENCES track.substations (substation_id)` | The marked substation |
| `geom`          | `geometry(POINT) NOT NULL`                                   | The node point        |

### Table `maps.substation_sources`
A point marker for a substation source. This should only be used on maps which aim to show the internal layout of substations.

`PRIMARY KEY (map_id, source_id)`

| Field       | Type                                                            | Description                 |
|-------------|-----------------------------------------------------------------|-----------------------------|
| `map_id`    | `TEXT NOT NULL REFERENCES maps.maps (map_id)`                   | The owning map              |
| `source_id` | `UUID NOT NULL REFERENCES track.substation_sources (source_id)` | The marked source           |
| `geom`      | `geometry(POINT) NOT NULL`                                      | The source point            |
| `rotation`  | `FLOAT NOT NULL`                                                | The rotation of this marker |

### Table `maps.electrical_connections`
A point marker for electrical connections. Maps may wish to not render all types of connections (i.e. jumpers).

`PRIMARY KEY (map_id, connection_id)`

| Field           | Type                                                                    | Description                 |
|-----------------|-------------------------------------------------------------------------|-----------------------------|
| `map_id`        | `TEXT NOT NULL REFERENCES maps.maps (map_id)`                           | The owning map              |
| `connection_id` | `TEXT NOT NULL REFERENCES track.electrical_connections (connection_id)` | The marked connection       |
| `geom`          | `geometry(POINT) NOT NULL`                                              | The connection point        |
| `rotation`      | `FLOAT NOT NULL`                                                        | The rotation of this marker |

### Table `maps.reentry_points`
A point marker for reentry points.

`PRIMARY KEY (map_id, reentry_id)`

| Field        | Type                                                        | Description                 |
|--------------|-------------------------------------------------------------|-----------------------------|
| `map_id`     | `TEXT NOT NULL REFERENCES maps.maps (map_id)`               | The owning map              |
| `reentry_id` | `INT NOT NULL REFERENCES track.reentry_points (reentry_id)` | The marked reentry point    |
| `geom`       | `geometry(POINT) NOT NULL`                                  | The reentry point           |
| `rotation`   | `FLOAT NOT NULL`                                            | The rotation of this marker |

### Table `maps.atc_maarkers`
A point marker for ATC markers.

`PRIMARY KEY (map_id, marker_id)`

| Field       | Type                                                     | Description           |
|-------------|----------------------------------------------------------|-----------------------|
| `map_id`    | `TEXT NOT NULL REFERENCES maps.maps (map_id)`            | The owning map        |
| `marker_id` | `TEXT NOT NULL REFERENCES track.atc_markers (marker_id)` | The marked ATC marker |
| `geom`      | `geometry(POINT) NOT NULL`                               | The marker point      |

### View `maps.combined_track_fragments`
Combines `maps.track_nodes` & `maps.track_fragments` into a `LINESTRING` for rendering, and calculates the color for the 
fragment from `line_styles` with line type `track_fragments` (`#FF00FF` if no color found). For a fragment to be present, both of its nodes must be 
present in `maps.track_nodes`, and the fragment must be present in `maps.track_fragments`. 

| Field         | Type                                                               | Description         |
|---------------|--------------------------------------------------------------------|---------------------|
| `ctf_id`      | `TEXT NOT NULL` "`UNIQUE`"                                         | qGIS ID             |
| `map_id`      | `TEXT NOT NULL` "`REFERENCES maps.maps (map_id)`"                  | Map ID              |
| `fragment_id` | `UUID NOT NULL` "`REFERENCES track.track_fragments (fragment_id)`" | Fragment ID         |
| `color`       | `TEXT NOT NULL`                                                    | Fragment RGB color  |
| `geom`        | `geometry(LINESTRING) NOT NULL`                                    | Fragment Linestring |

### View `maps.combined_track_sections`
Groups `maps.combined_track_fragments` by track section into a `MULTILINESTRING` for rendering, and calculates the color for the
track section from `line_styles` with line type `track_sections` (`#FF00FF` if no color found). This will only contain 
the fragments of the TS present in `maps.combined_track_fragments` for the given map.

| Field    | Type                                                        | Description        |
|----------|-------------------------------------------------------------|--------------------|
| `cts_id` | `TEXT NOT NULL` "`UNIQUE`"                                  | qGIS ID            |
| `map_id` | `TEXT NOT NULL` "`REFERENCES maps.maps (map_id)`"           | Map ID             |
| `ts_id`  | `TEXT NOT NULL` "`REFERENCES track.track_sections (ts_id)`" | Track section ID   |
| `color`  | `TEXT NOT NULL`                                             | TS RGB color       |
| `geom`   | `geometry(MULTILINESTRING) NOT NULL`                        | TS MultiLinestring |

### View `maps.combined_tracks`
Groups `maps.combined_track_sections` by track limit into a `MULTILINESTRING` for rendering, and calculates the color for the
track section from `line_styles` with line type `tracks` (`#FF00FF` if no color found). This will only contain
the TSs of the track present in `maps.combined_track_sections` for the given map.

| Field      | Type                                                  | Description           |
|------------|-------------------------------------------------------|-----------------------|
| `ct_id`    | `TEXT NOT NULL` "`UNIQUE`"                            | qGIS ID               |
| `map_id`   | `TEXT NOT NULL` "`REFERENCES maps.maps (map_id)`"     | Map ID                |
| `track_id` | `INT NOT NULL` "`REFERENCES track.tracks (track_id)`" | Track ID              |
| `color`    | `TEXT NOT NULL`                                       | Track RGB color       |
| `geom`     | `geometry(MULTILINESTRING) NOT NULL`                  | Track MultiLinestring |

### View `maps.combined_power_blocks`
Groups `maps.combined_track_fragments` by power block into a `MULTILINESTRING` for rendering, and calculates the color for the
track section from `line_styles` with line type `power_blocks` (`#FF00FF` if no color found). This will only contain
the fragments of the PB present in `maps.combined_track_fragments` for the given map.

| Field    | Type                                                      | Description        |
|----------|-----------------------------------------------------------|--------------------|
| `cpb_id` | `TEXT NOT NULL` "`UNIQUE`"                                | qGIS ID            |
| `map_id` | `TEXT NOT NULL` "`REFERENCES maps.maps (map_id)`"         | Map ID             |
| `pb_id`  | `UUID NOT NULL` "`REFERENCES track.power_blocks (pb_id)`" | Power block ID     |
| `color`  | `TEXT NOT NULL`                                           | PB RGB color       |
| `geom`   | `geometry(MULTILINESTRING) NOT NULL`                      | PB MultiLinestring |

### View `maps.combined_comm_loops`
Groups `maps.combined_track_fragments` by comm loop into a `MULTILINESTRING` for rendering, and calculates the color for the
track section from `line_styles` with line type `comm_loops` (`#FF00FF` if no color found). This will only contain
the fragments of the comm loop present in `maps.combined_track_fragments` for the given map.

"`FOREIGN KEY (vcc_id, loop_id) REFERENCES track.comm_loops (vcc_id, loop_id)`"

| Field               | Type                                              | Description               |
|---------------------|---------------------------------------------------|---------------------------|
| `ccl_id`            | `TEXT NOT NULL` "`UNIQUE`"                        | qGIS ID                   |
| `map_id`            | `TEXT NOT NULL` "`REFERENCES maps.maps (map_id)`" | Map ID                    |
| `vcc_id`            | `INT NOT NULL` "`REFERENCES track.vccs (vcc_id)`" | VCC ID                    |
| `loop_id`           | `INT NOT NULL`                                    | Comm loop ID              |
| `comm_loop_display` | `TEXT NOT NULL`                                   | `L<vcc_id>-<loop_id>`     |
| `color`             | `TEXT NOT NULL`                                   | Comm loop RGB color       |
| `geom`              | `geometry(MULTILINESTRING) NOT NULL`              | Comm loop MultiLinestring |

### View `maps.combined_station_zones`
Groups `maps.combined_track_fragments` by station zone into a `MULTILINESTRING` for rendering. This will only contain
the fragments of the station zone present in `maps.combined_track_fragments` for the given map.

| Field     | Type                                                         | Description          |
|-----------|--------------------------------------------------------------|----------------------|
| `csz_id`  | `TEXT NOT NULL` "`UNIQUE`"                                   | qGIS ID              |
| `map_id`  | `TEXT NOT NULL` "`REFERENCES maps.maps (map_id)`"            | Map ID               |
| `zone_id` | `TEXT NOT NULL` "`REFERENCES track.station_zones (zone_id)`" | Station zone ID      |
| `geom`    | `geometry(MULTILINESTRING) NOT NULL`                         | Zone MultiLinestring |

### View `maps.combined_auto_guide_lines`
Creates a `MULTILINESTRING` offset to `maps.combined_track_fragments` as configured in `maps.auto_guide_lines` for aiding in 
hand drawing.

| Field          | Type                                                                | Description               |
|----------------|---------------------------------------------------------------------|---------------------------|
| `cagl_id`      | `TEXT NOT NULL` "`UNIQUE`"                                          | qGIS ID                   |
| `map_id`       | `TEXT NOT NULL` "`REFERENCES maps.maps (map_id)`"                   | Map ID                    |
| `guideline_id` | `TEXT NOT NULL` "`REFERENCES maps.auto_guide_lines (guideline_id)`" | Guideline ID              |
| `geom`         | `geometry(MULTILINESTRING) NOT NULL`                                | Guideline MultiLinestring |

### View `maps.combined_switches`
Calculates a `POINT` position for switches from the `maps.track_nodes` entry for the switch node. Calculates a color 
from `switch_styles` (`#FF00FF` if no color found). Only switches with its node present in `maps.track_nodes` for the 
given map will be present.

| Field            | Type                                                       | Description                 |
|------------------|------------------------------------------------------------|-----------------------------|
| `cs_id`          | `TEXT NOT NULL` "`UNIQUE`"                                 | qGIS ID                     |
| `map_id`         | `TEXT NOT NULL` "`REFERENCES maps.maps (map_id)`"          | Map ID                      |
| `node_id`        | `UUID NOT NULL` "`REFERENCES track.track_nodes (node_id)`" | Switch node ID              |
| `switch_display` | `TEXT NOT NULL`                                            | `<switch_type>-<switch_id>` |
| `color`          | `TEXT NOT NULL`                                            | Switch RGB color            |
| `geom`           | `geometry(POINT) NOT NULL`                                 | Switch Point                |

- - -
## File `createPublishExport.sql`
This file dumps all tables to stable-order `.csv` files in the working directory; intended for publishing.
