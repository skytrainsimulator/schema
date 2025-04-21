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

CREATE SCHEMA IF NOT EXISTS georef;

CREATE TABLE georef.map_scale_groups (
    scale_key TEXT NOT NULL PRIMARY KEY,
    maps TEXT[] NOT NULL
);

CREATE TABLE georef.loops_linked_nodes (
    track_node UUID NOT NULL UNIQUE,
    osm_node TEXT NOT NULL UNIQUE,
    notes TEXT DEFAULT NULL,
    PRIMARY KEY (track_node, osm_node)
);

CREATE TABLE georef.georef_nodes (
    track_node UUID NOT NULL UNIQUE,
    osm_node TEXT NOT NULL UNIQUE,
    notes TEXT DEFAULT NULL,
    PRIMARY KEY (track_node, osm_node)
);

CREATE TABLE georef.intersection_lines (
    intersection_line_id TEXT NOT NULL PRIMARY KEY,
    geom geometry(LINESTRING, 3857) NOT NULL,
    notes TEXT DEFAULT NULL
);

CREATE TABLE georef.intersection_cross_node_pairs (
    intersection_line_id TEXT NOT NULL REFERENCES georef.intersection_lines (intersection_line_id),
    node_pair_id TEXT NOT NULL,
    track_node UUID NOT NULL UNIQUE,
    notes TEXT DEFAULT NULL,
    PRIMARY KEY (intersection_line_id, node_pair_id)
);

CREATE TABLE georef.closest_point (
    osm_node TEXT NOT NULL,
    node_pair_id TEXT NOT NULL,
    track_node UUID NOT NULL UNIQUE,
    notes TEXT DEFAULT NULL,
    PRIMARY KEY (osm_node, node_pair_id)
);

CREATE TABLE georef.force_auto_node_percentage_map_source (
    fragment_id UUID NOT NULL PRIMARY KEY,
    map_id TEXT NOT NULL,
    notes TEXT DEFAULT NULL
);

CREATE TABLE georef.force_fragment_trace_length (
    fragment_id UUID NOT NULL PRIMARY KEY,
    length_override DOUBLE PRECISION NOT NULL,
    notes TEXT DEFAULT NULL
);

-- -- -- Begin Materialized Views -- -- --

CREATE MATERIALIZED VIEW georef.georef_intersection_points AS
SELECT
    encode((intersection_line_id || np.node_pair_id)::bytea, 'base64') as ip_id,
    encode((track_node::text || 'IL')::bytea, 'base64') as georef_id,
    track_node,
    icnp.intersection_line_id,
    icnp.node_pair_id,
    st_intersection(st_transform(il.geom, 4326), np.geom) AS point_geo
FROM georef.intersection_cross_node_pairs icnp
JOIN georef.intersection_lines il USING (intersection_line_id)
JOIN osm.node_pairs np USING (node_pair_id);

CREATE MATERIALIZED VIEW georef.georef_closest_points  AS
SELECT
    encode((cp.osm_node || cp.node_pair_id)::bytea, 'base64') as cp_id,
    encode((track_node::text || 'CP')::bytea, 'base64') as georef_id,
    track_node,
    cp.node_pair_id,
    cp.osm_node,
    st_pointn(st_shortestline(np.geom::geography, rn.wkb_geometry::geography)::geometry, 2) AS point_geo
FROM georef.closest_point cp
JOIN osm.node_pairs np USING (node_pair_id)
JOIN osm.osm_raw_nodes rn ON cp.osm_node = rn.id;

CREATE MATERIALIZED VIEW georef.georef_points AS
SELECT
    track_node,
    encode((track_node::text || 'GRN')::bytea, 'base64') as georef_id,
    'GRN' AS type,
    rn.wkb_geometry AS point_geo
FROM georef.georef_nodes
JOIN osm.osm_raw_nodes rn ON osm_node = rn.id UNION
SELECT
    track_node,
    georef_id,
    'GL' AS type,
    point_geo AS point_geo
FROM georef.georef_intersection_points UNION
SELECT
    track_node,
    georef_id,
    'CP' AS type,
    point_geo AS point_geo
FROM georef.georef_closest_points;

CREATE MATERIALIZED VIEW georef.georef_line_points AS
SELECT
    id AS georef_node_id,
    wkb_geometry AS geo,
    gp.georef_id as georef_id
FROM osm.osm_raw_nodes
LEFT JOIN georef.georef_nodes gn ON id = gn.osm_node
LEFT JOIN georef.georef_points gp ON type = 'GRN' AND gp.track_node = gn.track_node UNION
SELECT
    ip_id AS georef_node_id,
    point_geo AS geo,
    georef_id
FROM georef.georef_intersection_points UNION
SELECT
    cp_id AS georef_node_id,
    point_geo AS geo,
    georef_id
FROM georef.georef_closest_points;

CREATE MATERIALIZED VIEW georef.georef_line_point_pairs AS
WITH nodes_along AS (
    SELECT
        ip_id AS georef_node_id,
        node_pair_id,
        st_linelocatepoint(np.geom, gip.point_geo) AS percent_along
    FROM georef.georef_intersection_points gip
    JOIN osm.node_pairs np USING (node_pair_id)
    UNION SELECT
        cp_id AS georef_node_id,
        node_pair_id,
        st_linelocatepoint(np.geom, gcp.point_geo) AS percent_along
    FROM georef.georef_closest_points gcp
    JOIN osm.node_pairs np USING (node_pair_id)
    UNION SELECT
        node_u AS georef_node_id,
        node_pair_id,
        0 AS percent_along
    FROM osm.node_pairs
    UNION SELECT
        node_v AS georef_node_id,
        node_pair_id,
        1 AS percent_along
    FROM osm.node_pairs
), with_nulls AS (
    SELECT
        georef_node_id AS node_u,
        last_value(georef_node_id) OVER (PARTITION BY node_pair_id ORDER BY percent_along ROWS UNBOUNDED PRECEDING EXCLUDE CURRENT ROW) AS node_v
    FROM nodes_along
)
SELECT
    *
FROM with_nulls
WHERE node_v IS NOT NULL;

CREATE MATERIALIZED VIEW georef.georef_lines AS
WITH track_node_pairs AS (
    SELECT
        node_u, node_v, fragment_id
    FROM track.track_fragments UNION
    SELECT
        node_v, node_u, fragment_id
    FROM track.track_fragments
), track_rec AS (
    WITH RECURSIVE rec AS (
        SELECT
            track_node AS start_node,
            georef_id AS start_georef,
            track_node AS end_node,
            georef_id AS end_georef,
            ARRAY [track_node]::uuid[] AS nodes,
            ARRAY []::uuid[] AS fragments
        FROM georef.georef_points
        UNION
        SELECT
            start_node,
            start_georef,
            node_v AS end_node,
            gtn.georef_id,
            nodes || node_v AS nodes,
            fragments || fragment_id AS fragments
        FROM rec
        JOIN track_node_pairs ON node_u = end_node AND NOT (fragment_id = ANY (fragments))
        LEFT JOIN georef.georef_points gtn_end ON end_node = gtn_end.track_node
        LEFT JOIN georef.georef_points gtn ON node_v = gtn.track_node
        WHERE gtn_end.track_node IS NULL OR start_node = end_node
    )
    SELECT rec.* FROM rec
    WHERE start_node != end_node AND end_georef IS NOT NULL
), georef_line_point_pairs AS (
    SELECT
        node_u, node_v
    FROM georef.georef_line_point_pairs
    UNION
    SELECT
        node_v,
        node_u
    FROM georef.georef_line_point_pairs
), osm_rec AS (
    WITH RECURSIVE rec AS (
        SELECT
            gp.georef_id AS start_georef,
            glp.georef_node_id AS start_node,
            gp.georef_id AS end_georef,
            glp.georef_node_id AS end_node,
            ARRAY [glp.georef_node_id]::text[] AS nodes,
            ARRAY [glp.geo]::geometry(POINT,4326)[] AS geo_points
        FROM georef.georef_points gp
        JOIN georef.georef_line_points glp ON glp.georef_id = gp.georef_id
        UNION
        SELECT
            start_georef,
            start_node,
            gon.georef_id,
            node_v,
            nodes || node_v AS nodes,
            (geo_points || glp.geo)::geometry(POINT,4326)[] AS geo_points
        FROM rec
        JOIN georef_line_point_pairs ON node_u = end_node AND NOT (node_v = ANY (nodes))
        JOIN georef.georef_line_points glp ON glp.georef_node_id = node_v
        LEFT JOIN georef.georef_line_points glp_end ON glp_end.georef_node_id = end_node
        LEFT JOIN georef.georef_points gon_end ON glp_end.georef_id = gon_end.georef_id
        LEFT JOIN georef.georef_points gon ON glp.georef_id = gon.georef_id
        WHERE gon_end.georef_id IS NULL OR start_node = end_node
    )
    SELECT DISTINCT rec.* FROM rec
    WHERE start_georef != end_georef AND end_georef IS NOT NULL
)
SELECT
    track_rec.start_georef, track_rec.end_georef,
    track_rec.start_node as start_track_node, track_rec.end_node AS end_track_node,
    track_rec.nodes AS track_nodes,
    fragments,
    array_agg(DISTINCT ctf.map_id) AS trace_maps,
    count(DISTINCT ctf.map_id) AS sourced_trace_maps,
    array_agg(DISTINCT msg.scale_key) AS scale_keys,
    count(DISTINCT msg.scale_key) AS sourced_scale_keys,
    start_georef || coalesce(lln.track_node::text, '') || end_georef AS georef_line_id,
    st_makeline(geo_points) AS osm_geo
FROM track_rec
JOIN osm_rec USING (start_georef, end_georef)
LEFT JOIN maps.combined_track_fragments ctf ON ctf.fragment_id = ANY (fragments) AND map_id NOT LIKE '%old%' AND map_id LIKE '%trace%'
LEFT JOIN georef.map_scale_groups msg ON map_id = ANY (msg.maps)
LEFT JOIN georef.loops_linked_nodes lln ON lln.track_node = ANY (track_rec.nodes)
WHERE
    start_georef < end_georef AND
    (lln.track_node IS NULL OR lln.osm_node = ANY (osm_rec.nodes))
GROUP BY
    track_rec.start_georef, track_rec.end_georef, track_rec.start_node, track_rec.end_node, track_rec.nodes, fragments,
    start_georef || end_georef, st_makeline(geo_points), lln.track_node;

CREATE MATERIALIZED VIEW georef.auto_traced_georef_lines AS
WITH tmp AS (
    SELECT
        gl.georef_line_id,
        ctf.map_id,
        st_linemerge(st_union(array_agg(geom))) AS geo,
        array_agg(ctf.fragment_id) AS included_fragments
    FROM georef.georef_lines gl
    JOIN maps.combined_track_fragments ctf ON ctf.fragment_id = ANY (fragments) AND map_id NOT LIKE '%old%' AND map_id LIKE '%trace%'
    GROUP BY gl.georef_line_id, ctf.map_id
), unnested_frags AS (
    SELECT
        georef_line_id,
        f.fragment_id,
        f.i
    FROM georef.georef_lines
    JOIN unnest(fragments) WITH ORDINALITY AS f(fragment_id, i) ON TRUE
), frag_order AS (
    SELECT DISTINCT
        first_value(fragment_id) OVER w AS first_frag,
        last_value(fragment_id) OVER w AS last_frag,
        georef_line_id,
        tmp.map_id
    FROM tmp
    JOIN unnested_frags USING (georef_line_id)
    WINDOW w AS (PARTITION BY georef_line_id ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
)
SELECT
    georef_line_id,
    tmp.map_id,
    CASE
        WHEN ctf_f IS NOT NULL AND st_linelocatepoint(geo, st_lineinterpolatepoint(ctf_f.geom, 0.5)) > 0.5 THEN st_reverse(geo)
        WHEN ctf_l IS NOT NULL AND st_linelocatepoint(geo, st_lineinterpolatepoint(ctf_l.geom, 0.5)) <= 0.5 THEN st_reverse(geo)
        ELSE geo
    END AS geo,
    included_fragments,
    st_length(geo) AS length,
    first_frag
FROM tmp
JOIN frag_order USING (georef_line_id, map_id)
LEFT JOIN maps.combined_track_fragments ctf_f ON ctf_f.map_id = tmp.map_id AND ctf_f.fragment_id = first_frag
LEFT JOIN maps.combined_track_fragments ctf_l ON ctf_l.map_id = tmp.map_id AND ctf_l.fragment_id = last_frag
WHERE geometrytype(geo) = 'LINESTRING';

-- I don't want to talk about this mess.
CREATE MATERIALIZED VIEW georef.auto_node_percentages AS
WITH auto_calculatable_georef_lines AS (
    WITH all_frags AS (
        SELECT
            *, unnest(included_fragments) AS fragment_id
        FROM georef.auto_traced_georef_lines atgl
    ), merged AS (
        SELECT
            georef_line_id,
            array_agg(fragment_id) AS all_fragments
        FROM all_frags
        JOIN georef.map_scale_groups msg ON map_id = ANY (msg.maps)
        GROUP BY georef_line_id, msg.scale_key
    )
    SELECT
        georef_line_id,
        count(DISTINCT atgl.map_id) AS map_count
    FROM georef.auto_traced_georef_lines atgl
    JOIN georef.georef_lines gl USING (georef_line_id)
    JOIN merged m USING (georef_line_id)
    JOIN georef.map_scale_groups msg ON map_id = ANY (msg.maps)
    WHERE m.all_fragments @> gl.fragments AND m.all_fragments <@ gl.fragments
    GROUP BY georef_line_id
    HAVING
        count(DISTINCT atgl.map_id) < 3 AND -- Logic can currently only calculate a single map split per georef_line. More is possible, but I'm lazy
        count(DISTINCT msg.scale_key) = 1 UNION DISTINCT
    SELECT DISTINCT
        georef_line_id, 1
    FROM georef.force_auto_node_percentage_map_source fanpms
    JOIN georef.georef_lines gl ON fanpms.fragment_id = ANY (fragments)
), fragments_ordered AS (
    SELECT
        georef_line_id,
        f.fragment_id,
        f.i
    FROM georef.georef_lines
    JOIN unnest(fragments) WITH ORDINALITY AS f(fragment_id, i) ON TRUE
), fragments_map_source AS (
    SELECT DISTINCT
        fo.georef_line_id,
        fo.fragment_id,
        i,
        coalesce(fanpms.map_id, first_value(atgl.map_id) OVER w) AS map_id
    FROM fragments_ordered fo
    JOIN georef.auto_traced_georef_lines atgl ON atgl.georef_line_id = fo.georef_line_id AND fo.fragment_id = ANY (atgl.included_fragments)
    JOIN auto_calculatable_georef_lines acgl ON fo.georef_line_id = acgl.georef_line_id
    LEFT JOIN georef.force_auto_node_percentage_map_source fanpms USING (fragment_id)
    WINDOW w AS (PARTITION BY fragment_id ORDER BY atgl.length ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
), fragments_length AS (
    SELECT
        fms.georef_line_id,
        fms.fragment_id,
        fms.i,
        fms.map_id,
        coalesce(fftl.length_override, st_length(ctf.geom)) AS length
    FROM fragments_map_source fms
    JOIN maps.combined_track_fragments ctf USING (fragment_id, map_id)
    LEFT JOIN georef.force_fragment_trace_length fftl USING (fragment_id)
), nodes_pixel_position AS (
    SELECT
        fl.georef_line_id,
        fl.fragment_id,
        fl.map_id,
        fl.i,
        sum(fl.length) OVER (PARTITION BY atgl.georef_line_id ORDER BY fl.i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS pixels_along,
        CASE
            WHEN st_linelocatepoint(atgl.geo, tnv.geom) >= st_linelocatepoint(atgl.geo, tnu.geom) THEN node_v
            ELSE node_u
        END AS node_id,
        st_linelocatepoint(atgl.geo, tnv.geom) AS tmp
    FROM fragments_length fl
    JOIN track.track_fragments tf USING (fragment_id)
    JOIN maps.track_nodes tnu ON tnu.node_id = node_u AND tnu.map_id = fl.map_id
    JOIN maps.track_nodes tnv ON tnv.node_id = node_v AND tnv.map_id = fl.map_id
    JOIN georef.auto_traced_georef_lines atgl ON atgl.georef_line_id = fl.georef_line_id AND atgl.map_id = fl.map_id
), total_length AS (
    SELECT
        *,
        max(pixels_along) OVER (PARTITION BY georef_line_id) AS pixels_length
    FROM nodes_pixel_position
), node_percentages AS (
    SELECT
        georef_line_id,
        node_id,
        pixels_length AS total_length_pixels,
        map_id,
        pixels_along / pixels_length AS percent_along,
        pixels_along
    FROM total_length
)

SELECT
    georef_line_id,
    node_id,
    min(total_length_pixels) AS total_length_pixels,
    map_id,
    min(percent_along) AS percent_along,
    min(pixels_along) AS pixels_along
FROM node_percentages
JOIN georef.georef_lines gl USING (georef_line_id)
WHERE node_id != gl.end_track_node AND node_id != gl.start_track_node
GROUP BY georef_line_id, node_id, map_id;
