#!/bin/bash

#
# SkytrainSim Track Schema
# Copyright (C) 2025 SkytrainSim contributors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
#

set -o errexit

rm -rf work/
mkdir work/
echo "Downloading OSM data..."
OSM_QUERY=$(cat overpass-query.txt | jq -sRr @uri)
curl -o work/raw-osm.json "https://overpass-api.de/api/interpreter?data=$OSM_QUERY"
echo "Downloaded!"
