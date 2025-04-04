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

CREATE SCHEMA IF NOT EXISTS maps;
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE maps.styles (
    style_id TEXT NOT NULL PRIMARY KEY,
    notes TEXT DEFAULT NULL
);

CREATE TABLE maps.line_styles (
    style_id TEXT NOT NULL REFERENCES maps.styles (style_id),
    line_type TEXT NOT NULL,
    color_id INT NOT NULL,
    color TEXT NOT NULL,
    PRIMARY KEY (style_id, line_type, color_id)
);

CREATE TABLE maps.switch_styles (
    style_id TEXT NOT NULL REFERENCES maps.styles (style_id),
    switch_type track.switch_type NOT NULL,
    color TEXT NOT NULL,
    PRIMARY KEY (style_id, switch_type)
);

CREATE TABLE maps.auto_guide_lines (
    style_id TEXT NOT NULL REFERENCES maps.styles (style_id),
    guideline_id TEXT NOT NULL,
    line_offset DOUBLE PRECISION NOT NULL,
    PRIMARY KEY (style_id, guideline_id)
);

CREATE TABLE maps.maps (
    srid INT NOT NULL,
    map_id TEXT NOT NULL PRIMARY KEY,
    style_id TEXT NOT NULL REFERENCES maps.styles (style_id),
    notes TEXT DEFAULT NULL
);

CREATE TABLE maps.guide_lines (
    guideline_id TEXT NOT NULL,
    map_id TEXT NOT NULL REFERENCES maps.maps (map_id) ON UPDATE CASCADE ON DELETE CASCADE,
    geom geometry(LINESTRING) NOT NULL,
    PRIMARY KEY (guideline_id, map_id)
);

CREATE TABLE maps.track_nodes (
    map_id TEXT NOT NULL REFERENCES maps.maps (map_id) ON UPDATE CASCADE ON DELETE CASCADE,
    node_id UUID NOT NULL REFERENCES track.track_nodes (node_id),
    geom geometry(POINT) NOT NULL,
    PRIMARY KEY (map_id, node_id)
);

CREATE TABLE maps.track_fragments (
    map_id TEXT NOT NULL REFERENCES maps.maps (map_id) ON UPDATE CASCADE ON DELETE CASCADE,
    fragment_id UUID NOT NULL REFERENCES track.track_fragments (fragment_id),
    geom geometry(POINT)[] NOT NULL,
    PRIMARY KEY (map_id, fragment_id)
);

CREATE TABLE maps.substation_markers (
    map_id TEXT NOT NULL REFERENCES maps.maps (map_id) ON UPDATE CASCADE ON DELETE CASCADE,
    substation_id TEXT NOT NULL REFERENCES track.substations (substation_id) ON UPDATE CASCADE ON DELETE CASCADE,
    geom geometry(POINT) NOT NULL,
    PRIMARY KEY (map_id, substation_id)
);

CREATE TABLE maps.substation_sources (
    map_id TEXT NOT NULL REFERENCES maps.maps (map_id) ON UPDATE CASCADE ON DELETE CASCADE,
    source_id UUID NOT NULL REFERENCES track.substation_sources (source_id) ON UPDATE CASCADE ON DELETE CASCADE,
    geom geometry(POINT) NOT NULL,
    rotation FLOAT NOT NULL DEFAULT 0,
    PRIMARY KEY (map_id, source_id)
);

CREATE TABLE maps.electrical_connections (
    map_id TEXT NOT NULL REFERENCES maps.maps (map_id) ON UPDATE CASCADE ON DELETE CASCADE,
    connection_id TEXT NOT NULL REFERENCES track.electrical_connections (connection_id) ON UPDATE CASCADE ON DELETE CASCADE,
    geom geometry(POINT) NOT NULL,
    rotation FLOAT NOT NULL DEFAULT 0,
    PRIMARY KEY (map_id, connection_id)
);

CREATE TABLE maps.reentry_points (
    map_id TEXT NOT NULL REFERENCES maps.maps (map_id) ON UPDATE CASCADE ON DELETE CASCADE,
    reentry_id INT NOT NULL REFERENCES track.reentry_points (reentry_id) ON UPDATE CASCADE ON DELETE CASCADE,
    geom geometry(POINT) NOT NULL,
    rotation FLOAT NOT NULL DEFAULT 0,
    PRIMARY KEY (map_id, reentry_id)
);

CREATE TABLE maps.atc_markers (
    map_id TEXT NOT NULL REFERENCES maps.maps (map_id) ON UPDATE CASCADE ON DELETE CASCADE,
    marker_id TEXT NOT NULL REFERENCES track.atc_markers (marker_id) ON UPDATE CASCADE ON DELETE CASCADE,
    geom geometry(POINT) NOT NULL,
    PRIMARY KEY (map_id, marker_id)
);

CREATE VIEW maps.combined_track_fragments AS
SELECT
    encode((mtf.map_id || mtf.fragment_id::text)::bytea, 'base64') AS ctf_id,
    mtf.map_id AS map_id,
    mtf.fragment_id AS fragment_id,
    coalesce(ls.color, '#ff00ff') AS color,
    st_makeline(tn1.geom || mtf.geom || tn2.geom) AS geom
FROM maps.track_fragments mtf
JOIN track.track_fragments tf USING (fragment_id)
JOIN maps.track_nodes tn1 ON tn1.map_id = mtf.map_id AND tn1.node_id = tf.node_u
JOIN maps.track_nodes tn2 ON tn2.map_id = mtf.map_id AND tn2.node_id = tf.node_v
JOIN maps.maps m ON mtf.map_id = m.map_id
LEFT JOIN maps.line_styles ls ON ls.style_id = m.style_id AND ls.color_id = tf.color AND ls.line_type = 'track_fragments';

CREATE VIEW maps.combined_track_sections AS
SELECT
    encode((tf.ts_id || array_to_string(array_agg(tf.fragment_id::text), ''))::bytea, 'base64') AS cts_id,
    ctf.map_id AS map_id,
    tf.ts_id AS ts_id,
    coalesce(ls.color, '#ff00ff') AS color,
    st_linemerge(st_union(array_agg(ctf.geom))) AS geom
FROM maps.combined_track_fragments ctf
JOIN track.track_fragments tf USING (fragment_id)
JOIN track.track_sections ts USING (ts_id)
JOIN maps.maps m USING (map_id)
LEFT JOIN maps.line_styles ls ON ls.style_id = m.style_id AND ls.color_id = ts.color AND ls.line_type = 'track_sections'
GROUP BY ctf.map_id, ls.color, tf.ts_id;

CREATE VIEW maps.combined_tracks AS
SELECT
    encode((ts.track_id || array_to_string(array_agg(cts.cts_id::text), ''))::bytea, 'base64') AS ct_id,
    cts.map_id AS map_id,
    ts.track_id AS track_id,
    coalesce(ls.color, '#ff00ff') AS color,
    st_linemerge(st_union(array_agg(cts.geom))) AS geom
FROM maps.combined_track_sections cts
JOIN track.track_sections ts USING (ts_id)
JOIN track.tracks t USING (track_id)
JOIN maps.maps m USING (map_id)
LEFT JOIN maps.line_styles ls ON ls.style_id = m.style_id AND ls.color_id = t.color AND ls.line_type = 'tracks'
GROUP BY cts.map_id, ls.color, ts.track_id;

CREATE VIEW maps.combined_power_blocks AS
SELECT
    encode((tf.pb_id || array_to_string(array_agg(tf.fragment_id::text), ''))::bytea, 'base64') AS cpb_id,
    ctf.map_id AS map_id,
    tf.pb_id AS pb_id,
    coalesce(ls.color, '#ff00ff') AS color,
    st_linemerge(st_union(array_agg(ctf.geom))) AS geom
FROM maps.combined_track_fragments ctf
JOIN track.track_fragments tf USING (fragment_id)
JOIN track.power_blocks pb USING (pb_id)
JOIN maps.maps m USING (map_id)
LEFT JOIN maps.line_styles ls ON ls.style_id = m.style_id AND ls.color_id = pb.color AND ls.line_type = 'power_blocks'
WHERE tf.pb_id IS NOT NULL
GROUP BY ctf.map_id, ls.color, tf.pb_id;

CREATE VIEW maps.combined_comm_loops AS
SELECT
    encode((cl.vcc_id::text || cl.loop_id::text || array_to_string(array_agg(tf.fragment_id::text), ''))::bytea, 'base64') AS ccl_id,
    ctf.map_id AS map_id,
    cl.vcc_id AS vcc_id,
    cl.loop_id AS loop_id,
    'L' || cl.vcc_id || '-' || cl.loop_id AS comm_loop_display,
    coalesce(ls.color, '#ff00ff') AS color,
    st_linemerge(st_union(array_agg(ctf.geom))) AS geom
FROM maps.combined_track_fragments ctf
JOIN track.track_fragments tf USING (fragment_id)
JOIN track.track_sections ts USING (ts_id)
JOIN track.tracks t USING (track_id)
JOIN track.comm_loops cl USING (vcc_id, loop_id)
JOIN maps.maps m USING (map_id)
LEFT JOIN maps.line_styles ls ON ls.style_id = m.style_id AND ls.color_id = cl.color AND ls.line_type = 'comm_loops'
GROUP BY ctf.map_id, ls.color, cl.vcc_id, cl.loop_id;

CREATE VIEW maps.combined_station_zones AS
SELECT
    encode(tf.zone_id::bytea, 'base64') AS csz_id,
    ctf.map_id AS map_id,
    tf.zone_id AS zone_id,
    st_linemerge(st_union(array_agg(ctf.geom))) AS geom
FROM maps.combined_track_fragments ctf
JOIN track.track_fragments tf USING (fragment_id)
WHERE tf.zone_id IS NOT NULL
GROUP BY ctf.map_id, tf.zone_id;

CREATE OR REPLACE VIEW maps.combined_auto_guide_lines AS
SELECT
    encode((ctf.map_id || agl.guideline_id)::bytea, 'base64') AS cagl_id,
    ctf.map_id AS map_id,
    agl.guideline_id AS guideline_id,
    st_linemerge(st_offsetcurve(st_union(array_agg(ctf.geom)), agl.line_offset, 'join=mitre')) AS geom
FROM maps.combined_track_fragments ctf
JOIN maps.maps m USING (map_id)
JOIN maps.auto_guide_lines agl USING (style_id)
GROUP BY ctf.map_id, agl.guideline_id, agl.line_offset;

CREATE VIEW maps.combined_switches AS
SELECT
    encode((s.switch_id::text || s.switch_type::text)::bytea, 'base64') as cs_id,
    tn.map_id AS map_id,
    tn.node_id AS node_id,
    (CASE WHEN s.switch_type = 'field' THEN 'FC' WHEN s.switch_type = 'manual' THEN 'MC' ELSE '' END) || s.switch_id AS switch_display,
    coalesce(ss.color, '#ff00ff') AS color,
    tn.geom AS geom
FROM maps.track_nodes tn
JOIN track.switches s USING (node_id)
JOIN maps.maps m USING (map_id)
LEFT JOIN maps.switch_styles ss USING (style_id,  switch_type);
