# Business rules and how they are enforced

Declarative constraints (primary key, foreign key, `NOT NULL`, `UNIQUE`, `CHECK`) are used wherever possible. Rules that span rows or tables are enforced by triggers. Derived values are views, never stored.

| BR | Rule | Mechanism |
|---|---|---|
| 1 | A country is identified by its ISO 3166-1 alpha-3 code and may exist with no team or rider | PK; `CHECK (country_code ~ '^[A-Z]{3}$')`; no FK out of `country` |
| 2 | A team has exactly one country and at least one rider | `NOT NULL` FK; deferred constraint trigger `team_has_rider` (checked at commit) |
| 3 | A rider has exactly one team and one country, which may differ from the team's | Two independent `NOT NULL` FKs |
| 4 | A location has one country, and is stored only if a stage starts or finishes there | `NOT NULL` FK; deferred constraint trigger `location_is_used` |
| 5 | A stage's start differs from its finish | Row `CHECK (start_location <> finish_location)` |
| 6 | A stage has one date, one start, one finish and a valid type | `NOT NULL`; `CHECK stage_type IN ('flat','hilly','mountain','individual time-trial')` |
| 7 | One result per rider per stage | Composite PK `(bib_number, stage_id)` |
| 8 | Rank captures finishing order | `UNIQUE (stage_id, rank)`; deferred trigger `rank_order` (a better rank never has a slower time) |
| 9 | No results for a rider from the stage they exited before | `BEFORE` triggers on both `result` and `exit` |
| 10 | A rider exits at most once | `exit` PK = `bib_number` |
| 11 | An award is won by a rider or a team, never both | `CHECK award_single_winner` with `award_type` |
| 12 | Adjusted time = finish − bonus + penalty | View `v_result` |
| 13 | Best team = lowest total of each team's three fastest riders per stage | View `v_best_team` |
| 14 | General classification = lowest cumulative adjusted time | View `v_general_classification` |

## Why some triggers are deferred

A rider cannot be inserted before their team exists (foreign key), yet a team is invalid until it has a rider (BR 2). Inserting a team and its riders in one transaction, and checking BR 2 at `COMMIT`, resolves the conflict. BR 4 (locations and stages) and BR 8 (a whole stage's results loaded before rank order is checked) follow the same pattern.

## Referential actions

- `ON UPDATE CASCADE` on every FK, because all keys are natural keys.
- `ON DELETE CASCADE` only from an owner to its weak entities (`rider` → `result`, `exit`; `stage` → `result`).
- `ON DELETE SET NULL` from `award` to its winner.
- Default `NO ACTION` everywhere else, so nothing still referenced can be deleted.
