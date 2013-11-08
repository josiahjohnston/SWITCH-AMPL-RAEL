-- makes the switch input database from which data is thrown into ampl via 'get_switch_input_tables.sh'
  
create database if not exists switch_inputs_wecc_v2_2;
use switch_inputs_wecc_v2_2;
 
-- LOAD AREA INFO	
-- made in postgresql
drop table if exists load_area_info;
create table load_area_info(
  area_id smallint primary key,
  load_area varchar(20) NOT NULL,
  primary_nerc_subregion varchar(20),
  primary_state varchar(20),
  economic_multiplier NUMERIC(3,2),
  rps_compliance_entity varchar(20),
  ccs_distance_km NUMERIC(5,2),
  UNIQUE load_area (load_area)
) ROW_FORMAT=FIXED;

load data local infile
	'wecc_load_area_info.csv'
	into table load_area_info
	fields terminated by	','
	optionally enclosed by '"'
	lines terminated by "\r"
	ignore 1 lines;

-- add nems_region column for fuel supply curves
alter table load_area_info add column nems_fuel_region varchar(20);

-- for now these actually match up to the primary nerc subregion/balancing areas, but I wanted to keep them separate as I don't know if they will also match if we expand to the East
update	load_area_info set nems_fuel_region =
	CASE	WHEN primary_nerc_subregion = 'AZNMSNV' THEN 'Southwest'
			WHEN primary_nerc_subregion = 'CA' THEN 'CA' 
			WHEN primary_nerc_subregion = 'MX' THEN 'Baja_Mexico'
			WHEN primary_nerc_subregion = 'NWPP' THEN 'NWPP' 
			WHEN primary_nerc_subregion = 'NWPP_CAN' THEN 'Canada_WECC'
			WHEN primary_nerc_subregion = 'RMPA' THEN 'Rockies'
	END;



-- BALANCING AREA INFO
-- based on the load area info table
-- the balancing areas are assumed to be the primary NERC subregions

drop table if exists balancing_areas;
create table balancing_areas (
	balancing_area varchar(20),
	load_only_spinning_reserve_requirement float,
	wind_spinning_reserve_requirement float,
	solar_spinning_reserve_requirement float,
	quickstart_requirement_relative_to_spinning_reserve_requirement float,
	UNIQUE balancing_area (balancing_area)
);

load data local infile 
	'wecc_balancing_area_info.csv'
	into table balancing_areas
	fields terminated by	','
	optionally enclosed by '"'
	lines terminated by "\r"
	ignore 1 lines;


-- HOURS-------------------------
-- takes the timepoints table from the weather database, as the solar data is synced to this hournum scheme.  The load data has also been similarly synced.
-- right now the hours only go through 2004-2005
-- incomplete hours will be exculded below in 'Setup_Study_Hours.sql'
drop table if exists hours;
CREATE TABLE hours (
  datetime_utc datetime NOT NULL COMMENT 'date & time in Coordinated Universal Time, with Daylight Savings Time ignored',
  hournum smallint unsigned NOT NULL COMMENT 'hournum = 0 is at datetime_utc = 2004-01-01 00:00:00, and counts up from there',
  month_of_year tinyint unsigned,
  day_of_month tinyint unsigned,
  hour_of_day tinyint unsigned,
  historical_year year,
  UNIQUE KEY datetime_utc (datetime_utc),
  UNIQUE KEY hournum (hournum),
  index date_ints (month_of_year, day_of_month, hour_of_day),
  index historical_year (historical_year)  
);

insert into hours (datetime_utc, hournum)
select 	timepoint as datetime_utc,
		timepoint_id as hournum
	from weather.timepoints
	order by datetime_utc;

update hours
set	month_of_year = MONTH(datetime_utc),
  	day_of_month = DAY(datetime_utc),
  	hour_of_day = HOUR(datetime_utc),
  	historical_year = YEAR(datetime_utc);


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
			WHEN primary_nerc_subregion = 'NWPP_CAN' THEN 66406.47311
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
			WHEN primary_nerc_subregion = 'NWPP_CAN' THEN 19.2
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
			WHEN primary_nerc_subregion = 'NWPP_CAN' THEN 8.64
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
	transmission_efficiency double,
	new_transmission_builds_allowed tinyint,
	first_line_direction tinyint,
	is_dc_line tinyint,
	transmission_derating_factor double,
	terrain_multiplier double,
	INDEX la_start_end (load_area_start, load_area_end)
);

load data local infile
	'/DatabasePrep/wecc_trans_lines.csv'
	into table transmission_lines
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;

-- ---------------------------------------------------------------------
--        NON-REGIONAL GENERATOR INFO
-- ---------------------------------------------------------------------
select 'Copying Generator and Fuel Info' as progress;

DROP TABLE IF EXISTS generator_info_v2;
create table generator_info_v2 (
	gen_info_scenario_id int unsigned NOT NULL,
	technology_id tinyint unsigned NOT NULL,
	technology varchar(64),
	min_online_year year,
	fuel varchar(64),
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
	distributed boolean default 0,
	resource_limited boolean,
	baseload boolean,
	flexible_baseload boolean,
	dispatchable boolean,
	cogen boolean,
	min_build_capacity float,
	can_build_new tinyint,
	competes_for_space tinyint,
	ccs tinyint,
	storage tinyint,
	storage_efficiency float,
	max_store_rate float,
	max_spinning_reserve_fraction_of_capacity float,
	heat_rate_penalty_spinning_reserve float,
	minimum_loading float,
	deep_cycling_penalty float,
	startup_mmbtu_per_mw float,
	startup_cost_dollars_per_mw float,
	data_source_and_notes varchar(512),
	index techology_id_name (technology_id, technology),
	PRIMARY KEY (gen_info_scenario_id, technology_id),
	INDEX tech (technology)
);

load data local infile
	'./GeneratorInfo/generator_info.csv'
	into table generator_info_v2
	fields terminated by	','
	optionally enclosed by '"'
	lines terminated by '\r'
	ignore 1 lines;


DROP TABLE IF EXISTS generator_costs_5yearly;
create table generator_costs_5yearly (
	gen_costs_scenario_id int NOT NULL,
	technology varchar(64) NOT NULL,
	year year,
	overnight_cost float,
	fixed_o_m float,
	var_o_m float,
	storage_energy_capacity_cost_per_mwh float,
	PRIMARY KEY (gen_costs_scenario_id, technology, year)
);

load data local infile
	'./GeneratorInfo/generator_costs.csv'
	into table generator_costs_5yearly
	fields terminated by	','
	optionally enclosed by '"'
	lines terminated by '\r'
	ignore 1 lines;

-- Now calculate costs for each year from 5-yearly data

-- little procedure to do the same thing that generate series does in postgresql to get us years until 2050
drop table if exists 2010_to_2050;
create table 2010_to_2050 (
year year);

DROP PROCEDURE IF EXISTS generate_year_series_to_2050;
DELIMITER $$
create procedure generate_year_series_to_2050()
BEGIN

declare max_year year default 2010;

WHILE max_year <= 2050 DO

insert into 2010_to_2050 (year)
select max_year;

set max_year = max_year + 1;

END WHILE;
END;
$$
DELIMITER ;

-- actually call the procedure
call generate_year_series_to_2050();
drop procedure generate_year_series_to_2050;

-- create final table with interpolated costs for each year
drop table if exists generator_costs_yearly;
create table generator_costs_yearly (
	gen_costs_scenario_id int NOT NULL,
	technology varchar(64) NOT NULL,
	year year,
	overnight_cost float,
	fixed_o_m float,
	var_o_m float,
	storage_energy_capacity_cost_per_mwh float,
	PRIMARY KEY (gen_costs_scenario_id, technology, year)
);

-- insert technology-year combinations in yearly gen costs table
insert ignore into generator_costs_yearly (technology, gen_costs_scenario_id, year)
select 	distinct(technology),
		gen_costs_scenario_id,
	   	2010_to_2050.year
from	generator_costs_5yearly, 2010_to_2050;
		
-- add all the years with cost data available
update generator_costs_yearly, generator_costs_5yearly
set generator_costs_yearly.overnight_cost = generator_costs_5yearly.overnight_cost,
	generator_costs_yearly.fixed_o_m = generator_costs_5yearly.fixed_o_m,
	generator_costs_yearly.var_o_m = generator_costs_5yearly.var_o_m,
	generator_costs_yearly.storage_energy_capacity_cost_per_mwh = generator_costs_5yearly.storage_energy_capacity_cost_per_mwh
where 	generator_costs_yearly.technology = generator_costs_5yearly.technology
and		generator_costs_yearly.year = generator_costs_5yearly.year
and		generator_costs_yearly.gen_costs_scenario_id = generator_costs_5yearly.gen_costs_scenario_id;


-- linear interpolation procedure to get us costs for all the years in between years with cost projections

DROP PROCEDURE IF EXISTS calculate_yearly_generator_costs;
DELIMITER $$
CREATE PROCEDURE calculate_yearly_generator_costs()
BEGIN

drop table if exists gen_scenario_ids;
create table gen_scenario_ids (gen_costs_scenario_id int);
insert into gen_scenario_ids (gen_costs_scenario_id) select distinct(gen_costs_scenario_id) from generator_costs_yearly;

-- iterate over generator costs scenarios (remove this loop if you only want to update one scenario)

gen_scenario_ids_loop: LOOP

set @current_gen_costs_scenario_id := (select gen_costs_scenario_id from gen_scenario_ids limit 1);

drop table if exists technologies_for_loop;
create table technologies_for_loop (technology varchar(64));
insert into technologies_for_loop (technology) select distinct(technology) from generator_costs_yearly where gen_costs_scenario_id = @current_gen_costs_scenario_id;

-- iterate over technologies

technologies_loop: LOOP

set @current_technology := (select technology from technologies_for_loop limit 1);

drop table if exists generator_costs_temp_calculation_table;
create table generator_costs_temp_calculation_table(
technology varchar(64),
year year,
year_id int AUTO_INCREMENT PRIMARY KEY,
previous_year_with_cost_data year,
overnight_cost_difference_from_previous_available_year decimal,
overnight_cost_yearly_difference_from_previous_available_year decimal,
fixed_o_m_cost_difference_from_previous_available_year decimal,
fixed_o_m_cost_yearly_difference_from_previous_available_year decimal,
var_o_m_cost_difference_from_previous_available_year decimal,
var_o_m_cost_yearly_difference_from_previous_available_year decimal,
storage_energy_cost_difference_from_previous_available_year decimal,
st_en_cost_yearly_difference_from_previous_available_year decimal,
UNIQUE INDEX (technology, year)
);

insert into generator_costs_temp_calculation_table (technology, year)
select technology, year from generator_costs_5yearly
where	technology = @current_technology
and		gen_costs_scenario_id = @current_gen_costs_scenario_id;

-- for each year with cost data, figure out which is the previous year with cost data to start calculating from
update generator_costs_temp_calculation_table,
       (select year, year_id from generator_costs_temp_calculation_table) as year_id_table
set previous_year_with_cost_data = year_id_table.year
where generator_costs_temp_calculation_table.year_id = year_id_table.year_id + 1;

-- calculate the total difference in cost between consecutive years with cost data
update generator_costs_temp_calculation_table join
			(	select year, overnight_cost, fixed_o_m, var_o_m, storage_energy_capacity_cost_per_mwh
				from generator_costs_5yearly
				where	technology=@current_technology
				and		gen_costs_scenario_id = @current_gen_costs_scenario_id) as current_year_table
        using (year) join
			(	select year, overnight_cost, fixed_o_m, var_o_m, storage_energy_capacity_cost_per_mwh
          from generator_costs_5yearly
				where	technology=@current_technology 
				and		gen_costs_scenario_id = @current_gen_costs_scenario_id) as previous_year_table
        on ( previous_year_table.year = generator_costs_temp_calculation_table.previous_year_with_cost_data )
set overnight_cost_difference_from_previous_available_year = current_year_table.overnight_cost - previous_year_table.overnight_cost,
	fixed_o_m_cost_difference_from_previous_available_year = current_year_table.fixed_o_m - previous_year_table.fixed_o_m,
	var_o_m_cost_difference_from_previous_available_year = current_year_table.var_o_m - previous_year_table.var_o_m,
	storage_energy_cost_difference_from_previous_available_year = current_year_table.storage_energy_capacity_cost_per_mwh - previous_year_table.storage_energy_capacity_cost_per_mwh
	;

-- calculate the yearly difference in cost between consecutive years with cost data
update generator_costs_temp_calculation_table
set 	overnight_cost_yearly_difference_from_previous_available_year =
		overnight_cost_difference_from_previous_available_year / ( year - previous_year_with_cost_data ),
		fixed_o_m_cost_yearly_difference_from_previous_available_year =
		fixed_o_m_cost_difference_from_previous_available_year / ( year - previous_year_with_cost_data ),
		var_o_m_cost_yearly_difference_from_previous_available_year =
		var_o_m_cost_difference_from_previous_available_year / ( year - previous_year_with_cost_data ),
		st_en_cost_yearly_difference_from_previous_available_year =
		storage_energy_cost_difference_from_previous_available_year / ( year - previous_year_with_cost_data );


-- now we will iterate over years
drop table if exists years_for_loop;
create table years_for_loop (year year);
insert into years_for_loop (year) select distinct(year) from generator_costs_yearly where technology = @current_technology and gen_costs_scenario_id = @current_gen_costs_scenario_id;

years_loop: LOOP

set @current_year := ( select year from years_for_loop LIMIT 1 );

-- calculate costs for each year in the final table
update 	generator_costs_yearly join
		(select * from generator_costs_5yearly
		join generator_costs_temp_calculation_table using (technology, year)
		where gen_costs_scenario_id = @current_gen_costs_scenario_id and @current_year > previous_year_with_cost_data and @current_year < year ) as cost_data_table using(technology)
set generator_costs_yearly.overnight_cost = cost_data_table.overnight_cost - (cost_data_table.year - @current_year ) * overnight_cost_yearly_difference_from_previous_available_year,
	generator_costs_yearly.fixed_o_m = cost_data_table.fixed_o_m - (cost_data_table.year - @current_year ) * fixed_o_m_cost_yearly_difference_from_previous_available_year,
	generator_costs_yearly.var_o_m = cost_data_table.var_o_m - (cost_data_table.year - @current_year ) * var_o_m_cost_yearly_difference_from_previous_available_year,
	generator_costs_yearly.storage_energy_capacity_cost_per_mwh = cost_data_table.storage_energy_capacity_cost_per_mwh - (cost_data_table.year - @current_year ) * st_en_cost_yearly_difference_from_previous_available_year
where 	generator_costs_yearly.year = @current_year
and		generator_costs_yearly.technology = @current_technology
and		generator_costs_yearly.gen_costs_scenario_id=@current_gen_costs_scenario_id;

delete from years_for_loop where year = @current_year;

	IF ( select count(*) from years_for_loop ) = 0 THEN LEAVE years_loop;
	END IF;
END LOOP years_loop;

delete from technologies_for_loop where technology = @current_technology;

	IF ( select count(*) from technologies_for_loop ) = 0 THEN LEAVE technologies_loop;
	END IF;
END LOOP technologies_loop;

delete from gen_scenario_ids where gen_costs_scenario_id = @current_gen_costs_scenario_id;

	IF ( select count(*) from gen_scenario_ids ) = 0 THEN LEAVE gen_scenario_ids_loop;
	END IF;
END LOOP gen_scenario_ids_loop;

END;
$$
DELIMITER ;

-- call procedure and clean up
call calculate_yearly_generator_costs();
drop procedure calculate_yearly_generator_costs;

drop table if exists 2010_to_2050;
drop table if exists gen_scenario_ids;
drop table if exists technologies_for_loop;
drop table if exists years_for_loop;
drop table if exists generator_costs_temp_calculation_table;

-- delete the EPs as their costs get input elsewhere
delete from generator_costs_yearly where technology like '%_EP%';

-- for CCS, make the cost at the beginning of construction for plants available in 2020 the same as in 2020
update generator_costs_yearly
join	( 	select  technology,
        			overnight_cost as min_online_year_overnight_cost,
        			fixed_o_m as min_online_year_fixed_o_m,
        			var_o_m as min_online_year_var_o_m
			from generator_costs_yearly
			join ( 		select	technology,
								min_online_year from generator_info_v2 ) as min_online_year_table
			using(technology)
        	where year = min_online_year
       		and technology like '%_CCS%' ) as min_online_year_costs
using(technology)
join	(	select 	technology,
					min_online_year,
					construction_time_years
			from generator_info_v2
			where technology like '%_CCS%' ) as construction_times
using (technology)
set	overnight_cost = min_online_year_overnight_cost,
	fixed_o_m = min_online_year_fixed_o_m,
	var_o_m = min_online_year_var_o_m
where	technology like '%_CCS%'
and		year < min_online_year
and		year >= min_online_year - construction_time_years;

-- now delete NULL values for years before CCS is available
delete generator_costs_yearly from generator_costs_yearly
join ( 	select	technology,
				min_online_year,
				construction_time_years
		from generator_info_v2 ) as min_online_year_table
using (technology)
where	technology like '%_CCS%'
and		year < min_online_year - construction_time_years;


-- add generator_assumption_scenarios to be able to easily change generator costs and other parameters
CREATE TABLE IF NOT EXISTS generator_costs_scenarios (
	gen_costs_scenario_id mediumint unsigned PRIMARY KEY AUTO_INCREMENT,
	notes varchar(256) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS generator_info_scenarios (
	gen_info_scenario_id mediumint unsigned PRIMARY KEY AUTO_INCREMENT,
	notes varchar(256) NOT NULL UNIQUE
);

-- ---------------------------------------------------------------------
--        FUELS
-- ---------------------------------------------------------------------
drop table if exists fuel_info_v2;
create table fuel_info_v2(
	fuel varchar(64) primary key,
	rps_fuel_category varchar(10),
	biofuel tinyint,
	carbon_content NUMERIC(5,5) COMMENT 'carbon content (tonnes CO2 per million Btu)',
	carbon_content_without_carbon_accounting NUMERIC(5,5) COMMENT 'carbon content before you account for the biomass being NET carbon neutral (or carbon negative for biomass CCS) (tonnes CO2 per million Btu)',
	carbon_sequestered NUMERIC(5,5)
);

load data local infile
	'./fuel_info.csv'
	into table fuel_info_v2
	fields terminated by ','
	optionally enclosed by '"'
	ignore 1 lines;

drop table if exists fuel_qualifies_for_rps;
create table fuel_qualifies_for_rps(
	rps_compliance_entity varchar(11),
	rps_fuel_category varchar(10),
	qualifies boolean,
	INDEX rps_compliance_entity (rps_compliance_entity)
);

insert into fuel_qualifies_for_rps
	select distinct 
	        rps_compliance_entity,
			rps_fuel_category,
			if(rps_fuel_category like 'renewable', 1, 0)
		from fuel_info_v2, load_area_info
		WHERE fuel != 'Storage';


-- FUEL PRICES-------------
-- run 'v2 wecc fuel price import no elasticity.sql' first
-- biomass fuel costs come from the biomass supply curve and thus aren't added here
-- natural gas fuel costs come from the natural gas supply curve and are also set to 0 here

drop table if exists _fuel_prices;
CREATE TABLE _fuel_prices (
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

set @this_scenario_id := (select if( max(scenario_id) + 1 is null, 1, max(scenario_id) + 1 ) from _fuel_prices);

-- insert fuel prices
-- for natural gas, insert 0 as the price because we'll have natural gas consumption on a supply curve
insert into _fuel_prices
	select
		@this_scenario_id as scenario_id,
        area_id,
        if(fuel like 'NaturalGas', 'Gas', fuel) as fuel,
        year,
        if(fuel like 'NaturalGas', 0, fuel_price) as fuel_price
    from fuel_prices.regional_fuel_prices
    join load_area_info using (load_area)
    where fuel not like 'Bio_Solid';

-- add fuel price forcasts out to 2100
-- this takes the fuel price from 5 years before the end of the fuel price projections
-- and the price from the last year of fuel price projections and linearly extrapolates the price onward in time
-- this could be done by a linear regression, but mysql support is limited.
drop table if exists integer_tmp;
create table integer_tmp( integer_val int not null AUTO_INCREMENT primary key, insert_tmp int );
	insert into integer_tmp (insert_tmp) select hournum from hours limit 70;
	
insert into _fuel_prices (scenario_id, area_id, fuel, year, fuel_price)
	select 	slope_table.scenario_id,
			slope_table.area_id,
			slope_table.fuel,
			integer_val + max_year as year,
			price_slope * integer_val + fuel_price_max_year as fuel_price
		from
		integer_tmp,
		(select max_year_table.scenario_id,
						max_year_table.area_id,
						max_year_table.fuel,
						max_year,
						fuel_price as fuel_price_max_year
						from 
						( select scenario_id, area_id, fuel, max(year) as max_year from _fuel_prices group by 1, 2, 3 ) as max_year_table,
						_fuel_prices
				where max_year_table.max_year = _fuel_prices.year
				and max_year_table.scenario_id = _fuel_prices.scenario_id
				and max_year_table.area_id = _fuel_prices.area_id
				and max_year_table.fuel = _fuel_prices.fuel
				) as max_year_table,
	
		(select  m.scenario_id,
				m.area_id,
				m.fuel,
				( fuel_price_max_year - fuel_price_max_year_minus_five ) / 5 as price_slope
				from
		
				(select max_year_table.scenario_id,
						max_year_table.area_id,
						max_year_table.fuel,
						fuel_price as fuel_price_max_year
						from 
						( select scenario_id, area_id, fuel, max(year) as max_year from _fuel_prices group by 1, 2, 3 ) as max_year_table,
						_fuel_prices
				where max_year_table.max_year = _fuel_prices.year
				and max_year_table.scenario_id = _fuel_prices.scenario_id
				and max_year_table.area_id = _fuel_prices.area_id
				and max_year_table.fuel = _fuel_prices.fuel
				) as m,
				(select 	max_year_table.scenario_id,
						max_year_table.area_id,
						max_year_table.fuel,
						fuel_price as fuel_price_max_year_minus_five
						from 
						( select scenario_id, area_id, fuel, max(year) as max_year from _fuel_prices group by 1, 2, 3 ) as max_year_table,
						_fuel_prices
				where (max_year_table.max_year - 5 ) = _fuel_prices.year
				and max_year_table.scenario_id = _fuel_prices.scenario_id
				and max_year_table.area_id = _fuel_prices.area_id
				and max_year_table.fuel = _fuel_prices.fuel
				) as m5
			where m.scenario_id = m5.scenario_id
			and m.area_id = m5.area_id
			and m.fuel = m5.fuel) as slope_table
		where 	slope_table.scenario_id = max_year_table.scenario_id
		and		slope_table.area_id = max_year_table.area_id
		and		slope_table.fuel = max_year_table.fuel
		;
			
delete from _fuel_prices where year > 2100;

-- add in fuel prices for CCS - these are the same as for the non-CCS technologies, but with a CCS added to the name
insert into _fuel_prices (scenario_id, area_id, fuel, year, fuel_price)
	select 	scenario_id,
			area_id,
			concat(fuel, '_CCS') as fuel,
			year,
			fuel_price
	from _fuel_prices where fuel in ('Gas', 'Coal', 'DistillateFuelOil', 'ResidualFuelOil');

-- add fuel prices of zero for renewables... this could be handedled through default fuel price values
-- but in the past bugs have been caused by using a default fuel price of 0 in switch.mod
-- biomass_solid gets a default of zero here, but it comes in on the biomass supply curve.
insert into _fuel_prices (scenario_id, area_id, fuel, year, fuel_price)
	select 	scenario_id,
			area_id,
			fuel,
			year,
			0 as fuel_price
	from 	(select distinct scenario_id, area_id, year from _fuel_prices) as scenarios_areas_years,
			fuel_info_v2
	where 	fuel not in (select distinct fuel from _fuel_prices);

DROP VIEW IF EXISTS fuel_prices;
CREATE VIEW fuel_prices as
SELECT _fuel_prices.scenario_id, load_area_info.area_id, load_area, fuel, year, fuel_price 
    FROM _fuel_prices, load_area_info
    WHERE _fuel_prices.area_id = load_area_info.area_id;


-- NATURAL GAS PRICE ELASTICITY

-- the prices in the supply curve include producer surplus
-- the supply curves are created in postgresql -- see build_fuel_supply_cuves.sql
-- regional adders are also included in addition to the supply curve to account for variations in wellhead and transportation costs across regions

-- supply curve
create table if not exists natural_gas_supply_curve(
	fuel varchar(40),
	nems_scenario varchar(40),
	simulation_year int,
	breakpoint_id int,
	consumption_breakpoint double,
	price_surplus_adjusted double,
	PRIMARY KEY (fuel, nems_scenario, simulation_year, breakpoint_id),
	INDEX fuel (fuel),
	INDEX nems_scenario (nems_scenario)
);

load data local infile
	'/DatabasePrep/NG_supply_curve/natural_gas_supply_curve.csv'
	into table natural_gas_supply_curve
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;


-- regional price adders
create table if not exists natural_gas_regional_price_adders(
	fuel varchar(40),
	nems_region varchar(40),
	nems_scenario varchar(40),
	simulation_year int,
	regional_price_adder double,
	PRIMARY KEY (fuel, nems_region, nems_scenario, simulation_year),
	INDEX fuel (fuel),
	INDEX nems_region (nems_region),
	INDEX nems_scenario (nems_scenario)
);

load data local infile
	'/DatabasePrep/NG_supply_curve/natural_gas_regional_price_adders.csv'
	into table natural_gas_regional_price_adders
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;

-- add nems scenarios to be able to vary the NG supply curve starting point depending on consumption in the rest of the economy
create table if not exists nems_fuel_scenarios(
nems_fuel_scenario_id int auto_increment primary key,
nems_fuel_scenario varchar(40) unique
);

-- the order by here is just a way to trick the 2011 reference scenario to be #1
insert into nems_fuel_scenarios (nems_fuel_scenario)
select distinct nems_scenario from natural_gas_supply_curve
order by right(nems_scenario, 1), nems_scenario desc;

-- BIOMASS SUPPLY CURVE

-- the prices on this supply curve INCLUDE producer surplus.... create_bio_supply_curve.sql shows how this is done
drop table if exists biomass_solid_supply_curve;
create table biomass_solid_supply_curve(
	breakpoint_id int,
	load_area varchar(11),
	year int,
	price_dollars_per_mmbtu_surplus_adjusted double,
	breakpoint_mmbtu_per_year double,
	PRIMARY KEY (load_area, year, price_dollars_per_mmbtu_surplus_adjusted),
	UNIQUE INDEX bp_la (breakpoint_id, load_area, year),
	INDEX load_area (load_area)
);

load data local infile
	'biomass_solid_supply_curve_breakpoints_prices.csv'
	into table biomass_solid_supply_curve
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;

-- the AMPL forumlation of piecewise linear curves requires a slope above the last breakpoint.
-- this slope has no meaning for us, as we cap biomass installations above this level
-- but we still need something, so we'll say biomass costs $999999999/MMbtu above this level.
-- as we don't want to be mistaken, we'll set breakpoint_mmbtu_per_year for these values
update 	biomass_solid_supply_curve
set		breakpoint_mmbtu_per_year = null
where	price_dollars_per_mmbtu_surplus_adjusted = 999999999;


-- RPS COMPLIANCE INFO ---------------
-- the column enable_rps is a bit of a misnomer as it now indicates rps_scenario_id...
-- should change in future versions
drop table if exists rps_compliance_entity_targets_v2;
create table rps_compliance_entity_targets_v2(
	enable_rps tinyint default 1,
	rps_compliance_entity character varying(20),
	rps_compliance_type character varying(20),
	rps_compliance_year year,
	rps_compliance_fraction float,
	PRIMARY KEY (enable_rps, rps_compliance_entity, rps_compliance_type, rps_compliance_year),
	INDEX rps_compliance_year (rps_compliance_year)
	);

load data local infile
	'rps_compliance_targets.csv'
	into table rps_compliance_entity_targets_v2
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;

-- add in the option to not have an rps target... set the targets all to zero
INSERT INTO rps_compliance_entity_targets_v2 (enable_rps, rps_compliance_entity, rps_compliance_type, rps_compliance_year, rps_compliance_fraction)
	SELECT  0 as enable_rps,
			rps_compliance_entity, rps_compliance_type, rps_compliance_year,
			0 as rps_compliance_fraction
	FROM 	rps_compliance_entity_targets_v2;

-- RPS scenarios other than the default ones
-- for now this will be only boosting California's RPS to 50% by 2030
INSERT INTO rps_compliance_entity_targets_v2 (enable_rps, rps_compliance_entity, rps_compliance_type, rps_compliance_year, rps_compliance_fraction)
	SELECT  2 as enable_rps,
			rps_compliance_entity, rps_compliance_type, rps_compliance_year,
			CASE WHEN primary_state = 'CA' AND rps_compliance_year BETWEEN 2021 AND 2030 AND rps_compliance_type = 'Primary'
					THEN rps_compliance_fraction + (0.5-0.33)/(2030-2020) * (rps_compliance_year - 2020)
				 WHEN primary_state = 'CA' AND rps_compliance_year > 2030 AND rps_compliance_type = 'Primary' THEN 0.5
				 ELSE rps_compliance_fraction
			END AS rps_compliance_fraction
	FROM 	rps_compliance_entity_targets_v2
	JOIN	(SELECT DISTINCT rps_compliance_entity, primary_state FROM load_area_info) as map_table USING (rps_compliance_entity)
	WHERE	enable_rps = 1;
    
-- CARBON CAP INFO ---------------
-- the current carbon cap in SWITCH is set by a linear decrease
-- from 100% of 1990 levels in 2020 to 20% of 1990 levels in 2050
-- these two goals are the california emission goals.
drop table if exists carbon_cap_scenarios;
create table carbon_cap_scenarios(
  carbon_cap_scenario_id int unsigned PRIMARY KEY,
  name text,
  description text
);


drop table if exists _carbon_cap_targets;
create table _carbon_cap_targets(
  carbon_cap_scenario_id INT UNSIGNED,
	year YEAR,
	carbon_emissions_relative_to_base FLOAT,
	PRIMARY KEY (carbon_cap_scenario_id,year),
	FOREIGN KEY (carbon_cap_scenario_id) REFERENCES carbon_cap_scenarios(carbon_cap_scenario_id)
);


drop view if exists carbon_cap_targets;
CREATE VIEW carbon_cap_targets as
  SELECT carbon_cap_scenario_id, carbon_cap_scenarios.name as carbon_cap_scenario_name, year, carbon_emissions
    FROM _carbon_cap_targets join carbon_cap_scenarios using (carbon_cap_scenario_id);

load data local infile
	'carbon_cap_targets.csv'
	into table carbon_cap_targets
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;


-- EXISTING PLANTS---------
-- made in 'build existing plants table.sql'
select 'Copying existing_plants' as progress;

drop table if exists existing_plants_v2;
CREATE TABLE existing_plants_v2 (
    project_id int unsigned PRIMARY KEY,
	load_area varchar(11) NOT NULL,
 	technology varchar(64) NOT NULL,
	ep_id mediumint unsigned NOT NULL,
	area_id smallint unsigned NOT NULL,
	plant_name varchar(40) NOT NULL,
	eia_id int default 0,
	primemover varchar(10) NOT NULL,
	fuel varchar(64) NOT NULL,
	capacity_mw double NOT NULL,
	heat_rate double NOT NULL,
	cogen_thermal_demand_mmbtus_per_mwh double NOT NULL,
	start_year year NOT NULL,
	forced_retirement_year smallint NOT NULL default 9999,
	overnight_cost float NOT NULL,
	connect_cost_per_mw float,
	fixed_o_m double NOT NULL,
	variable_o_m double NOT NULL,
	forced_outage_rate double NOT NULL,
	scheduled_outage_rate double NOT NULL,
	UNIQUE (technology, plant_name, eia_id, primemover, fuel, start_year),
	INDEX area_id (area_id),
	INDEX plant_name (plant_name)
);

 -- The << operation moves the numeric form of the letter "E" (for existing plants) over by 3 bytes, effectively making its value into the most significant digits.
-- make sure the joins work in the future - not updated correctly in the past...
insert into existing_plants_v2 (project_id, load_area, technology, ep_id, area_id, plant_name, eia_id,
								primemover, fuel, capacity_mw, heat_rate, cogen_thermal_demand_mmbtus_per_mwh, start_year, forced_retirement_year
								overnight_cost, connect_cost_per_mw, fixed_o_m, variable_o_m, forced_outage_rate, scheduled_outage_rate )
	select 	CASE WHEN e.fuel = 'Water' THEN e.ep_id ELSE e.ep_id+ (ascii( 'E' ) << 8*3) END,
			e.load_area,
			technology,
			e.ep_id,
			a.area_id,
			e.plant_name,
			e.eia_id,
			e.primemover,
			e.fuel,
			round(e.capacity_mw, 1) as capacity_mw,
			e.heat_rate,
			e.cogen_thermal_demand_mmbtus_per_mwh,
			e.start_year,
			e.forced_retirement_year,
			c.overnight_cost * economic_multiplier,
			g.connect_cost_per_mw_generic * economic_multiplier,		
			c.fixed_o_m * economic_multiplier,
			c.var_o_m * economic_multiplier,
			g.forced_outage_rate,
			g.scheduled_outage_rate
			from generator_info.existing_plants_agg e
			join generator_info_v2 g using (technology)
			join generator_costs_5yearly c using (technology)
			join load_area_info a using (load_area)
			WHERE year = 2000
			AND	gen_costs_scenario_id = 2
			AND gen_info_scenario_id = 2;

			
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
		FOREIGN KEY project_id (project_id) REFERENCES existing_plants_v2 (project_id),
		FOREIGN KEY (area_id) REFERENCES load_area_info(area_id)
);

DROP VIEW IF EXISTS existing_intermittent_plant_cap_factor;
CREATE VIEW existing_intermittent_plant_cap_factor as
  SELECT cp.project_id, load_area, technology, hour, cap_factor
    FROM _existing_intermittent_plant_cap_factor cp join existing_plants_v2 using (project_id);

-- US Existing Wind
insert into _existing_intermittent_plant_cap_factor (project_id, area_id, hour, cap_factor)
SELECT      existing_plants_v2.project_id,
            existing_plants_v2.area_id,
            hournum as hour,
            3tier.windfarms_existing_cap_factor.cap_factor
    from    existing_plants_v2, 
            3tier.windfarms_existing_cap_factor
    where   technology = 'Wind_EP'
    and		concat('Wind_EP_', 3tier.windfarms_existing_cap_factor.windfarm_existing_id) = existing_plants_v2.plant_name;

-- Canada Existing Wind
drop table if exists can_existing_wind_hourly_import;
create table can_existing_wind_hourly_import (
	windfarm_existing_id int,
	datetime_utc datetime,
	cap_factor float,
	primary key (windfarm_existing_id, datetime_utc),
	index windfarm_existing_id (windfarm_existing_id),
	index datetime_utc (datetime_utc) );

load data local infile
	'/Volumes/switch/Models/GIS/Canada_Wind_AWST/windfarms_canada_existing_cap_factor.csv'
	into table can_existing_wind_hourly_import
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;
	
insert into _existing_intermittent_plant_cap_factor (project_id, area_id, hour, cap_factor)
SELECT      project_id,
            area_id,
            hournum as hour,
            i.cap_factor
    from    can_existing_wind_hourly_import i 
    join	hours using (datetime_utc)
	join	existing_plants_v2 e on (e.plant_name = concat('Wind_EP_Can_', i.windfarm_existing_id) )
    where   technology = 'Wind_EP';

drop table can_existing_wind_hourly_import;

-- HYDRO-------------------
-- made in 'existing_plants_usa_can.sql' and imported directly
-- the project_id here is the ep_id (see how existing_plants_v2 is populated above)
select 'Copying Hydro' as progress;

drop table if exists _hydro_monthly_limits_v2;
CREATE TABLE _hydro_monthly_limits_v2 (
  project_id int unsigned,
  month tinyint,
  avg_capacity_factor_hydro float check (avg_capacity_factor_hydro between 0 and 1),
  INDEX (project_id),
  PRIMARY KEY (project_id, month),
  FOREIGN KEY (project_id) REFERENCES existing_plants_v2 (project_id)
);

DROP VIEW IF EXISTS hydro_monthly_limits_v2;
CREATE VIEW hydro_monthly_limits_v2 as
  SELECT project_id, load_area, technology, month, avg_capacity_factor_hydro
    FROM _hydro_monthly_limits_v2 join existing_plants_v2 using (project_id);


load data local infile
	'/Volumes/switch/Models/USA_CAN/existing_plants/hydro_monthly_average_output_mysql.csv'
	into table _hydro_monthly_limits_v2
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;

-- ---------------------------------------------------------------------
-- PROPOSED PROJECTS--------------
-- imported from postgresql, this table has all pv, csp, wind, geothermal, biomass and compressed air energy storage sites
-- if this table is remade, the avg cap factors must be reinserted (see below) 
-- ---------------------------------------------------------------------
drop table if exists proposed_projects_import;
create table proposed_projects_import(
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


drop table if exists _proposed_projects_v2;
CREATE TABLE _proposed_projects_v2 (
  project_id int unsigned default NULL,
  gen_info_project_id mediumint unsigned PRIMARY KEY AUTO_INCREMENT,
  technology_id tinyint unsigned NOT NULL,
  area_id smallint unsigned NOT NULL,
  location_id INT DEFAULT NULL,
  ep_project_replacement_id INT DEFAULT NULL,
  technology varchar(64),
  original_dataset_id INT DEFAULT NULL,
  capacity_limit float DEFAULT NULL,
  capacity_limit_conversion float DEFAULT NULL,
  connect_cost_per_mw float,
  heat_rate float default 0,
  cogen_thermal_demand float default 0,
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
  UNIQUE (technology_id, location_id, ep_project_replacement_id, area_id),
  FOREIGN KEY (area_id) REFERENCES load_area_info(area_id), 
  FOREIGN KEY (technology_id) REFERENCES generator_info_v2 (technology_id)
) ROW_FORMAT=FIXED;

-- the capacity limit is either in MW if the capacity_limit_conversion is 1, or in other units if the capacity_limit_conversion is nonzero
-- so for CSP and central PV the limit is expressed in land area, not MW
-- The << operation moves the numeric form of the letter "G" (for generators) over by 3 bytes, effectively making its value into the most significant digits.
-- change to 'P' on a complete rebuild of the database to make this more clear
insert into _proposed_projects_v2
	(project_id, gen_info_project_id, technology_id, technology, area_id, location_id, original_dataset_id,
	capacity_limit, capacity_limit_conversion, connect_cost_per_mw, heat_rate )
	select  project_id + (ascii( 'G' ) << 8*3) as project_id,
	        project_id as gen_info_project_id,
	        technology_id,
	        technology,
			area_id,
			location_id,
			original_dataset_id,
			capacity_limit,
			capacity_limit_conversion,
			(connect_cost_per_mw + connect_cost_per_mw_generic) * economic_multiplier  as connect_cost_per_mw,
    		heat_rate			
	from proposed_projects_import join generator_info_v2 using (technology) join load_area_info using (load_area)
	order by 2;


-- before we do anything else, we need to change the capacity_limit and capacity_limit_conversion for biomass and biogas
-- as imported, the capacity_limit is in MMBtu per hour per load area, and the capacity_limit_conversion is in 1/heat_rate, or MWh/MMBtu.  Multiplying these together gives MW of capacity.
-- due to a (minor) error in postgresql, the generator availability isn't taken into account, so the MW of capacity multiplication will result in the correct MMBtu per hour per load area
alter table load_area_info add column bio_gas_capacity_limit_mmbtu_per_hour float default 0;

update load_area_info join proposed_projects_v2 using (load_area)
	set 	bio_gas_capacity_limit_mmbtu_per_hour = capacity_limit
	where	technology = 'Bio_Gas'

-- we've changed how bio projects are done since proposed projects was done in postgresql
-- so update _proposed_projects to be consistent here
update _proposed_projects_v2
set		location_id = null,
		capacity_limit = null
where	technology like 'Bio%';

update _proposed_projects_v2
set		capacity_limit_conversion = null
where	capacity_limit_conversion = 1;


-- add CAES for Canada and Mexico - we didn't have shapefiles for CAES geology in these areas but it is very likely that their is ample caes potential
-- this should be cleaned up in Postgresql eventually
insert into _proposed_projects_v2
	(technology_id, technology, area_id, location_id, original_dataset_id,
	capacity_limit, connect_cost_per_mw, heat_rate )
	select  technology_id,
	        technology,
			area_id,
			0 as location_id,
			0 as original_dataset_id,
			100000 as capacity_limit,
			connect_cost_per_mw_generic * economic_multiplier  as connect_cost_per_mw,
    		heat_rate			
	from generator_info_v2, load_area_info
where technology = 'Compressed_Air_Energy_Storage'
and load_area in ('CAN_ALB', 'CAN_BC', 'MEX_BAJA');

-- Insert "generic" projects that can be built almost anywhere.
-- Note, project_id is automatically set here because it is an autoincrement column. The renewable proposed_projects with ids set a-priori need to be imported first to avoid unique id conflicts.
 -- The << operation moves the numeric form of the letter "G" (for generic projects) over by 3 bytes, effectively making its value into the most significant digits.
insert into _proposed_projects_v2
	(technology_id, technology, area_id, connect_cost_per_mw, heat_rate )
    select 	technology_id,
    		technology,
    		area_id,
    		connect_cost_per_mw_generic * economic_multiplier as connect_cost_per_mw,
    		heat_rate
    from 	generator_info_v2,
			load_area_info
	where   generator_info_v2.can_build_new  = 1 and 
	        generator_info_v2.resource_limited = 0
	order by 1,3;

-- regional generator restrictions: Coal and Nuclear can't be built in CA.
delete from _proposed_projects_v2
 	where 	(technology_id in (select technology_id from generator_info_v2 where fuel in ('Uranium', 'Coal', 'Coal_CCS')) and
			area_id in (select area_id from load_area_info where primary_nerc_subregion like 'CA'));

-- add new Biomass_IGCC_CCS and Bio_Gas_CCS projects that aren't cogen... we'll add cogen CCS elsewhere
-- neither capacity_limit nor capacity_limit_conversion show up here - they'll be null in the database
-- because these projects will be capacity constrained by bio_fuel_limit_by_load_area instead
insert into _proposed_projects_v2 (technology_id, technology, area_id,
								connect_cost_per_mw, heat_rate)
   select 	technology_id,
    		technology,
    		load_area_info.area_id,
    		connect_cost_per_mw_generic * economic_multiplier as connect_cost_per_mw,
    		heat_rate
    from 	generator_info_v2,
    		load_area_info,
			( select area_id, concat(technology, '_CCS') as ccs_technology from _proposed_projects_v2,
				( select trim(trailing '_CCS' from technology) as non_ccs_technology
						from generator_info_v2
						where technology in ('Biomass_IGCC_CCS', 'Bio_Gas_CCS') ) as non_ccs_technology_table
					where non_ccs_technology_table.non_ccs_technology = _proposed_projects_v2.technology ) as resource_limited_ccs_load_area_projects
	where 	generator_info_v2.technology = resource_limited_ccs_load_area_projects.ccs_technology
	and		load_area_info.area_id = resource_limited_ccs_load_area_projects.area_id;


-- add geothermal replacements projects that will be constrained to replace existing projects by ep_project_replacement_id
-- the capacity limit of these projects is the same as for the plant they're replacing
insert into _proposed_projects_v2 (original_dataset_id, technology_id, technology, area_id, capacity_limit, ep_project_replacement_id,
								connect_cost_per_mw, heat_rate)
   select 	existing_plants_v2.ep_id as original_dataset_id,
   			technology_id,
    		'Geothermal' as technology,
    		area_id,
			capacity_mw as capacity_limit,
    		existing_plants_v2.project_id as ep_project_replacement_id,
    		0 as connect_cost_per_mw,
    		generator_info_v2.heat_rate
    from 	generator_info_v2,
    		existing_plants_v2
    join    load_area_info using (area_id)
	where 	existing_plants_v2.technology = 'Geothermal_EP'
	and		generator_info_v2.technology = 'Geothermal'
;	


-- add new (non-CCS) cogen projects which will replace existing cogen projects via ep_project_replacement_id
-- the capacity limit, heat rate and cogen thermal demand of these projects is the same as for the plant they're replacing
-- these plants will compete with CCS cogen projects through ep_project_replacement_id for the cogen resource
insert into _proposed_projects_v2 (original_dataset_id, technology_id, technology, area_id, capacity_limit, ep_project_replacement_id,
								connect_cost_per_mw, heat_rate, cogen_thermal_demand)
   select 	existing_plants_v2.ep_id as original_dataset_id,
   			technology_id,
    		generator_info_v2.technology,
    		area_id,
			capacity_mw as capacity_limit,
    		existing_plants_v2.project_id as ep_project_replacement_id,
    		0 as connect_cost_per_mw,
    		existing_plants_v2.heat_rate,
      		existing_plants_v2.cogen_thermal_demand_mmbtus_per_mwh as cogen_thermal_demand
    from 	generator_info_v2,
    		existing_plants_v2
    join    load_area_info using (area_id)
	where 	replace(existing_plants_v2.technology, 'Cogen_EP', 'Cogen') = generator_info_v2.technology
	and		generator_info_v2.cogen = 1
	and		generator_info_v2.ccs = 0
	and		generator_info_v2.can_build_new = 1
;	

-- COGEN CCS---------------------------------
-- the heat rate and cogen thermal demand of cogen CCS is calculated here...
-- it takes energy to do CCS, so we add this energy onto the existing heat rate and cogen thermal demand in equal proportion

-- create a temporary table to calculate the increase in heat_rate and cogen_thermal_demand from adding ccs onto cogen plants
-- this should be made with the same assumptions that are used to calculate these params in generator_info.xlsx for other CCS technologies
drop table if exists cogen_ccs_var_costs_and_heat_rates;
create table cogen_ccs_var_costs_and_heat_rates (
			technology varchar(64) primary key,		
			non_cogen_reference_ccs_technology varchar(64),
			non_cogen_reference_non_ccs_technology varchar(64),
			heat_rate_increase_factor float
			);

insert into 	cogen_ccs_var_costs_and_heat_rates (technology)
	select	distinct(technology) from generator_info_v2 where technology like '%Cogen_CCS%';

update	cogen_ccs_var_costs_and_heat_rates
set		non_cogen_reference_ccs_technology =
		CASE
			WHEN technology in ('Gas_Combustion_Turbine_Cogen_CCS', 'Gas_Internal_Combustion_Engine_Cogen_CCS') THEN 'Gas_Combustion_Turbine_CCS'
			WHEN technology = 'Bio_Gas_Internal_Combustion_Engine_Cogen_CCS' THEN 'Bio_Gas_CCS'
			WHEN technology in ('Coal_Steam_Turbine_Cogen_CCS') THEN 'Coal_Steam_Turbine_CCS'
			WHEN technology in ('Bio_Liquid_Steam_Turbine_Cogen_CCS', 'Bio_Solid_Steam_Turbine_Cogen_CCS') THEN 'Biomass_IGCC_CCS'
			WHEN technology in ('CCGT_Cogen_CCS', 'Gas_Steam_Turbine_Cogen_CCS') THEN 'CCGT_CCS'
		END;
		
update	cogen_ccs_var_costs_and_heat_rates
set 	non_cogen_reference_non_ccs_technology = replace(non_cogen_reference_ccs_technology, '_CCS', '');

-- calculate the fraction increase in heat rate for CCS cogen plants (relative to non-CCS) from the base technology
-- also calculate the base increase in variable cost for adding CCS to a plant from the base technology
-- this will later be multiplied by the relative increases in heat rates
-- we assume that the increase in variable costs (delta variable cost) scales with the relative increase in heat rate (delta heat rate)
update 	cogen_ccs_var_costs_and_heat_rates,
		(select cogen_ccs_var_costs_and_heat_rates.technology, 
				heat_rate as heat_rate_reference_ccs
			from	generator_info_v2,
			 		cogen_ccs_var_costs_and_heat_rates
			where generator_info_v2.technology = non_cogen_reference_ccs_technology
		) as reference_ccs_table,
		(select cogen_ccs_var_costs_and_heat_rates.technology, 
				heat_rate as heat_rate_reference_non_ccs
			from	generator_info_v2,
				 	cogen_ccs_var_costs_and_heat_rates
			where generator_info_v2.technology = non_cogen_reference_non_ccs_technology
		) as reference_non_ccs_table
set		cogen_ccs_var_costs_and_heat_rates.heat_rate_increase_factor = heat_rate_reference_ccs / heat_rate_reference_non_ccs
where	cogen_ccs_var_costs_and_heat_rates.technology = reference_ccs_table.technology
and		cogen_ccs_var_costs_and_heat_rates.technology = reference_non_ccs_table.technology
;


-- add new CCS cogen projects which will replace existing cogen projects after the existing cogen project plant lifetime
-- these plants will compete with non-CCS cogen projects through ep_project_replacement_id for the cogen resource
-- the capacity limit of these projects is the same as for the plant they're replacing,
-- as we're assuming that the plants will burn extra fuel to get the same amount of useful heat and electricity out (CCS has an efficiency penalty which makes them burn more fuel)
-- the variable costs are a bit complicated, so they're updated below
insert into _proposed_projects_v2 (original_dataset_id, technology_id, technology, area_id, capacity_limit, ep_project_replacement_id,
								connect_cost_per_mw, heat_rate, cogen_thermal_demand)
   select 	existing_plants_v2.ep_id as original_dataset_id,
   			technology_id,
    		generator_info_v2.technology,
    		area_id,
			capacity_mw as capacity_limit,
    		existing_plants_v2.project_id as ep_project_replacement_id,
    		0 as connect_cost_per_mw,
    		existing_plants_v2.heat_rate * heat_rate_increase_factor as heat_rate,
      		existing_plants_v2.cogen_thermal_demand_mmbtus_per_mwh * heat_rate_increase_factor as cogen_thermal_demand
	from    generator_info_v2
    join	cogen_ccs_var_costs_and_heat_rates using (technology)
   	join 	existing_plants_v2 on (replace(existing_plants_v2.technology, 'Cogen_EP', 'Cogen_CCS') = generator_info_v2.technology)
	where 	generator_info_v2.cogen = 1
	and		generator_info_v2.ccs = 1
	and		generator_info_v2.can_build_new = 1
;

drop table if exists cogen_ccs_var_costs_and_heat_rates;

-- make a unique identifier for all proposed projects
UPDATE _proposed_projects_v2 SET project_id = gen_info_project_id + (ascii( 'G' ) << 8*3) where project_id is null;


DROP VIEW IF EXISTS proposed_projects_v2;
CREATE VIEW proposed_projects_v2 as
  SELECT 	project_id, 
            gen_info_project_id,
            technology_id, 
            technology, 
            area_id, 
            load_area,
            location_id,
            ep_project_replacement_id,
            original_dataset_id, 
            capacity_limit, 
            capacity_limit_conversion, 
            connect_cost_per_mw,
            heat_rate,
            cogen_thermal_demand,
            avg_cap_factor_intermittent,
            avg_cap_factor_percentile_by_intermittent_tech,
            cumulative_avg_MW_tech_load_area,
            rank_by_tech_in_load_area
    FROM _proposed_projects_v2
    join load_area_info using (area_id);
    

---------------------------------------------------------------------
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
	CONSTRAINT project_fk FOREIGN KEY project_id (project_id) REFERENCES proposed_projects_v2 (project_id)
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
    join proposed_projects_v2 using (project_id)
    join load_area_info using (load_area);
    
    
-- includes Wind and Offshore_Wind in the US
select 'Compiling Wind' as progress;
insert into _cap_factor_intermittent_sites
SELECT      proposed_projects_v2.project_id,
            3tier.wind_farm_power_output.hournum as hour,
            3tier.wind_farm_power_output.cap_factor
    from    proposed_projects_v2, 
            3tier.wind_farm_power_output
    where   technology in ('Wind', 'Offshore_Wind')
    and		proposed_projects_v2.original_dataset_id = 3tier.wind_farm_power_output.wind_farm_id;

-- Canadian wind.. it's all onshore
drop table if exists windfarms_canada_hourly_cap_factor;
create table windfarms_canada_hourly_cap_factor (
	id int,
	datetime_utc datetime,
	cap_factor float,
	primary key (id, datetime_utc),
	index id (id),
	index datetime_utc (datetime_utc) );
	

load data local infile
	'/Volumes/switch/Models/GIS/Canada_Wind_AWST/windfarms_canada_hourly_cap_factor.csv'
	into table windfarms_canada_hourly_cap_factor
	fields terminated by	','
	optionally enclosed by '"'
	lines terminated by "\r"
	ignore 1 lines;

-- NOTE: the gen_info_project_id right now determines if the wind is Canadian or not... should be made more robust in the future...
insert into _cap_factor_intermittent_sites (project_id, hour, cap_factor)
SELECT      proposed_projects_v2.project_id,
            hournum as hour,
            cap_factor
    from    proposed_projects_v2
    join	windfarms_canada_hourly_cap_factor on (original_dataset_id = id)
    join	hours using (datetime_utc)
    WHERE	technology = 'Wind'
    and		gen_info_project_id between 28512 and 28512 + 47;


-- REMOVE when CSP_Trough_6h_Storage is finished in SAM
-- these cap factors for some reason don't have the 31st of December, 2004... as long as this isnt sampled,
-- then it's fine and it will get fixed once we're finished with SAM
select 'Compiling CSP_Trough_6h_Storage' as progress;
insert into _cap_factor_intermittent_sites
SELECT      proposed_projects_v2.project_id,
            hournum as hour,
            3tier.csp_power_output.e_net_mw/100 as cap_factor
    from    proposed_projects_v2, 
            3tier.csp_power_output,
            hours
    where   proposed_projects_v2.technology_id = 7
    and		proposed_projects_v2.original_dataset_id = 3tier.csp_power_output.siteid
    and		3tier.csp_power_output.datetime_utc = hours.datetime_utc;


-- includes Residential_PV, Commercial_PV, Central_PV, CSP_Trough_No_Storage and CSP_Trough_6h_Storage
-- CSP_Trough_6h_Storage broken at the moment from the Solar_Advisor_Model... taken care of below
-- remove the <> 7 to reinsert it, and delete the extra script below
select 'Compiling Solar' as progress;
insert into _cap_factor_intermittent_sites
SELECT      proposed_projects_v2.project_id,
            hournum as hour,
            cap_factor
    from    proposed_projects_v2,
            suny.solar_farm_cap_factors
    where   proposed_projects_v2.original_dataset_id = solar_farm_cap_factors.solar_farm_id
    and		proposed_projects_v2.technology_id = solar_farm_cap_factors.technology_id
    and 	proposed_projects_v2.technology_id <> 7;


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
update	_proposed_projects_v2,
		avg_cap_factor_table
set	_proposed_projects_v2.avg_cap_factor_intermittent = avg_cap_factor_table.avg_cap_factor
where _proposed_projects_v2.project_id = avg_cap_factor_table.project_id;

-- ----------------------------
select 'Checking Cap Factors' as progress;
-- first, output the number of points with incomplete hours
-- as many of the sites are missing the first few hours of output due to the change from local to utc time,
-- we'll consider a site complete if it has cap factors for all hours from 2004-2005,
-- so ( 366 days in 2004 + 365 days in 2005 - 1 day ) * 24 hours per day is about 17500
select 	proposed_projects_v2.*,
		number_of_cap_factor_hours
	from 	avg_cap_factor_table,
			proposed_projects_v2
	where number_of_cap_factor_hours < 17500
	and	avg_cap_factor_table.project_id = proposed_projects_v2.project_id
	order by project_id;
		
-- also, make sure each intermittent site has cap factors
select 	proposed_projects_v2.*
	from 	proposed_projects_v2,
			generator_info_v2
	where	proposed_projects_v2.technology_id = generator_info_v2.technology_id
	and		generator_info_v2.intermittent = 1
	and		project_id not in (select project_id from avg_cap_factor_table where number_of_cap_factor_hours >= 17500)
	order by project_id, generator_info_v2.technology;
	
-- delete the projects that don't have cap factors
-- for the WECC, if nothing is messed up, this means Central_PV on the eastern border of Colorado that contains
-- a few grid points didn't get simulated because they were too far east... only 16 total solar farms out of thousands
drop table if exists project_ids_to_delete;
create temporary table project_ids_to_delete as 
 	select 	_proposed_projects_v2.project_id
 		from 	_proposed_projects_v2 join generator_info_v2 using (technology_id)
 		where	generator_info_v2.intermittent = 1
 		and		project_id not in (select project_id from avg_cap_factor_table where number_of_cap_factor_hours >= 17500)
 		order by project_id, generator_info_v2.technology;
 		
 delete from _proposed_projects_v2 where project_id in (select project_id from project_ids_to_delete);

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
	select project_id, technology_id, capacity_limit * IF(capacity_limit_conversion is null, 1, capacity_limit_conversion) * avg_cap_factor_intermittent as avg_MW from _proposed_projects_v2
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
			
	update _proposed_projects_v2, rank_table
	set avg_cap_factor_percentile_by_intermittent_tech = rank_total
	where rank_table.project_id = _proposed_projects_v2.project_id
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
			capacity_limit * IF(capacity_limit_conversion is null, 1, capacity_limit_conversion) * avg_cap_factor_intermittent as avg_MW
		from _proposed_projects_v2
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
			
	update _proposed_projects_v2, cumulative_gen_load_area_table
	set cumulative_avg_MW_tech_load_area = cumulative_avg_MW,
		rank_by_tech_in_load_area = rank_load_area
	where cumulative_gen_load_area_table.project_id = _proposed_projects_v2.project_id
	and cumulative_gen_load_area_table.ordering_id = current_ordering_id;
	
	
	set current_ordering_id = current_ordering_id + 1;        
	
IF current_ordering_id > (select max(ordering_id) from cumulative_gen_load_area_table)
	THEN LEAVE cumulative_capacity_loop;
		END IF;
END LOOP cumulative_capacity_loop;

drop table cumulative_gen_load_area_table;

END;
$$
delimiter ;

CALL cumulative_intermittent_cap_factor_rank;
DROP PROCEDURE IF EXISTS cumulative_intermittent_cap_factor_rank;

