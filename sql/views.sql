
CREATE OR REPLACE VIEW team_matches AS
WITH sides AS (
    SELECT match_id, match_date::date AS match_date, competition_name AS competition,
           home_team AS team, away_team AS opponent, 'Home' AS venue,
           home_score AS goals_for, away_score AS goals_against
    FROM matches
    UNION ALL
    SELECT match_id, match_date::date, competition_name,
           away_team, home_team, 'Away', away_score, home_score
    FROM matches
),
team_xg AS (
    SELECT match_id, team, SUM(shot_statsbomb_xg) AS xg, COUNT(*) AS shots
    FROM events
    WHERE type = 'Shot'
    GROUP BY match_id, team
),
results AS (
    SELECT s.*,
           CASE WHEN goals_for > goals_against THEN 'W'
                WHEN goals_for = goals_against THEN 'D' ELSE 'L' END AS result,
           CASE WHEN goals_for > goals_against THEN 3
                WHEN goals_for = goals_against THEN 1 ELSE 0 END AS points,
           COALESCE(f.xg, 0) AS xg_for,
           COALESCE(a.xg, 0) AS xg_against,
           COALESCE(f.shots, 0) AS shots_for,
           COALESCE(a.shots, 0) AS shots_against
    FROM sides s
    LEFT JOIN team_xg f ON f.match_id = s.match_id AND f.team = s.team
    LEFT JOIN team_xg a ON a.match_id = s.match_id AND a.team = s.opponent
    WHERE s.team IN ('Arsenal', 'Juventus')
)
SELECT *,
       ROW_NUMBER() OVER w AS game_number,
       SUM(points) OVER w AS running_points,
       SUM(goals_for) OVER w AS running_goals,
       SUM(xg_for) OVER w AS running_xg
FROM results
WINDOW w AS (PARTITION BY team ORDER BY match_date);


CREATE OR REPLACE VIEW shots AS
SELECT s.id AS shot_id, s.match_id, s.team, s.player, s.minute,
       s.location_x AS x, s.location_y AS y,
       CASE WHEN s.location_x >= 114 AND s.location_y BETWEEN 30 AND 50 THEN 'Six-yard box'
            WHEN s.location_x >= 102 AND s.location_y BETWEEN 18 AND 62 THEN 'Penalty box'
            ELSE 'Outside the box' END AS shot_area,
       s.shot_statsbomb_xg AS xg,
       s.shot_outcome AS outcome,
       (s.shot_outcome = 'Goal') AS is_goal,
       s.shot_type, s.shot_body_part AS body_part, s.play_pattern,
       s.shot_end_location_y AS end_y, s.shot_end_location_z AS end_z,
       kp.player AS created_by
FROM events s
LEFT JOIN events kp ON kp.id = s.shot_key_pass_id
WHERE s.type = 'Shot' AND s.team IN ('Arsenal', 'Juventus');


CREATE OR REPLACE VIEW pressing AS
WITH opp_passes AS (
    SELECT tm.match_id, tm.team, COUNT(*) AS opp_passes
    FROM team_matches tm
    JOIN events e ON e.match_id = tm.match_id AND e.team = tm.opponent
    WHERE e.type = 'Pass' AND e.location_x < 72
    GROUP BY tm.match_id, tm.team
),
our_actions AS (
    SELECT match_id, team,
           COUNT(*) FILTER (WHERE location_x >= 48
                            AND (type IN ('Interception', 'Foul Committed')
                                 OR (type = 'Duel' AND duel_type = 'Tackle'))) AS def_actions,
           COUNT(*) FILTER (WHERE type = 'Pressure') AS pressures,
           COUNT(*) FILTER (WHERE type = 'Pressure' AND location_x >= 80) AS high_pressures,
           COUNT(*) FILTER (WHERE type = 'Pressure' AND counterpress) AS counterpresses
    FROM events
    WHERE team IN ('Arsenal', 'Juventus')
    GROUP BY match_id, team
)
SELECT tm.match_id, tm.team, tm.opponent, tm.match_date, tm.game_number, tm.venue,
       op.opp_passes, oa.def_actions,
       ROUND(op.opp_passes::numeric / NULLIF(oa.def_actions, 0), 2) AS ppda,
       oa.pressures, oa.high_pressures, oa.counterpresses
FROM team_matches tm
JOIN opp_passes op ON op.match_id = tm.match_id AND op.team = tm.team
JOIN our_actions oa ON oa.match_id = tm.match_id AND oa.team = tm.team;


CREATE OR REPLACE VIEW ball_wins AS
SELECT match_id, team, player, type,
       location_x AS x, location_y AS y,
       LEAST(FLOOR(location_x / 20), 5)::int + 1 AS zone_col,
       LEAST(FLOOR(location_y / 20), 3)::int + 1 AS zone_row
FROM events
WHERE team IN ('Arsenal', 'Juventus')
  AND ((type = 'Ball Recovery' AND ball_recovery_recovery_failure IS NOT TRUE)
       OR (type = 'Interception' AND interception_outcome IN ('Won', 'Success In Play', 'Success Out'))
       OR (type = 'Duel' AND duel_type = 'Tackle' AND duel_outcome IN ('Won', 'Success In Play', 'Success Out')));


CREATE OR REPLACE VIEW player_minutes AS
WITH match_end AS (
    SELECT match_id, MAX(minute + second / 60.0) AS end_minute
    FROM events
    WHERE period <= 2
    GROUP BY match_id
)
SELECT pp.match_id, pp.team, pp.player_id, l.player_name,
       SUM(COALESCE(pp.end_minute, me.end_minute) - pp.start_minute) AS minutes
FROM player_positions pp
JOIN match_end me ON me.match_id = pp.match_id
JOIN lineups l ON l.match_id = pp.match_id AND l.team = pp.team AND l.player_id = pp.player_id
GROUP BY pp.match_id, pp.team, pp.player_id, l.player_name;


CREATE OR REPLACE VIEW player_stats AS
WITH mins AS (
    SELECT team, player_id, player_name, COUNT(*) AS matches, SUM(minutes)::numeric AS minutes
    FROM player_minutes
    WHERE team IN ('Arsenal', 'Juventus')
    GROUP BY team, player_id, player_name
),
assisted AS (
    SELECT p.player_id::bigint AS player_id, SUM(s.shot_statsbomb_xg) AS xg_assisted
    FROM events p
    JOIN events s ON s.id = p.pass_assisted_shot_id
    WHERE p.type = 'Pass' AND p.team IN ('Arsenal', 'Juventus')
    GROUP BY p.player_id
),
actions AS (
    SELECT player_id::bigint AS player_id,
           COUNT(*) FILTER (WHERE type = 'Shot') AS shots,
           COUNT(*) FILTER (WHERE type = 'Shot' AND shot_outcome = 'Goal') AS goals,
           COUNT(*) FILTER (WHERE type = 'Shot' AND shot_outcome = 'Goal'
                            AND shot_type <> 'Penalty') AS np_goals,
           COALESCE(SUM(shot_statsbomb_xg), 0) AS xg,
           COALESCE(SUM(shot_statsbomb_xg) FILTER (WHERE shot_type <> 'Penalty'), 0) AS np_xg,
           COUNT(*) FILTER (WHERE pass_goal_assist) AS assists,
           COUNT(*) FILTER (WHERE pass_goal_assist OR pass_shot_assist) AS chances_created,
           COUNT(*) FILTER (WHERE type = 'Pass' AND pass_outcome IS NULL
                            AND location_x < 80 AND pass_end_location_x >= 80) AS passes_into_final_third,
           COUNT(*) FILTER (WHERE type = 'Carry'
                            AND location_x < 80 AND carry_end_location_x >= 80) AS carries_into_final_third,
           COUNT(*) FILTER (WHERE type = 'Ball Recovery'
                            AND ball_recovery_recovery_failure IS NOT TRUE) AS recoveries,
           COUNT(*) FILTER (WHERE type = 'Duel' AND duel_type = 'Tackle') AS tackles,
           COUNT(*) FILTER (WHERE type = 'Duel' AND duel_type = 'Tackle'
                            AND duel_outcome IN ('Won', 'Success In Play', 'Success Out')) AS tackles_won,
           COUNT(*) FILTER (WHERE type = 'Pressure') AS pressures
    FROM events
    WHERE team IN ('Arsenal', 'Juventus') AND player_id IS NOT NULL
    GROUP BY player_id
)
SELECT m.team, m.player_name, m.matches, ROUND(m.minutes) AS minutes,
       a.shots, a.goals, a.np_goals, ROUND(a.xg::numeric, 2) AS xg, ROUND(a.np_xg::numeric, 2) AS np_xg,
       a.assists, ROUND(COALESCE(x.xg_assisted, 0)::numeric, 2) AS xg_assisted, a.chances_created,
       a.passes_into_final_third, a.carries_into_final_third,
       a.recoveries, a.tackles, a.tackles_won, a.pressures,

       ROUND((a.np_xg * 90 / m.minutes)::numeric, 2) AS np_xg_per90,
       ROUND((COALESCE(x.xg_assisted, 0) * 90 / m.minutes)::numeric, 2) AS xg_assisted_per90,
       ROUND(a.chances_created * 90 / m.minutes, 2) AS chances_created_per90,
       ROUND((a.passes_into_final_third + a.carries_into_final_third) * 90 / m.minutes, 2) AS progressions_per90,
       ROUND(a.recoveries * 90 / m.minutes, 2) AS recoveries_per90
FROM mins m
JOIN actions a ON a.player_id = m.player_id
LEFT JOIN assisted x ON x.player_id = m.player_id;


CREATE OR REPLACE VIEW attack_starts AS
WITH possessions AS (
    SELECT match_id, possession, possession_team AS team,
           BOOL_OR(type = 'Shot' AND team = possession_team) AS ended_in_shot,
           COALESCE(SUM(shot_statsbomb_xg) FILTER (WHERE team = possession_team), 0) AS xg
    FROM events
    GROUP BY match_id, possession, possession_team
),
first_touch AS (
    SELECT DISTINCT ON (match_id, possession) match_id, possession, location_x, location_y
    FROM events
    WHERE location_x IS NOT NULL AND team = possession_team
    ORDER BY match_id, possession, "index"
)
SELECT p.match_id, p.team, p.possession, p.ended_in_shot, p.xg,
       f.location_x AS x, f.location_y AS y,
       LEAST(FLOOR(f.location_x / 20), 5)::int + 1 AS zone_col,
       LEAST(FLOOR(f.location_y / 20), 3)::int + 1 AS zone_row
FROM possessions p
JOIN first_touch f ON f.match_id = p.match_id AND f.possession = p.possession
WHERE p.team IN ('Arsenal', 'Juventus');


CREATE OR REPLACE VIEW pass_pairs AS
SELECT team, player AS passer, pass_recipient AS receiver, COUNT(*) AS passes
FROM events
WHERE type = 'Pass' AND pass_outcome IS NULL AND team IN ('Arsenal', 'Juventus')
GROUP BY team, player, pass_recipient;