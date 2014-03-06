-- This script sets up a uniform range of carbon cap scenarios ranging from 100% to 0% of 1990 levels for cost sensitivity analysis
use switch_inputs_wecc_v2_2;

create temporary table tmp_cc_scenario (id int unsigned, p2020 float, p2050 float);
INSERT INTO tmp_cc_scenario VALUES 
  (51, 1.0, 1),
  (52, 1.0, 0.95),
  (53, 1.0, 0.9),
  (54, 1.0, 0.85),
  (55, 1.0, 0.8),
  (56, 1.0, 0.75),
  (57, 1.0, 0.7),
  (58, 1.0, 0.65),
  (59, 1.0, 0.6),
  (60, 1.0, 0.55),
  (61, 1.0, 0.5),
  (62, 1.0, 0.45),
  (63, 1.0, 0.4),
  (64, 1.0, 0.35),
  (65, 1.0, 0.3),
  (66, 1.0, 0.25),
  (67, 1.0, 0.225),
  (68, 1.0, 0.2),
  (69, 1.0, 0.175),
  (70, 1.0, 0.15),
  (71, 1.0, 0.125),
  (72, 1.0, 0.1),
  (73, 1.0, 0.075),
  (74, 1.0, 0.05),
  (75, 1.0, 0.025),
  (76, 1.0, 0)
;

-- Make new carbon cap scenario entries
INSERT INTO carbon_cap_scenarios (carbon_cap_scenario_id, name, description)
  SELECT id, concat( round(100*(1-p2050)), '% by 2050'), 
    concat( 'CA targets for 2010 to 2020, then a linear decrease from 100% of 1990 levels in 2020 to ', round(100*(1-p2050)), '% by 2050, and continuing on that slope to zero emissions.')
  FROM tmp_cc_scenario
  ORDER BY id
;

-- Make yearly goals

-- Copy CA targets from scenario id 1 for 2010 to 2020. 
INSERT INTO _carbon_cap_targets (carbon_cap_scenario_id, year, carbon_emissions_relative_to_base ) 
  SELECT id, year, carbon_emissions_relative_to_base
  FROM tmp_cc_scenario, _carbon_cap_targets
  WHERE _carbon_cap_targets.carbon_cap_scenario_id = 1 AND year <= 2020
  ORDER BY 1,2;

-- Do a linear extrapolation for 2020 to 2100 using the slope from 2020 to 2050.
-- Use an if statement to prevent the carbon cap from dipping below 0%. 
INSERT INTO _carbon_cap_targets (carbon_cap_scenario_id, year, carbon_emissions_relative_to_base ) 
  SELECT id, year, 
    if((@target:=(p2020-p2050)/(2020-2050)*(year-2020) + p2020) < 0, 0, @target)
  FROM tmp_cc_scenario, _carbon_cap_targets
  WHERE _carbon_cap_targets.carbon_cap_scenario_id = 1 AND year > 2020
  ORDER BY 1,2;


-- Make new complete scenarios that vary from a base
set @base_scenario := 9170;
INSERT INTO scenarios_v3 (scenario_name, training_set_id, regional_cost_multiplier_scenario_id,
  regional_fuel_cost_scenario_id, gen_costs_scenario_id, gen_info_scenario_id, enable_rps,
  nems_fuel_scenario_id, dr_scenario_id, ev_scenario_id, enforce_ca_dg_mandate, linearize_optimization,
  carbon_cap_scenario_id, notes)
SELECT CONCAT(round(100*(1-p2050),1), '% reduct. cap sensitivity'), 
  training_set_id, regional_cost_multiplier_scenario_id,
  regional_fuel_cost_scenario_id, gen_costs_scenario_id, gen_info_scenario_id, enable_rps,
  nems_fuel_scenario_id, dr_scenario_id, ev_scenario_id, enforce_ca_dg_mandate, linearize_optimization,
  tmp_cc_scenario.id AS carbon_cap_scenario_id, 
  'Carbon cap sensitivity on base no ccs scenario' as notes
  FROM scenarios_v3, tmp_cc_scenario
  WHERE scenario_id=@base_scenario;
