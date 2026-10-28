SELECT COUNT(DISTINCT match_id) AS matches_loaded FROM events;

Select Count(*) AS total_events FROM events;

SELECT MIN(n) AS fewest, ROUND(AVG(n), 2) AS average, MAX(n) AS most
FROM (
    SELECT match_id, COUNT(*) AS n
    FROM events
    GROUP BY match_id) AS per_match; 

SELECT id, COUNT(*) FROM events GROUP BY id HAVING COUNT(*) > 1;

SELECT COUNT(*) AS passes_without_passer FROM events WHERE type = 'Pass' AND player IS NULL;

SELECT COUNT(*) AS ozil_assists FROM events WHERE player = 'Mesut Özil' and pass_goal_assist;

SELECT team, MAX(running_points) AS points, SUM(goals_for) AS scored, SUM(goals_against) AS conceded
FROM team_matches GROUP BY team;