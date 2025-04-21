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

BEGIN;

DELETE FROM maps.track_nodes WHERE map_id = 'geo';
DELETE FROM maps.track_fragments WHERE map_id = 'geo';

REFRESH MATERIALIZED VIEW georef.georef_intersection_points;
REFRESH MATERIALIZED VIEW georef.georef_closest_points;
REFRESH MATERIALIZED VIEW georef.georef_points;
REFRESH MATERIALIZED VIEW georef.georef_line_points;
REFRESH MATERIALIZED VIEW georef.georef_line_point_pairs;
REFRESH MATERIALIZED VIEW georef.georef_lines;
REFRESH MATERIALIZED VIEW georef.auto_traced_georef_lines;
REFRESH MATERIALIZED VIEW georef.auto_node_percentages;

INSERT INTO maps.track_nodes (map_id, node_id, geom)
SELECT
    'geo', track_node, point_geo
FROM georef.georef_points;

WITH insertable AS (
    SELECT DISTINCT ON (node_id)
        georef_line_id, node_id, percent_along
    FROM georef.auto_node_percentages anp
    GROUP BY node_id, percent_along, georef_line_id
    HAVING count(node_id) = 1
)
INSERT INTO maps.track_nodes (map_id, node_id, geom)
SELECT
    'geo',
    node_id,
    st_lineinterpolatepoint(gl.osm_geo, percent_along)
--     georef_line_id,
--     fragment_id
FROM insertable
JOIN georef.georef_lines gl USING (georef_line_id);

WITH percentages AS (
    SELECT
        osm_geo,
        st_linelocatepoint(osm_geo, tn_u.geom) AS fraction_u,
        st_linelocatepoint(osm_geo, tn_v.geom) AS fraction_v,
        fragment_id
    FROM georef.georef_lines gl
    JOIN track.track_fragments tf ON tf.fragment_id = ANY (gl.fragments)
    JOIN maps.track_nodes tn_u ON tn_u.map_id = 'geo' AND tn_u.node_id = tf.node_u
    JOIN maps.track_nodes tn_v ON tn_v.map_id = 'geo' AND tn_v.node_id = tf.node_v
), linestrings AS (
    SELECT
        fragment_id,
        CASE
            WHEN fraction_u < fraction_v THEN st_linesubstring(osm_geo, fraction_u, fraction_v)
            ELSE st_reverse(st_linesubstring(osm_geo, fraction_v, fraction_u))
        END AS geo
    FROM percentages p
), split_linestrings AS (
    SELECT
        fragment_id,
        array_agg((g).geom ORDER BY (g).path[1]) AS geo
    FROM linestrings, LATERAL st_dumppoints(geo) g
    GROUP BY fragment_id
)
INSERT INTO maps.track_fragments (map_id, fragment_id, geom)
SELECT
    'geo',
    fragment_id,
    geo[2:array_upper(geo, 1) - 1]
FROM split_linestrings;

COMMIT;
