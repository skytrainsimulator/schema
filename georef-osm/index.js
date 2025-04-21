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

import * as fs from "node:fs";
import osmtogeojson from "osmtogeojson";

const workDir = './work/'
const overpassData = JSON.parse(fs.readFileSync(workDir + "raw-osm.json", "utf8"))

console.log(`Version: ${overpassData.version}`)
console.log(`OSM Time: ${overpassData.osm3s.timestamp_osm_base}`)
console.log(`OSM's Copyright: "${overpassData.osm3s.copyright}"`)
console.log(`Found ${overpassData.elements.length} elements`)

function copyOsm(data, type) {
    let out = structuredClone(data)
    console.log(`Pre-filter elements: ${out.elements.length}`)
    out.elements = out.elements.filter(e => e.type === type)
    console.log(`Post-filter elements: ${out.elements.length}`)
    return out
}

let nodes = copyOsm(overpassData, "node")
let ways = copyOsm(overpassData, "way")
let wayNodes = "COPY osm.osm_raw_way_nodes (raw_way, raw_node, ordinal) FROM STDIN csv;\n"

for (const way of ways.elements) {
    for (const node in way.nodes) {
        wayNodes += `way/${way.id},node/${way.nodes[node]},${node}\n`
    }
}
wayNodes += "\\.\n"

function writeGeoJSON(data, file) {
    const geojson = osmtogeojson(data, { uninterestingTags: () => false })
    fs.writeFileSync(workDir + file, JSON.stringify(geojson), 'utf8')
}

writeGeoJSON(nodes, "nodes.geojson")
writeGeoJSON(ways, "ways.geojson")
fs.writeFileSync(workDir + "way_nodes.sql", wayNodes, 'utf8')
