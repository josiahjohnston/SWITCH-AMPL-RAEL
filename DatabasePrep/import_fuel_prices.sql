-- the fuel prices here are primarly from the 2011 reference NEMS AEO case
-- more specifically the regional fuel price projections in the Electric Power Projections for Electricity Market Module regions

-- the source tables can be found in the same directory
-- biomass comes in as a supply curve so isn't imported here


-- minemouth coal prices for the powder river basin are added as well, as the NEMS region doesn't have
-- enough resolution in this area to accurately capture the regional price differences of this commodity
-- this data comes from the EIA Annual Energy Outlook 2011

-- uranium prices come from the pdf CEC Cost of Generation - has Uranium Projections.pdf in the same directory.
-- it's a summary of the CEC's cost of generation study, and as Uranium is an international commodity,
-- we'll use these prices as the prices everywhere (for now at least).  TEPPC doesn't have regional prices for uranium.

-- For Canada and Mexico, the nearest US load area is used for their costs

-- all prices are in real 2009 dollars per mmbtu, except for uranium, which is in $2007
-- and for powder river basin coal, which is in $2009 per short ton (we'll convert them to mmbtu right after import)
-- here puts powder river basin (prb) coal at 8800Btu/lb = 17.6 MMBtu/short ton
-- http://www.eia.doe.gov/cneaf/coal/page/coalnews/coalmar.html
-- we'll convert all $2009 to $2007 using the CPI factor of 0.97

create database if not exists fuel_prices;
use fuel_prices;

drop table if exists fuel_price_import;
create table fuel_price_import(
	nems_region varchar(30),
	fuel varchar(30),
	price_2008 float,
	price_2009 float,
	price_2010 float,
	price_2011 float,
	price_2012 float,
	price_2013 float,
	price_2014 float,
	price_2015 float,
	price_2016 float,
	price_2017 float,
	price_2018 float,
	price_2019 float,
	price_2020 float,
	price_2021 float,
	price_2022 float,
	price_2023 float,
	price_2024 float,
	price_2025 float,
	price_2026 float,
	price_2027 float,
	price_2028 float,
	price_2029 float,
	price_2030 float,
	price_2031 float,
	price_2032 float,
	price_2033 float,
	price_2034 float,
	price_2035 float,
	primary key (nems_region, fuel)
);

load data local infile
	'/Volumes/1TB_RAID/Models/Switch_Input_Data/Fuel_Prices/AEO_2011_Ref/NEMS_Fuel_Prices.csv'
	into table fuel_price_import
	fields terminated by	','
	optionally enclosed by '"'
	lines terminated by '\r'
	ignore 1 lines;
	

-- PIVOT AND POPULATE THE FUEL PRICE DATA--------------------------
-- now we have all the data imported... all we have to do is match load area to nems subregion,
-- then do a bit of extra updating... look at the bottom - a few values get overwritten.

drop table if exists regional_fuel_prices;
CREATE TABLE regional_fuel_prices (
	load_area varchar(11),
	fuel VARCHAR(25),
	year year,
	fuel_price FLOAT,
	primary key (load_area, fuel, year) );


-- do some pivoting of the data
DROP PROCEDURE IF EXISTS pivot_fuel_price_data;

delimiter $$
create procedure pivot_fuel_price_data()
BEGIN

set @year_tmp = 2008;

years_loop: LOOP

-- first match all of the nems region specific prices, converting from $2009 -->$2007
set @each_hour_insert_statment =
	concat( 'INSERT into regional_fuel_prices (load_area, fuel, year, fuel_price) ',
			'SELECT load_area, fuel, ',
			@year_tmp,
			' as year, 0.97 * price_',
			@year_tmp,
			' as fuel_price from fuel_price_import join switch_inputs_wecc_v2_2.load_area_info on (primary_nerc_subregion = nems_region)'
			);

select @each_hour_insert_statment;

PREPARE stmt_name FROM @each_hour_insert_statment;
EXECUTE stmt_name;
DEALLOCATE PREPARE stmt_name;

-- now give every load area the same uranium price... it's already in $2007
set @each_hour_insert_statment =
	concat( 'INSERT into regional_fuel_prices (load_area, fuel, year, fuel_price) ',
			'SELECT load_area, fuel, ',
			@year_tmp,
			' as year, price_',
			@year_tmp,
			' as fuel_price from fuel_price_import, switch_inputs_wecc_v2_2.load_area_info where fuel = \'Uranium\''
			);

PREPARE stmt_name FROM @each_hour_insert_statment;
EXECUTE stmt_name;
DEALLOCATE PREPARE stmt_name;

-- now update coal prices for the powder river basin, converting to mmbtu and from $2009 -->$2007
set @each_hour_insert_statment =
	concat( 'replace into regional_fuel_prices (load_area, fuel, year, fuel_price) ',
			'SELECT load_area, fuel, ',
			@year_tmp,
			' as year, ( 0.97 / 17.6) * price_',
			@year_tmp,
			' as fuel_price from fuel_price_import, switch_inputs_wecc_v2_2.load_area_info '
			' where load_area in (\'WY_SE\', \'WY_NE\', \'MT_SE\') and nems_region = \'PRB\''
			);

PREPARE stmt_name FROM @each_hour_insert_statment;
EXECUTE stmt_name;
DEALLOCATE PREPARE stmt_name;
set @year_tmp = @year_tmp + 1;

IF (@year_tmp > 2035)
    THEN LEAVE years_loop;
        END IF;
END LOOP years_loop;

END;
$$
delimiter ;

-- call and clean up
call pivot_fuel_price_data();
drop procedure pivot_fuel_price_data;

-- delete historical years for now
delete from regional_fuel_prices where year < 2011;
-- also delete values that don't exist... uranium price projections only go out to 2030
delete from regional_fuel_prices where fuel = 'Uranium' and year > 2030;

-- add Mexico Fuel prices
insert ignore into regional_fuel_prices ( load_area, fuel, year, fuel_price )
select 	'MEX_BAJA',
		fuel,
		year,
		fuel_price
	from
	(select fuel, year, fuel_price from regional_fuel_prices where load_area like 'CA_IID') as ca_fuel_prices;

-- add Canada prices
insert ignore into regional_fuel_prices ( load_area, fuel, year, fuel_price )
select 	'CAN_BC',
		fuel,
		year,
		fuel_price
	from
	(select fuel, year, fuel_price from regional_fuel_prices where load_area like 'WA_W') as wa_fuel_prices;

insert ignore into regional_fuel_prices ( load_area, fuel, year, fuel_price )
select 	'CAN_ALB',
		fuel,
		year,
		fuel_price
	from
	(select fuel, year, fuel_price from regional_fuel_prices where load_area like 'MT_NW') as mt_fuel_prices;
