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

\set ON_ERROR_STOP on
BEGIN;

DROP SCHEMA IF EXISTS osm CASCADE;
CREATE SCHEMA osm;

\i work/nodes.sql
\i work/ways.sql
CREATE TABLE osm.osm_raw_way_nodes (
    raw_way TEXT NOT NULL,
    raw_node TEXT NOT NULL,
    ordinal INT NOT NULL,
    UNIQUE(raw_way, ordinal)
);
\i work/way_nodes.sql

-- osm2geojson includes nodes in the ways dataset
DELETE FROM osm.osm_raw_ways WHERE id NOT LIKE 'way%';

\i pre-osm-parse.sql

CREATE TYPE osm.switch_type AS ENUM ('direct', 'field', 'manual');

CREATE VIEW osm.switches AS
SELECT
    n.id AS osm_id,
    n.ref AS switch_id,
    (
        CASE WHEN "railway:switch:electric" = 'no' THEN 'manual'
        WHEN "railway:switch:local_operated" = 'yes' THEN 'field'
        ELSE 'direct' END
    )::osm.switch_type AS switch_type
FROM osm.osm_raw_nodes n
WHERE n.railway = 'switch';

CREATE MATERIALIZED VIEW osm.node_pairs AS
WITH node_pairs AS (
    SELECT
        raw_node AS node_u,
        last_value(raw_node) OVER (PARTITION BY raw_way ORDER BY ordinal ROWS UNBOUNDED PRECEDING EXCLUDE CURRENT ROW) AS node_v
    FROM osm.osm_raw_way_nodes rwn
    JOIN osm.osm_raw_ways rw ON rw.id = rwn.raw_way AND rw.railway IS NOT NULL
)
SELECT DISTINCT
    node_u,
    node_v,
    encode((replace(node_u || node_v, 'node/', ''))::bytea, 'base64') AS node_pair_id,
    st_makeline(rnu.wkb_geometry, rnv.wkb_geometry) AS geom
FROM node_pairs
JOIN osm.osm_raw_nodes rnu ON rnu.id = node_u
JOIN osm.osm_raw_nodes rnv ON rnv.id = node_v
WHERE node_u IS NOT NULL AND node_v IS NOT NULL;

COMMIT;
