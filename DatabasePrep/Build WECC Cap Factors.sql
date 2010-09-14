 -- makes the switch input database from which data is thrown into ampl via 'get_switch_input_tables.sh'
 -- run at command line from the DatabasePrep directory:
 -- mysql -h switch-db1.erg.berkeley.edu -u jimmy -p < /Volumes/1TB_RAID/Models/Switch\ Runs/WECCv2_2/122/DatabasePrep/Build\ WECC\ Cap\ Factors.sql
 
 create database if not exists switch_inputs_wecc_v2_2;
 use switch_inputs_wecc_v2_2;

-- LOAD AREA INFO	
-- made in postgresql
drop table if exists load_area_info;
create table load_area_info(
  load_area varchar(20) NOT NULL,
  primary_nerc_subregion varchar(20),
  primary_state varchar(20),
  economic_multiplier double,
  rps_compliance_year integer,
  rps_compliance_percentage double,
  UNIQUE load_area (load_area)
) ROW_FORMAT=FIXED;

load data local infile
	'wecc_load_area_info.csv'
	into table load_area_info
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;

alter table load_area_info add column scenario_id INT NOT NULL first;
alter table load_area_info add index scenario_id (scenario_id);
alter table load_area_info add column area_id smallint unsigned NOT NULL AUTO_INCREMENT primary key first;

set @load_area_scenario_id := (select if( count(distinct scenario_id) = 0, 1, max(scenario_id)) from load_area_info);

update load_area_info set scenario_id = @load_area_scenario_id;


-- RPS COMPLIANCE INFO
drop table if exists rps_load_area_targets;
create table rps_load_area_targets(
	load_area character varying(11),
	compliance_year year,
	compliance_fraction float,
	PRIMARY KEY (load_area, compliance_year),
	INDEX compliance_year (compliance_year)
	);

load data local infile
	'load_area_yearly_rps_complaince_fractions.csv'
	into table rps_load_area_targets
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;

alter table rps_load_area_targets add column area_id smallint unsigned first;
alter table rps_load_area_targets add unique index (area_id, compliance_year);
update rps_load_area_targets, load_area_info set rps_load_area_targets.area_id = load_area_info.area_id
where rps_load_area_targets.load_area = load_area_info.load_area;
	

-- HOURS-------------------------
-- takes the timepoints table from the weather database, as the solar data is synced to this hournum scheme.  The load data has also been similarly synced.
-- right now the hours only go through 2004-2005
-- incomplete hours will be exculded below in 'Setup_Study_Hours.sql'
drop table if exists hours;
CREATE TABLE hours (
  datetime_utc datetime NOT NULL COMMENT 'date & time in Coordinated Universal Time, with Daylight Savings Time ignored',
  hournum smallint unsigned NOT NULL COMMENT 'hournum = 0 is at datetime_utc = 2004-01-01 00:00:00, and counts up from there',
  UNIQUE KEY datetime_utc (datetime_utc),
  UNIQUE KEY hournum (hournum)
);

insert into hours
select 	timepoint as datetime_utc,
		timepoint_id as hournum
	from weather.timepoints
	where year( timepoint ) < 2006
	order by datetime_utc;

-- SYSTEM LOAD
-- patched together from the old wecc loads...
-- should be improved in the future from FERC data
select 'Compiling Loads' as progress;
drop table if exists _system_load;
CREATE TABLE  _system_load (
  area_id smallint unsigned,
  hour smallint unsigned,
  power double,
  INDEX hour ( hour ),
  INDEX area_id (area_id),
  FOREIGN KEY (area_id) REFERENCES load_area_info(area_id), 
  UNIQUE KEY hour_load_area (hour, area_id)
);

insert into _system_load 
select 	area_id, 
		hournum as hour,
		sum( power * population_fraction) as power
from 	loads_wecc.v1_wecc_load_areas_to_v2_wecc_load_areas,
		loads_wecc.system_load,
		load_area_info
where	v1_load_area = system_load.load_area
and 	v2_load_area = load_area_info.load_area
group by v2_load_area, hour;

DROP VIEW IF EXISTS system_load;
CREATE VIEW system_load as 
  SELECT area_id, load_area, hour, power FROM _system_load JOIN load_area_info USING (area_id);

-- now add a column for projected peak 2010 load in each load area, as
-- the amount of new local T&D needed in each load area will be referenced to this number
alter table load_area_info add column max_coincident_load_for_local_td float;
update load_area_info,
			(select _system_load.area_id,
					datetime_utc,
					max_load
				from _system_load,
					hours,
					(SELECT area_id, max(power) as max_load FROM _system_load group by 1) as max_load_table
				where _system_load.power = max_load_table.max_load
				and _system_load.area_id = max_load_table.area_id
				and hours.hournum = _system_load.hour) as max_load_hour_table
set max_coincident_load_for_local_td = max_load * power(1.010, 2010 - year( datetime_utc ) )
where load_area_info.area_id = max_load_hour_table.area_id;

-- add a column for projected total MWh 2010 load in each load area, as
-- the sunk costs of local t&d and transmission will be based off these costs
alter table load_area_info add column total_yearly_load_mwh float;
update 	load_area_info,
		(select area_id,
				total_load_mwh / ( number_of_load_hours / 8766 ) as total_yearly_load_mwh
			from
			(select area_id,
					count(hour) as number_of_load_hours,
					sum( power * power( 1.010, 2010 - year( datetime_utc ) ) ) as total_load_mwh
				from _system_load, hours
				where _system_load.hour = hours.hournum
				group by 1) as mwh_table
		) as avg_load_table
set load_area_info.total_yearly_load_mwh = avg_load_table.total_yearly_load_mwh
where load_area_info.area_id = avg_load_table.area_id;

-- also add the local_td_new_annual_payment_per_mw ($2007/MW), which comes from EIA AEO data
-- and is complied in /Volumes/1TB_RAID/Models/Switch\ Input\ Data/Transmission/Sunk\ Costs/Calc_trans_dist_sunk_costs_WECC.xlsx
-- these already have a version of an economic multiplier built in, so we won't multiply by the regional economic multiplier here
-- Canada is assumed to be similar to NWPP and Mexico Baja CA is assumed to be similar to AZNMSNV
alter table load_area_info add column local_td_new_annual_payment_per_mw float;
update load_area_info set local_td_new_annual_payment_per_mw = 
	CASE 	WHEN primary_nerc_subregion = 'NWPP' THEN 66406.47311
			WHEN primary_nerc_subregion = 'NWPP Can' THEN 66406.47311
			WHEN primary_nerc_subregion = 'CA' THEN 128039.8671
			WHEN primary_nerc_subregion = 'AZNMSNV' THEN 61663.36634
			WHEN primary_nerc_subregion = 'RMPA' THEN 61663.36634
			WHEN primary_nerc_subregion = 'MX' THEN 61663.36634
	END;

-- add yearly costs for maintaining the existing distribution system
-- the cost per MWh is multiplied by the total_yearly_load_mwh to get the full cost per load area 
alter table load_area_info add column local_td_sunk_annual_payment float;
update load_area_info set local_td_sunk_annual_payment = 
	total_yearly_load_mwh *
	CASE 	WHEN primary_nerc_subregion = 'NWPP' THEN 19.2
			WHEN primary_nerc_subregion = 'NWPP Can' THEN 19.2
			WHEN primary_nerc_subregion = 'CA' THEN 45.12
			WHEN primary_nerc_subregion = 'AZNMSNV' THEN 20.16
			WHEN primary_nerc_subregion = 'RMPA' THEN 20.16
			WHEN primary_nerc_subregion = 'MX' THEN 20.16
	END;

-- similar to above, add yearly costs for maintaining the existing transmission system
alter table load_area_info add column transmission_sunk_annual_payment float;
update load_area_info set transmission_sunk_annual_payment = 
	total_yearly_load_mwh *
	CASE 	WHEN primary_nerc_subregion = 'NWPP' THEN 8.64
			WHEN primary_nerc_subregion = 'NWPP Can' THEN 8.64
			WHEN primary_nerc_subregion = 'CA' THEN 6.72
			WHEN primary_nerc_subregion = 'AZNMSNV' THEN 6.72
			WHEN primary_nerc_subregion = 'RMPA' THEN 6.72
			WHEN primary_nerc_subregion = 'MX' THEN 6.72
	END;


-- Study Hours----------------------
select 'Setting Up Study Hours' as progress;
source Setup_Study_Hours.sql;


-- TRANS LINES----------
-- made in postgresql
select 'Copying Trans Lines' as progress;
drop table if exists transmission_lines;
create table transmission_lines(
	transmission_line_id int primary key,
	load_area_start varchar(11),
	load_area_end varchar(11),
	existing_transfer_capacity_mw double,
	transmission_length_km double,
	load_areas_border_each_other char(1),
	transmission_efficiency double,
	INDEX la_start_end (load_area_start, load_area_end)
);

load data local infile
	'wecc_trans_lines.csv'
	into table transmission_lines
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;


-- ---------------------------------------------------------------------
--        NON-REGIONAL GENERATOR INFO
-- ---------------------------------------------------------------------
select 'Copying Generator and Fuel Info' as progress;

DROP TABLE IF EXISTS generator_info;
create table generator_info (
	technology_id tinyint unsigned NOT NULL PRIMARY KEY,
	technology varchar(64) UNIQUE,
	min_build_year year,
	fuel varchar(64),
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
	can_build_new boolean,
	storage boolean
);
insert into generator_info
 select 
 	technology_id,
 	technology,
	min_build_year,
	fuel,
	heat_rate,
	construction_time_years,
	year_1_cost_fraction,
	year_2_cost_fraction,
	year_3_cost_fraction,
	year_4_cost_fraction,
	year_5_cost_fraction,
	year_6_cost_fraction,
	max_age_years,
	forced_outage_rate,
	scheduled_outage_rate,
	intermittent,
	resource_limited,
	baseload,
	min_build_capacity,
	min_dispatch_fraction,
	min_runtime,
	min_downtime,
	max_ramp_rate_mw_per_hour,
	startup_fuel_mbtu,
	can_build_new,
	storage
 from generator_info.generator_costs;

-- ---------------------------------------------------------------------
--        REGION-SPECIFIC GENERATOR COSTS & AVAILIBILITY
-- ---------------------------------------------------------------------

-- FUEL PRICES-------------
-- run 'v2 wecc fuel price import no elasticity.sql' first

drop table if exists _fuel_prices_regional;
CREATE TABLE _fuel_prices_regional (
  scenario_id INT NOT NULL,
  area_id smallint unsigned NOT NULL,
  fuel VARCHAR(64),
  year year,
  fuel_price FLOAT NOT NULL COMMENT 'Regional fuel prices for various types of fuel in $2007 per MMBtu',
  INDEX scenario_id(scenario_id),
  INDEX area_id(area_id),
  INDEX year_idx (year),
  PRIMARY KEY (scenario_id, area_id, fuel, year),
  CONSTRAINT area_id FOREIGN KEY area_id (area_id) REFERENCES load_area_info (area_id)
);

set @this_scenario_id := (select if( max(scenario_id) + 1 is null, 1, max(scenario_id) + 1 ) from _fuel_prices_regional);
  
insert into _fuel_prices_regional
	select
		@this_scenario_id as scenario_id,
        area_id,
        if(fuel like 'NaturalGas', 'Gas', fuel),
        year,
        fuel_price
    from fuel_prices.regional_fuel_prices, load_area_info
    where load_area_info.load_area = fuel_prices.regional_fuel_prices.load_area
    and fuel not like 'DistillateFuelOil'
    and fuel not like 'ResidualFuelOil';

-- TODO: the fuel prices above go out to 2030 - if we want to do scenarios out further
-- (including toys with an 8 year, 2026-2033 investment period) then we need fuel prices out further.
-- write code that extrapolates the fuel price linearly to 2050 for years in which there aren't fuel price projections

  
DROP VIEW IF EXISTS fuel_prices_regional;
CREATE VIEW fuel_prices_regional as
SELECT _fuel_prices_regional.scenario_id, load_area_info.area_id, load_area, fuel, year, fuel_price 
    FROM _fuel_prices_regional, load_area_info
    WHERE _fuel_prices_regional.area_id = load_area_info.area_id;

-- RPS----------------------
drop table if exists fuel_info;
create table fuel_info(
	fuel varchar(64),
	rps_fuel_category varchar(10), 
	carbon_content float COMMENT 'carbon content (tonnes CO2 per million Btu)'
);

-- gas converted from http://www.eia.doe.gov/oiaf/1605/coefficients.html
-- this page says nevada and arizona coal are around 205-208 pounds per million Btu: http://www.eia.doe.gov/cneaf/coal/quarterly/co2_article/co2.html
-- Nuclear, Geothermal, Biomass, Water, Wind and Solar have non-zero LCA emissions. To model those emissions, we'd need to divide carbon content into capital, fixed, 
--   and variable emissions. Currently, this only lists variable emissions. 
insert into fuel_info (fuel, rps_fuel_category, carbon_content) values
	('Gas', 'fossilish', 0.0531),
	('Wind', 'renewable', 0),
	('Solar', 'renewable', 0),
	('Bio_Solid', 'renewable', 0),
	('Bio_Gas', 'renewable', 0),
	('Coal', 'fossilish', 0.0939),
	('Uranium', 'fossilish', 0),
	('Geothermal', 'renewable', 0),
	('Water', 'fossilish', 0);


drop table if exists fuel_qualifies_for_rps;
create table fuel_qualifies_for_rps(
	area_id smallint unsigned NOT NULL,
	load_area varchar(11),
	rps_fuel_category varchar(10),
	qualifies boolean,
	INDEX area_id (area_id),
  	CONSTRAINT area_id FOREIGN KEY area_id (area_id) REFERENCES load_area_info (area_id)
);

insert into fuel_qualifies_for_rps
	select distinct 
	        area_id,
			load_area,
			rps_fuel_category,
			if(rps_fuel_category like 'renewable', 1, 0)
		from fuel_info, load_area_info;


-- HYDRO-------------------
-- made in 'build existing plants table.sql'
select 'Copying Hydro' as progress;

drop table if exists hydro_monthly_limits;
CREATE TABLE hydro_monthly_limits (
  project_id int unsigned,
  hydro_id mediumint unsigned,
  area_id smallint unsigned,
  load_area varchar(20),
  technology varchar(64), 
  technology_id tinyint unsigned NOT NULL,
  year year,
  month tinyint(4),
  capacity_mw double,
  avg_output double,
  INDEX ym (year,month),
  INDEX (area_id),
  INDEX (project_id),
  INDEX (technology),
  PRIMARY KEY (project_id, year, month),
  UNIQUE (area_id, technology_id, year, month),
  FOREIGN KEY (area_id) REFERENCES load_area_info(area_id)
) ROW_FORMAT=FIXED;

-- The << operation moves the numeric form of the letter "H" (for hydro) over by 3 bytes, effectively making its value into the most significant digits.
insert into hydro_monthly_limits (project_id, hydro_id, area_id, load_area, technology, technology_id, year, month, capacity_mw, avg_output )
	select 
	  agg.hydro_id + (ascii( 'H' ) << 8*3),
	  agg.hydro_id, area_id, agg.load_area,
	  technology, technology_id,
	  year, month, capacity_mw, avg_output
	from generator_info, generator_info.hydro_monthly_limits_agg agg join load_area_info using(load_area)
	where generator_info.technology = 	CASE WHEN agg.primemover = 'HY' THEN 'Hydro_NonPumped'
										WHEN agg.primemover = 'PS' THEN 'Hydro_Pumped' END;

-- EXISTING PLANTS---------
-- made in 'build existing plants table.sql'
select 'Copying existing_plants' as progress;

drop table if exists existing_plants;
CREATE TABLE existing_plants (
    project_id int unsigned PRIMARY KEY,
    ep_id mediumint unsigned,
	area_id smallint unsigned,
	load_area varchar(11),
	plant_code varchar(40),
	primemover varchar(10),
	fuel varchar(20),
	peak_mw double,
	heat_rate double,
	start_year year,
	baseload boolean,
	cogen boolean,
	overnight_cost double,
	fixed_o_m double,
	variable_o_m double,
	forced_outage_rate double,
	scheduled_outage_rate double,
	max_age double,
	intermittent boolean,
	technology varchar(64),
	INDEX area_id (area_id),
	FOREIGN KEY (area_id) REFERENCES load_area_info(area_id), 
	INDEX load_area_plant_code (load_area, plant_code)
) ROW_FORMAT=FIXED;

 -- The << operation moves the numeric form of the letter "E" (for existing plants) over by 3 bytes, effectively making its value into the most significant digits.
insert into existing_plants (project_id, area_id, ep_id, load_area, plant_code, primemover, fuel, peak_mw, heat_rate, start_year, baseload, cogen, overnight_cost, fixed_o_m, variable_o_m, forced_outage_rate, scheduled_outage_rate, max_age, intermittent, technology )
	select 	existing_plants_agg.ep_id + (ascii( 'E' ) << 8*3),
			load_area_info.area_id,
			existing_plants_agg.*
			from generator_info.existing_plants_agg
			join load_area_info using(load_area);


drop table if exists _existing_intermittent_plant_cap_factor;
create table _existing_intermittent_plant_cap_factor(
		project_id int unsigned,
		area_id smallint unsigned,
		hour smallint unsigned,
		cap_factor float,
		INDEX eip_index (area_id, project_id, hour),
		INDEX hour (hour),
		INDEX project_id (project_id),
		PRIMARY KEY (project_id, hour),
		FOREIGN KEY project_id (project_id) REFERENCES existing_plants (project_id),
		FOREIGN KEY (area_id) REFERENCES load_area_info(area_id)
);

DROP VIEW IF EXISTS existing_intermittent_plant_cap_factor;
CREATE VIEW existing_intermittent_plant_cap_factor as
  SELECT cp.project_id, plant_code, load_area, cp.area_id, hour, cap_factor
    FROM _existing_intermittent_plant_cap_factor cp join existing_plants using (project_id);


insert into _existing_intermittent_plant_cap_factor
SELECT      existing_plants.project_id,
            existing_plants.area_id,
            hournum as hour,
            3tier.windfarms_existing_cap_factor.cap_factor
    from    existing_plants, 
            3tier.windfarms_existing_cap_factor
    where   technology = 'Wind_EP'
    and		concat('Wind_EP', '_', 3tier.windfarms_existing_cap_factor.windfarm_existing_id) = existing_plants.plant_code;



-- ---------------------------------------------------------------------
-- PROPOSED PROJECTS--------------
-- imported from postgresql, this table has all pv, csp, wind, geothermal, biomass and compressed air energy storage sites
-- if this table is remade, the avg cap factors must be reinserted (see below) 
-- ---------------------------------------------------------------------
drop table if exists proposed_projects_import;
create temporary table proposed_projects_import(
	project_id bigint PRIMARY KEY,
	technology varchar(30),
	original_dataset_id integer NOT NULL,
	load_area varchar(11),
	capacity_limit float,
 	capacity_limit_conversion float,
	connect_cost_per_mw double,
	location_id INT,
	INDEX project_id (project_id),
	INDEX load_area (load_area),
	UNIQUE (technology, location_id, load_area)
);
	
load data local infile
	'proposed_projects.csv'
	into table proposed_projects_import
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;	


drop table if exists _proposed_projects;
CREATE TABLE _proposed_projects (
  project_id int unsigned default NULL,
  gen_info_project_id mediumint unsigned PRIMARY KEY AUTO_INCREMENT,
  technology_id tinyint unsigned NOT NULL,
  area_id smallint unsigned NOT NULL,
  location_id INT DEFAULT NULL,
  technology varchar(64),
  original_dataset_id INT DEFAULT NULL,
  capacity_limit float DEFAULT NULL,
  capacity_limit_conversion float DEFAULT 1,
  connect_cost_per_mw float,
  price_and_dollar_year year(4),
  overnight_cost float,
  fixed_o_m float,
  variable_o_m float,
  overnight_cost_change float,
  nonfuel_startup_cost float,
  avg_cap_factor_intermittent float default NULL,
  avg_cap_factor_percentile_by_intermittent_tech float default NULL,
  cumulative_avg_MW_tech_load_area float default NULL,
  rank_by_tech_in_load_area int default NULL,
  INDEX project_id (project_id),
  INDEX area_id (area_id),
  INDEX technology_and_location (technology, location_id),
  INDEX technology_id (technology_id),
  INDEX location_id (location_id),
  INDEX original_dataset_id (original_dataset_id),
  INDEX original_dataset_id_tech_id (original_dataset_id, technology_id),
  INDEX avg_cap_factor_percentile_by_intermittent_tech_idx (avg_cap_factor_percentile_by_intermittent_tech),
  INDEX rank_by_tech_in_load_area_idx (rank_by_tech_in_load_area),
  UNIQUE (technology_id, original_dataset_id, area_id),
  UNIQUE (technology_id, location_id, area_id),
  FOREIGN KEY (area_id) REFERENCES load_area_info(area_id), 
  FOREIGN KEY (technology_id) REFERENCES generator_info (technology_id)
) ROW_FORMAT=FIXED;


-- the capacity limit is either in MW if the capacity_limit_conversion is 1, or in other units if the capacity_limit_conversion is nonzero
-- so for CSP and central PV the limit is expressed in land area, not MW
-- The << operation moves the numeric form of the letter "G" (for generators) over by 3 bytes, effectively making its value into the most significant digits.
-- change to 'P' on a complete rebuild of the database to make this more clear
insert into _proposed_projects
	(project_id, gen_info_project_id, technology_id, technology, area_id, location_id, original_dataset_id,
	capacity_limit, capacity_limit_conversion, connect_cost_per_mw, price_and_dollar_year,
	overnight_cost, fixed_o_m, variable_o_m, overnight_cost_change, nonfuel_startup_cost)
	select  project_id + (ascii( 'G' ) << 8*3),
	        project_id,
	        technology_id,
	        technology,
			area_id,
			location_id,
			original_dataset_id,
			capacity_limit,
			capacity_limit_conversion,
			(connect_cost_per_mw + connect_cost_per_mw_generic) * economic_multiplier  as connect_cost_per_mw,
    		price_and_dollar_year,  
   			overnight_cost * economic_multiplier       as overnight_cost,
    		fixed_o_m * economic_multiplier            as fixed_o_m,
    		variable_o_m * economic_multiplier         as variable_o_m,
   			overnight_cost_change,
   			nonfuel_startup_cost * economic_multiplier as nonfuel_startup_cost
			
	from proposed_projects_import join generator_info.generator_costs using (technology) join load_area_info using (load_area)
	order by 2;


-- UPDATE CSP COSTS - they're done differently!
-- to go backwards to aperture from mw_per_km2 (capacity_limit_conversion), use this:
-- ( pow( (sqrt( ( 1000000 * 100 ) / capacity_limit_conversion ) - 15 ), 2 ) - 15625 ) / ( 1.06315118 * 3 )
-- see proposed_projects.sql in the GIS directory for more info.

-- the cost of a solar thermal trough plant as a function of field area, per MW is $420/m^2 * (1 + 0.247),
-- as the indirect costs are 24.7% of the direct field costs
-- the costs in the database for CSP Trough are for sample 100MW plants,
-- with areas of 600000m^2 for CSP_Trough_No_Storage and 800000m^2 for CSP_Trough_6h_Storage,
-- so first we find the difference between the above assumed area and the calculated area (the third and forth lines),
-- then divide the difference by 100 to get the per MW cost difference
-- then multiply by 420 * (1 + 0.247) to find the difference in cost from the reference,
-- then finally add the reference cost to obtain the total CSP Trough cost

update _proposed_projects set overnight_cost = 
		overnight_cost + 420 * (1 + 0.247) *
		( ( ( pow( (sqrt( ( 1000000 * 100 ) / capacity_limit_conversion ) - 15 ), 2 ) - 15625 ) / ( 1.06315118 * 3 )
		- if( technology = 'CSP_Trough_No_Storage', 600000, 800000 ) ) / 100 ) 
where technology in ('CSP_Trough_No_Storage', 'CSP_Trough_6h_Storage');

-- Insert "generic" projects that can be built almost anywhere. These used to be in the table  _generator_costs_regional.
-- Note, project_id is automatically set here because it is an autoincrement column. The renewable proposed_projects with ids set a-priori need to be imported first to avoid unique id conflicts.
 -- The << operation moves the numeric form of the letter "G" (for generic projects) over by 3 bytes, effectively making its value into the most significant digits.
insert into _proposed_projects
	(technology_id, technology, area_id, connect_cost_per_mw, price_and_dollar_year,
	overnight_cost, fixed_o_m, variable_o_m, overnight_cost_change, nonfuel_startup_cost)
    select 	technology_id,
    		technology,
    		area_id,
    		connect_cost_per_mw_generic * economic_multiplier as connect_cost_per_mw,
    		price_and_dollar_year,  
   			overnight_cost * economic_multiplier as overnight_cost,
    		fixed_o_m * economic_multiplier as fixed_o_m,
    		variable_o_m * economic_multiplier as variable_o_m,
   			overnight_cost_change,
   			nonfuel_startup_cost * economic_multiplier as nonfuel_startup_cost
    from 	generator_info.generator_costs gen_costs,
			load_area_info
	where   gen_costs.can_build_new  = 1 and 
	        gen_costs.resource_limited = 0
	order by 1,3;
UPDATE _proposed_projects SET project_id = gen_info_project_id + (ascii( 'G' ) << 8*3) where project_id is null;

-- regional generator restrictions
-- Coal_ST and Nuclear can't be built in CA. Nuclear can't be built in Mexico.
delete from _proposed_projects
 	where 	(technology_id in (select technology_id from generator_info where fuel in ('Uranium', 'Coal')) and
			area_id in (select area_id from load_area_info where primary_nerc_subregion like 'CA'));
delete from _proposed_projects
 	where 	(technology_id in (select technology_id from generator_info where fuel in ('Uranium')) and
			area_id in (select area_id from load_area_info where primary_nerc_subregion like 'MX'));

DROP VIEW IF EXISTS proposed_projects;
CREATE VIEW proposed_projects as
  SELECT 	project_id, 
            gen_info_project_id,
            technology_id, 
            technology, 
            area_id, 
            load_area,
            location_id, 
            original_dataset_id, 
            capacity_limit, 
            capacity_limit_conversion, 
            connect_cost_per_mw,
            price_and_dollar_year,
            overnight_cost,
            fixed_o_m,
            variable_o_m,
            overnight_cost_change,
            nonfuel_startup_cost,
            avg_cap_factor_intermittent,
            avg_cap_factor_percentile_by_intermittent_tech,
            cumulative_avg_MW_tech_load_area,
            rank_by_tech_in_load_area
    FROM _proposed_projects 
    join load_area_info using (area_id);
    



-- ---------------------------------------------------------------------
-- CAP FACTOR-----------------
-- assembles the hourly power output for wind and solar technologies
drop table if exists _cap_factor_intermittent_sites;
create table _cap_factor_intermittent_sites(
	project_id int unsigned,
	hour smallint unsigned,
	cap_factor float,
	INDEX project_id (project_id),
	INDEX hour (hour),
	PRIMARY KEY (project_id, hour),
	CONSTRAINT project_fk FOREIGN KEY project_id (project_id) REFERENCES proposed_projects (project_id)
);


DROP VIEW IF EXISTS cap_factor_intermittent_sites;
CREATE VIEW cap_factor_intermittent_sites as
  SELECT 	cp.project_id,
  			technology,
  			load_area_info.area_id,
  			load_area,
  			location_id,
  			original_dataset_id,
  			hour,
  			cap_factor
    FROM _cap_factor_intermittent_sites cp
    join proposed_projects using (project_id)
    join load_area_info using (load_area);
    
    
-- includes Wind and Offshore_Wind
select 'Compiling Wind' as progress;
insert into _cap_factor_intermittent_sites
SELECT      proposed_projects.project_id,
            3tier.wind_farm_power_output.hournum as hour,
            3tier.wind_farm_power_output.cap_factor
    from    proposed_projects, 
            3tier.wind_farm_power_output
    where   technology in ('Wind', 'Offshore_Wind')
    and		proposed_projects.original_dataset_id = 3tier.wind_farm_power_output.wind_farm_id;

-- REMOVE when CSP_Trough_6h_Storage is finished in SAM
-- these cap factors for some reason don't have the 31st of December, 2004... as long as this isnt sampled,
-- then it's fine and it will get fixed once we're finished with SAM
select 'Compiling CSP_Trough_6h_Storage' as progress;
insert into _cap_factor_intermittent_sites
SELECT      proposed_projects.project_id,
            hournum as hour,
            3tier.csp_power_output.e_net_mw/100 as cap_factor
    from    proposed_projects, 
            3tier.csp_power_output,
            hours
    where   proposed_projects.technology_id = 7
    and		proposed_projects.original_dataset_id = 3tier.csp_power_output.siteid
    and		3tier.csp_power_output.datetime_utc = hours.datetime_utc;


-- includes Residential_PV, Commercial_PV, Central_PV, CSP_Trough_No_Storage and CSP_Trough_6h_Storage
-- CSP_Trough_6h_Storage broken at the moment from the Solar_Advisor_Model... taken care of below
-- remove the <> 7 to reinsert it, and delete the extra script below
select 'Compiling Solar' as progress;
insert into _cap_factor_intermittent_sites
SELECT      proposed_projects.project_id,
            hournum as hour,
            cap_factor
    from    proposed_projects,
            suny.solar_farm_cap_factors
    where   proposed_projects.original_dataset_id = solar_farm_cap_factors.solar_farm_id
    and		proposed_projects.technology_id = solar_farm_cap_factors.technology_id
    and 	proposed_projects.technology_id <> 7;


select 'Calculating Average Cap Factors' as progress;
-- calculate average capacity factors for subsampling purposes
-- and count the number of capacity factors for each intermittent project to check for completeness
drop table if exists avg_cap_factor_table;
create table avg_cap_factor_table (
	project_id int unsigned primary key,
	avg_cap_factor float,
	number_of_cap_factor_hours int);

insert into avg_cap_factor_table
	select	project_id,
			avg(cap_factor) as avg_cap_factor,
			count(*) as number_of_cap_factor_hours
		from _cap_factor_intermittent_sites
		group by project_id;

-- put the average cap factor values in proposed projects for easier access
update	_proposed_projects,
		avg_cap_factor_table
set	_proposed_projects.avg_cap_factor_intermittent = avg_cap_factor_table.avg_cap_factor
where _proposed_projects.project_id = avg_cap_factor_table.project_id;

-- ----------------------------
select 'Checking Cap Factors' as progress;
-- first, output the number of points with incomplete hours
-- as many of the sites are missing the first few hours of output due to the change from local to utc time,
-- we'll consider a site complete if it has cap factors for all hours from 2004-2005,
-- so ( 366 days in 2004 + 365 days in 2005 - 1 day ) * 24 hours per day is about 17500
select 	proposed_projects.*,
		number_of_cap_factor_hours
	from 	avg_cap_factor_table,
			proposed_projects
	where number_of_cap_factor_hours < 17500
	and	avg_cap_factor_table.project_id = proposed_projects.project_id
	order by project_id;
		
-- also, make sure each intermittent site has cap factors
select 	proposed_projects.*
	from 	proposed_projects,
			generator_info
	where	proposed_projects.technology_id = generator_info.technology_id
	and		generator_info.intermittent = 1
	and		project_id not in (select project_id from avg_cap_factor_table where number_of_cap_factor_hours >= 17500)
	order by project_id, generator_info.technology;
	
-- delete the projects that don't have cap factors
-- for the WECC, if nothing is messed up, this means Central_PV on the eastern border of Colorado that contains
-- a few grid points didn't get simulated because they were too far east... only 16 total solar farms out of thousands
drop table if exists project_ids_to_delete;
create temporary table project_ids_to_delete as 
 	select 	_proposed_projects.project_id
 		from 	_proposed_projects join generator_info using (technology_id)
 		where	generator_info.intermittent = 1
 		and		project_id not in (select project_id from avg_cap_factor_table where number_of_cap_factor_hours >= 17500)
 		order by project_id, generator_info.technology;
 		
 delete from _proposed_projects where project_id in (select project_id from project_ids_to_delete);

-- --------------------
select 'Calculating Intermittent Resource Quality Ranks' as progress;
DROP PROCEDURE IF EXISTS determine_intermittent_cap_factor_rank;
delimiter $$
CREATE PROCEDURE determine_intermittent_cap_factor_rank()
BEGIN

declare current_ordering_id int;
declare rank_total float;

-- RANK BY TECH--------------------------
-- add the avg_cap_factor_percentile_by_intermittent_tech values
-- which will be used to subsample the larger range of intermittent tech hourly values
drop table if exists rank_table;
create table rank_table (
	ordering_id int unsigned PRIMARY KEY AUTO_INCREMENT,
	project_id int unsigned NOT NULL,
	technology_id tinyint unsigned NOT NULL,
	avg_MW double,
	INDEX ord_tech (ordering_id, technology_id),
	INDEX tech (technology_id),
	INDEX ord_proj (ordering_id, project_id)
	);

insert into rank_table (project_id, technology_id, avg_MW)
	select project_id, technology_id, capacity_limit * capacity_limit_conversion * avg_cap_factor_intermittent as avg_MW from _proposed_projects
	where avg_cap_factor_intermittent is not null
	order by technology_id, avg_cap_factor_intermittent;

set current_ordering_id = (select min(ordering_id) from rank_table);

rank_loop_total: LOOP

	-- find the rank by technology class such that all resources above a certain class can be included
	set rank_total = 
		(select 	sum(avg_MW)/total_tech_avg_mw
			from 	rank_table,
					(select sum(avg_MW) as total_tech_avg_mw
						from rank_table
						where technology_id = (select technology_id from rank_table where ordering_id = current_ordering_id)
					) as total_tech_capacity_table
			where ordering_id <= current_ordering_id
			and technology_id = (select technology_id from rank_table where ordering_id = current_ordering_id)
		);
			
	update _proposed_projects, rank_table
	set avg_cap_factor_percentile_by_intermittent_tech = rank_total
	where rank_table.project_id = _proposed_projects.project_id
	and rank_table.ordering_id = current_ordering_id;
	
	set current_ordering_id = current_ordering_id + 1;        
	
IF current_ordering_id > (select max(ordering_id) from rank_table)
	THEN LEAVE rank_loop_total;
    	END IF;
END LOOP rank_loop_total;

drop table rank_table;

END;
$$
delimiter ;

CALL determine_intermittent_cap_factor_rank;
DROP PROCEDURE IF EXISTS determine_intermittent_cap_factor_rank;


-- CUMULATIVE AVERAGE MW AND RANK IN EACH LOAD AREA BY TECH-------------------------
-- find the amount of average MW of each technology in each load area at or above the level of each project
-- also get the rank in each load area for each tech 
DROP PROCEDURE IF EXISTS cumulative_intermittent_cap_factor_rank;
delimiter $$
CREATE PROCEDURE cumulative_intermittent_cap_factor_rank()
BEGIN

declare current_ordering_id int;
declare cumulative_avg_MW float;
declare rank_load_area float;

drop table if exists cumulative_gen_load_area_table;
create table cumulative_gen_load_area_table (
	ordering_id int unsigned PRIMARY KEY AUTO_INCREMENT,
	project_id int unsigned NOT NULL,
	technology_id tinyint unsigned NOT NULL,
	area_id smallint unsigned NOT NULL,
  	avg_MW double,
	INDEX ord_tech (ordering_id, technology_id),
	INDEX tech (technology_id),
	INDEX ord_proj (ordering_id, project_id),
	INDEX area_id (area_id),
	INDEX ord_tech_area (ordering_id, technology_id, area_id),
	INDEX ord_proj_area (ordering_id, project_id, area_id)
	);

insert into cumulative_gen_load_area_table (project_id, technology_id, area_id, avg_MW)
	select 	project_id, technology_id, area_id,
			capacity_limit * capacity_limit_conversion * avg_cap_factor_intermittent as avg_MW
		from _proposed_projects
		where avg_cap_factor_intermittent is not null
		order by technology_id, area_id, avg_cap_factor_intermittent;


set current_ordering_id = (select min(ordering_id) from cumulative_gen_load_area_table);

cumulative_capacity_loop: LOOP

	set cumulative_avg_MW = 
		(select 	sum(avg_MW) 
			from 	cumulative_gen_load_area_table
			where ordering_id >= current_ordering_id
			and technology_id = (select technology_id from cumulative_gen_load_area_table where ordering_id = current_ordering_id)
			and area_id = (select area_id from cumulative_gen_load_area_table where ordering_id = current_ordering_id)
		);

	set rank_load_area = 
		(select 	count(*) 
			from 	cumulative_gen_load_area_table
			where ordering_id >= current_ordering_id
			and technology_id = (select technology_id from cumulative_gen_load_area_table where ordering_id = current_ordering_id)
			and area_id = (select area_id from cumulative_gen_load_area_table where ordering_id = current_ordering_id)
		);
			
	update _proposed_projects, cumulative_gen_load_area_table
	set cumulative_avg_MW_tech_load_area = cumulative_avg_MW,
		rank_by_tech_in_load_area = rank_load_area
	where cumulative_gen_load_area_table.project_id = _proposed_projects.project_id
	and cumulative_gen_load_area_table.ordering_id = current_ordering_id;
	
	
	set current_ordering_id = current_ordering_id + 1;        
	
IF current_ordering_id > (select max(ordering_id) from cumulative_capacity_load_area_table)
	THEN LEAVE cumulative_capacity_loop;
		END IF;
END LOOP cumulative_capacity_loop;

drop table cumulative_gen_load_area_table;

END;
$$
delimiter ;

CALL cumulative_intermittent_cap_factor_rank;
DROP PROCEDURE IF EXISTS cumulative_intermittent_cap_factor_rank;

