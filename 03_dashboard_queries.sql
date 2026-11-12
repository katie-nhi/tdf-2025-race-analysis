-- Analytical queries behind the dashboard metrics (Q1-Q11).
-- Run after 01_schema.sql and a data load. Tested on PostgreSQL 16.

\echo Q1 stage winners
SELECT s.stage_id, s.stage_type, s.start_location || ' → ' || s.finish_location AS route,
       rd.rider_name, rd.team_name
FROM   result r
JOIN   rider  rd ON rd.bib_number = r.bib_number
JOIN   stage  s  ON s.stage_id    = r.stage_id
WHERE  r.rank = 1
ORDER  BY s.stage_id;

\echo Q2 top10 by terrain
SELECT rd.rider_name,
       COUNT(*)                                              AS top10_total,
       COUNT(*) FILTER (WHERE s.stage_type = 'flat')         AS flat,
       COUNT(*) FILTER (WHERE s.stage_type = 'hilly')        AS hilly,
       COUNT(*) FILTER (WHERE s.stage_type = 'mountain')     AS mountain,
       COUNT(*) FILTER (WHERE s.stage_type = 'individual time-trial') AS time_trial
FROM   result r
JOIN   rider  rd ON rd.bib_number = r.bib_number
JOIN   stage  s  ON s.stage_id    = r.stage_id
WHERE  r.rank <= 10
GROUP  BY rd.rider_name
ORDER  BY top10_total DESC, rd.rider_name
LIMIT  11;

\echo Q3 dropouts by stage
SELECT e.stage_id, COUNT(*) AS riders_out,
       STRING_AGG(rd.rider_name || ' (' || rd.team_name || ')', ', ' ORDER BY rd.rider_name) AS who
FROM   exit e
JOIN   rider rd ON rd.bib_number = e.bib_number
GROUP  BY e.stage_id
ORDER  BY e.stage_id;

\echo Q4 GC after every stage + gap + yellow
WITH cum AS (
    SELECT v.bib_number, v.stage_id,
           SUM(v.adjusted_time_sec) OVER (PARTITION BY v.bib_number ORDER BY v.stage_id) AS cum_time,
           COUNT(*)                 OVER (PARTITION BY v.bib_number ORDER BY v.stage_id) AS stages_done
    FROM   v_result v
),
eligible AS (            -- only riders who have finished every stage so far
    SELECT * FROM cum WHERE stages_done = stage_id
)
SELECT stage_id, bib_number, cum_time,
       RANK() OVER (PARTITION BY stage_id ORDER BY cum_time)              AS gc_pos,
       cum_time - MIN(cum_time) OVER (PARTITION BY stage_id)              AS gap_sec
FROM   eligible
ORDER  BY stage_id, gc_pos;

\echo Q5 yellow jersey holder after each stage
WITH cum AS (
    SELECT v.bib_number, v.stage_id,
           SUM(v.adjusted_time_sec) OVER (PARTITION BY v.bib_number ORDER BY v.stage_id) AS cum_time,
           COUNT(*)                 OVER (PARTITION BY v.bib_number ORDER BY v.stage_id) AS stages_done
    FROM   v_result v
), ranked AS (
    SELECT stage_id, bib_number,
           RANK() OVER (PARTITION BY stage_id ORDER BY cum_time) AS gc_pos
    FROM   cum WHERE stages_done = stage_id
)
SELECT r.stage_id, rd.rider_name AS yellow_jersey
FROM   ranked r JOIN rider rd USING (bib_number)
WHERE  r.gc_pos = 1
ORDER  BY r.stage_id;

\echo Q6 young rider classification
SELECT RANK() OVER (ORDER BY gc.total_adjusted_time_sec) AS young_pos,
       gc.rider_name, gc.team_name, rd.date_of_birth,
       gc.total_adjusted_time_sec - MIN(gc.total_adjusted_time_sec) OVER () AS gap_sec
FROM   v_general_classification gc
JOIN   rider rd ON rd.bib_number = gc.bib_number
WHERE  rd.date_of_birth >= DATE '2000-01-01'
ORDER  BY young_pos;

\echo Q7 riders and teams per country
SELECT c.country_name,
       (SELECT COUNT(*) FROM rider r WHERE r.country_code = c.country_code) AS riders,
       (SELECT COUNT(*) FROM team  t WHERE t.country_code = c.country_code) AS teams
FROM   country c
ORDER  BY riders DESC, c.country_name;

\echo Q8 nationality vs team country
SELECT rc.country_name AS rider_nationality,
       tc.country_name AS team_country,
       COUNT(*)        AS riders
FROM   rider rd
JOIN   team    t  ON t.team_name     = rd.team_name
JOIN   country rc ON rc.country_code = rd.country_code
JOIN   country tc ON tc.country_code = t.country_code
GROUP  BY rc.country_name, tc.country_name
ORDER  BY riders DESC;

\echo Q9 nationality lens
SELECT c.country_name,
       COUNT(DISTINCT rd.bib_number)                                   AS riders,
       COUNT(DISTINCT rd.bib_number) FILTER (WHERE e.bib_number IS NULL) AS reached_paris,
       COUNT(r.*) FILTER (WHERE r.rank = 1)                            AS stage_wins,
       COUNT(r.*) FILTER (WHERE r.rank <= 3)                           AS podiums,
       COUNT(r.*) FILTER (WHERE r.rank <= 10)                          AS top10,
       COUNT(DISTINCT r.stage_id) FILTER (WHERE r.rank <= 3)           AS podium_days
FROM   country c
JOIN   rider  rd ON rd.country_code = c.country_code
LEFT   JOIN exit   e ON e.bib_number = rd.bib_number
LEFT   JOIN result r ON r.bib_number = rd.bib_number
GROUP  BY c.country_name
ORDER  BY stage_wins DESC, podiums DESC;

\echo Q10 team: how often each rider counted in the team top 3
WITH ranked AS (
    SELECT rd.team_name, rd.rider_name, r.stage_id,
           ROW_NUMBER() OVER (PARTITION BY rd.team_name, r.stage_id
                              ORDER BY r.finish_time_sec, r.rank) AS pos_in_team
    FROM   result r JOIN rider rd ON rd.bib_number = r.bib_number
)
SELECT team_name, rider_name, COUNT(*) AS stages_counted
FROM   ranked
WHERE  pos_in_team <= 3
GROUP  BY team_name, rider_name
ORDER  BY team_name, stages_counted DESC;

\echo Q11 stage-by-stage strip for one team (pivot)
SELECT rd.rider_name,
       MAX(r.rank) FILTER (WHERE r.stage_id = 1) AS s1,
       MAX(r.rank) FILTER (WHERE r.stage_id = 2) AS s2,
       MAX(r.rank) FILTER (WHERE r.stage_id = 3) AS s3
FROM   rider rd
LEFT   JOIN result r ON r.bib_number = rd.bib_number
WHERE  rd.team_name = 'UAE Team Emirates'
GROUP  BY rd.rider_name
ORDER  BY rd.rider_name;
