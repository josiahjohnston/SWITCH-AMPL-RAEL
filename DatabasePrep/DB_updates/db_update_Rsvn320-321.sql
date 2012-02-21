-- This script adds support for multiple carbon cap scenarios. As I write this description, the switch_inputs_wecc_v2_2 database allows a particular run to disable carbon caps or use one particular carbon cap scenario based on California state targets. 

-- A fully-specified scenario from in the scenarios_v2 table will reference a particular set of fuel prices, capital costs, load forecasts, and now carbon caps. Each set is specified independently of others so a fully-specified scenario will pick and choose "fuel price scenario", a capital cost scenario, and so on through each of the categories. Since the word scenario is used so much, I wanted to explain that "fully-specified" scenario means the complete set of inputs that includes a particular "carbon cap" scenario. 

-- The last implementation forced each fully-specified scenario (table scenarios_v2) to enable or disable carbon caps. Another table, carbon_cap_targets, stored annual emmission targets in percent of 1990 levels for 2010 to 2100. That table defined one and only one scenario. 

-- I am going to add a carbon_cap_scenario column to the carbon_cap_targets table to enable multiple co-existing policy scenarios. The table carbon_cap_scenarios will store a textual description of each scenario, and carbon_cap_targets will continue to store annual targets in percentage of 1990 levels. 
-- The presence of both the enable_carbon_cap column and the carbon cap scenario column presents room for potential ambiguity (when enable_carbon_cap is 0, and a valid carbon cap scenario is references, which one do you pay attention to?) and makes model users set a valid reference even when they disable the carbon cap or else code that is relying on a valid carbon_cap_scenario_id will break. 
-- On the other hand, it is nice to be able to disable the carbon cap constraints in AMPL. I don't know if the existance of carbon cap constraints might slow down an LP even when they are not binding by adding complexity. Leaving the enable_carbon_cap column in place enables a direct and transparent link from the record in MySQL and the use of those constraints when AMPL compiles an LP. 
-- So, I'm going to define the default carbon cap scenario to be effectively unbounded and set its id to 0. For some reason the redundancy of the enable_carbon_cap bothers me, so I'll add some logic to the export script to base the enable_carbon_cap flag that ampl expects on whether the carbon cap scenario id is 0 or not. I'll consult with colleagues to determine if upper bounds on variables slows LP solution time. If it doesn't effect runtime, then I'll just always include the carbon cap constraints. 

use switch_inputs_wecc_v2_2;

drop table IF EXISTS carbon_cap_scenarios;
create table carbon_cap_scenarios(
  carbon_cap_scenario_id int unsigned PRIMARY KEY,
  name text,
  description text
);
drop table IF EXISTS _carbon_cap_targets;
create table _carbon_cap_targets(
  carbon_cap_scenario_id INT UNSIGNED,
	year YEAR,
	carbon_emissions_relative_to_base FLOAT,
	PRIMARY KEY (carbon_cap_scenario_id,year),
	FOREIGN KEY (carbon_cap_scenario_id) REFERENCES carbon_cap_scenarios(carbon_cap_scenario_id)
);
drop table IF EXISTS carbon_cap_targets;
drop VIEW IF EXISTS carbon_cap_targets;
CREATE VIEW carbon_cap_targets as
  SELECT carbon_cap_scenario_id, carbon_cap_scenarios.name as carbon_cap_scenario_name, year, carbon_emissions_relative_to_base
    FROM _carbon_cap_targets join carbon_cap_scenarios using (carbon_cap_scenario_id);

load data local infile
	'../carbon_cap_scenarios.csv'
	into table carbon_cap_scenarios
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;
load data local infile
	'../carbon_cap_targets.csv'
	into table _carbon_cap_targets
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;

ALTER TABLE scenarios_v2 
  ADD COLUMN carbon_cap_scenario_id int unsigned DEFAULT 0 COMMENT 'The default scenario is no cap. Browse existing scenarios or define new ones in the table carbon_cap_scenarios.' AFTER `enable_rps`,
  ADD CONSTRAINT carbon_cap_scenario_id FOREIGN KEY carbon_cap_scenario_id (carbon_cap_scenario_id) 
	  REFERENCES carbon_cap_scenarios (carbon_cap_scenario_id)
;

UPDATE scenarios_v2 set 
  carbon_cap_scenario_id = enable_carbon_cap;

ALTER TABLE scenarios_v2
  DROP INDEX `unique_params`,
  ADD UNIQUE INDEX unique_params (training_set_id, regional_cost_multiplier_scenario_id, regional_fuel_cost_scenario_id, gen_price_scenario_id, enable_rps, carbon_cap_scenario_id, model_version, inputs_adjusted),
  DROP COLUMN enable_carbon_cap;

DELIMITER $$
DROP FUNCTION IF EXISTS clone_scenario_v2$$
CREATE FUNCTION clone_scenario_v2 (name varchar(128), model_v varchar(16), inputs_diff varchar(16), source_scenario_id int ) RETURNS int
BEGIN

	DECLARE new_id INT DEFAULT 0;
	INSERT INTO scenarios_v2 (scenario_name, training_set_id, regional_cost_multiplier_scenario_id, regional_fuel_cost_scenario_id, regional_gen_price_scenario_id, enable_rps, carbon_cap_scenario_id, notes, model_version, inputs_adjusted)

  SELECT name, training_set_id, regional_cost_multiplier_scenario_id, regional_fuel_cost_scenario_id, regional_gen_price_scenario_id, enable_rps, carbon_cap_scenario_id, notes, model_v, inputs_diff
		FROM scenarios_v2 where scenario_id=source_scenario_id;

  SELECT LAST_INSERT_ID() into new_id;

  RETURN (new_id);
END$$

DELIMITER ;
