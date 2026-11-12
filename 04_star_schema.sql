-- Star schema for analytics: dim_country, dim_team, dim_rider, dim_stage and fact_result
-- (grain: one rider on one stage), loaded from the normalised tables. Tested on PostgreSQL 16.

DROP TABLE IF EXISTS fact_result, dim_rider, dim_team, dim_stage, dim_country CASCADE;
CREATE TABLE dim_country (country_key SERIAL PRIMARY KEY, country_code CHAR(3) UNIQUE, country_name VARCHAR(100));
CREATE TABLE dim_team    (team_key SERIAL PRIMARY KEY, team_name VARCHAR(100) UNIQUE, team_country_name VARCHAR(100));
CREATE TABLE dim_rider   (rider_key SERIAL PRIMARY KEY, bib_number INT UNIQUE, rider_name VARCHAR(100),
                          date_of_birth DATE, is_young BOOLEAN, team_name VARCHAR(100), nationality VARCHAR(100),
                          exit_stage INT, exit_reason VARCHAR(255));
CREATE TABLE dim_stage   (stage_key SERIAL PRIMARY KEY, stage_id INT UNIQUE, stage_date DATE, stage_type VARCHAR(25),
                          distance_km NUMERIC(5,1), start_location VARCHAR(100), finish_location VARCHAR(100));
CREATE TABLE fact_result (
    rider_key INT REFERENCES dim_rider, stage_key INT REFERENCES dim_stage,
    team_key  INT REFERENCES dim_team,  country_key INT REFERENCES dim_country,
    finish_time_sec INT, time_bonus_sec INT, time_penalty_sec INT, adjusted_time_sec INT, rank INT,
    is_win BOOLEAN, is_podium BOOLEAN, is_top10 BOOLEAN,
    PRIMARY KEY (rider_key, stage_key));

INSERT INTO dim_country (country_code, country_name) SELECT country_code, country_name FROM country;
INSERT INTO dim_team (team_name, team_country_name)
  SELECT t.team_name, c.country_name FROM team t JOIN country c USING (country_code);
INSERT INTO dim_rider (bib_number, rider_name, date_of_birth, is_young, team_name, nationality, exit_stage, exit_reason)
  SELECT r.bib_number, r.rider_name, r.date_of_birth, r.date_of_birth >= DATE '2000-01-01',
         r.team_name, c.country_name, e.stage_id, e.reason
  FROM rider r JOIN country c USING (country_code) LEFT JOIN exit e USING (bib_number);
INSERT INTO dim_stage (stage_id, stage_date, stage_type, distance_km, start_location, finish_location)
  SELECT stage_id, stage_date, stage_type, distance_km, start_location, finish_location FROM stage;
INSERT INTO fact_result
  SELECT dr.rider_key, ds.stage_key, dt.team_key, dc.country_key,
         v.finish_time_sec, v.time_bonus_sec, v.time_penalty_sec, v.adjusted_time_sec, v.rank,
         v.rank = 1, v.rank <= 3, v.rank <= 10
  FROM v_result v
  JOIN rider r      ON r.bib_number = v.bib_number
  JOIN dim_rider dr ON dr.bib_number = v.bib_number
  JOIN dim_stage ds ON ds.stage_id = v.stage_id
  JOIN dim_team dt  ON dt.team_name = r.team_name
  JOIN dim_country dc ON dc.country_code = r.country_code;

\echo STAR: top-10 by terrain
SELECT dr.rider_name, COUNT(*) FILTER (WHERE f.is_top10) top10,
       COUNT(*) FILTER (WHERE f.is_top10 AND ds.stage_type='flat') flat
FROM fact_result f JOIN dim_rider dr USING (rider_key) JOIN dim_stage ds USING (stage_key)
GROUP BY dr.rider_name ORDER BY top10 DESC LIMIT 3;
\echo STAR: wins per nationality
SELECT dc.country_name, COUNT(*) FILTER (WHERE f.is_win) wins
FROM fact_result f JOIN dim_country dc USING (country_key) GROUP BY dc.country_name ORDER BY wins DESC;
