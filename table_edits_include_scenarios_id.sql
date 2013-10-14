--
-- October/Wednesday 2nd/2013
-- patricia.hidalgo.g@berkeley.edu
--
-- This script is meant to be executed once, and kept as record of the changes.

--------------------------------------------------------------------------------------------

-- EDITIONS TO INCLUDE SCENARIO ID

--------------------------------------------------------------------------------------------

SET search_path TO chile;

ALTER TABLE scenarios_switch_chile ADD COLUMN carbon_cap_id SMALLINT;
ALTER TABLE scenarios_switch_chile ADD COLUMN rps_id SMALLINT; --done
-- rps_id has to be 0 when no rps is forced
ALTER TABLE scenarios_switch_chile ADD COLUMN sic_sing_id SMALLINT; --done
-- sic_sing_id=0 means that it will not be built
ALTER TABLE scenarios_switch_chile ADD COLUMN fuel_cost_id SMALLINT; --done
ALTER TABLE scenarios_switch_chile ADD COLUMN new_project_portfolio_id SMALLINT; --done
-- demand_scenario_id was already included in the table training_sets



-- new_project_portfolio_id ---------------------------------------------------------------- 
-- New new projects table: new_projects_v2
-- id = 0, 1, 2 and, 3 correspond to new_projects, new_projects_alternative_1, new_projects_alternative_2 and, new_projects_alternative_3, respectively.

ALTER TABLE new_projects ADD COLUMN new_project_portfolio_id SMALLINT;
ALTER TABLE new_projects_alternative_1 ADD COLUMN new_project_portfolio_id SMALLINT;
ALTER TABLE new_projects_alternative_2 ADD COLUMN new_project_portfolio_id SMALLINT;
ALTER TABLE new_projects_alternative_3 ADD COLUMN new_project_portfolio_id SMALLINT;

UPDATE new_projects SET new_project_portfolio_id = 0;
UPDATE new_projects_alternative_1 SET new_project_portfolio_id = 1;
UPDATE new_projects_alternative_2 SET new_project_portfolio_id = 2;
UPDATE new_projects_alternative_3 SET new_project_portfolio_id = 3;

DROP TABLE IF EXISTS new_projects_v2;
CREATE TABLE new_projects_v2 AS SELECT * FROM new_projects;

INSERT INTO new_projects_v2 SELECT * FROM new_projects_alternative_1;
INSERT INTO new_projects_v2 SELECT * FROM new_projects_alternative_2;
INSERT INTO new_projects_v2 SELECT * FROM new_projects_alternative_3;
--------------------------------------------------------------------------------------------


-- fuel_cost_id ----------------------------------------------------------------------------
-- id = 0 corresponds to the intial fuel_costs

ALTER TABLE fuel_prices ADD COLUMN fuel_cost_id SMALLINT;

UPDATE fuel_prices SET fuel_cost_id = 0;
--------------------------------------------------------------------------------------------


-- rps_id ----------------------------------------------------------------------------
-- id = 0, 1, 2 and, 3 corresponds to 10%, 20%, 30% and, 50% RPS

ALTER TABLE rps_compliance_entity_targets ADD COLUMN rps_id SMALLINT;
ALTER TABLE rps_compliance_entity_targets20 ADD COLUMN rps_id SMALLINT;
ALTER TABLE rps_compliance_entity_targets30 ADD COLUMN rps_id SMALLINT;
ALTER TABLE rps_compliance_entity_targets50 ADD COLUMN rps_id SMALLINT;

UPDATE rps_compliance_entity_targets SET rps_id = 0;
UPDATE rps_compliance_entity_targets20 SET rps_id = 1;
UPDATE rps_compliance_entity_targets30 SET rps_id = 2;
UPDATE rps_compliance_entity_targets50 SET rps_id = 3;

DROP TABLE IF EXISTS rps_compliance_entity_targets_v2;
CREATE TABLE rps_compliance_entity_targets_v2 AS SELECT * FROM rps_compliance_entity_targets;

INSERT INTO rps_compliance_entity_targets_v2 SELECT * FROM rps_compliance_entity_targets20;
INSERT INTO rps_compliance_entity_targets_v2 SELECT * FROM rps_compliance_entity_targets30;
INSERT INTO rps_compliance_entity_targets_v2 SELECT * FROM rps_compliance_entity_targets50;
--------------------------------------------------------------------------------------------

-- Filling scenarios_switch_chile ----------------------------------------------------------

-- scenario_id = 1000
UPDATE scenarios_switch_chile SET carbon_cap_id = 0 WHERE scenario_id = 1000;
UPDATE scenarios_switch_chile SET rps_id = 0 WHERE scenario_id = 1000;
UPDATE scenarios_switch_chile SET sic_sing_id = 0 WHERE scenario_id = 1000;
UPDATE scenarios_switch_chile SET fuel_cost_id = 0 WHERE scenario_id = 1000;
UPDATE scenarios_switch_chile SET new_project_portfolio_id = 0 WHERE scenario_id = 1000;














