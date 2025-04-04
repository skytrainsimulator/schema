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

CREATE SCHEMA IF NOT EXISTS track;
CREATE EXTENSION IF NOT EXISTS postgis;

-- Sides are denoted when facing the "1" direction
CREATE TYPE track.track_side AS ENUM ('left', 'right');
CREATE TYPE track.switch_turnout_side AS ENUM ('wye', 'left', 'right');
CREATE TYPE track.switch_type AS ENUM ('direct', 'field', 'manual');
CREATE FUNCTION track.switch_type_as_display(t track.switch_type) RETURNS TEXT AS $$
    SELECT CASE WHEN t = 'direct' THEN 'DC' WHEN t = 'field' THEN 'FC' ELSE 'MC' END
$$ LANGUAGE sql;

CREATE TYPE track.electrical_connection_type AS ENUM ('electrical_switch', 'transfer_switch', 'cross_connect_switch', 'breaker', 'jumper');

CREATE TABLE track.stations (
    station_id TEXT NOT NULL PRIMARY KEY,
    full_name TEXT NOT NULL,
    gtfs_id TEXT DEFAULT NULL,
    notes TEXT DEFAULT NULL
);

CREATE TABLE track.station_zones (
    zone_id TEXT NOT NULL PRIMARY KEY,
    station_id TEXT REFERENCES track.stations (station_id),
    gtfs_id TEXT DEFAULT NULL,
    notes TEXT DEFAULT NULL
);

CREATE TABLE track.station_platforms (
    zone_id TEXT NOT NULL REFERENCES track.station_zones (zone_id),
    platform_id TEXT NOT NULL,
    track_side track.track_side NOT NULL,
    notes TEXT DEFAULT NULL,
    PRIMARY KEY (zone_id, platform_id)
);

CREATE TABLE track.vccs (
    vcc_id INT NOT NULL PRIMARY KEY,
    color INT NOT NULL DEFAULT 0,
    notes TEXT DEFAULT NUll
);

CREATE TABLE track.comm_loops (
    loop_id INT NOT NULL,
    vcc_id INT NOT NULL REFERENCES track.vccs (vcc_id),
    color INT NOT NULL DEFAULT 0,
    notes TEXT DEFAULT NUll,
    PRIMARY KEY (loop_id, vcc_id)
);

CREATE TABLE track.substations (
    substation_id TEXT NOT NULL PRIMARY KEY,
    full_name TEXT DEFAULT NULL,
    notes TEXT DEFAULT NULL
);

CREATE TABLE track.power_blocks (
    pb_id UUID NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    color INT NOT NULL DEFAULT 0,
    encompassing_substation TEXT REFERENCES track.substations (substation_id) DEFAULT NULL,
    notes TEXT DEFAULT NUll
);

CREATE TABLE track.track_nodes (
    node_id UUID NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    notes TEXT DEFAULT NUll
);

CREATE TABLE track.tracks (
    track_id INT NOT NULL PRIMARY KEY,
    vcc_id INT NOT NULL REFERENCES track.vccs (vcc_id),
    loop_id INT NOT NULL,
    is_bidirectional BOOLEAN NOT NULL DEFAULT FALSE,
    color INT NOT NULL DEFAULT 0,
    notes TEXT DEFAULT NUll,
    CONSTRAINT track_limits_loop_key FOREIGN KEY (vcc_id, loop_id) REFERENCES track.comm_loops (vcc_id, loop_id)
);

CREATE TABLE track.track_sections (
    ts_id TEXT NOT NULL PRIMARY KEY,
    track_id INT NOT NULL REFERENCES track.tracks (track_id),
    max_speed INT NOT NULL,
    color INT NOT NULL DEFAULT 0,
    notes TEXT DEFAULT NUll
);

CREATE TABLE track.track_fragments (
    fragment_id UUID NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    ts_id TEXT REFERENCES track.track_sections (ts_id),
    length FLOAT NOT NULL DEFAULT 25,
    node_u UUID NOT NULL REFERENCES track.track_nodes (node_id),
    node_v UUID NOT NULL REFERENCES track.track_nodes (node_id),
    pb_id UUID REFERENCES track.power_blocks (pb_id) DEFAULT NULL,
    zone_id TEXT REFERENCES track.station_zones (zone_id) DEFAULT NULL,
    color INT NOT NULL DEFAULT 0,
    notes TEXT DEFAULT NUll
);

CREATE TABLE track.switches (
    switch_id INT NOT NULL,
    node_id UUID NOT NULL UNIQUE REFERENCES track.track_nodes (node_id),
    switch_type track.switch_type NOT NULL DEFAULT 'direct',
    turnout_side track.switch_turnout_side NOT NULL,
    common_fragment UUID NOT NULL REFERENCES track.track_fragments (fragment_id),
    left_fragment UUID NOT NULL REFERENCES track.track_fragments (fragment_id),
    right_fragment UUID NOT NULL REFERENCES track.track_fragments (fragment_id),
    notes TEXT DEFAULT NUll,
    PRIMARY KEY (switch_id, switch_type)
);

CREATE TABLE track.atc_markers (
    node_id UUID NOT NULL PRIMARY KEY REFERENCES track.track_nodes (node_id),
    marker_id TEXT UNIQUE NOT NULL,
    notes TEXT DEFAULT NUll
);

CREATE TABLE track.reentry_points (
    reentry_id INT NOT NULL PRIMARY KEY,
    vcc_id INT NOT NULL REFERENCES track.vccs (vcc_id),
    loop_id INT NOT NULL,
    node_id UUID NOT NULL REFERENCES track.track_nodes (node_id),
    fragment_id UUID NOT NULL REFERENCES track.track_fragments (fragment_id),
    notes TEXT DEFAULT NUll,
    CONSTRAINT reentry_points_loop_foreign_key FOREIGN KEY (vcc_id, loop_id) REFERENCES track.comm_loops (vcc_id, loop_id)
);

CREATE TABLE track.substation_sources (
    source_id UUID NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    substation_id TEXT NOT NULL REFERENCES track.substations (substation_id),
    fed_block UUID NOT NULL REFERENCES track.power_blocks (pb_id),
    notes TEXT DEFAULT NULL
);

CREATE TABLE track.electrical_connections (
    connection_id TEXT NOT NULL PRIMARY KEY,
    block_u UUID NOT NULL REFERENCES track.power_blocks (pb_id),
    block_v UUID NOT NULL REFERENCES track.power_blocks (pb_id),
    connection_type track.electrical_connection_type NOT NULL,
    encompassing_substation TEXT REFERENCES track.substations (substation_id) DEFAULT NULL,
    normally_open BOOLEAN NOT NULL DEFAULT FALSE,
    motorized BOOLEAN NOT NULL DEFAULT TRUE,
    notes TEXT DEFAULT NULL
);
