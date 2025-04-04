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

CREATE TYPE track.split_result AS (original_fragment_id UUID, created_node_id UUID, created_fragment_id UUID);

CREATE OR REPLACE FUNCTION track.split_fragment(split_fragment_id UUID) RETURNS track.split_result AS $$
    DECLARE
        old_fragment record;
        new_fragment_id UUID := gen_random_uuid();
        new_node_id UUID := gen_random_uuid();
    BEGIN
        SELECT * FROM track.track_fragments WHERE fragment_id = split_fragment_id INTO old_fragment;
        IF NOT FOUND THEN RETURN NULL; END IF;

        INSERT INTO track.track_nodes (node_id) VALUES (new_node_id);

        INSERT INTO maps.track_nodes (map_id, node_id, geom)
        SELECT ctf.map_id, new_node_id, st_lineinterpolatepoint(ctf.geom, 0.5)
        FROM maps.combined_track_fragments ctf
        WHERE ctf.fragment_id = old_fragment.fragment_id;

        UPDATE track.track_fragments SET node_v = new_node_id, length = old_fragment.length / 2 WHERE fragment_id = split_fragment_id;

        INSERT INTO track.track_fragments (fragment_id, ts_id, length, node_u, node_v, pb_id)
        VALUES (new_fragment_id, old_fragment.ts_id, old_fragment.length / 2, new_node_id, old_fragment.node_v, old_fragment.pb_id);

        INSERT INTO maps.track_fragments (map_id, fragment_id, geom)
        SELECT mtf.map_id, new_fragment_id, ARRAY []::geometry[]
        FROM maps.track_fragments mtf
        WHERE fragment_id = old_fragment.fragment_id;

        RETURN ROW (split_fragment_id, new_node_id, new_fragment_id)::track.split_result;
    END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION track.gen_track(track INT, ts_from INT, ts_to INT) RETURNS VOID AS $$
    DECLARE
        step INT;
        last_node UUID := gen_random_uuid();
        next_node UUID;
        ts INT;
    BEGIN
        step := CASE WHEN ts_from < ts_to THEN 1 ELSE -1 END;
        INSERT INTO track.track_nodes (node_id) VALUES (last_node);
        FOR ts IN SELECT i FROM generate_series(ts_from, ts_to, step) AS i LOOP
            INSERT INTO track.track_sections (ts_id, track_id, max_speed) VALUES (ts::text, track, -1);

            INSERT INTO track.track_nodes (node_id) VALUES (gen_random_uuid()) RETURNING node_id INTO next_node;

            INSERT INTO track.track_fragments (fragment_id, ts_id, node_u, node_v, pb_id)
            VALUES (gen_random_uuid(), ts, last_node, next_node, NULL);
            last_node = next_node;
        END LOOP;
    END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION track.gen_omc_track(track INT, ts_from INT, ts_to INT) RETURNS VOID AS $$
    DECLARE
        last_node UUID := gen_random_uuid();
        next_node UUID;
        i INT;
        ts_id TEXT;
    BEGIN
        IF ts_from < ts_to THEN
            RAISE EXCEPTION 'Expected ts_from > ts_to! Are you sure you entered the correct numbers?';
        END IF;
        INSERT INTO track.track_nodes (node_id) VALUES (last_node);
        FOR i IN SELECT iterate FROM generate_series(ts_from, ts_to, -2) AS iterate LOOP
            ts_id = i::text || ' - '  || (i - 1)::text;
            INSERT INTO track.track_sections (ts_id, track_id, max_speed) VALUES (ts_id, track, 25);

            INSERT INTO track.track_nodes (node_id) VALUES (gen_random_uuid()) RETURNING node_id INTO next_node;

            INSERT INTO track.track_fragments (fragment_id, ts_id, node_u, node_v, pb_id)
            VALUES (gen_random_uuid(), ts_id, last_node, next_node, NULL);
            last_node = next_node;
        END LOOP;
    END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION track.gen_substation(substation TEXT, sub_full_name TEXT, zero_ib_pb UUID, zero_ob_pb UUID, one_ib_pb UUID, one_ob_pb UUID) RETURNS VOID AS $$
    DECLARE
        feed_pb UUID := gen_random_uuid();
        zero_pb UUID := gen_random_uuid();
        one_pb UUID := gen_random_uuid();
    BEGIN
        INSERT INTO track.substations (substation_id, full_name) VALUES (substation, sub_full_name);
        INSERT INTO track.power_blocks (pb_id, color, encompassing_substation, notes) VALUES
            (feed_pb, 0, substation, substation || '-Feed'),
            (zero_pb, 0, substation, substation || '/0'),
            (one_pb, 0, substation, substation || '/1');
        INSERT INTO track.substation_sources (source_id, substation_id, fed_block) VALUES (gen_random_uuid(), substation, feed_pb);
        INSERT INTO track.electrical_connections (connection_id, block_u, block_v, connection_type, encompassing_substation, normally_open, motorized) VALUES
            (substation || '-Feed', feed_pb, zero_pb, 'breaker', substation, FALSE, TRUE),
            (substation || '-Tie', zero_pb, one_pb, 'breaker', substation, FALSE, TRUE),
            (substation || '-IB/0', zero_pb, zero_ib_pb, 'breaker', substation, FALSE, TRUE),
            (substation || '-OB/0', zero_pb, zero_ob_pb, 'breaker', substation, FALSE, TRUE),
            (substation || '-IB/1', one_pb, one_ib_pb, 'breaker', substation, FALSE, TRUE),
            (substation || '-OB/1', one_pb, one_ob_pb, 'breaker', substation, FALSE, TRUE);
    END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION maps.place_substation(map TEXT, sub TEXT, x FLOAT, y FLOAT) RETURNS VOID AS $$
    DECLARE
        found_feeds INT;
    BEGIN
        INSERT INTO maps.electrical_connections (map_id, connection_id, geom, rotation) VALUES
        (map, sub || '-Feed', st_point(x - 18, y), 0),
        (map, sub || '-Tie', st_point(x, y), 0),
        (map, sub || '-IB/0', st_point(x - 9, y + 9), 90),
        (map, sub || '-OB/0', st_point(x - 9, y - 9), 90),
        (map, sub || '-IB/1', st_point(x + 9, y + 9), 90),
        (map, sub || '-OB/1', st_point(x + 9, y - 9), 90);
        INSERT INTO maps.substation_markers (map_id, substation_id, geom) VALUES (map, sub, st_point(x, y));
        SELECT count(*) FROM track.substation_sources WHERE substation_id = sub INTO found_feeds;
        IF found_feeds = 1 THEN
            INSERT INTO maps.substation_sources (map_id, source_id, geom)
            SELECT
                map, source_id, st_point(x - 30, y)
            FROM track.substation_sources
            WHERE substation_id = sub
            LIMIT 1;
        ELSE
            RAISE WARNING 'Could not place feed, found a non-1 number of feeds!';
        END IF;
    END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE VIEW track.node_adjacent_fragments AS
SELECT
    fragment_id,
    node_u AS node_id
FROM track.track_fragments
UNION SELECT
    fragment_id,
    node_v AS node_id
FROM track.track_fragments;

CREATE OR REPLACE FUNCTION maps.place_nodes(ts_from INT, ts_to INT, map TEXT, x FLOAT, y FLOAT, spacing FLOAT) RETURNS VOID AS $$
    DECLARE
        i INT;
    BEGIN
        IF ts_from < ts_to THEN
            RAISE EXCEPTION 'Expected ts_from > ts_to! Are you sure you entered the correct numbers?';
        END IF;
        FOR i IN 0..(ts_from - ts_to) LOOP
            INSERT INTO maps.track_nodes (map_id, node_id, geom)
            SELECT
                map,
                node_u,
                st_point(x + (i * spacing), y - (row_number() OVER (ORDER BY fragment_id) - 1) * spacing)
            FROM track.track_fragments
            LEFT JOIN maps.track_nodes existing ON existing.node_id = node_u AND existing.map_id = map
            WHERE ts_id = (ts_from - i)::text AND existing.node_id IS NULL;
        END LOOP;

        INSERT INTO maps.track_nodes (map_id, node_id, geom)
        SELECT
            map,
            node_v,
            st_point(x + ((ts_from - ts_to + 1) * spacing), y - (row_number() OVER (ORDER BY fragment_id) - 1) * spacing)
        FROM track.track_fragments
        LEFT JOIN maps.track_nodes existing ON existing.node_id = node_v AND existing.map_id = map
        WHERE ts_id = ts_to::text AND existing.node_id IS NULL;
    END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION maps.randomly_place_nodes(map TEXT, x INT, y INT, place_track INT) RETURNS VOID AS $$
    INSERT INTO maps.track_nodes (map_id, node_id, geom)
    SELECT DISTINCT ON (tn.node_id)
        map,
        tn.node_id,
        st_point(round(random() * 100) - 50 + x, round(random() * 100) - 50 + y, 0)
    FROM track.track_sections ts
    JOIN track.track_fragments tf ON tf.ts_id = ts.ts_id
    JOIN track.track_nodes tn ON tf.node_u = tn.node_id OR tf.node_v = tn.node_id
    LEFT JOIN maps.track_nodes existing ON existing.map_id = map AND existing.node_id = tn.node_id
    WHERE existing.node_id IS NULL AND ts.track_id = place_track;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION maps.update_fragment_path_trigger() RETURNS TRIGGER AS $$
    DECLARE
        new_points geometry[];
    BEGIN
        SELECT
            array_agg((points).geom)
        FROM LATERAL st_dumppoints(NEW.geom) AS points
        INTO new_points;

        new_points := new_points[2:array_upper(new_points, 1) - 1];

        UPDATE maps.track_fragments SET geom = new_points WHERE map_id = NEW.map_id AND fragment_id = NEW.fragment_id;
        RETURN NEW;
    END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER update_fragment_path
    INSTEAD OF UPDATE ON maps.combined_track_fragments
    FOR EACH ROW EXECUTE PROCEDURE maps.update_fragment_path_trigger();
