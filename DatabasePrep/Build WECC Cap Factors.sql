-- GENERATOR COSTS---------------


create database if not exists switch_inputs_wecc_v2_1;
use switch_inputs_wecc_v2_1;

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
	'/Volumes/1TB_RAID/Models/GIS/wecc_load_area_info.csv'
	into table load_area_info
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;

alter table load_area_info add column scenario_id INT NOT NULL first;
alter table load_area_info add index scenario_id (scenario_id);
alter table load_area_info add column area_id int NOT NULL AUTO_INCREMENT primary key first;

select if( max(scenario_id) + 1 is null, 1, max(scenario_id) + 1 ) into @load_area_scenario_id
    from load_area_info;

update load_area_info set scenario_id = @load_area_scenario_id;


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
drop table if exists _system_load;
CREATE TABLE  _system_load (
  area_id int,
  hour int,
  power double,
  INDEX hour (hour ),
  INDEX area_id (area_id),
  FOREIGN KEY (area_id) REFERENCES load_area_info(area_id), 
  UNIQUE KEY hour_load_area (hour, area_id)
);

insert into _system_load 
select 	area_id, 
		hour,
		sum( power * population_fraction) as power
from 	loads_wecc.v1_wecc_load_areas_to_v2_wecc_load_areas,
		wecc.system_load, load_area_info
where	v1_load_area = wecc.system_load.load_area and v2_load_area = load_area_info.load_area
group by v2_load_area, hour;

DROP VIEW IF EXISTS system_load;
CREATE VIEW system_load as 
  SELECT area_id, load_area, hour, power FROM _system_load JOIN load_area_info USING (area_id);

-- Study Hours----------------------
source Setup_Study_Hours.sql;


-- Do NOT drop this table unless you want to do a reset of the whole inputs & results databases
CREATE TABLE if not exists _project_ids (
  project_id int NOT NULL PRIMARY KEY AUTO_INCREMENT,
  project_type varchar(50) COMMENT "This can be 'proposed_renewable_sites', 'existing_plants', 'hydro', or 'proposed_generation' where proposed_generation refers to new traditional sites that could be built, information for which is in the generator_costs_regional table.",
  label varchar(50) COMMENT "For proposed_renewable_sites, this references site. For existing_plants and hydro, plant_code. ",
  UNIQUE info (project_type, label),
  INDEX label (label)
) ROW_FORMAT=FIXED;



-- RENEWABLE SITES--------------
-- imported from postgresql, this table has all distributed pv, trough, wind, geothermal and biomass sites
drop table if exists proposed_renewable_sites;
CREATE TABLE  proposed_renewable_sites (
  project_id int PRIMARY KEY DEFAULT 0,
  technology_id INT NOT NULL,
  generator_type varchar(30),
  load_area varchar(11),
  site varchar(50) NOT NULL,
  renewable_id bigint(20),
  capacity_mw float,
  connect_cost_per_mw float,
  INDEX generator_type_renewable_id (generator_type,renewable_id),
  INDEX technology_id (technology_id),
  INDEX renewable_id (renewable_id),
  UNIQUE (site),
  FOREIGN KEY (technology_id) REFERENCES generator_info (technology_id)
) ROW_FORMAT=FIXED;

DELIMITER $$

/*!50003 DROP TRIGGER IF EXISTS `trg_ren_proj_id` */$$

/*!50003 CREATE TRIGGER `trg_ren_proj_id` BEFORE INSERT ON `proposed_renewable_sites` FOR EACH ROW BEGIN
	INSERT IGNORE INTO _project_ids (project_type,label) VALUES ('proposed_renewable_sites', NEW.site);
	SET NEW.project_id = (SELECT project_id from _project_ids where project_type = 'proposed_renewable_sites' and label = NEW.site);
END */$$

DELIMITER ;

insert into proposed_renewable_sites (technology_id, generator_type, load_area, site, renewable_id, capacity_mw, connect_cost_per_mw )
	select 	(select technology_id from generator_info.generator_costs where technology=generator_type),
	        generator_type,
			load_area,
			site,
			renewable_id,
			capacity_mw,
			connect_cost_per_mw
	from generator_info.proposed_renewable_sites
	order by 1,2,3;


-- CAP FACTOR-----------------
-- assembles the hourly power output for Distributed_PV, CSP_Trough, Wind and Offshore_Wind
drop table if exists _cap_factor_proposed_renewable_sites;
create table _cap_factor_proposed_renewable_sites(
	project_id int NOT NULL,
	configuration char(3),
	hour int,
	cap_factor float,
	INDEX hour (hour),
	INDEX configuration (configuration),
	PRIMARY KEY (project_id, configuration, hour),
	CONSTRAINT site_fk FOREIGN KEY project_id (project_id) REFERENCES proposed_renewable_sites (project_id)
);

select 'Compiling Distributed_PV' as progress;
insert into _cap_factor_proposed_renewable_sites
SELECT      proposed_renewable_sites.project_id,
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
insert into _cap_factor_proposed_renewable_sites
SELECT      proposed_renewable_sites.project_id,
            'na' as configuration,
            hours.hournum as hour,
            3tier.csp_power_output.e_net_mw/100 as cap_factor
    from    proposed_renewable_sites, 
            3tier.csp_power_output,
            hours
    where   generator_type = 'CSP_Trough_6h_TES'
    and     proposed_renewable_sites.renewable_id = 3tier.csp_power_output.siteid
    and     hours.datetime_utc = 3tier.csp_power_output.datetime_utc;

select 'Compiling Offshore_Wind' as progress;
insert into _cap_factor_proposed_renewable_sites
SELECT      proposed_renewable_sites.project_id,
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
insert into _cap_factor_proposed_renewable_sites
SELECT      proposed_renewable_sites.project_id,
            'na' as configuration,
            hours.hournum as hour,
            3tier.wind_farm_power_output.cap_factor
    from    proposed_renewable_sites, 
            3tier.wind_farm_power_output,
            hours
    where   generator_type = 'Wind'
    and     proposed_renewable_sites.renewable_id = 3tier.wind_farm_power_output.wind_farm_id
    and     hours.datetime_utc = 3tier.wind_farm_power_output.datetime_utc;

DROP VIEW IF EXISTS cap_factor_proposed_renewable_sites;
CREATE VIEW cap_factor_proposed_renewable_sites as
  SELECT cp.project_id, generator_type, load_area_info.area_id, load_area, site, configuration, hour, cap_factor
    FROM _cap_factor_proposed_renewable_sites cp join proposed_renewable_sites using (project_id) join load_area_info using (area_id);



-- EXISTING PLANTS---------
-- made in 'build proposed plants table.sql'
select 'Copying existing_plants' as progress;

drop table if exists existing_plants;
CREATE TABLE existing_plants (
	project_id int PRIMARY KEY DEFAULT 0,
	area_id int,
	load_area varchar(11),
	plant_code varchar(40),
	gentype varchar(10),
	aer_fuel varchar(20),
	peak_mw double,
	avg_mw double,
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
	technology varchar(30),
	INDEX area_id (area_id),
	FOREIGN KEY (area_id) REFERENCES load_area_info(area_id), 
	INDEX load_area_plant_code (load_area, plant_code)
) ROW_FORMAT=FIXED;

DELIMITER $$

/*!50003 DROP TRIGGER IF EXISTS `trg_ep_proj_id` */$$

/*!50003 CREATE TRIGGER `trg_ep_proj_id` BEFORE INSERT ON `existing_plants` FOR EACH ROW BEGIN
	INSERT IGNORE INTO _project_ids (project_type,label) VALUES ('existing_plants', NEW.plant_code);
	SET NEW.project_id = (SELECT project_id from _project_ids where project_type = 'existing_plants' and label = NEW.plant_code);
END */$$

DELIMITER ;


insert into existing_plants
	select load_area_info.area_id, ep_agg.* from generator_info.existing_plants_agg ep_agg join load_area_info using(load_area);

-- existing windfarms added here
-- should find overnight costs of historical wind turbines
-- $2/W is used here ($2,000,000/MW)
-- fixed O+M,forced_outage_rate are from new wind
insert into existing_plants
		(area_id,
		load_area,
		plant_code,
		gentype,
		aer_fuel,
		peak_mw,
		avg_mw,
		heat_rate,
		start_year,
		baseload,
		cogen,
		overnight_cost,
		fixed_o_m,
		variable_o_m,
		forced_outage_rate,
		scheduled_outage_rate,
		max_age,
		intermittent,
		technology)
select 	load_area_info.area_id, load_area,
		concat('Wind', '_', load_area, '_', 3tier.windfarms_existing_info_wecc.windfarm_existing_id) as plant_code,
		'Wind' as gentype,
		'Wind' as aer_fuel,
		capacity_mw as peak_mw,
		avg(cap_factor) * capacity_mw as avg_mw,
		0 as heat_rate,
		year_online as start_year,
		0 as baseload,
		0 as cogen,
		2000000 as overnight_cost,
		30300 as fixed_o_m,
		0 as variable_o_m,
		0.015 as forced_outage_rate,
		0.003 as scheduled_outage_rate,
		30 as max_age,
		1 as intermittent,
		'Wind' as technology
from 	3tier.windfarms_existing_info_wecc join 
        load_area_info using(load_area) join 
		3tier.windfarms_existing_cap_factor using(windfarm_existing_id)
group by 3tier.windfarms_existing_info_wecc.windfarm_existing_id
;


drop table if exists _existing_intermittent_plant_cap_factor;
create table _existing_intermittent_plant_cap_factor(
		project_id int,
		area_id int,
		hour int,
		cap_factor float,
		INDEX eip_index (area_id, project_id, hour),
		INDEX hour (hour),
		INDEX project_id (project_id),
		UNIQUE (project_id, hour),
		CONSTRAINT plant_code_fk FOREIGN KEY project_id (project_id) REFERENCES existing_plants (project_id),
		FOREIGN KEY (area_id) REFERENCES load_area_info(area_id)
);


insert into _existing_intermittent_plant_cap_factor
SELECT      existing_plants.project_id,
            existing_plants.area_id,
            hours.hournum as hour,
            3tier.windfarms_existing_cap_factor.cap_factor
    from    existing_plants, 
            3tier.windfarms_existing_cap_factor,
            hours
    where   technology = 'Wind'
    and		concat('Wind', '_', load_area, '_', 3tier.windfarms_existing_cap_factor.windfarm_existing_id) = existing_plants.plant_code
    and     hours.datetime_utc = 3tier.windfarms_existing_cap_factor.datetime_utc;

DROP VIEW IF EXISTS existing_intermittent_plant_cap_factor;
CREATE VIEW existing_intermittent_plant_cap_factor as
  SELECT cp.project_id, plant_code, load_area, cp.area_id, hour, cap_factor
    FROM _existing_intermittent_plant_cap_factor cp join load_area_info using (area_id) join existing_plants using (project_id);


-- HYDRO-------------------
-- made in 'build proposed plants table.sql'
drop table if exists hydro_monthly_limits;
CREATE TABLE hydro_monthly_limits (
  project_id int PRIMARY KEY DEFAULT 0,
  area_id int,
  load_area varchar(20),
  plntcode int,
  plntname varchar(50),
  primemover char(2),
  year year,
  month tinyint(4),
  min_flow double,
  max_flow double,
  avg_flow double,
  index ym (year,month),
  FOREIGN KEY (area_id) REFERENCES load_area_info(area_id)
) ROW_FORMAT=FIXED;
insert into hydro_monthly_limits
	select area_id, agg.* from generator_info.hydro_monthly_limits_agg agg join load_area_info using(load_area);

DELIMITER $$

/*!50003 DROP TRIGGER IF EXISTS `trg_hydro_proj_id` */$$

/*!50003 CREATE TRIGGER `trg_hydro_proj_id` BEFORE INSERT ON `hydro_monthly_limits` FOR EACH ROW BEGIN
	INSERT IGNORE INTO _project_ids (project_type,label) VALUES ('hydro', NEW.plant_code);
	SET NEW.project_id = (SELECT project_id from _project_ids where project_type = 'hydro' and label = NEW.plant_code);
END */$$

DELIMITER ;



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
	


-----------------------------------------------------------------------
--        NON-REGIONAL GENERATOR INFO
-----------------------------------------------------------------------

DROP TABLE IF EXISTS generator_info;
create table generator_info (
	technology_id INT NOT NULL PRIMARY KEY,
	technology varchar(30) UNIQUE,
	min_build_year year,
	fuel varchar(30),
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
	startup_fuel_mbtu float
);
insert into generator_info
 select 
 	technology_id,
 	technology,
	min_build_year,
	fuel,
	heat_rate,
	construction_time_years,
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
	startup_fuel_mbtu
 from generator_info.generator_costs;

-----------------------------------------------------------------------
--        REGION-SPECIFIC GENERATOR COSTS & AVAILIBILITY
-----------------------------------------------------------------------

DROP TABLE if exists _generator_costs_regional;
CREATE TABLE _generator_costs_regional(
  project_id int DEFAULT 0,
  scenario_id INT NOT NULL,
  area_id INT NOT NULL,
  technology_id INT NOT NULL,
  price_and_dollar_year year(4),
  overnight_cost float,
  fixed_o_m float,
  variable_o_m float,
  overnight_cost_change float,
  connect_cost_per_mw_generic float,
  nonfuel_startup_cost float,
  INDEX technology_id (technology_id),
  INDEX area_id (area_id),
  FOREIGN KEY (area_id) REFERENCES load_area_info(area_id), 
  FOREIGN KEY (technology_id) REFERENCES generator_info(technology_id),
  PRIMARY KEY (scenario_id, area_id, technology_id)
);


DELIMITER $$

/*!50003 DROP TRIGGER IF EXISTS `trg_proposed_gen_proj_id` */$$

/*!50003 CREATE TRIGGER `trg_proposed_gen_proj_id` BEFORE INSERT ON `_generator_costs_regional` FOR EACH ROW BEGIN
	INSERT IGNORE INTO _project_ids (project_type,label) VALUES ('proposed_generation', concat(NEW.area_id, '_', NEW.technology_id));
	SET NEW.project_id = (SELECT project_id from _project_ids where project_type = 'proposed_generation' and label = concat(NEW.area_id, '_', NEW.technology_id));
END */$$

DELIMITER ;


-- This would find the next scenario id. 
-- select if( max(scenario_id) + 1 is null, 1, max(scenario_id) + 1 ) into @reg_generator_scenario_id from _generator_costs_regional;
set @reg_generator_scenario_id = 1;

-- The middle four lines in the select statment are prices that are affected by regional price differences
-- The rest of these variables aren't affected by region, but they're brought along here to make it easier in AMPL
-- technologies that Switch can't build yet but might in the future are eliminated in the last line
insert into _generator_costs_regional
    (scenario_id, area_id, technology_id, price_and_dollar_year, overnight_cost, 
     fixed_o_m, variable_o_m, overnight_cost_change, connect_cost_per_mw_generic,  nonfuel_startup_cost)

    select 	@reg_generator_scenario_id as scenario_id, 
    		area_id,
    		technology_id,
    		price_and_dollar_year,  
   			overnight_cost * economic_multiplier as overnight_cost,
    		fixed_o_m * economic_multiplier as fixed_o_m,
    		variable_o_m * economic_multiplier as variable_o_m,
   			overnight_cost_change,
    		connect_cost_per_mw_generic * economic_multiplier as connect_cost_per_mw_generic,
   			nonfuel_startup_cost * economic_multiplier as nonfuel_startup_cost
    from 	generator_info.generator_costs gen_costs,
			load_area_info
			where gen_costs.min_build_year > 0
	where 	load_area_info.scenario_id  = @load_area_scenario_id
 on duplicate key update
	price_and_dollar_year       = gen_costs.price_and_dollar_year,
	overnight_cost              = gen_costs.overnight_cost * economic_multiplier,
	fixed_o_m                   = gen_costs.fixed_o_m * economic_multiplier,
	variable_o_m                = gen_costs.variable_o_m * economic_multiplier,
	overnight_cost_change       = gen_costs.overnight_cost_change,
	connect_cost_per_mw_generic = gen_costs.connect_cost_per_mw_generic * economic_multiplier,
	nonfuel_startup_cost        = gen_costs.nonfuel_startup_cost * economic_multiplier
;


-- regional generator restrictions
-- currently, the only restrictions are that Coal_ST and Nuclear can't be built in CA
delete from _generator_costs_regional
 	where 	(technology_id in (select technology_id from generator_info where fuel in ('Uranium', 'Coal')) and
			area_id in (select area_id from load_area_info where primary_nerc_subregion like 'CA'));


-- Make a view that is more user-friendly
DROP VIEW IF EXISTS generator_costs_regional;
CREATE VIEW generator_costs_regional as
  SELECT _generator_costs_regional.scenario_id, project_id, load_area, technology, price_and_dollar_year, overnight_cost, fixed_o_m, variable_o_m, overnight_cost_change, connect_cost_per_mw_generic,  nonfuel_startup_cost
    FROM _generator_costs_regional join load_area_info using (area_id) join generator_info using (technology_id);


-- FUEL PRICES-------------
-- run 'v2 wecc fuel price import no elasticity.sql' first

drop table if exists _fuel_prices_regional;
CREATE TABLE _fuel_prices_regional (
  scenario_id INT NOT NULL,
  area_id INT NOT NULL,
  fuel VARCHAR(30),
  year year,
  fuel_price FLOAT NOT NULL COMMENT 'Regional fuel prices for various types of fuel in $2007 per MMBtu',
  INDEX scenario_id(scenario_id),
  INDEX area_id(area_id),
  CONSTRAINT area_id FOREIGN KEY area_id (area_id) REFERENCES load_area_info (area_id)
);

select if( max(scenario_id) + 1 is null, 1, max(scenario_id) + 1 ) into @this_scenario_id
    from _fuel_prices_regional;
  
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

  
DROP VIEW IF EXISTS fuel_prices_regional;
CREATE VIEW fuel_prices_regional as
SELECT _fuel_prices_regional.scenario_id, load_area_info.area_id, load_area, fuel, year, fuel_price 
    FROM _fuel_prices_regional, load_area_info
    WHERE _fuel_prices_regional.area_id = load_area_info.area_id;

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
	('Bio_Solid', 'renewable', 0),
	('Bio_Gas', 'renewable', 0),
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
  	CONSTRAINT area_id FOREIGN KEY area_id (area_id) REFERENCES load_area_info (area_id)
);

insert into fuel_qualifies_for_rps
	select distinct 
	        area_id,
			load_area,
			rps_fuel_category,
			if(rps_fuel_category like 'renewable', 1, 0)
		from fuel_info, load_area_info;

