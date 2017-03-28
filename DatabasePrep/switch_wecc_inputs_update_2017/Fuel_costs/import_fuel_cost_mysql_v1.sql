use switch_inputs_wecc_v2_2;

select * from load_area_info;

ALTER TABLE load_area_info ADD COLUMN eia_fuel_region VARCHAR(50);


DROP TABLE fuel_prices_regional_v3;

CREATE TABLE IF NOT EXISTS fuel_prices_regional_v3 (
	fuel VARCHAR(50),
	year INT,
    fuel_price DOUBLE,
    eia_region VARCHAR(50),
    notes VARCHAR(300),
    PRIMARY KEY (fuel, year, eia_region)
    );
    
    
SELECT * FROM fuel_prices_regional_v3;


-- '/Users/pehidalg/Documents/switch_wecc_inputs_update/Fuel_costs/step4_all_regions_import_mysql_table.csv'
-- '/var/tmp/home_pehidalg/switch_wecc_inputs_update/Fuel_costs/step4_all_regions_import_mysql_table.csv'
-- Lesson learnt: the cvs file doesn’t need to be in the same server as the db.
load data local infile
	'/Users/pehidalg/Documents/switch_wecc_inputs_update/Fuel_costs/step4_all_regions_import_mysql_table.csv'
	into table fuel_prices_regional_v3
	fields terminated by	','
	optionally enclosed by '"'
	lines terminated by "\r"
	ignore 1 lines;


CREATE TABLE IF NOT EXISTS load_area_eia_regions_match (
	load_area VARCHAR(50),
	eia_region VARCHAR(50),
    PRIMARY KEY (load_area, eia_region)
    );
    
load data local infile
	'/Users/pehidalg/Documents/switch_wecc_inputs_update/Fuel_costs/load_areas_EIA_regions_match.csv'
	into table load_area_eia_regions_match
	fields terminated by	','
	optionally enclosed by '"'
	lines terminated by "\r"
	ignore 1 lines;    
    
    select * from load_area_eia_regions_match;
    select * from load_area_info;

-- select area_id, load_area, primary_nerc_subregion, primary_state, economic_multiplier_archive, total_yearly_load_mwh,
-- local_td_sunk_annual_payment, transmission_sunk_annual_payment, max_coincident_load_for_local_td, ccs_distance_km,
-- rps_compliance_entity, bio_gas_capacity_limit_mmbtu_per_hour, nems_fuel_region, economic_multiplier, t.eia_region 
-- from load_area_info join load_area_eia_regions_match as t using(load_area);

update load_area_info
set eia_fuel_region = (select eia_region from load_area_eia_regions_match where load_area_info.load_area = load_area_eia_regions_match.load_area);   
    
select * from fuel_prices_regional_v3;

DROP TABLE fuel_prices_v3;

CREATE TABLE IF NOT EXISTS fuel_prices_v3 (
	fuel_scenario_id INT,
    area_id int,
	load_area VARCHAR(50),
	fuel VARCHAR(50),
	year INT,
    fuel_price DOUBLE,
    notes VARCHAR(300),
    PRIMARY KEY (fuel_scenario_id, load_area, fuel, year)
    ) COMMENT 'Fuel_prices table. Built in 2017 using EIA energy outlook 2017. 2016 $/MMBtu' ;
    
    
SELECT * FROM fuel_prices;
-- select fuel from fuel_prices group by fuel limit 99999;
-- select (2100-2011)*50*20;

-- copy values from old fuel_prices table. Adjust to dollars in 2016.
insert into fuel_prices_v3 (fuel_scenario_id, area_id, load_area, fuel, year, fuel_price)
	select scenario_id, area_id, t1.load_area, t1.fuel, t1.year, 1.15*fuel_price from fuel_prices as t1; 
    -- 1.15 is the inflation between 2007 and 2016 for the US dollar ($1 in 2007 = $1.15 in 2016)
    
     
SELECT * FROM fuel_prices_v3;   

-- to do next: update fuel_prices for DistillateFuelOil, ResidualFuelOil, SteamCoal, Uranium
--  match fuels to switch fuels

-- update fuel_prices_v3 
-- set fuel_price = 
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    