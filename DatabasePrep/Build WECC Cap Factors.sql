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
  rps_compliance_entity varchar(20),
  UNIQUE load_area (load_area)
) ROW_FORMAT=FIXED;

load data local infile
	'wecc_load_area_info.csv'
	into table load_area_info
	fields terminated by	','
	optionally enclosed by '"'
	lines terminated by "\r"
	ignore 1 lines;

alter table load_area_info add column scenario_id INT NOT NULL first;
alter table load_area_info add index scenario_id (scenario_id);
alter table load_area_info add column area_id smallint unsigned NOT NULL AUTO_INCREMENT primary key first;

set @load_area_scenario_id := (select if( count(distinct scenario_id) = 0, 1, max(scenario_id)) from load_area_info);

update load_area_info set scenario_id = @load_area_scenario_id;


-- add ccs distance costs
-- ccs costs will increase with distance from a viable sink - right now this is handeled on a load area level basis
-- the distance from load areas without viable sinks to the nearest sink is calculated in postgresql and imported here
alter table load_area_info add column ccs_distance_km float default 0;

drop table if exists ccs_distances;
create temporary table ccs_distances(
	load_area  varchar(11) PRIMARY KEY,
	distance_km float);
	
load data local infile
	'ccs_distances.csv'
	into table ccs_distances
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;	

update load_area_info join ccs_distances using (load_area)
set ccs_distance_km = distance_km;


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
	Data_Source varchar(512),
	index techology_id_name (technology_id, technology)
);

load data local infile
	'GeneratorInfo/generator_costs.csv'
	into table generator_info
	fields terminated by	','
	optionally enclosed by '"'
	lines terminated by '\r'
	ignore 1 lines;


-- create a view for backwards compatibility - the tech ids are the important part
use generator_info;
DROP VIEW IF EXISTS generator_costs;
CREATE VIEW generator_costs as select * from switch_inputs_wecc_v2_2.generator_info;
use switch_inputs_wecc_v2_2;


-- add generator_price_scenarios to be able to easily change the capital costs of generators
CREATE TABLE IF NOT EXISTS generator_price_scenarios (
	gen_price_scenario_id mediumint unsigned PRIMARY KEY AUTO_INCREMENT,
	notes varchar(256) NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS  generator_price_adjuster (
	gen_price_scenario_id mediumint unsigned NOT NULL,
	technology_id tinyint unsigned NOT NULL,
	overnight_adjuster float NOT NULL,
	PRIMARY KEY (gen_price_scenario_id, technology_id)
);
DELIMITER $$
DROP FUNCTION IF EXISTS create_generator_price_scenario$$
CREATE FUNCTION create_generator_price_scenario (notes_dat varchar(1024)) RETURNS mediumint 
BEGIN
	INSERT INTO generator_price_scenarios (notes) VALUES (notes_dat);
	SELECT last_insert_id() into @gen_price_scenario_id;
	INSERT INTO generator_price_adjuster 
		SELECT @gen_price_scenario_id, technology_id, 1 from generator_info;
	RETURN @gen_price_scenario_id;
END$$
DELIMITER $$
DROP PROCEDURE IF EXISTS adjust_generator_price$$
CREATE PROCEDURE adjust_generator_price (gen_scenario_id mediumint unsigned, technology_name varchar(64), capital_adjuster float)
BEGIN
   UPDATE generator_price_adjuster SET overnight_adjuster=capital_adjuster
     WHERE gen_price_scenario_id=gen_scenario_id AND technology_id=(select technology_id from generator_info where technology=technology_name);
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
--        FUELS
-- ---------------------------------------------------------------------
drop table if exists fuel_info;
create table fuel_info(
	fuel varchar(64),
	rps_fuel_category varchar(10),
	biofuel tinyint,
	carbon_content float COMMENT 'carbon content (tonnes CO2 per million Btu)',
	carbon_content_without_carbon_accounting float COMMENT 'carbon content before you account for the biomass being NET carbon neutral (or carbon negative for biomass CCS) (tonnes CO2 per million Btu)',
	carbon_sequestered float
);

-- carbon content in tCO2/MMBtu from http://www.eia.doe.gov/oiaf/1605/coefficients.html:
-- Voluntary Reporting of Greenhouse Gases Program (Voluntary Reporting of Greenhouse Gases Program Fuel Carbon Dioxide Emission Coefficients)

-- Nuclear, Geothermal, Biomass, Water, Wind and Solar have non-zero LCA emissions
-- To model those emissions, we'd need to divide carbon content into capital, fixed, and variable emissions. Currently, this only lists variable emissions. 

-- carbon_content_without_carbon_accounting represents the amount of carbon actually emitted by a technology
-- before you sequester carbon or before you account for the biomass being NET carbon neutral (or carbon negative for biomass CCS)
-- the Bio_Solid value comes from: Biomass integrated gasiﬁcation combined cycle with reduced CO2emissions: Performance analysis and life cycle assessment (LCA), A. Corti, L. Lombardi / Energy 29 (2004) 2109–2124
-- on page 2119 they say that biomass STs are 23% efficient and emit 1400 kg CO2=MWh, which converts to .094345 tCO2/MMBtu
-- the Bio_Liquid value is derived from http://www.ipst.gatech.edu/faculty/ragauskas_art/technical_reviews/Black%20Liqour.pdf
-- in the spreadsheet /Volumes/1TB_RAID/Models/GIS/Biomass/black_liquor_emissions_calc.xlsx
-- Bio_Gas (landfill gas) is almost exactly 50:50 methane (NG) and CO2... we'll therefore use 2x the natural gas value

insert into fuel_info (fuel, rps_fuel_category, carbon_content_without_carbon_accounting) values
	('Gas', 'fossilish', 0.05306),
	('DistillateFuelOil', 'fossilish', 0.07315),
	('ResidualFuelOil', 'fossilish', 0.07880),
	('Wind', 'renewable', 0),
	('Solar', 'renewable', 0),
	('Bio_Solid', 'renewable', 0.094345),
	('Bio_Liquid', 'renewable', 0.07695),
	('Bio_Gas', 'renewable', 0.10612),
	('Coal', 'fossilish', 0.09552),
	('Uranium', 'fossilish', 0),
	('Geothermal', 'renewable', 0),
	('Water', 'fossilish', 0);

update fuel_info set carbon_content = if(fuel like 'Bio%', 0, carbon_content_without_carbon_accounting);

-- currently we assume that CCS captures all but 15% of the carbon emissions of a plant
-- this assumption also affects carbon_sequestered below
insert into fuel_info (fuel, rps_fuel_category, carbon_content, carbon_content_without_carbon_accounting)
select 	concat(fuel, '_CCS') as fuel,
		rps_fuel_category,
		if(fuel like 'Bio%',
			( -1 * ( 1 - 0.15) * carbon_content_without_carbon_accounting ),
			( 0.15 * carbon_content_without_carbon_accounting )
			) as carbon_content,
		carbon_content_without_carbon_accounting
	from fuel_info
	where ( fuel like 'Bio%' or fuel in ('Gas', 'DistillateFuelOil', 'ResidualFuelOil', 'Coal') );

update fuel_info set biofuel = if( fuel like 'Bio%', 1, 0 );

update fuel_info set carbon_sequestered =
	if(fuel like '%CCS', ( 1 - 0.15 ) * carbon_content_without_carbon_accounting, 0);

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
		from fuel_info, load_area_info;


-- FUEL PRICES-------------
-- run 'v2 wecc fuel price import no elasticity.sql' first
-- biomass fuel costs come from the biomass supply curve and thus aren't added here

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
        if(fuel like 'NaturalGas', 'Gas', fuel) as fuel,
        year,
        fuel_price
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
	
insert into _fuel_prices_regional (scenario_id, area_id, fuel, year, fuel_price)
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
						( select scenario_id, area_id, fuel, max(year) as max_year from _fuel_prices_regional group by 1, 2, 3 ) as max_year_table,
						_fuel_prices_regional
				where max_year_table.max_year = _fuel_prices_regional.year
				and max_year_table.scenario_id = _fuel_prices_regional.scenario_id
				and max_year_table.area_id = _fuel_prices_regional.area_id
				and max_year_table.fuel = _fuel_prices_regional.fuel
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
						( select scenario_id, area_id, fuel, max(year) as max_year from _fuel_prices_regional group by 1, 2, 3 ) as max_year_table,
						_fuel_prices_regional
				where max_year_table.max_year = _fuel_prices_regional.year
				and max_year_table.scenario_id = _fuel_prices_regional.scenario_id
				and max_year_table.area_id = _fuel_prices_regional.area_id
				and max_year_table.fuel = _fuel_prices_regional.fuel
				) as m,
				(select 	max_year_table.scenario_id,
						max_year_table.area_id,
						max_year_table.fuel,
						fuel_price as fuel_price_max_year_minus_five
						from 
						( select scenario_id, area_id, fuel, max(year) as max_year from _fuel_prices_regional group by 1, 2, 3 ) as max_year_table,
						_fuel_prices_regional
				where (max_year_table.max_year - 5 ) = _fuel_prices_regional.year
				and max_year_table.scenario_id = _fuel_prices_regional.scenario_id
				and max_year_table.area_id = _fuel_prices_regional.area_id
				and max_year_table.fuel = _fuel_prices_regional.fuel
				) as m5
			where m.scenario_id = m5.scenario_id
			and m.area_id = m5.area_id
			and m.fuel = m5.fuel) as slope_table
		where 	slope_table.scenario_id = max_year_table.scenario_id
		and		slope_table.area_id = max_year_table.area_id
		and		slope_table.fuel = max_year_table.fuel
		;
			
delete from _fuel_prices_regional where year > 2100;

-- add in fuel prices for CCS - these are the same as for the non-CCS technologies, but with a CCS added to the name
insert into _fuel_prices_regional (scenario_id, area_id, fuel, year, fuel_price)
	select 	scenario_id,
			area_id,
			concat(fuel, '_CCS') as fuel,
			year,
			fuel_price
	from _fuel_prices_regional where fuel in ('Gas', 'Coal', 'DistillateFuelOil', 'ResidualFuelOil');

-- add fuel prices of zero for renewables... this could be handedled through default fuel price values
-- but in the past bugs have been caused by using a default fuel price of 0 in switch.mod
-- biomass_solid gets a default of zero here, but it comes in on the biomass supply curve.
insert into _fuel_prices_regional (scenario_id, area_id, fuel, year, fuel_price)
	select 	scenario_id,
			area_id,
			fuel,
			year,
			0 as fuel_price
	from 	( select distinct scenario_id, area_id, year from _fuel_prices_regional) as scenarios_areas_years,
			fuel_info
	where 	fuel not in (select distinct fuel from _fuel_prices_regional);

-- add values for the fuel 'Storage'
insert into _fuel_prices_regional (scenario_id, area_id, fuel, year, fuel_price)
	select 	scenario_id,
			area_id,
			'Storage' as fuel,
			year,
			0 as fuel_price
	from 	( select distinct scenario_id, area_id, year from _fuel_prices_regional) as scenarios_areas_years;
  
DROP VIEW IF EXISTS fuel_prices_regional;
CREATE VIEW fuel_prices_regional as
SELECT _fuel_prices_regional.scenario_id, load_area_info.area_id, load_area, fuel, year, fuel_price 
    FROM _fuel_prices_regional, load_area_info
    WHERE _fuel_prices_regional.area_id = load_area_info.area_id;

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
drop table if exists rps_compliance_entity_targets;
create table rps_compliance_entity_targets(
	rps_compliance_entity character varying(20),
	rps_compliance_type character varying(20),
	rps_compliance_year year,
	rps_compliance_fraction float,
	PRIMARY KEY (rps_compliance_entity, rps_compliance_type, rps_compliance_year),
	INDEX rps_compliance_year (rps_compliance_year)
	);

load data local infile
	'rps_compliance_targets.csv'
	into table rps_compliance_entity_targets
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;


-- CARBON CAP INFO ---------------
-- the current carbon cap in SWITCH is set by a linear decrease
-- from 100% of 1990 levels in 2020 to 20% of 1990 levels in 2050
-- these two goals are the california emission goals.
drop table if exists carbon_cap_targets;
create table carbon_cap_targets(
	year year primary key,
	carbon_emissions_relative_to_base float
	);

load data local infile
	'carbon_cap_targets.csv'
	into table carbon_cap_targets
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;

-- EXISTING PLANTS---------
-- made in 'build existing plants table.sql'
select 'Copying existing_plants' as progress;

drop table if exists existing_plants;
CREATE TABLE existing_plants (
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
	overnight_cost float NOT NULL,
	connect_cost_per_mw float,
	fixed_o_m double NOT NULL,
	variable_o_m double NOT NULL,
	forced_outage_rate double NOT NULL,
	scheduled_outage_rate double NOT NULL,
	ep_location_id int unsigned default 0,
	UNIQUE (technology, plant_name, eia_id, primemover, fuel, start_year),
	INDEX area_id (area_id),
	FOREIGN KEY (area_id) REFERENCES load_area_info(area_id), 
	INDEX plant_name (plant_name)
);

 -- The << operation moves the numeric form of the letter "E" (for existing plants) over by 3 bytes, effectively making its value into the most significant digits.
insert into existing_plants (project_id, load_area, technology, ep_id, area_id, plant_name, eia_id,
								primemover, fuel, capacity_mw, heat_rate, cogen_thermal_demand_mmbtus_per_mwh, start_year,
								overnight_cost, connect_cost_per_mw, fixed_o_m, variable_o_m, forced_outage_rate, scheduled_outage_rate )
	select 	e.ep_id + (ascii( 'E' ) << 8*3),
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
			g.overnight_cost * economic_multiplier,
			g.connect_cost_per_mw_generic * economic_multiplier,		
			g.fixed_o_m * economic_multiplier,
			g.variable_o_m * economic_multiplier,
			g.forced_outage_rate,
			g.scheduled_outage_rate
			from generator_info.existing_plants_agg e
			join generator_info g using (technology)
			join load_area_info a using (load_area);

			
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
  SELECT cp.project_id, load_area, technology, hour, cap_factor
    FROM _existing_intermittent_plant_cap_factor cp join existing_plants using (project_id);

insert into _existing_intermittent_plant_cap_factor
SELECT      existing_plants.project_id,
            existing_plants.area_id,
            hournum as hour,
            3tier.windfarms_existing_cap_factor.cap_factor
    from    existing_plants, 
            3tier.windfarms_existing_cap_factor
    where   technology = 'Wind_EP'
    and		concat('Wind_EP', '_', 3tier.windfarms_existing_cap_factor.windfarm_existing_id) = existing_plants.plant_name;


-- HYDRO-------------------
-- made in 'build existing plants table.sql'
select 'Copying Hydro' as progress;

drop table if exists _hydro_monthly_limits;
CREATE TABLE _hydro_monthly_limits (
  project_id int unsigned,
  year year,
  month tinyint,
  avg_output float,
  INDEX (project_id),
  PRIMARY KEY (project_id, year, month),
  FOREIGN KEY (project_id) REFERENCES existing_plants (project_id)
);

DROP VIEW IF EXISTS hydro_monthly_limits;
CREATE VIEW hydro_monthly_limits as
  SELECT project_id, load_area, technology, year, month, avg_output
    FROM _hydro_monthly_limits join existing_plants using (project_id);

-- the join is long here in an attempt to reduce the # of numeric ids flying around
insert into hydro_monthly_limits (project_id, year, month, avg_output )
	select 
	  project_id,
	  year,
	  month,
	  avg_output
	from generator_info.hydro_monthly_limits
	join existing_plants using (load_area, plant_name, eia_id, start_year, capacity_mw)
	where fuel = 'Water';


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


drop table if exists _proposed_projects;
CREATE TABLE _proposed_projects (
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
  price_and_dollar_year year(4),
  overnight_cost float,
  fixed_o_m float,
  variable_o_m float,
  heat_rate float default 0,
  cogen_thermal_demand float default 0,
  overnight_cost_change float,
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
  FOREIGN KEY (technology_id) REFERENCES generator_info (technology_id)
) ROW_FORMAT=FIXED;

-- the capacity limit is either in MW if the capacity_limit_conversion is 1, or in other units if the capacity_limit_conversion is nonzero
-- so for CSP and central PV the limit is expressed in land area, not MW
-- The << operation moves the numeric form of the letter "G" (for generators) over by 3 bytes, effectively making its value into the most significant digits.
-- change to 'P' on a complete rebuild of the database to make this more clear
insert into _proposed_projects
	(project_id, gen_info_project_id, technology_id, technology, area_id, location_id, original_dataset_id,
	capacity_limit, capacity_limit_conversion, connect_cost_per_mw, price_and_dollar_year,
	overnight_cost, fixed_o_m, variable_o_m, heat_rate, overnight_cost_change )
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
    		price_and_dollar_year,  
   			overnight_cost * economic_multiplier       as overnight_cost,
    		fixed_o_m * economic_multiplier            as fixed_o_m,
    		variable_o_m * economic_multiplier         as variable_o_m,
    		heat_rate,
   			overnight_cost_change			
	from proposed_projects_import join generator_info using (technology) join load_area_info using (load_area)
	order by 2;


-- before we do anything else, we need to change the capacity_limit and capacity_limit_conversion for biomass and biogas
-- as imported, the capacity_limit is in MMBtu per hour per load area, and the capacity_limit_conversion is in 1/heat_rate, or MWh/MMBtu.  Multiplying these together gives MW of capacity.
-- due to a (minor) error in postgresql, the generator availability isn't taken into account, so the MW of capacity multiplication will result in the correct MMBtu per hour per load area
alter table load_area_info add column bio_gas_capacity_limit_mmbtu_per_hour float default 0;

update load_area_info join proposed_projects using (load_area) join generator_info using (technology)
	set 	bio_gas_capacity_limit_mmbtu_per_hour = capacity_limit
	where	technology = 'Bio_Gas'

-- we've changed how bio projects are done since proposed projects was done in postgresql
-- so update _proposed_projects to be consistent here
update _proposed_projects
set		location_id = null,
		capacity_limit = null
where	technology like 'Bio%';

update _proposed_projects
set		capacity_limit_conversion = null
where	capacity_limit_conversion = 1;


-- add CAES for Canada and Mexico - we didn't have shapefiles for CAES geology in these areas but it is very likely that their is ample caes potential
-- this should be cleaned up in Postgresql eventually
insert into _proposed_projects
	(technology_id, technology, area_id, location_id, original_dataset_id,
	capacity_limit, connect_cost_per_mw, price_and_dollar_year,
	overnight_cost, fixed_o_m, variable_o_m, heat_rate, overnight_cost_change )
	select  technology_id,
	        technology,
			area_id,
			0 as location_id,
			0 as original_dataset_id,
			100000 as capacity_limit,
			connect_cost_per_mw_generic * economic_multiplier  as connect_cost_per_mw,
    		price_and_dollar_year,  
   			overnight_cost * economic_multiplier       as overnight_cost,
    		fixed_o_m * economic_multiplier            as fixed_o_m,
    		variable_o_m * economic_multiplier         as variable_o_m,
    		heat_rate,
   			overnight_cost_change			
	from generator_info, load_area_info
where technology = 'Compressed_Air_Energy_Storage'
and load_area in ('CAN_ALB', 'CAN_BC', 'MEX_BAJA');



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

-- Insert "generic" projects that can be built almost anywhere.
-- Note, project_id is automatically set here because it is an autoincrement column. The renewable proposed_projects with ids set a-priori need to be imported first to avoid unique id conflicts.
 -- The << operation moves the numeric form of the letter "G" (for generic projects) over by 3 bytes, effectively making its value into the most significant digits.
insert into _proposed_projects
	(technology_id, technology, area_id, connect_cost_per_mw, price_and_dollar_year,
	overnight_cost, fixed_o_m, variable_o_m, heat_rate, overnight_cost_change )
    select 	technology_id,
    		technology,
    		area_id,
    		connect_cost_per_mw_generic * economic_multiplier as connect_cost_per_mw,
    		price_and_dollar_year,  
   			overnight_cost * economic_multiplier as overnight_cost,
    		fixed_o_m * economic_multiplier as fixed_o_m,
    		variable_o_m * economic_multiplier as variable_o_m,
    		heat_rate,
   			overnight_cost_change
    from 	generator_info,
			load_area_info
	where   generator_info.can_build_new  = 1 and 
	        generator_info.resource_limited = 0
	order by 1,3;

-- regional generator restrictions: Coal and Nuclear can't be built in CA.
delete from _proposed_projects
 	where 	(technology_id in (select technology_id from generator_info where fuel in ('Uranium', 'Coal', 'Coal_CCS')) and
			area_id in (select area_id from load_area_info where primary_nerc_subregion like 'CA'));

-- add new Biomass_IGCC_CCS and Bio_Gas_CCS projects that aren't cogen... we'll add cogen CCS elsewhere
-- neither capacity_limit nor capacity_limit_conversion show up here - they'll be null in the database
-- because these projects will be capacity constrained by bio_fuel_limit_by_load_area instead
insert into _proposed_projects (technology_id, technology, area_id,
								connect_cost_per_mw, price_and_dollar_year, overnight_cost, fixed_o_m, variable_o_m, heat_rate, overnight_cost_change)
   select 	technology_id,
    		technology,
    		load_area_info.area_id,
    		connect_cost_per_mw_generic * economic_multiplier as connect_cost_per_mw,
    		price_and_dollar_year,  
   			overnight_cost * economic_multiplier as overnight_cost,
    		fixed_o_m * economic_multiplier as fixed_o_m,
    		variable_o_m * economic_multiplier as variable_o_m,
    		heat_rate,
   			overnight_cost_change
    from 	generator_info,
    		load_area_info,
			( select area_id, concat(technology, '_CCS') as ccs_technology from _proposed_projects,
				( select trim(trailing '_CCS' from technology) as non_ccs_technology
						from generator_info
						where technology in ('Biomass_IGCC_CCS', 'Bio_Gas_CCS') ) as non_ccs_technology_table
					where non_ccs_technology_table.non_ccs_technology = _proposed_projects.technology ) as resource_limited_ccs_load_area_projects
	where 	generator_info.technology = resource_limited_ccs_load_area_projects.ccs_technology
	and		load_area_info.area_id = resource_limited_ccs_load_area_projects.area_id;


-- add geothermal replacements projects that will be constrained to replace existing cogen projects by ep_project_replacement_id
-- the capacity limit of these projects is the same as for the plant they're replacing
insert into _proposed_projects (original_dataset_id, technology_id, technology, area_id, capacity_limit, ep_project_replacement_id,
								connect_cost_per_mw, price_and_dollar_year, overnight_cost, fixed_o_m, variable_o_m, heat_rate, overnight_cost_change)
   select 	existing_plants.ep_id as original_dataset_id,
   			technology_id,
    		'Geothermal' as technology,
    		area_id,
			capacity_mw as capacity_limit,
    		existing_plants.project_id as ep_project_replacement_id,
    		0 as connect_cost_per_mw,
    		price_and_dollar_year,  
   			generator_info.overnight_cost * economic_multiplier as overnight_cost,
    		generator_info.fixed_o_m * economic_multiplier as fixed_o_m,
    		generator_info.variable_o_m * economic_multiplier as variable_o_m,
    		existing_plants.heat_rate,
   			overnight_cost_change
    from 	generator_info,
    		existing_plants
    join    load_area_info using (area_id)
	where 	existing_plants.technology = 'Geothermal_EP'
	and		generator_info.technology = 'Geothermal'
;	


-- add new (non-CCS) cogen projects which will replace existing cogen projects via ep_project_replacement_id
-- the capacity limit, heat rate and cogen thermal demand of these projects is the same as for the plant they're replacing
-- these plants will compete with CCS cogen projects through ep_project_replacement_id for the cogen resource
insert into _proposed_projects (original_dataset_id, technology_id, technology, area_id, capacity_limit, ep_project_replacement_id,
								connect_cost_per_mw, price_and_dollar_year, overnight_cost, fixed_o_m, variable_o_m, heat_rate, cogen_thermal_demand, overnight_cost_change)
   select 	existing_plants.ep_id as original_dataset_id,
   			technology_id,
    		generator_info.technology,
    		area_id,
			capacity_mw as capacity_limit,
    		existing_plants.project_id as ep_project_replacement_id,
    		0 as connect_cost_per_mw,
    		price_and_dollar_year,  
   			generator_info.overnight_cost * economic_multiplier as overnight_cost,
    		generator_info.fixed_o_m * economic_multiplier as fixed_o_m,
    		generator_info.variable_o_m * economic_multiplier as variable_o_m,
    		existing_plants.heat_rate,
      		existing_plants.cogen_thermal_demand_mmbtus_per_mwh as cogen_thermal_demand,
 			overnight_cost_change
    from 	generator_info,
    		existing_plants
    join    load_area_info using (area_id)
	where 	replace(existing_plants.technology, 'Cogen_EP', 'Cogen') = generator_info.technology
	and		generator_info.cogen = 1
	and		generator_info.ccs = 0
	and		generator_info.can_build_new = 1
;	

-- COGEN CCS---------------------------------
-- the heat rate and cogen thermal demand of cogen CCS is calculated here...
-- it takes energy to do CCS, so we add this energy onto the existing heat rate and cogen thermal demand in equal proportion

-- create a temporary table to calculate the increase in heat_rate and cogen_thermal_demand from adding ccs onto cogen plants
-- this should be made with the same assumptions that are used to calculate these params in generator_info.xlsx for other CCS technologies
drop table if exists cogen_ccs_var_costs_and_heat_rates;
create temporary table cogen_ccs_var_costs_and_heat_rates (
			technology varchar(64) primary key,		
			non_cogen_reference_ccs_technology varchar(64),
			non_cogen_reference_non_ccs_technology varchar(64),
			heat_rate_increase_factor float,
			heat_rate_increase_mmbtu_per_mwh float,
			variable_cost_increase_factor float,
			variable_o_m_cogen_non_ccs_base float
			);

insert into 	cogen_ccs_var_costs_and_heat_rates (technology)
	select	distinct(technology) from generator_info where technology like '%Cogen_CCS%';

update	cogen_ccs_var_costs_and_heat_rates
set		non_cogen_reference_ccs_technology =
		CASE
			WHEN technology in ('Gas_Combustion_Turbine_Cogen_CCS', 'Gas_Internal_Combustion_Engine_Cogen_CCS') THEN 'Gas_Combustion_Turbine_CCS'
			WHEN technology = 'Bio_Gas_Internal_Combustion_Engine_Cogen_CCS' THEN 'Bio_Gas_CCS'
			WHEN technology in ('Bio_Liquid_Steam_Turbine_Cogen_CCS', 'Bio_Solid_Steam_Turbine_Cogen_CCS', 'Coal_Steam_Turbine_Cogen_CCS', 'Gas_Steam_Turbine_Cogen_CCS') THEN 'Coal_Steam_Turbine_CCS'
			WHEN technology = 'CCGT_Cogen_CCS' THEN 'CCGT_CCS'
		END;
		
update	cogen_ccs_var_costs_and_heat_rates
set 	non_cogen_reference_non_ccs_technology = replace(non_cogen_reference_ccs_technology, '_CCS', '');

-- calculate the fraction increase in heat rate for CCS cogen plants (relative to non-CCS) from the base technology
-- also calculate the base increase in variable cost for adding CCS to a plant from the base technology
-- this will later be multiplied by the relative increases in heat rates
-- we assume that the increase in variable costs (delta variable cost) scales with the relative increase in heat rate (delta heat rate)
update 	cogen_ccs_var_costs_and_heat_rates,
		(select cogen_ccs_var_costs_and_heat_rates.technology, 
				heat_rate as heat_rate_reference_ccs,
				variable_o_m as variable_o_m_reference_ccs
			from	generator_info,
			 		cogen_ccs_var_costs_and_heat_rates
			where generator_info.technology = non_cogen_reference_ccs_technology
		) as reference_ccs_table,
		(select cogen_ccs_var_costs_and_heat_rates.technology, 
				heat_rate as heat_rate_reference_non_ccs,
				variable_o_m as variable_o_m_reference_non_ccs
			from	generator_info,
				 	cogen_ccs_var_costs_and_heat_rates
			where generator_info.technology = non_cogen_reference_non_ccs_technology
		) as reference_non_ccs_table
set		cogen_ccs_var_costs_and_heat_rates.heat_rate_increase_factor = heat_rate_reference_ccs / heat_rate_reference_non_ccs,
		cogen_ccs_var_costs_and_heat_rates.heat_rate_increase_mmbtu_per_mwh = heat_rate_reference_ccs - heat_rate_reference_non_ccs,
		cogen_ccs_var_costs_and_heat_rates.variable_cost_increase_factor = variable_o_m_reference_ccs - variable_o_m_reference_non_ccs
where	cogen_ccs_var_costs_and_heat_rates.technology = reference_ccs_table.technology
and		cogen_ccs_var_costs_and_heat_rates.technology = reference_non_ccs_table.technology
;

-- we'll look to the non-CCS cogen values for each cogen CCS technology to the the variable_o_m base cost ($/MWh)
update 	cogen_ccs_var_costs_and_heat_rates,
		generator_info
set		cogen_ccs_var_costs_and_heat_rates.variable_o_m_cogen_non_ccs_base = generator_info.variable_o_m
where	replace(cogen_ccs_var_costs_and_heat_rates.technology, 'Cogen_CCS', 'Cogen') = generator_info.technology;

-- add new CCS cogen projects which will replace existing cogen projects after the existing cogen project plant lifetime
-- these plants will compete with non-CCS cogen projects through ep_project_replacement_id for the cogen resource
-- the capacity limit of these projects is the same as for the plant they're replacing,
-- as we're assuming that the plants will burn extra fuel to get the same amount of useful heat and electricity out (CCS has an efficiency penalty which makes them burn more fuel)
-- the variable costs are a bit complicated, so they're updated below
insert into _proposed_projects (original_dataset_id, technology_id, technology, area_id, capacity_limit, ep_project_replacement_id,
								connect_cost_per_mw, price_and_dollar_year, overnight_cost, fixed_o_m, variable_o_m, heat_rate, cogen_thermal_demand, overnight_cost_change)
   select 	existing_plants.ep_id as original_dataset_id,
   			technology_id,
    		generator_info.technology,
    		area_id,
			capacity_mw as capacity_limit,
    		existing_plants.project_id as ep_project_replacement_id,
    		0 as connect_cost_per_mw,
    		price_and_dollar_year,  
   			generator_info.overnight_cost * economic_multiplier as overnight_cost,
    		generator_info.fixed_o_m * economic_multiplier as fixed_o_m,
    		variable_o_m_cogen_non_ccs_base  +
    			economic_multiplier * variable_cost_increase_factor * ( existing_plants.heat_rate * heat_rate_increase_factor - existing_plants.heat_rate ) 
    				/ heat_rate_increase_mmbtu_per_mwh
    			as variable_o_m,
 			existing_plants.heat_rate * heat_rate_increase_factor as heat_rate,
      		existing_plants.cogen_thermal_demand_mmbtus_per_mwh * heat_rate_increase_factor as cogen_thermal_demand,
   			overnight_cost_change
	from    generator_info
    join	cogen_ccs_var_costs_and_heat_rates using (technology)
   	join 	existing_plants on (replace(existing_plants.technology, 'Cogen_EP', 'Cogen_CCS') = generator_info.technology)
    join    load_area_info using (area_id)
	where 	generator_info.cogen = 1
	and		generator_info.ccs = 1
	and		generator_info.can_build_new = 1
;



-- make a unique identifier for all proposed projects
UPDATE _proposed_projects SET project_id = gen_info_project_id + (ascii( 'G' ) << 8*3) where project_id is null;


DROP VIEW IF EXISTS proposed_projects;
CREATE VIEW proposed_projects as
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
            price_and_dollar_year,
            overnight_cost,
            fixed_o_m,
            variable_o_m,
            heat_rate,
            cogen_thermal_demand,
            overnight_cost_change,
            avg_cap_factor_intermittent,
            avg_cap_factor_percentile_by_intermittent_tech,
            cumulative_avg_MW_tech_load_area,
            rank_by_tech_in_load_area
    FROM _proposed_projects 
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

