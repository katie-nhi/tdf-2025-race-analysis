-- =====================================================================
-- Constraint tests
-- Run AFTER 01_schema.sql. Part A loads a small valid data set.
-- Part B tries to break each business rule; every test in Part B
-- is EXPECTED TO FAIL with an error and roll back.
-- =====================================================================
\set ON_ERROR_STOP off
\echo '===== PART A: valid sample data ====='

BEGIN;   -- countries, teams and riders go in together (BR 2 is checked at COMMIT)
INSERT INTO country VALUES ('FRA','France'), ('SVN','Slovenia'), ('DNK','Denmark'),
                           ('BEL','Belgium'), ('NLD','Netherlands'), ('USA','United States'),
                           ('ARE','United Arab Emirates');
INSERT INTO team VALUES ('UAE Team Emirates','ARE'), ('Visma Lease a Bike','NLD'),
                        ('Soudal Quick-Step','BEL');
INSERT INTO rider VALUES
 (1,'Tadej Pogacar','1998-09-21','UAE Team Emirates','SVN'),
 (2,'Joao Almeida','1998-08-05','UAE Team Emirates','FRA'),
 (3,'Adam Yates','1992-08-07','UAE Team Emirates','FRA'),
 (11,'Jonas Vingegaard','1996-12-10','Visma Lease a Bike','DNK'),
 (12,'Wout van Aert','1994-09-15','Visma Lease a Bike','BEL'),
 (13,'Matteo Jorgenson','1999-07-01','Visma Lease a Bike','USA'),
 (21,'Remco Evenepoel','2000-01-25','Soudal Quick-Step','BEL'),
 (22,'Ilan Van Wilder','2000-05-14','Soudal Quick-Step','BEL'),
 (23,'Valentin Paret-Peintre','2001-01-14','Soudal Quick-Step','FRA');
COMMIT;

BEGIN;   -- locations and stages together (BR 4 is checked at COMMIT)
INSERT INTO location VALUES ('Lille','FRA'), ('Dunkerque','FRA'), ('Caen','FRA'), ('Paris','FRA');
INSERT INTO stage VALUES
 (1,'2026-07-04','Lille','Dunkerque',185.0,'flat'),
 (2,'2026-07-05','Dunkerque','Caen',210.5,'hilly'),
 (3,'2026-07-06','Caen','Paris',33.0,'individual time-trial');
COMMIT;

BEGIN;
INSERT INTO result VALUES
 (1,1,15600,1,10,0),(11,1,15600,2,6,0),(21,1,15600,3,4,0),(2,1,15620,4,0,0),(12,1,15620,5,0,0),
 (22,1,15640,6,0,0),(3,1,15650,7,0,0),(13,1,15650,8,0,20),(23,1,15700,9,0,0),
 (11,2,18000,1,10,0),(1,2,18005,2,6,0),(21,2,18010,3,4,0),(2,2,18030,4,0,0),(12,2,18030,5,0,0),
 (13,2,18040,6,0,0),(3,2,18060,7,0,0),(22,2,18090,8,0,0),
 (1,3,2400,1,0,0),(21,3,2410,2,0,0),(11,3,2415,3,0,0),(2,3,2450,4,0,0),(12,3,2460,5,0,0),
 (13,3,2470,6,0,0),(3,3,2480,7,0,0),(22,3,2490,8,0,0);
COMMIT;

INSERT INTO exit VALUES (23,2,'Crash in stage 1 - broken collarbone');

INSERT INTO award VALUES
 ('General Classification','Yellow jersey - lowest cumulative time','RIDER',NULL,NULL),
 ('Best Team','Lowest time of three best riders per stage','TEAM',NULL,NULL);
UPDATE award SET winner_bib  = 1                   WHERE award_name = 'General Classification';
UPDATE award SET winner_team = 'Visma Lease a Bike' WHERE award_name = 'Best Team';

\echo '--- row counts ---'
SELECT 'country' t, COUNT(*) FROM country UNION ALL SELECT 'team',COUNT(*) FROM team
UNION ALL SELECT 'rider',COUNT(*) FROM rider UNION ALL SELECT 'location',COUNT(*) FROM location
UNION ALL SELECT 'stage',COUNT(*) FROM stage UNION ALL SELECT 'result',COUNT(*) FROM result
UNION ALL SELECT 'exit',COUNT(*) FROM exit UNION ALL SELECT 'award',COUNT(*) FROM award;

\echo '--- v_result (stage 1, first 3) ---'
SELECT bib_number, stage_id, finish_time_sec, time_bonus_sec, time_penalty_sec, adjusted_time_sec
FROM v_result WHERE stage_id = 1 ORDER BY rank LIMIT 3;
\echo '--- v_general_classification ---'
SELECT * FROM v_general_classification ORDER BY gc_position;
\echo '--- v_best_team ---'
SELECT * FROM v_best_team ORDER BY team_position;

\echo ''
\echo '===== PART B: each statement below MUST be rejected ====='

\echo 'B1  BR1  country code not 3 capital letters'
INSERT INTO country VALUES ('fr','France 2');

\echo 'B2  BR2  team without any rider'
INSERT INTO team VALUES ('Ghost Team','FRA');

\echo 'B3  BR2  deleting the last rider of a team'
BEGIN; DELETE FROM result WHERE bib_number IN (21,22); DELETE FROM exit WHERE bib_number = 23;
DELETE FROM rider WHERE team_name = 'Soudal Quick-Step'; COMMIT;

\echo 'B4  BR3  rider with no team'
INSERT INTO rider VALUES (99,'No Team','2000-01-01',NULL,'FRA');

\echo 'B5  BR3  rider in a team that does not exist'
INSERT INTO rider VALUES (99,'Bad Team','2000-01-01','Nobody','FRA');

\echo 'B6  BR4  location not used by any stage'
INSERT INTO location VALUES ('Nice','FRA');

\echo 'B7  BR5  stage starting and finishing at the same place'
INSERT INTO stage VALUES (4,'2026-07-07','Paris','Paris',100,'flat');

\echo 'B8  BR6  invalid stage type'
INSERT INTO stage VALUES (4,'2026-07-07','Paris','Lille',100,'cobbles');

\echo 'B9  BR7  second result for the same rider and stage'
INSERT INTO result VALUES (1,1,15600,10,0,0);

\echo 'B10 BR8  two riders with the same rank in a stage'
UPDATE result SET rank = 7 WHERE bib_number = 22 AND stage_id = 3;

\echo 'B11 BR8  rank that contradicts finish times'
UPDATE result SET finish_time_sec = 99999 WHERE bib_number = 1 AND stage_id = 1;

\echo 'B12 BR9  result for a rider in the stage they exited before'
INSERT INTO result VALUES (23,2,18100,9,0,0);

\echo 'B13 BR9  exit recorded before a stage the rider already has a result for'
INSERT INTO exit VALUES (22,2,'Illness');

\echo 'B14 BR10 a rider exiting twice'
INSERT INTO exit VALUES (23,3,'Second exit');

\echo 'B15 BR11 an award with both a rider and a team winner'
UPDATE award SET winner_team = 'UAE Team Emirates' WHERE award_name = 'General Classification';

\echo 'B16 BR11 team award given to a rider'
UPDATE award SET winner_bib = 1 WHERE award_name = 'Best Team';

\echo 'B17 FK  deleting a country still referenced by a team'
DELETE FROM country WHERE country_code = 'BEL';

\echo ''
\echo '===== row counts after Part B (must be unchanged) ====='
SELECT 'country' t, COUNT(*) FROM country UNION ALL SELECT 'team',COUNT(*) FROM team
UNION ALL SELECT 'rider',COUNT(*) FROM rider UNION ALL SELECT 'location',COUNT(*) FROM location
UNION ALL SELECT 'stage',COUNT(*) FROM stage UNION ALL SELECT 'result',COUNT(*) FROM result
UNION ALL SELECT 'exit',COUNT(*) FROM exit UNION ALL SELECT 'award',COUNT(*) FROM award;
