-- GENERATOR COSTS---------------


create database if not exists switch_inputs_wecc_v2;
use switch_inputs_wecc_v2;


-- HOURS-------------------------
-- creates hours table from the CSP data because 3tier knows how to deal correctly in UTC, right now only for 2004-2005
-- omits the last day because we're using UTC and so records for the first day (Jan 1 2004) won't be complete.
drop table if exists hours;
CREATE TABLE hours (
  datetime_utc datetime NOT NULL COMMENT 'date & time in Coordinated Universal Time, with Daylight Savings Time ignored',
  hournum int NOT NULL,
  UNIQUE KEY datetime_utc (datetime_utc),
  UNIQUE KEY hournum (hournum)
);

set @curhour = 0;
insert into hours
	select distinct(datetime_utc), (@curhour := @curhour+1)
		FROM 3tier.csp_power_output
		where datetime_utc between "2004-01-02 00:00" and "2005-12-31 23:59"
	order by datetime_utc;

-- SYSTEM LOAD
-- patched together from the old wecc loads...
-- should be improved in the future from FERC data
drop table if exists system_load;
CREATE TABLE  system_load (
  load_area varchar(11),
  hour int,
  power double,
  INDEX hour (hour ),
  INDEX load_area (load_area),
  UNIQUE KEY hour_load_area (hour, load_area)
);

insert into system_load 
select 	v2_load_area as load_area, 
		hour,
		sum( power * population_fraction) as power
from 	loads_wecc.v1_wecc_load_areas_to_v2_wecc_load_areas,
		wecc.system_load
where	v1_load_area = wecc.system_load.load_area
group by v2_load_area, hour;

-- Study Hours----------------------
source Setup_Study_Hours.sql;





-- RENEWABLE SITES--------------
-- imported from postgresql, this table has all distributed pv, trough, wind, geothermal and biomass sites
drop table if exists proposed_renewable_sites;
CREATE TABLE  proposed_renewable_sites (
  generator_type varchar(20),
  load_area varchar(11),
  site varchar(50),
  renewable_id bigint(20),
  capacity_mw float,
  connect_cost_per_mw float,
  INDEX generator_type_renewable_id (generator_type,renewable_id),
  INDEX renewable_id (renewable_id),
  UNIQUE (site)
);

insert into proposed_renewable_sites
	select 	generator_type,
			load_area,
			site,
			renewable_id,
			capacity_mw,
			connect_cost_per_mw
	from generator_info.proposed_renewable_sites
	order by 1,2,3;


-- CAP FACTOR-----------------
-- assembles the hourly power output for Distributed_PV, CSP_Trough, Wind and Offshore_Wind
drop table if exists cap_factor_proposed_renewable_sites;
create table cap_factor_proposed_renewable_sites(
	generator_type varchar(30),
	load_area varchar(11),
	site varchar(50),
	configuration varchar(20),
	hour int,
	cap_factor float,
	INDEX hour (hour),
	INDEX site (site),
	INDEX generator_type (generator_type),
	UNIQUE (site, configuration, hour),
	CONSTRAINT site_fk FOREIGN KEY site (site) REFERENCES proposed_renewable_sites (site)
);

select 'Compiling Distributed_PV' as progress;
insert into cap_factor_proposed_renewable_sites
SELECT      proposed_renewable_sites.generator_type,
            proposed_renewable_sites.load_area,
            proposed_renewable_sites.site as site,
			suny.grid_hourlies.orientation as configuration,
            hours.hournum as hour,
            suny.grid_hourlies.cap_factor
    from    suny.grid_hourlies       join
            proposed_renewable_sites join
            hours
    where   generator_type = 'Distributed_PV'
	and		suny.grid_hourlies.grid_id = proposed_renewable_sites.renewable_id
    and     hours.datetime_utc = suny.grid_hourlies.datetime_utc;
 
select 'Compiling CSP_Trough' as progress;
insert into cap_factor_proposed_renewable_sites
SELECT      proposed_renewable_sites.generator_type,
            proposed_renewable_sites.load_area,
            proposed_renewable_sites.site as site,
            'na' as configuration,
            hours.hournum as hour,
            3tier.csp_power_output.e_net_mw/100 as cap_factor
    from    proposed_renewable_sites, 
            3tier.csp_power_output,
            hours
    where   generator_type = 'CSP_Trough'
    and     proposed_renewable_sites.renewable_id = 3tier.csp_power_output.siteid
    and     hours.datetime_utc = 3tier.csp_power_output.datetime_utc;

select 'Compiling Offshore_Wind' as progress;
insert into cap_factor_proposed_renewable_sites
SELECT      proposed_renewable_sites.generator_type,
            proposed_renewable_sites.load_area,
            proposed_renewable_sites.site as site,
            'na' as configuration,
            hours.hournum as hour,
            3tier.wind_farm_power_output.cap_factor
    from    proposed_renewable_sites, 
            3tier.wind_farm_power_output,
            hours
    where   generator_type = 'Offshore_Wind'
    and     proposed_renewable_sites.renewable_id = 3tier.wind_farm_power_output.wind_farm_id
    and     hours.datetime_utc = 3tier.wind_farm_power_output.datetime_utc;

select 'Compiling Wind' as progress;
insert into cap_factor_proposed_renewable_sites
SELECT      proposed_renewable_sites.generator_type,
            proposed_renewable_sites.load_area,
            proposed_renewable_sites.site as site,
            'na' as configuration,
            hours.hournum as hour,
            3tier.wind_farm_power_output.cap_factor
    from    proposed_renewable_sites, 
            3tier.wind_farm_power_output,
            hours
    where   generator_type = 'Wind'
    and     proposed_renewable_sites.renewable_id = 3tier.wind_farm_power_output.wind_farm_id
    and     hours.datetime_utc = 3tier.wind_farm_power_output.datetime_utc;




-- EXISTING PLANTS---------
-- made in 'build proposed plants table.sql'
select 'Copying existing_plants' as progress;
drop table if exists existing_plants;
create table existing_plants
select * from generator_info.existing_plants_agg;


-- HYDRO-------------------
-- made in 'build proposed plants table.sql'
drop table if exists hydro_monthly_limits;
create table hydro_monthly_limits
select * from generator_info.hydro_monthly_limits;

alter table hydro_monthly_limits add index (year,month);


-- TRANS LINES----------
-- made in postgresql
drop table if exists transmission_lines;
create table transmission_lines(
	transmission_line_id int,
	load_area_start varchar(11),
	load_area_end varchar(11),
	existing_transfer_capacity_mw double,
	transmission_length_km double,
	load_areas_border_each_other char(1)
);

load data local infile
	'/Volumes/1TB_RAID/Models/Switch\ Input\ Data/Transmission/wecc_trans_lines.csv'
	into table transmission_lines
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;
	
-- LOAD AREA INFO	
-- made in postgresql
drop table if exists load_area_info;
create table load_area_info(
  load_area varchar(11),
  primary_nerc_subregion varchar(20),
  primary_state varchar(20),
  economic_multiplier double,
  rps_compliance_year integer,
  rps_compliance_percentage double,
  INDEX load_area (load_area)
);

load data local infile
	'/Volumes/1TB_RAID/Models/GIS/wecc_load_area_info.csv'
	into table load_area_info
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;

alter table load_area_info add column scenario_id INT NOT NULL first;
alter table load_area_info add index scenario_id (scenario_id);
alter table load_area_info add column area_id int NOT NULL AUTO_INCREMENT primary key first;

select if( max(scenario_id) + 1 is null, 1, max(scenario_id) + 1 ) into @this_scenario_id
    from load_area_info;

update load_area_info set scenario_id = @this_scenario_id;



-----------------------------------------------------------------------
--        REGION-SPECIFIC GENERATOR COSTS & AVAILIBILITY
-----------------------------------------------------------------------

DROP TABLE if exists regional_generator_costs;
CREATE TABLE regional_generator_costs(
  scenario_id INT NOT NULL,
  area_id INT NOT NULL,
  technology varchar(30),
  price_year year(4),
  overnight_cost double,
  connect_cost_per_mw_generic double,
  fixed_o_m double,
  variable_o_m double,
  overnight_cost_change double,
  fixed_o_m_change double,
  variable_o_m_change double
);

set @cost_mult_scenario_id = 1;

-- Find the next scenario id. 
select if( max(scenario_id) + 1 is null, 1, max(scenario_id) + 1 ) into @reg_generator_scenario_id
    from regional_generator_costs;

-- The middle four lines in the select statment are prices that are affected by regional price differences
-- The rest of these variables aren't affected by region, but they're brought along here to make it easier in AMPL
-- technologies that Switch can't build yet but might in the future are eliminated in the last line
insert into regional_generator_costs
    (scenario_id, area_id, technology, price_year, overnight_cost, connect_cost_per_mw_generic, 
     fixed_o_m, variable_o_m, overnight_cost_change, fixed_o_m_change, variable_o_m_change)

    select 	@reg_generator_scenario_id as scenario_id, 
    		area_id,
    		technology,
    		price_year,  
   			overnight_cost * economic_multiplier as overnight_cost,
    		connect_cost_per_mw_generic * economic_multiplier as connect_cost_per_mw_generic,
    		fixed_o_m * economic_multiplier as fixed_o_m,
    		variable_o_m * economic_multiplier as variable_o_m,
   			overnight_cost_change,
   			fixed_o_m_change,
   			variable_o_m_change
    from 	generator_info.generator_costs,
			load_area_info
	where 	load_area_info.scenario_id  = @cost_mult_scenario_id
	and		technology not in ('Central_Station_PV', 'CSP_Trough_No_Storage', 'Coal_IGCC', 'Coal_IGCC_With_CSS')
;


-- regional generator restrictions
-- currently, the only restrictions are that Coal_ST and Nuclear can't be built in CA
delete from regional_generator_costs
 	where 	(technology in ('Nuclear', 'Coal_ST') and
			area_id in (select area_id from load_area_info where primary_nerc_subregion like 'CA'));


-- Make a view that is more user-friendly
drop view if exists regional_generator_costs_view;
CREATE VIEW regional_generator_costs_view as
  SELECT load_area, regional_generator_costs.* 
    FROM regional_generator_costs, load_area_info
    WHERE	load_area_info.area_id = regional_generator_costs.area_id;
    
-----------------------------------------------------------------------
--        NON-REGIONAL GENERATOR INFO
-----------------------------------------------------------------------


DROP TABLE IF EXISTS generator_info;
CREATE TABLE generator_info (
  select technology, min_build_year, fuel, heat_rate, construction_time_years,
  		max_age_years, forced_outage_rate, scheduled_outage_rate, intermittent,
  		resource_limited, baseload, min_build_capacity
  from generator_info.generator_costs );



-- FUEL PRICES-------------
-- run 'v2 wecc fuel price import no elasticity.sql' first

drop table if exists regional_fuel_prices;
CREATE TABLE regional_fuel_prices (
  scenario_id INT NOT NULL,
  area_id INT NOT NULL,
  fuel VARCHAR(30),
  year year,
  fuel_price FLOAT NOT NULL COMMENT 'Regional fuel prices for various types of fuel in $2007 per MMBtu',
  INDEX scenario_id(scenario_id),
  INDEX area_id(area_id),
  CONSTRAINT area_id FOREIGN KEY area_id (area_id)
    REFERENCES load_area_info (area_id)
);

select if( max(scenario_id) + 1 is null, 1, max(scenario_id) + 1 ) into @this_scenario_id
    from regional_fuel_prices;
  
insert into regional_fuel_prices
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

  
drop view if exists regional_fuel_prices_view;
CREATE VIEW regional_fuel_prices_view as
SELECT regional_fuel_prices.scenario_id, load_area_info.area_id, load_area, fuel, year, fuel_price 
    FROM regional_fuel_prices, load_area_info
    WHERE regional_fuel_prices.area_id = load_area_info.area_id;

-- RPS----------------------
drop table if exists fuel_info;
create table fuel_info(
	fuel varchar(30),
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
	('Biomass', 'renewable', 0),
	('Coal', 'fossilish', 0.0939),
	('Uranium', 'fossilish', 0),
	('Geothermal', 'renewable', 0),
	('Water', 'fossilish', 0);


drop table if exists fuel_qualifies_for_rps;
create table fuel_qualifies_for_rps(
	area_id INT NOT NULL,
	load_area varchar(11),
	rps_fuel_category varchar(10),
	qualifies boolean,
	INDEX area_id (area_id),
  	CONSTRAINT area_id FOREIGN KEY area_id (area_id)
   		REFERENCES load_area_info (area_id)
);

insert into fuel_qualifies_for_rps
	select distinct 
	        area_id,
			load_area,
			rps_fuel_category,
			if(rps_fuel_category like 'renewable', 1, 0)
		from fuel_info, load_area_info;

