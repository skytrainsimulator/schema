/*
 * SkytrainSim Track Schema
 * Copyright (C) 2025 SkytrainSim contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 */

-- This script is to be run with the working directory where output is desired.


\pset format csv
\pset null 'NULL'

SELECT * FROM track.stations ORDER BY station_id;
\g track/stations.csv

SELECT * FROM track.station_zones ORDER BY zone_id;
\g track/station_zones.csv

SELECT * FROM track.station_platforms ORDER BY zone_id, platform_id;
\g track/station_platforms.csv

SELECT * FROM track.vccs ORDER BY vcc_id;
\g track/vccs.csv

SELECT * FROM track.comm_loops ORDER BY vcc_id, loop_id;
\g track/comm_loops.csv

SELECT * FROM track.substations ORDER BY substation_id;
\g track/substations.csv

SELECT * FROM track.power_blocks ORDER BY pb_id;
\g track/power_blocks.csv

SELECT * FROM track.track_nodes ORDER BY node_id;
\g track/track_nodes.csv

SELECT * FROM track.tracks ORDER BY track_id;
\g track/tracks.csv

SELECT * FROM track.track_sections ORDER BY ts_id;
\g track/track_sections.csv

SELECT * FROM track.track_fragments ORDER BY ts_id, fragment_id;
\g track/track_fragments.csv

SELECT * FROM track.switches ORDER BY switch_type, switch_id;
\g track/switches.csv

SELECT * FROM track.atc_markers ORDER BY marker_id;
\g track/atc_markers.csv

SELECT * FROM track.reentry_points ORDER BY reentry_id;
\g track/reentry_points.csv

SELECT * FROM track.substation_sources ORDER BY substation_id, source_id;
\g track/substation_sources.csv

SELECT * FROM track.electrical_connections ORDER BY connection_id;
\g track/electrical_connections.csv



SELECT * FROM maps.styles ORDER BY style_id;
\g maps/styles.csv

SELECT * FROM maps.line_styles ORDER BY style_id, line_type, color_id;
\g maps/line_styles.csv

SELECT * FROM maps.switch_styles ORDER BY style_id, switch_type;
\g maps/switch_styles.csv

SELECT * FROM maps.auto_guide_lines ORDER BY style_id, guideline_id;
\g maps/auto_guide_lines.csv

SELECT * FROM maps.maps ORDER BY map_id;
\g maps/maps.csv

SELECT * FROM maps.guide_lines ORDER BY map_id, guideline_id;
\g maps/guide_lines.csv

SELECT * FROM maps.track_nodes ORDER BY map_id, node_id;
\g maps/track_nodes.csv

SELECT * FROM maps.track_fragments ORDER BY map_id, fragment_id;
\g maps/track_fragments.csv

SELECT * FROM maps.substation_markers ORDER BY map_id, substation_id;
\g maps/substation_markers.csv

SELECT * FROM maps.substation_sources ORDER BY map_id, source_id;
\g maps/substation_sources.csv

SELECT * FROM maps.electrical_connections ORDER BY map_id, connection_id;
\g maps/electrical_connections.csv

SELECT * FROM maps.reentry_points ORDER BY map_id, reentry_id;
\g maps/reentry_points.csv

SELECT * FROM maps.atc_markers ORDER BY map_id, marker_id;
\g maps/atc_markers.csv



SELECT * FROM georef.map_scale_groups ORDER BY scale_key;
\g georef/map_scale_groups.csv

SELECT * FROM georef.loops_linked_nodes ORDER BY track_node, osm_node;
\g georef/loops_linked_nodes.csv

SELECT * FROM georef.georef_nodes ORDER BY track_node, osm_node;
\g georef/georef_nodes.csv

SELECT * FROM georef.intersection_lines ORDER BY intersection_line_id;
\g georef/intersection_lines.csv

SELECT * FROM georef.intersection_cross_node_pairs ORDER BY intersection_line_id, node_pair_id;
\g georef/intersection_cross_node_pairs.csv

SELECT * FROM georef.closest_point ORDER BY osm_node, node_pair_id;
\g georef/closest_point.csv

SELECT * FROM georef.force_auto_node_percentage_map_source ORDER BY fragment_id;
\g georef/force_auto_node_percentage_map_source.csv

SELECT * FROM georef.force_fragment_trace_length ORDER BY fragment_id;
\g georef/force_fragment_trace_length.csv
