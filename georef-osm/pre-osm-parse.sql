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

-- ## pre-osm-parse.sql ## --
-- Executed after osm.osm_raw_nodes, osm.osm_raw_ways, and osm.osm_raw_way_nodes are loaded.
-- Use if there's data that's easier to fix in the osm tables before the import logic runs than after.

CREATE TABLE osm.canada_line_territory (
    geom geometry(POLYGON, 4326) NOT NULL,
    id INT NOT NULL PRIMARY KEY
);
INSERT INTO osm.canada_line_territory (geom, id) VALUES ('0103000020E6100000010000001F000000BD3CFB823CC75EC04B6DC81C9EA44840897ADCA836C75EC05F8ECB9997A44840045F3F7374C75EC0BE9FBD8444A448408B37AB75D3C75EC0D985AB4558A34840B17EBE9478C75EC02B60F33F84A24840E9E249E142C75EC0762C4A19EFA148405AC604FA5AC75EC095FB15065D9E4840A0397F2375C75EC03796ADC5579948401BF6D88429C85EC052FAB034BB98484038C3C22A92C85EC064F7583A899748404BE03A58B7C85EC0A49BF08245954840E6333660CDC85EC095F5F6B5439548405A9E3521D0C85EC0D77F08D49E974840F8350A0E6FC85EC0EEA9B44EB19848405CACBE71A5C85EC0B34838E5F398484043ED558765C95EC09DD02A7D129948403BD143E6BAC95EC000BAFA81AF98484036659B28A7CB5EC07563B468A7984840B63CA19E8BCB5EC0FCE204640A994840B872F9C7EBC95EC0B8E6E665E698484076BC13DB6FC95EC02EB16A5E64994840D7D3526F46C85EC0AD5C2A2F27994840FAC9717AB4C75EC0262CAB25AE994840AAF779EC8DC75EC0BAF07258489E48401EB36DC1C7C75EC098DBF706B69E4840DF9E70FCB9C75EC0A92C21DF3C9F4840302EFDC67EC75EC045FAAE696D9F48406AE37C2780C75EC0729112E9E7A14840D023E1F602C85EC005C28E5634A34840EEAD5FD909C85EC082D259579EA34840BD3CFB823CC75EC04B6DC81C9EA44840', 1);

-- Some CL OMC switches "marked" as manual simply with an M prefix
UPDATE osm.osm_raw_nodes SET "railway:switch:electric" = 'no', ref = trim(LEADING 'M' FROM ref)
WHERE railway = 'switch' AND ref LIKE 'M%';

UPDATE osm.osm_raw_nodes SET ref = '-' || coalesce(ref, 'NULL')
FROM osm.canada_line_territory
WHERE canada_line_territory.id = 1 AND railway = 'switch' AND st_contains(geom, wkb_geometry);

-- Mainline track marked as crossover?
UPDATE osm.osm_raw_ways SET service = 'mainline'
WHERE id = 'way/494354325';

-- Switches not marked as manual
WITH manual_switches AS ( VALUES
    ('node/4454496695'),
    ('node/4454496699')
)
UPDATE osm.osm_raw_nodes SET "railway:switch:electric" = 'no'
FROM manual_switches
WHERE id = manual_switches.column1;

-- Switches not marked as field
WITH field_switches AS ( VALUES
    ('node/1030282889'),
    ('node/1030282961'),
    ('node/1030282426'),
    ('node/1030282578'),
    ('node/1030282623'),
    ('node/1030282519'),
    ('node/1030282707'),
    ('node/1030282766')
)
UPDATE osm.osm_raw_nodes SET "railway:switch:local_operated" = 'yes'
FROM field_switches
WHERE id = field_switches.column1;

-- Erroneous refs for the following switches
WITH switches AS ( VALUES
    ('node/4454496695', '901'),
    ('node/4454496699', '902'),
    ('node/4454496702', '903'),
    ('node/8573215808', '904'),
    ('node/1030282823', '905'),
    ('node/12374983482', '906'),
    ('node/8140799026', '320'),
    ('node/8140799027', '321')
)
UPDATE osm.osm_raw_nodes SET ref = switches.column2
FROM switches
WHERE id = switches.column1;
