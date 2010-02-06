-- loads a table of all possible generators that Switch can build
-- the ones that will actually be given to the model as an option will be selected in build WECC cap factors
-- some of the parameters are also not currently in use, but it's good to have them in there in case we want to use them
-- all costs are in $, all fuel paramaters are in MBtu and all energy and power paramaters are in MW or MWh

use generator_info;

drop table if exists generator_costs;
create table if not exists generator_costs (
	technology_id INT NOT NULL PRIMARY KEY,
	technology varchar(30) UNIQUE,
	price_and_dollar_year year,
	min_build_year year,
	fuel varchar(30),
	overnight_cost float,
	fixed_o_m float,
	variable_o_m float,
	overnight_cost_change float,
	connect_cost_per_mw_generic float,
	heat_rate float,
	construction_time_years float,
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
	nonfuel_startup_cost float
);

-- import the data
load data local infile "/Volumes/1TB_RAID/Models/Switch\ Input\ Data/Generators/Generator\ Costs/generator_costs_02-03-2010.csv"
  into table generator_costs 
  fields terminated by ","
  optionally enclosed by '"'
  lines terminated by "\r"
  ignore 1 lines;

update generator_costs 
	set min_build_year = 0 where min_build_year is NULL;
update generator_costs set
	price_and_dollar_year = 0, 
	min_build_year = 0, 
	overnight_cost = 0, 
	fixed_o_m = 0, 
	variable_o_m = 0, 
	overnight_cost_change = 0, 
	connect_cost_per_mw_generic = 0, 
	heat_rate = 0, 
	construction_time_years = 0, 
	max_age_years = 0, 
	forced_outage_rate = 0, 
	scheduled_outage_rate = 0, 
	intermittent = 0, 
	resource_limited = 0, 
	baseload = 0, 
	min_build_capacity = 0, 
	min_dispatch_fraction = 0, 
	min_runtime = 0, 
	min_downtime = 0, 
	max_ramp_rate_mw_per_hour = 0, 
	startup_fuel_mbtu = 0, 
	nonfuel_startup_cost = 0
  where price_and_dollar_year is NULL or price_and_dollar_year = 0;