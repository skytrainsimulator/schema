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
        total_problems int = 0;
    BEGIN
        RAISE NOTICE 'Beginning node checks...';
        DECLARE
            node record;
            notes_string text;
            nodes int = 0;
            problems int = 0;
        BEGIN
            FOR node IN SELECT * FROM track.track_nodes ORDER BY node_id LOOP
                    DECLARE
                        in_fragments int;
                    BEGIN
                        nodes = nodes + 1;
                        notes_string = CASE WHEN node.notes IS NOT NULL THEN '; Notes: "' || node.notes || '"' ELSE '' END;
                        SELECT count(*) FROM track.track_fragments WHERE node_u = node.node_id OR node_v = node.node_id INTO in_fragments;
                        IF in_fragments = 0 THEN
                            RAISE WARNING '%: Node is unused%', node.node_id, notes_string;
                            problems = problems + 1;
                        END IF;

                        IF in_fragments > 3 THEN
                            RAISE WARNING '%: Node is used in > 3 fragments (%)%', node.node_id, in_fragments, notes_string;
                            problems = problems + 1;
                        END IF;
                    END;
                END LOOP;

            IF problems > 0 THEN
                RAISE WARNING 'Checked % nodes, found % problems!', nodes, problems;
                total_problems = total_problems + problems;
            ELSE
                RAISE NOTICE 'Checked % nodes.', nodes;
            END IF;
        END;

        RAISE NOTICE 'Beginning fragment checks...';
        DECLARE
            frag record;
            notes_string text;
            fragments int = 0;
            problems int = 0;
        BEGIN
            FOR frag IN SELECT * FROM track.track_fragments ORDER BY fragment_id LOOP
                fragments = fragments + 1;
                notes_string = CASE WHEN frag.notes IS NOT NULL THEN '; Notes: "' || frag.notes || '"' ELSE '' END;
                IF frag.node_u = frag.node_v THEN
                    RAISE WARNING '%: Node U = Node V%', frag.fragment_id, notes_string;
                    problems = problems + 1;
                END IF;
                IF frag.length < 0 THEN
                    RAISE WARNING '%: Length < 0 (%)%', frag.fragment_id, frag.length, notes_string;
                    problems = problems + 1;
                END IF;
            END LOOP;

            IF problems > 0 THEN
                RAISE WARNING 'Checked % fragments, found % problems!', fragments, problems;
                total_problems = total_problems + problems;
            ELSE
                RAISE NOTICE 'Checked % fragments.', fragments;
            END IF;
        END;

        RAISE NOTICE 'Beginning track section checks...';
        DECLARE
            ts record;
            notes_string text;
            track_sections int = 0;
            problems int = 0;
        BEGIN
            FOR ts IN SELECT * FROM track.track_sections ORDER BY ts_id LOOP
                track_sections = track_sections + 1;
                notes_string = CASE WHEN ts.notes IS NOT NULL THEN '; Notes: "' || ts.notes || '"' ELSE '' END;
                IF ts.max_speed < 0 THEN
                    RAISE WARNING '%: max_speed < 0 (%)%', ts.ts_id, ts.max_speed, notes_string;
                    problems = problems + 1;
                END IF;
                IF NOT exists(SELECT FROM track.track_fragments WHERE ts_id = ts.ts_id) THEN
                    RAISE WARNING '%: TS is unused%', ts.ts_id, notes_string;
                    problems = problems + 1;
                END IF;
            END LOOP;

            IF problems > 0 THEN
                RAISE WARNING 'Checked % track sections, found % problems!', track_sections, problems;
                total_problems = total_problems + problems;
            ELSE
                RAISE NOTICE 'Checked % track sections.', track_sections;
            END IF;
        END;

        RAISE NOTICE 'Beginning track limit checks...';
        DECLARE
            track_limit record;
            notes_string text;
            tracks int = 0;
            problems int = 0;
        BEGIN
            FOR track_limit IN SELECT * FROM track.tracks ORDER BY track_id LOOP
                tracks = tracks + 1;
                notes_string = CASE WHEN track_limit.notes IS NOT NULL THEN '; Notes: "' || track_limit.notes || '"' ELSE '' END;
                IF NOT exists(SELECT FROM track.track_sections ts WHERE ts.track_id = track_limit.track_id) THEN
                    RAISE WARNING '%: Track is unused%', track_limit.track_id, notes_string;
                    problems = problems + 1;
                END IF;
            END LOOP;

            IF problems > 0 THEN
                RAISE WARNING 'Checked % track limits, found % problems!', tracks, problems;
                total_problems = total_problems + problems;
            ELSE
                RAISE NOTICE 'Checked % track limits.', tracks;
            END IF;
        END;

        RAISE NOTICE 'Beginning switch checks...';
        DECLARE
            switch record;
            switches int = 0;
            problems int = 0;
        BEGIN
            FOR switch IN SELECT * FROM track.switches ORDER BY switch_type, switch_id LOOP
                DECLARE
                    displayText text;
                    notes_string text;
                    common_frag record;
                    left_frag record;
                    right_frag record;
                BEGIN
                    switches = switches + 1;
                    notes_string = CASE WHEN switch.notes IS NOT NULL THEN '; Notes: "' || switch.notes || '"' ELSE '' END;
                    displayText = track.switch_type_as_display(switch.switch_type) || switch.switch_id || ':';
                    IF
                        switch.common_fragment = switch.left_fragment OR
                        switch.common_fragment = switch.right_fragment OR
                        switch.left_fragment = switch.right_fragment
                    THEN
                        RAISE WARNING '% Duplicate fragments (C=%, L=%, R=%)%',
                            displayText,
                            switch.common_fragment,
                            switch.left_fragment,
                            switch.right_fragment,
                            notes_string;
                        problems = problems + 1;
                    END IF;
                    SELECT * FROM track.track_fragments WHERE fragment_id = switch.common_fragment INTO common_frag;
                    SELECT * FROM track.track_fragments WHERE fragment_id = switch.left_fragment INTO left_frag;
                    SELECT * FROM track.track_fragments WHERE fragment_id = switch.right_fragment INTO right_frag;

                    IF NOT (switch.node_id = common_frag.node_u OR switch.node_id = common_frag.node_v) THEN
                        RAISE WARNING '% Common fragment does not have node (F=%, N=%)%', displayText, common_frag.fragment_id, switch.node_id, notes_string;
                        problems = problems + 1;
                    END IF;
                    IF NOT (switch.node_id = left_frag.node_u OR switch.node_id = left_frag.node_v) THEN
                        RAISE WARNING '% Left fragment does not have node (F=%, N=%)%', displayText, left_frag.fragment_id, switch.node_id, notes_string;
                        problems = problems + 1;
                    END IF;
                    IF NOT (switch.node_id = right_frag.node_u OR switch.node_id = right_frag.node_v) THEN
                        RAISE WARNING '% Right fragment does not have node (F=%, N=%)%', displayText, right_frag.fragment_id, switch.node_id, notes_string;
                        problems = problems + 1;
                    END IF;
                END;
            END LOOP;

            IF problems > 0 THEN
                RAISE WARNING 'Checked % switches, found % problems!', switches, problems;
                total_problems = total_problems + problems;
            ELSE
                RAISE NOTICE 'Checked % switches.', switches;
            END IF;
        END;

        RAISE NOTICE 'Beginning power block checks...';
        DECLARE
            pb record;
            power_blocks int = 0;
            problems int = 0;
        BEGIN
            FOR pb IN SELECT * FROM track.power_blocks ORDER BY pb_id LOOP
                DECLARE
                    notes_string text;
                    fed_frags int;
                    sources int;
                    connections int;
                BEGIN
                    power_blocks = power_blocks + 1;
                    notes_string = CASE WHEN pb.notes IS NOT NULL THEN '; Notes: "' || pb.notes || '"' ELSE '' END;
                    SELECT count(*) FROM track.track_fragments WHERE pb_id = pb.pb_id INTO fed_frags;
                    SELECT count(*) FROM track.substation_sources WHERE fed_block = pb.pb_id INTO sources;
                    SELECT count(*) FROM track.electrical_connections WHERE block_u = pb.pb_id OR block_v = pb.pb_id INTO connections;
                    -- S | C | F
                    -- 0   0   0 : [!] Unused
                    -- 0   0   + : [!] Isolated
                    -- +   0   0 : [!] Isolated
                    -- 0   1   0 : [!] Dead-end
                    -- +   0   + : [!] Directly Connected; Isolated
                    -- +   +   + : [!] Directly Connected
                    -- 0   +   0 : Substation Block
                    -- 0   +   + : Normal Block
                    -- +   +   0 : Substation Block
                    IF sources = 0 AND connections = 0 AND fed_frags = 0 THEN
                        RAISE WARNING '%: Block is unused%', pb.pb_id, notes_string;
                        problems = problems + 1;
                    ELSEIF sources = 0 AND connections = 0 AND fed_frags != 0 THEN
                        RAISE WARNING '%: Block is isolated (No sources nor connections; % fragments)%', pb.pb_id, fed_frags, notes_string;
                        problems = problems + 1;
                    ELSEIF sources != 0 AND connections = 0 AND fed_frags = 0 THEN
                        RAISE WARNING '%: Block is isolated (No connections nor fragments; % sources)%', pb.pb_id, sources, notes_string;
                        problems = problems + 1;
                    ELSEIF sources = 0 AND connections = 1 AND fed_frags = 0 THEN
                        RAISE WARNING '%: Block is dead-end (No sources nor fragments; one connection)%', pb.pb_id, notes_string;
                        problems = problems + 1;
                    ELSEIF sources = 0 AND connections = 0 AND fed_frags != 0 THEN
                        RAISE WARNING '%: Block is directly connected; isolated if fragments removed (No connections; % sources, % fragments)%', pb.pb_id, sources, fed_frags, notes_string;
                        problems = problems + 1;
                    ELSEIF sources != 0 AND connections != 0 AND fed_frags != 0 THEN
                        RAISE WARNING '%: Block is directly connected (No fragments; % sources, % connections)%', pb.pb_id, sources, connections, notes_string;
                        problems = problems + 1;
                    END IF;
                END;
            END LOOP;

            IF problems > 0 THEN
                RAISE WARNING 'Checked % power blocks, found % problems!', power_blocks, problems;
                total_problems = total_problems + problems;
            ELSE
                RAISE NOTICE 'Checked % power blocks.', power_blocks;
            END IF;
        END;

        RAISE NOTICE 'Beginning electrical connection checks...';
        DECLARE
            ec record;
            electrical_connections int = 0;
            problems int = 0;
        BEGIN
            FOR ec IN SELECT * FROM track.electrical_connections ORDER BY connection_type, connection_id LOOP
                DECLARE
                    notes_string text;
                BEGIN
                    electrical_connections = electrical_connections + 1;
                    notes_string = CASE WHEN ec.notes IS NOT NULL THEN '; Notes: "' || ec.notes || '"' ELSE '' END;

                    IF ec.block_u = ec.block_v THEN
                        RAISE WARNING '%: Connection block_u = block_v%', ec.connection_id, notes_string;
                        problems = problems + 1;
                    END IF;

                    IF ec.connection_type = 'jumper' AND ec.motorized THEN
                        RAISE WARNING '%: JIS marked as motorized%', ec.connection_id, notes_string;
                        problems = problems + 1;
                    END IF;
                END;
            END LOOP;

            IF problems > 0 THEN
                RAISE WARNING 'Checked % electrical connections, found % problems!', electrical_connections, problems;
                total_problems = total_problems + problems;
            ELSE
                RAISE NOTICE 'Checked % electrical connections.', electrical_connections;
            END IF;
        END;

        RAISE NOTICE 'Beginning reentry point checks...';
        DECLARE
            re record;
            reentry_points int = 0;
            problems int = 0;
        BEGIN
            FOR re IN SELECT * FROM track.reentry_points ORDER BY reentry_id LOOP
                DECLARE
                    notes_string text;
                    frag record;
                    ts record;
                    track record;
                    adjacent int;
                    adjacent_different_loops int;
                    adjacent_same_loop int;
                BEGIN
                    reentry_points = reentry_points + 1;
                    notes_string = CASE WHEN re.notes IS NOT NULL THEN '; Notes: "' || re.notes || '"' ELSE '' END;
                    SELECT * FROM track.track_fragments WHERE fragment_id = re.fragment_id INTO frag;

                    IF NOT (frag.node_u = re.node_id OR frag.node_v = re.node_id) THEN
                        RAISE WARNING '%: Node is not on fragment (Node: %, Frag: %)%', re.reentry_id, re.node_id, re.fragment_id, notes_string;
                        problems = problems + 1;
                    END IF;

                    IF frag.ts_id IS NULL THEN
                        RAISE WARNING '%: Fragment has no TS%', re.reentry_id, notes_string;
                        problems = problems + 1;
                    END IF;

                    SELECT * FROM track.track_sections WHERE ts_id = frag.ts_id INTO ts;
                    SELECT * FROM track.tracks WHERE tracK_id = ts.track_id INTO track;

                    IF track.vcc_id != re.vcc_id OR track.loop_id != re.loop_id THEN
                        RAISE WARNING '%: Track & reentry point have mismatched loops (RE: L%-%, Track: L%-%)%',
                            re.reentry_id, re.vcc_id, re.loop_id, track.vcc_id, track.loop_id, notes_string;
                        problems = problems + 1;
                    END IF;

                    SELECT count(*)
                    FROM track.track_fragments tf
                    WHERE (tf.node_u = re.node_id OR tf.node_v = re.node_id) AND tf.fragment_id != re.fragment_id
                    INTO adjacent;

                    SELECT count(*)
                    FROM track.track_fragments tf
                    JOIN track.track_sections _ts ON _ts.ts_id = tf.ts_id
                    JOIN track.tracks t ON t.track_id = _ts.track_id
                    WHERE (tf.node_u = re.node_id OR tf.node_v = re.node_id) AND tf.fragment_id != re.fragment_id AND
                          t.vcc_id = re.vcc_id AND t.loop_id = re.loop_id
                    INTO adjacent_same_loop;

                    SELECT count(*)
                    FROM track.track_fragments tf
                             JOIN track.track_sections _ts ON _ts.ts_id = tf.ts_id
                             JOIN track.tracks t ON t.track_id = _ts.track_id
                    WHERE (tf.node_u = re.node_id OR tf.node_v = re.node_id) AND tf.fragment_id != re.fragment_id AND
                        (t.vcc_id != re.vcc_id OR t.loop_id != re.loop_id)
                    INTO adjacent_different_loops;

                    -- A | S | D
                    -- 0   0   0 : [!] Track End
                    -- 0   0   + : [!] Impossible
                    -- 0   +   0 : [!] Impossible
                    -- 0   +   + : [!] Impossible
                    -- +   0   0 : Entry from manual
                    -- +   0   + : Normal
                    -- +   +   0 : [!] Middle of loop
                    -- +   +   + : [!] Middle of loop; switch

                    IF adjacent = 0 THEN
                        RAISE WARNING '%: Reentry point has no other adjacent fragment%', re.reentry_id, notes_string;
                        problems = problems + 1;
                    ELSEIF adjacent_same_loop != 0 AND adjacent_different_loops = 0 THEN
                        RAISE WARNING '%: Reentry point in middle of loop (Adjacent fragments: %, Same loop: %, Different loop: none)%', re.reentry_id, adjacent, adjacent_same_loop, notes_string;
                        problems = problems + 1;
                    ELSEIF adjacent_same_loop != 0 AND adjacent_different_loops != 0 THEN
                        RAISE WARNING '%: Reentry point in middle of loop; on switch (Adjacent fragments: %, Same loop: %, Different loop: %)%', re.reentry_id, adjacent, adjacent_same_loop, adjacent_different_loops, notes_string;
                        problems = problems + 1;
                    ELSEIF adjacent_same_loop = 0 AND adjacent_different_loops > 1 THEN
                        RAISE WARNING '%: Reentry point on switch (Adjacent fragments: %, Same loop: none, Different loop: %)%', re.reentry_id, adjacent, adjacent_different_loops, notes_string;
                        problems = problems + 1;
                    END IF;
                END;
            END LOOP;

            IF problems > 0 THEN
                RAISE WARNING 'Checked % reentry points, found % problems!', reentry_points, problems;
                total_problems = total_problems + problems;
            ELSE
                RAISE NOTICE 'Checked % reentry points.', reentry_points;
            END IF;
        END;

        IF total_problems > 0 THEN
            RAISE EXCEPTION 'Checks complete. Found % problems!', total_problems;
        ELSE
            RAISE NOTICE 'Checks complete. No problems found.';
        END IF;
    END;
$$ LANGUAGE plpgsql;
