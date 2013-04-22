-- This script sets up a range of carbon cap scenarios in the id block of 2-8.

use switch_inputs_wecc_v2_2;
create temporary table tmp_cc_scenario (id int unsigned, p2020 float, p2030 float);
INSERT INTO tmp_cc_scenario VALUES 
  (2,  1.0, 0.5),
  (3,  1.0, 0.45),
  (4,  1.0, 0.4),
  (5,  1.0, 0.35),
  (6,  1.0, 0.3),
  (7,  1.0, 0.25),
  (8,  1.0, 0.2),
  (9,  1.0, 0.15),
  (10, 1.0, 0.1),
  (11, 1.0, 0.05),
  (12, 1.0, 0);

-- Clear out any prior entries
DELETE FROM carbon_cap_scenarios
  WHERE carbon_cap_scenario_id IN (SELECT id FROM tmp_cc_scenario);
DELETE FROM _carbon_cap_targets
  WHERE carbon_cap_scenario_id IN (SELECT id FROM tmp_cc_scenario);

-- Make new scenario entries
INSERT INTO carbon_cap_scenarios (carbon_cap_scenario_id, name, description)
  SELECT id, concat( round(100*(1-p2030)), '% by 2030'), 
    concat( 'CA targets for 2010 to 2020, then a linear decrease from 100% of 1990 levels in 2020 to ', round(100*(1-p2030)), '% by 2030, and continuing on that slope to zero emissions.')
  FROM tmp_cc_scenario
  ORDER BY id
;

-- Copy CA targets from scenario id 1 for 2010 to 2020. 
INSERT INTO _carbon_cap_targets (carbon_cap_scenario_id, year, carbon_emissions_relative_to_base ) 
  SELECT id, year, carbon_emissions_relative_to_base
  FROM tmp_cc_scenario, _carbon_cap_targets
  WHERE _carbon_cap_targets.carbon_cap_scenario_id = 1 AND year <= 2020
  ORDER BY 1,2;

-- Do a linear extrapolation for 2020 to 2100 using the slope from 2020 to 2030
INSERT INTO _carbon_cap_targets (carbon_cap_scenario_id, year, carbon_emissions_relative_to_base ) 
  SELECT id, year, 
    (p2020-p2030)/(2020-2030)*(year-2020) + p2020
  FROM tmp_cc_scenario, _carbon_cap_targets
  WHERE _carbon_cap_targets.carbon_cap_scenario_id = 1 AND year > 2020
  ORDER BY 1,2;

-- Set negative emission values to 0
UPDATE _carbon_cap_targets 
  SET carbon_emissions_relative_to_base = 0
  WHERE carbon_emissions_relative_to_base < 0
    AND carbon_cap_scenario_id IN (SELECT id FROM tmp_cc_scenario);

-- CARBON CAP SCENARIO 13 and 14--------------
-- these targets get to 90% and 120% below 1990 levels by 2050 

-- Make new scenario entries
INSERT INTO carbon_cap_scenarios (carbon_cap_scenario_id, name, description) VALUES
  (13, '10% by 2050', 'CA targets for 2010 to 2020, then a linear decrease from 100% of 1990 levels in 2020 to 10% by 2050, and continuing on that slope to zero emissions.'),
  (14, '-20% by 2050', 'CA targets for 2010 to 2020, then a linear decrease from 100% of 1990 levels in 2020 to -20% by 2050, and continuing on that slope to -40% emissions'),
  (15, '-40% by 2050', 'CA targets for 2010 to 2020, then a linear decrease from 100% of 1990 levels in 2020 to -40% by 2050, and continuing on that slope to -60% emissions'),
  (16, '-50% by 2050', 'CA targets for 2010 to 2020, then a linear decrease from 100% of 1990 levels in 2020 to -50% by 2050, and continuing on that slope to -70% emissions');

-- Copy CA targets from scenario id 1 for 2010 to 2020. 
INSERT INTO _carbon_cap_targets (carbon_cap_scenario_id, year, carbon_emissions_relative_to_base ) 
  SELECT id, year, carbon_emissions_relative_to_base
  FROM (SELECT 13 AS id UNION SELECT 14 UNION SELECT 15 UNION SELECT 16) as new_id_table, _carbon_cap_targets
  WHERE _carbon_cap_targets.carbon_cap_scenario_id = 1 AND year <= 2020
  ORDER BY 1,2;

-- Do a linear extrapolation for 2020 to 2100 using the slope from 2020 to 2050
INSERT INTO _carbon_cap_targets (carbon_cap_scenario_id, year, carbon_emissions_relative_to_base ) 
  SELECT 13, year, 
    (1-0.1)/(2020-2050)*(year-2020) + 1
  FROM _carbon_cap_targets
  WHERE _carbon_cap_targets.carbon_cap_scenario_id = 1 AND year > 2020
  ORDER BY 1,2;

UPDATE _carbon_cap_targets 
  SET carbon_emissions_relative_to_base = 0
  WHERE carbon_emissions_relative_to_base < 0
    AND carbon_cap_scenario_id = 13;

INSERT INTO _carbon_cap_targets (carbon_cap_scenario_id, year, carbon_emissions_relative_to_base ) 
  SELECT 14, year, 
    (1+0.2)/(2020-2050)*(year-2020) + 1
  FROM _carbon_cap_targets
  WHERE _carbon_cap_targets.carbon_cap_scenario_id = 1 AND year > 2020
  ORDER BY 1,2;

UPDATE _carbon_cap_targets 
  SET carbon_emissions_relative_to_base = -0.4
  WHERE carbon_emissions_relative_to_base < -0.4
    AND carbon_cap_scenario_id = 14;

INSERT INTO _carbon_cap_targets (carbon_cap_scenario_id, year, carbon_emissions_relative_to_base ) 
  SELECT 15, year, 
    (1+0.4)/(2020-2050)*(year-2020) + 1
  FROM _carbon_cap_targets
  WHERE _carbon_cap_targets.carbon_cap_scenario_id = 1 AND year > 2020
  ORDER BY 1,2;

UPDATE _carbon_cap_targets 
  SET carbon_emissions_relative_to_base = -0.6
  WHERE carbon_emissions_relative_to_base < -0.6
    AND carbon_cap_scenario_id = 15;

INSERT INTO _carbon_cap_targets (carbon_cap_scenario_id, year, carbon_emissions_relative_to_base ) 
  SELECT 16, year, 
    (1+0.5)/(2020-2050)*(year-2020) + 1
  FROM _carbon_cap_targets
  WHERE _carbon_cap_targets.carbon_cap_scenario_id = 1 AND year > 2020
  ORDER BY 1,2;

UPDATE _carbon_cap_targets 
  SET carbon_emissions_relative_to_base = -0.7
  WHERE carbon_emissions_relative_to_base < -0.7
    AND carbon_cap_scenario_id = 16;