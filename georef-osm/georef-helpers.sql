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

-- Add switches to georef nodes
INSERT INTO georef.georef_nodes (track_node, osm_node, notes)
SELECT
    s.node_id, os.osm_id, 'Switch ' || track.switch_type_as_display(s.switch_type) || s.switch_id
FROM osm.switches os
LEFT JOIN track.switches s ON os.switch_id::int = s.switch_id AND os.switch_type::text = s.switch_type::text
WHERE s.switch_id IS NOT NULL AND os.switch_id NOT LIKE '-%';
