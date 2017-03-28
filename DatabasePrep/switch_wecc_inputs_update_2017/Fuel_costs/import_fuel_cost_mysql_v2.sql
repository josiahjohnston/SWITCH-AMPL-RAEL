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


-- delete rows from fuel_prices_v3
DELETE FROM fuel_prices_v3;
-- copy values from old fuel_prices table. Adjust to dollars in 2016. -- ONLY UNTIL 2065 (in the new EIA's projection (we have until 2065)).
insert into fuel_prices_v3 (fuel_scenario_id, area_id, load_area, fuel, year, fuel_price)
	select scenario_id, area_id, t1.load_area, t1.fuel, t1.year, 1.15*fuel_price from fuel_prices as t1 WHERE year < 2066; 
    -- 1.15 is the inflation between 2007 and 2016 for the US dollar ($1 in 2007 = $1.15 in 2016)
    
     
SELECT * FROM fuel_prices_v3;   

-- the query below was used to check that _CCS fuel costs where the same as the fuel without CCS. 
-- Result: both fuel values were the same
select max(t1.area_id), avg(t1.area_id), min(t2.area_id), count(t1.year), count(t2.year),t1.fuel, t2.fuel, 
max(t2.fuel_price - t1.fuel_price), min(t2.fuel_price - t1.fuel_price)
from _fuel_prices as t1 join _fuel_prices as t2 using (fuel_price) -- area_id, year
where t1.fuel != t2.fuel and t1.fuel = 'ResidualFuelOil' and t2.fuel = 'ResidualFuelOil_CCS' 
-- where t1.fuel != t2.fuel and t1.fuel = 'DistillateFuelOil' and t2.fuel = 'DistillateFuelOil_CCS' 
-- where t1.fuel != t2.fuel and t1.fuel = 'Coal' and t2.fuel = 'Coal_CCS'
limit 100;



-- Fuel matching (EIA = switch)
-- DistillateFuelOil = DistillateFuelOil and DistillateFuelOil_CCS
-- ResidualFuelOil = ResidualFuelOil and ResidualFuelOil_CCS
-- SteamCoal = Coal and Coal_CCS
-- Uranium = Uranium


select fuel, year, fuel_price, eia_region, notes from fuel_prices_regional_v3;

select fuel_scenario_id, area_id, load_area, fuel, year, fuel_price, notes, eia_region 
from fuel_prices_v3 where load_area = 'CAN_ALB';

select load_area, eia_region from load_area_eia_regions_match; 
select * from load_area_info;


alter table fuel_prices_v3 add column eia_region VARCHAR(50);

update fuel_prices_v3 as t1
set eia_region = (select eia_region from load_area_eia_regions_match as t2 where t1.load_area = t2.load_area);


SELECT * FROM fuel_prices_v3;

-- edit prices for coal with eia's prices
update fuel_prices_v3 as w
set fuel_price = (select fuel_price 
                    from fuel_prices_regional_v3 as t 
                    where w.eia_region = t.eia_region
                    and w.year = t.year
                    and t.fuel = 'SteamCoal')
                    where fuel = 'Coal' or fuel = 'Coal_CCS';
                    
select * from fuel_prices_v3 where fuel = 'Coal' or fuel = 'Coal_CCS' limit 100;

-- edit prices for DistillateFuelOil with eia's prices
update fuel_prices_v3 as w
set fuel_price = (select fuel_price 
                    from fuel_prices_regional_v3 as t 
                    where w.eia_region = t.eia_region
                    and w.year = t.year
                    and t.fuel = 'DistillateFuelOil')
                    where fuel = 'DistillateFuelOil' or fuel = 'DistillateFuelOil_CCS';

select * from fuel_prices_v3 where fuel = 'DistillateFuelOil' or fuel = 'DistillateFuelOil_CCS' limit 100;
    
    
    -- edit prices for DistillateFuelOil with eia's prices
update fuel_prices_v3 as w
set fuel_price = (select fuel_price 
                    from fuel_prices_regional_v3 as t 
                    where w.eia_region = t.eia_region
                    and w.year = t.year
                    and t.fuel = 'ResidualFuelOil')
                    where fuel = 'ResidualFuelOil' or fuel = 'ResidualFuelOil_CCS';

select * from fuel_prices_v3 where fuel = 'ResidualFuelOil' or fuel = 'ResidualFuelOil_CCS' limit 100;

-- updating notes
update fuel_prices_v3 as t1
set notes = (select notes from fuel_prices_regional_v3 as t2 where t1.eia_region = t2.eia_region and t1.year = t2.year and t2.fuel = 'SteamCoal') 
where t1.fuel = 'Coal' or fuel = 'Coal_CCS';

select * from fuel_prices_v3 where fuel = 'Coal' or fuel = 'Coal_CCS' limit 100;

-- updating notes
update fuel_prices_v3 as t1
set notes = (select notes from fuel_prices_regional_v3 as t2 where t1.eia_region = t2.eia_region and t1.year = t2.year and t2.fuel = 'DistillateFuelOil') 
where t1.fuel = 'DistillateFuelOil' or fuel = 'DistillateFuelOil_CCS';

select * from fuel_prices_v3 where fuel = 'DistillateFuelOil' or fuel = 'DistillateFuelOil_CCS' limit 100;

-- updating notes ResidualFuelOil
update fuel_prices_v3 as t1
set notes = (select notes from fuel_prices_regional_v3 as t2 where t1.eia_region = t2.eia_region and t1.year = t2.year and t2.fuel = 'ResidualFuelOil') 
where t1.fuel = 'ResidualFuelOil' or fuel = 'ResidualFuelOil_CCS';

select * from fuel_prices_v3 where fuel = 'ResidualFuelOil' or fuel = 'ResidualFuelOil_CCS' limit 100;    


-- updating notes for fuels not in EIAs new data
update fuel_prices_v3 as t1
set notes = '2016 $/MMBtu. Source: Old data from _fuel_prices table (switch_inputs_wecc_v2_2)'
where fuel != 'ResidualFuelOil' 
and fuel != 'ResidualFuelOil_CCS' 
and fuel != 'DistillateFuelOil' 
and fuel != 'DistillateFuelOil_CCS'
and fuel != 'Coal' 
and fuel != 'Coal_CCS';


select * from fuel_prices_v3;

    -- edit prices for Uranium with eia's prices (I forgot to do it earlier!)
update fuel_prices_v3 as w
set fuel_price = (select fuel_price 
                    from fuel_prices_regional_v3 as t 
                    where w.eia_region = t.eia_region
                    and w.year = t.year
                    and t.fuel = 'Uranium')
                    where fuel = 'Uranium';

update fuel_prices_v3 as t1
set notes = (select notes from fuel_prices_regional_v3 as t2 where t1.eia_region = t2.eia_region and t1.year = t2.year and t2.fuel = 'Uranium') 
where t1.fuel = 'Uranium';

select * from fuel_prices_v3 where fuel = 'Uranium' limit 100;    



-- Notes on how to use:
-- Use the column fuel_scenario_id as regional_fuel_cost_scenario_id in the table scenarios_v3
--  edit get_swith_input_tables.sh to reflect this. DONE!

    
    
    
    
    
    
    
    
    
    
    
    
    