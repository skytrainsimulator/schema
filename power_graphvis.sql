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

DO $$
    DECLARE
        out TEXT = E'\ngraph G {\n';
        subgraph_end TEXT = E'  }\n';
        body TEXT = '';
        pb record;
        es record;
        src record;
    BEGIN
        out = out ||
              E'  subgraph feeds {\n' ||
              E'    node [shape=star,style=filled,color=blue,label=""]\n';
        FOR src IN SELECT * FROM track.substation_sources ORDER BY substation_id, source_id LOOP
            out = out || '    "' || src.source_id || E'";\n';
            body = body || '  "' || src.source_id || '" -- "' || src.fed_block || E'"[color=blue];\n';
        END LOOP;
        out = out || subgraph_end;

        out = out ||
              E'  subgraph power_blocks {\n' ||
              E'    node [shape=point,label=""]\n';
        FOR pb IN SELECT * FROM track.power_blocks ORDER BY pb_id LOOP
            out = out || '    "' || pb.pb_id || '"' || (CASE WHEN pb.encompassing_substation IS NOT NULL THEN '[color=blue]' ELSE '' END) ||E';\n';
        END LOOP;
        out = out || subgraph_end;

        DECLARE
            electrical TEXT = E'  subgraph electrical_switches {\n' ||
                              E'    node [shape=house]\n';
            transfer TEXT = E'  subgraph transfer_switches {\n' ||
                            E'    node [shape=invtrapezium]\n';
            cross_connect TEXT = E'  subgraph cross_connect_switches {\n' ||
                                 E'    node [shape=diamond]\n';
            breaker TEXT = E'  subgraph breakers {\n' ||
                           E'    node [shape=rect]\n';
            jumper TEXT = E'  subgraph jumpers {\n' ||
                          E'    node [shape=circle]\n';

            normally_open_edges TEXT = E'  subgraph normally_open_edges {\n' ||
                                       E'    edge [style=dotted]\n';
        BEGIN
            FOR es IN SELECT * FROM track.electrical_connections ORDER BY connection_type, connection_id LOOP
                DECLARE
                    es_out TEXT;
                    connection_string_u TEXT;
                    connection_string_v TEXT;
                BEGIN
                    es_out = '    "' || es.connection_id || '"';
                    connection_string_u = '  "' || es.block_u || '" -- "' || es.connection_id || '"';
                    connection_string_v = '  "' || es.connection_id || '" -- "' || es.block_v || '"';
                    IF es.encompassing_substation IS NOT NULL THEN
                        es_out = es_out || '[color=blue]';
                        connection_string_u = connection_string_u || '[color=blue]';
                        connection_string_v = connection_string_v || '[color=blue]';
                    END IF;
                    IF es.motorized THEN es_out = es_out || '[style=filled,fillcolor=lightgray]'; END IF;
                    IF es.normally_open THEN
                        normally_open_edges = normally_open_edges || '  ' || connection_string_u || E';\n  ' || connection_string_v || E';\n';
                    ELSE
                        body = body || connection_string_u || E';\n' || connection_string_v || E';\n';
                    END IF;
                    es_out = es_out || E';\n';

                    IF es.connection_type = 'electrical_switch' THEN electrical = electrical || es_out;
                    ELSEIF es.connection_type = 'transfer_switch' THEN transfer = transfer || es_out;
                    ELSEIF es.connection_type = 'cross_connect_switch' THEN cross_connect = cross_connect || es_out;
                    ELSEIF es.connection_type = 'breaker' THEN breaker = breaker || es_out;
                    ELSEIF es.connection_type = 'jumper' THEN jumper = jumper || es_out;
                    END IF;
                END;
            END LOOP;
            out = out || electrical || subgraph_end || transfer || subgraph_end || cross_connect || subgraph_end || breaker || subgraph_end || jumper || subgraph_end || normally_open_edges || subgraph_end;
        END;

        out = out || body || E'}\n';

        RAISE NOTICE '%', out;
    END;
$$ LANGUAGE plpgsql;
