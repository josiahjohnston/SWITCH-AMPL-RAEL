-- loads a table of all possible generators that Switch can build
-- the ones that will actually be given to the model as an option will be selected in build WECC cap factors
-- some of the parameters are also not currently in use, but it's good to have them in there in case we want to use them
-- all costs are in $, all fuel paramaters are in MBtu and all energy and power paramaters are in MW or MWh

use generator_info;

drop table if exists generator_costs;
create table generator_costs (
	technology_id tinyint unsigned NOT NULL PRIMARY KEY,
	technology varchar(64) UNIQUE,
	price_and_dollar_year year,
	min_build_year year,
	fuel varchar(64),
	overnight_cost float,
	fixed_o_m float,
	variable_o_m float,
	overnight_cost_change float,
	connect_cost_per_mw_generic float,
	heat_rate float,
	construction_time_years float,
	year_1_cost_fraction float,
	year_2_cost_fraction float,
	year_3_cost_fraction float,
	year_4_cost_fraction float,
	year_5_cost_fraction float,
	year_6_cost_fraction float,
	max_age_years float,
	forced_outage_rate float,
	scheduled_outage_rate float,
	intermittent boolean,
	resource_limited boolean,
	baseload boolean,
	min_build_capacity float,
	min_dispatch_fraction float,
	min_runtime int,
	min_downtime int,
	max_ramp_rate_mw_per_hour float,
	startup_fuel_mbtu float,
	nonfuel_startup_cost float, 
	can_build_new tinyint,
	storage tinyint,
	index techology_id_name (technology_id, technology)
);

-- import the data
load data local infile "generator_costs.csv"
  into table generator_costs 
  fields terminated by ","
  optionally enclosed by '"'
  lines terminated by "\r"
  ignore 1 lines;
