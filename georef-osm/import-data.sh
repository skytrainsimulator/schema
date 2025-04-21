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

convertGeoJSON() {
  echo "Converting $1 to PGSQL..."
  time ogr2ogr -f PGDump "work/$1.sql" "work/$1.geojson" \
  -lco SCHEMA=osm -lco DROP_TABLE=OFF -lco CREATE_SCHEMA=OFF \
  -nln "osm_raw_$1" --config PG_USE_COPY YES \
  # ogr2ogr doesn't have an option to not wrap the output in a transaction
  # Normally that's sane, but in this case the script is being ran in another transaction.
  sed -i '/BEGIN;\|COMMIT;\|END;/d' "./work/$1.sql"
  echo "Done!"
}

echo "Converting OSM data to GeoJSON..."
time node index.js
echo "Done!"
convertGeoJSON nodes
convertGeoJSON ways
echo "Running import script..."
time psql -b -f import.sql
echo "Done!"
