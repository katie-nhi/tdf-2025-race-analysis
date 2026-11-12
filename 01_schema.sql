-- =====================================================================
-- Tour de France 2025 Race Analytics - Relational schema (PostgreSQL)
--
-- Translated from the ER diagram (docs/er_diagram.png) using standard
-- ER-to-relational translation rules:
--   Rule 1  attributes      -> columns with domains (types + CHECKs)
--   Rule 2  entity types    -> tables; key -> PRIMARY KEY; derived omitted
--   Rule 3  relationships   -> tables (none needed: no M:N remains)
--   Rule 4  1:1 / 1:N       -> merged into the (x,1) side as a FOREIGN KEY
--   Rule 5  total (1,1)     -> the merged FK is declared NOT NULL
--   Rule 6  weak entities   -> owner key (+ partial key) as PRIMARY KEY
--
-- Business-rule numbers (BR n) refer to docs/business_rules.md.
-- Run order: this whole file, top to bottom, in one session.
-- =====================================================================

SET client_min_messages = warning;

DROP VIEW  IF EXISTS v_best_team, v_general_classification, v_result CASCADE;
DROP TABLE IF EXISTS award, exit, result, stage, location, rider, team, country CASCADE;
DROP FUNCTION IF EXISTS trg_team_has_rider(), trg_location_is_used(),
                        trg_result_after_exit(), trg_exit_before_results(),
                        trg_rank_order() CASCADE;

-- ---------------------------------------------------------------------
-- 1. COUNTRY                                         (BR 1)
--    Entity -> table. No FK: a country may exist with no team/rider,
--    which is exactly the (0,n) on Country's side of every relationship.
-- ---------------------------------------------------------------------
CREATE TABLE country (
    country_code  CHAR(3)       PRIMARY KEY
                  CHECK (country_code ~ '^[A-Z]{3}$'),      -- ISO 3166-1 alpha-3 format
    country_name  VARCHAR(100)  NOT NULL UNIQUE             -- candidate key
);

-- ---------------------------------------------------------------------
-- 2. TEAM                                            (BR 2)
--    Based_in: Team (1,1) - Country (0,n)  -> FK on team, NOT NULL.
--    "At least one rider" (Team (1,n) in Rides_for) cannot be a column
--    constraint: see deferred trigger trg_team_has_rider below.
-- ---------------------------------------------------------------------
CREATE TABLE team (
    team_name     VARCHAR(100)  PRIMARY KEY,
    country_code  CHAR(3)       NOT NULL
                  REFERENCES country(country_code)
                  ON UPDATE CASCADE
);

-- ---------------------------------------------------------------------
-- 3. RIDER                                           (BR 3)
--    Rides_for:  Rider (1,1) - Team (1,n)     -> FK team_name NOT NULL
--    Represents: Rider (1,1) - Country (0,n)  -> FK country_code NOT NULL
--    Two independent FKs, so rider nationality may differ from team's.
-- ---------------------------------------------------------------------
CREATE TABLE rider (
    bib_number     INT           PRIMARY KEY CHECK (bib_number > 0),
    rider_name     VARCHAR(100)  NOT NULL,
    date_of_birth  DATE          NOT NULL,
    team_name      VARCHAR(100)  NOT NULL
                   REFERENCES team(team_name)
                   ON UPDATE CASCADE,
    country_code   CHAR(3)       NOT NULL
                   REFERENCES country(country_code)
                   ON UPDATE CASCADE
);

-- ---------------------------------------------------------------------
-- 4. LOCATION                                        (BR 4)
--    Located_in: Location (1,1) - Country (0,n) -> FK NOT NULL.
--    "Only stored if used by a stage" -> deferred trigger below.
-- ---------------------------------------------------------------------
CREATE TABLE location (
    location_name  VARCHAR(100)  PRIMARY KEY,
    country_code   CHAR(3)       NOT NULL
                   REFERENCES country(country_code)
                   ON UPDATE CASCADE
);

-- ---------------------------------------------------------------------
-- 5. STAGE                                           (BR 5, 6)
--    Starts_at / Finishes_at: Stage (1,1) - Location (0,n)
--    -> two separate FKs into location, both NOT NULL.
--    stage_id is the stage number and gives race order (used by BR 9).
-- ---------------------------------------------------------------------
CREATE TABLE stage (
    stage_id         INT           PRIMARY KEY CHECK (stage_id > 0),
    stage_date       DATE          NOT NULL,
    start_location   VARCHAR(100)  NOT NULL
                     REFERENCES location(location_name)
                     ON UPDATE CASCADE,
    finish_location  VARCHAR(100)  NOT NULL
                     REFERENCES location(location_name)
                     ON UPDATE CASCADE,
    distance_km      NUMERIC(5,1)  NOT NULL CHECK (distance_km > 0),
    stage_type       VARCHAR(25)   NOT NULL
                     CHECK (stage_type IN ('flat', 'hilly', 'mountain',
                                           'individual time-trial')),
    CONSTRAINT stage_start_ne_finish
        CHECK (start_location <> finish_location)               -- BR 5
);

-- ---------------------------------------------------------------------
-- 6. RESULT  (weak entity, owners Rider and Stage)   (BR 7, 8, 12)
--    Rule 6: PK = keys of both owners. This table is also how the
--    many-to-many "rider completes stage" association is resolved.
--    adjusted_time is DERIVED -> omitted (Rule 2); see view v_result.
-- ---------------------------------------------------------------------
CREATE TABLE result (
    bib_number        INT  NOT NULL
                      REFERENCES rider(bib_number)
                      ON UPDATE CASCADE ON DELETE CASCADE,
    stage_id          INT  NOT NULL
                      REFERENCES stage(stage_id)
                      ON UPDATE CASCADE ON DELETE CASCADE,
    finish_time_sec   INT  NOT NULL CHECK (finish_time_sec > 0),
    rank              INT  NOT NULL CHECK (rank > 0),
    time_bonus_sec    INT  NOT NULL DEFAULT 0 CHECK (time_bonus_sec   >= 0),
    time_penalty_sec  INT  NOT NULL DEFAULT 0 CHECK (time_penalty_sec >= 0),
    PRIMARY KEY (bib_number, stage_id),
    CONSTRAINT result_rank_unique UNIQUE (stage_id, rank)       -- BR 8: one rider per rank
);

-- ---------------------------------------------------------------------
-- 7. EXIT  (weak entity, owner Rider)                (BR 9, 10)
--    Exit_of is the identifying relationship and Rider's side is (0,1),
--    so the owner key bib_number alone is the PK (at most one exit).
--    Before_stage: Exit (1,1) - Stage (0,n) -> FK stage_id NOT NULL.
-- ---------------------------------------------------------------------
CREATE TABLE exit (
    bib_number  INT           PRIMARY KEY
                REFERENCES rider(bib_number)
                ON UPDATE CASCADE ON DELETE CASCADE,
    stage_id    INT           NOT NULL
                REFERENCES stage(stage_id)
                ON UPDATE CASCADE,
    reason      VARCHAR(255)  NOT NULL
);

-- ---------------------------------------------------------------------
-- 8. AWARD (Classification/Award)                    (BR 11, 13, 14)
--    Won_by_rider: Award (0,1) - Rider (0,n) -> nullable FK winner_bib
--    Won_by_team:  Award (0,1) - Team  (0,n) -> nullable FK winner_team
--    award_type is a small refinement over the ER diagram so that a team award
--    can never be given to a rider (and vice versa).
-- ---------------------------------------------------------------------
CREATE TABLE award (
    award_name   VARCHAR(100)  PRIMARY KEY,
    description  VARCHAR(255),
    award_type   VARCHAR(5)    NOT NULL CHECK (award_type IN ('RIDER', 'TEAM')),
    winner_bib   INT           REFERENCES rider(bib_number)
                               ON UPDATE CASCADE ON DELETE SET NULL,
    winner_team  VARCHAR(100)  REFERENCES team(team_name)
                               ON UPDATE CASCADE ON DELETE SET NULL,
    -- BR 11: never both. Both NULL is allowed until the award is decided.
    CONSTRAINT award_single_winner CHECK (
        (award_type = 'RIDER' AND winner_team IS NULL) OR
        (award_type = 'TEAM'  AND winner_bib  IS NULL)
    )
);

-- =====================================================================
-- Constraints the column/table syntax cannot express -> triggers
-- =====================================================================

-- BR 2: every team has at least one rider.
-- DEFERRABLE INITIALLY DEFERRED: the check runs at COMMIT, so a team and
-- its riders can be inserted in one transaction (team first, then riders).
CREATE FUNCTION trg_team_has_rider() RETURNS trigger AS $$
DECLARE t VARCHAR(100);
BEGIN
    IF TG_TABLE_NAME = 'team' THEN t := NEW.team_name;
    ELSE                           t := OLD.team_name;   -- rider moved/deleted
    END IF;
    IF EXISTS (SELECT 1 FROM team WHERE team_name = t)
       AND NOT EXISTS (SELECT 1 FROM rider WHERE team_name = t) THEN
        RAISE EXCEPTION 'BR2 violated: team "%" has no riders', t;
    END IF;
    RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER team_has_rider_on_team
    AFTER INSERT OR UPDATE ON team
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION trg_team_has_rider();

CREATE CONSTRAINT TRIGGER team_has_rider_on_rider
    AFTER UPDATE OF team_name OR DELETE ON rider
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION trg_team_has_rider();

-- BR 4: a location is stored only if it starts or finishes some stage.
CREATE FUNCTION trg_location_is_used() RETURNS trigger AS $$
DECLARE loc VARCHAR(100);
BEGIN
    IF TG_TABLE_NAME = 'location' THEN
        PERFORM 1 WHERE EXISTS (SELECT 1 FROM location WHERE location_name = NEW.location_name)
                AND NOT EXISTS (SELECT 1 FROM stage
                                WHERE NEW.location_name IN (start_location, finish_location));
        IF FOUND THEN
            RAISE EXCEPTION 'BR4 violated: location "%" is not used by any stage', NEW.location_name;
        END IF;
    ELSE  -- a stage was changed or deleted: its old locations must still be used
        FOREACH loc IN ARRAY ARRAY[OLD.start_location, OLD.finish_location] LOOP
            IF EXISTS (SELECT 1 FROM location WHERE location_name = loc)
               AND NOT EXISTS (SELECT 1 FROM stage WHERE loc IN (start_location, finish_location)) THEN
                RAISE EXCEPTION 'BR4 violated: location "%" is no longer used by any stage', loc;
            END IF;
        END LOOP;
    END IF;
    RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER location_is_used_on_location
    AFTER INSERT OR UPDATE ON location
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION trg_location_is_used();

CREATE CONSTRAINT TRIGGER location_is_used_on_stage
    AFTER UPDATE OF start_location, finish_location OR DELETE ON stage
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION trg_location_is_used();

-- BR 9 (direction 1): no result for a rider at or after the stage they exited before.
CREATE FUNCTION trg_result_after_exit() RETURNS trigger AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM exit e
               WHERE e.bib_number = NEW.bib_number
                 AND NEW.stage_id >= e.stage_id) THEN
        RAISE EXCEPTION 'BR9 violated: rider % exited before stage % or earlier',
                        NEW.bib_number, NEW.stage_id;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER result_after_exit
    BEFORE INSERT OR UPDATE ON result
    FOR EACH ROW EXECUTE FUNCTION trg_result_after_exit();

-- BR 9 (direction 2): cannot record an exit if results already exist from that stage on.
CREATE FUNCTION trg_exit_before_results() RETURNS trigger AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM result r
               WHERE r.bib_number = NEW.bib_number
                 AND r.stage_id >= NEW.stage_id) THEN
        RAISE EXCEPTION 'BR9 violated: rider % already has results from stage % onwards',
                        NEW.bib_number, NEW.stage_id;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER exit_before_results
    BEFORE INSERT OR UPDATE ON exit
    FOR EACH ROW EXECUTE FUNCTION trg_exit_before_results();

-- BR 8: within a stage, rank must follow finishing time
-- (a better rank can never have a slower finish time; equal times may take any order).
-- Deferred, so a whole stage's results can be loaded before it is checked.
CREATE FUNCTION trg_rank_order() RETURNS trigger AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM result a JOIN result b
                 ON a.stage_id = b.stage_id
               WHERE a.stage_id = NEW.stage_id
                 AND a.rank < b.rank
                 AND a.finish_time_sec > b.finish_time_sec) THEN
        RAISE EXCEPTION 'BR8 violated: ranks in stage % do not follow finish times', NEW.stage_id;
    END IF;
    RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER rank_order
    AFTER INSERT OR UPDATE ON result
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION trg_rank_order();

-- =====================================================================
-- Derived data -> views (not stored, so they can never go stale)
-- =====================================================================

-- BR 12: adjusted time = finish time - time bonus + time penalty
CREATE VIEW v_result AS
SELECT r.*,
       r.finish_time_sec - r.time_bonus_sec + r.time_penalty_sec AS adjusted_time_sec
FROM   result r;

-- BR 14: General Classification = lowest cumulative adjusted time.
-- Only riders still in the race (no exit) are classified.
CREATE VIEW v_general_classification AS
SELECT RANK() OVER (ORDER BY SUM(v.adjusted_time_sec)) AS gc_position,
       v.bib_number, rd.rider_name, rd.team_name,
       COUNT(*)                AS stages_completed,
       SUM(v.adjusted_time_sec) AS total_adjusted_time_sec
FROM   v_result v
JOIN   rider rd ON rd.bib_number = v.bib_number
WHERE  NOT EXISTS (SELECT 1 FROM exit e WHERE e.bib_number = v.bib_number)
GROUP  BY v.bib_number, rd.rider_name, rd.team_name;

-- BR 13: Best Team = lowest aggregate of the three fastest riders per stage,
-- summed over stages (official Tour method; uses finish time without bonuses).
CREATE VIEW v_best_team AS
WITH ranked AS (
    SELECT rd.team_name, r.stage_id, r.finish_time_sec,
           ROW_NUMBER() OVER (PARTITION BY rd.team_name, r.stage_id
                              ORDER BY r.finish_time_sec, r.rank) AS pos_in_team
    FROM   result r JOIN rider rd ON rd.bib_number = r.bib_number
),
per_stage AS (
    SELECT team_name, stage_id, SUM(finish_time_sec) AS stage_team_time
    FROM   ranked
    WHERE  pos_in_team <= 3
    GROUP  BY team_name, stage_id
    HAVING COUNT(*) = 3                       -- team needs 3 finishers on the stage
)
SELECT RANK() OVER (ORDER BY SUM(stage_team_time)) AS team_position,
       team_name,
       COUNT(*)             AS stages_counted,
       SUM(stage_team_time) AS total_team_time_sec
FROM   per_stage
GROUP  BY team_name
-- a team must have 3 finishers on every stage raced so far to be classified
HAVING COUNT(*) = (SELECT COUNT(DISTINCT stage_id) FROM result);
