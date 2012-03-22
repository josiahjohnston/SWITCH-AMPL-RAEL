-- This creates a supply curve for natural gas for the WECC electric sector
-- However, this script is written so that it can also create supply curves for multiple types of fuels at a time (with some modifications)
-- Data for every scenario and region are from NEMS forecasts
-- NEMS forcasts natural gas, coal, and oil consumption and price for 2010-2035 for the whole US as well as regionally
-- The WECC is subdivided into four regions: California, Northwest, Rockies, and Southwest
-- Data for Baja, BC, and Alberta are added manually
-- Country-level data (US, Mexico/Chile, Mexico, and Canada) includes consumption in ALL SECTORS
-- Regional data (California, Northwest, Rockies, Southwest, Baja, BC, and Alberta) includes consumption in the ELECTRIC SECTOR ONLY
-- The US_Electric region gives consumption data for electricity sector in all of the US
-- Natural gas and coal consumption data for all of Canada are imported initially based on IEO2011 projections and then subdivided into regional consumption by province based on historic consumption data by province
-- Natural gas price data for Canada are based on the average border price forecast for natural gas from AEO2011
-- Natural gas consumption data for all of Mexico/Chile are imported initially based on IEO2011 projections and then subdivided in consumption for Baja based on population
-- Natural gas price for Baja Mexico are assumed equal to the prices in the Southwest
-- Consumption forecasts do not exist for all AEO2011 scenarios for Canada and Mexico, so consumption for scenarios other the Reference case is scaled based on the percentage change in US consumption in each scenario relative to the Reference scenario

-- Units from NEMS are: natural gas consumption: quadrillion Btu
-- natural gas price: 2009 Dollars per million Btu


SET search_path TO fuels;

-----------------------------------------------
-------------- Import the data ----------------

drop table if exists nems_supply_curve_data_import;
create table nems_supply_curve_data_import(
	fuel varchar(40),
	nems_region char(40),
	a2010 char(40),
	b2010 char(40),
	c2010 char(40),
	d2010 char(40),
	e2010 char(40),
	a2011 char(40),
	b2011 char(40),
	c2011 char(40),
	d2011 char(40),
	e2011 char(40),
	a2012 char(40),
	b2012 char(40),
	c2012 char(40),
	d2012 char(40),
	e2012 char(40),
	a2013 char(40),
	b2013 char(40),
	c2013 char(40),
	d2013 char(40),
	e2013 char(40),
	a2014 char(40),
	b2014 char(40),
	c2014 char(40),
	d2014 char(40),
	e2014 char(40),
	a2015 char(40),
	b2015 char(40),
	c2015 char(40),
	d2015 char(40),
	e2015 char(40),
	a2016 char(40),
	b2016 char(40),
	c2016 char(40),
	d2016 char(40),
	e2016 char(40),
	a2017 char(40),
	b2017 char(40),
	c2017 char(40),
	d2017 char(40),
	e2017 char(40),
	a2018 char(40),
	b2018 char(40),
	c2018 char(40),
	d2018 char(40),
	e2018 char(40),
	a2019 char(40),
	b2019 char(40),
	c2019 char(40),
	d2019 char(40),
	e2019 char(40),
	a2020 char(40),
	b2020 char(40),
	c2020 char(40),
	d2020 char(40),
	e2020 char(40),
	a2021 char(40),
	b2021 char(40),
	c2021 char(40),
	d2021 char(40),
	e2021 char(40),
	a2022 char(40),
	b2022 char(40),
	c2022 char(40),
	d2022 char(40),
	e2022 char(40),
	a2023 char(40),
	b2023 char(40),
	c2023 char(40),
	d2023 char(40),
	e2023 char(40),
	a2024 char(40),
	b2024 char(40),
	c2024 char(40),
	d2024 char(40),
	e2024 char(40),
	a2025 char(40),
	b2025 char(40),
	c2025 char(40),
	d2025 char(40),
	e2025 char(40),
	a2026 char(40),
	b2026 char(40),
	c2026 char(40),
	d2026 char(40),
	e2026 char(40),
	a2027 char(40),
	b2027 char(40),
	c2027 char(40),
	d2027 char(40),
	e2027 char(40),
	a2028 char(40),
	b2028 char(40),
	c2028 char(40),
	d2028 char(40),
	e2028 char(40),
	a2029 char(40),
	b2029 char(40),
	c2029 char(40),
	d2029 char(40),
	e2029 char(40),
	a2030 char(40),
	b2030 char(40),
	c2030 char(40),
	d2030 char(40),
	e2030 char(40),
	a2031 char(40),
	b2031 char(40),
	c2031 char(40),
	d2031 char(40),
	e2031 char(40),
	a2032 char(40),
	b2032 char(40),
	c2032 char(40),
	d2032 char(40),
	e2032 char(40),
	a2033 char(40),
	b2033 char(40),
	c2033 char(40),
	d2033 char(40),
	e2033 char(40),
	a2034 char(40),
	b2034 char(40),
	c2034 char(40),
	d2034 char(40),
	e2034 char(40),
	a2035 char(40),
	b2035 char(40),
	c2035 char(40),
	d2035 char(40),
	e2035 char(40)
);


drop table if exists nems_fuel_region_scenario_consumption_price_raw_data_import;
create table nems_fuel_region_scenario_consumption_price_raw_data_import(
	fuel varchar(40),
	nems_scenario varchar(40),
	nems_region varchar(40),
	simulation_year int,
	price double precision,
	consumption double precision,
	primary key (fuel, nems_scenario, nems_region, simulation_year)
	);
 
CREATE OR REPLACE RULE "replace_nems_fuel_region_scenario_consumption_price_raw_data_import" AS ON INSERT TO "nems_fuel_region_scenario_consumption_price_raw_data_import"
  WHERE
  EXISTS(SELECT 1 FROM nems_fuel_region_scenario_consumption_price_raw_data_import WHERE fuel=NEW.fuel and nems_region=NEW.nems_region and nems_scenario=NEW.nems_scenario and simulation_year=NEW.simulation_year)
    DO INSTEAD
       (UPDATE nems_fuel_region_scenario_consumption_price_raw_data_import SET consumption=NEW.consumption WHERE fuel=NEW.fuel and nems_region=NEW.nems_region and nems_scenario=NEW.nems_scenario and simulation_year=NEW.simulation_year);
      
-- now do some fancyish pivoting of the import table to insert all of the supply curve data
-- make sure that fuel-region combination exists in consumption spreadsheet or price data for that fuel-region combination will not get imported

-- this is a dummy function that will excecute an sql statement inserted into it in the form of text
-- we'll create this text string below by concating parts of an insert statement together
-- with a variable that runs through all of the years we're interested in
CREATE OR REPLACE FUNCTION exec(text) RETURNS text AS $$ BEGIN EXECUTE $1; RETURN $1; END $$ LANGUAGE plpgsql;

-- create the year-looping function
CREATE OR REPLACE FUNCTION pivot_natural_gas() RETURNS void AS $$

	declare current_column_name char(40);
 
    BEGIN

	drop table if exists all_columns_to_import;
	create table all_columns_to_import(
		column_name char(5) primary key,
		simulation_year int,
		nems_scenario varchar(40)
		);
		
	insert into all_columns_to_import (column_name, simulation_year)
		SELECT 	column_name,
				cast(substring(column_name from 2) as numeric) as simulation_year
		FROM information_schema.columns
		where table_name = 'nems_supply_curve_data_import'
		and column_name <> 'fuel'
		and column_name <> 'nems_region';

	update 	all_columns_to_import
	set		nems_scenario = letter_to_scenario_table.nems_scenario
	from 	(
		select 'a' as scenario_identifier, a2010 as nems_scenario from nems_supply_curve_data_import where length(nems_region) is null
			UNION
		select 'b' as scenario_identifier, b2010 as nems_scenario from nems_supply_curve_data_import where length(nems_region) is null
			UNION
		select 'c' as scenario_identifier, c2010 as nems_scenario from nems_supply_curve_data_import where length(nems_region) is null
			UNION
		select 'd' as scenario_identifier, d2010 as nems_scenario from nems_supply_curve_data_import where length(nems_region) is null
			UNION
		select 'e' as scenario_identifier, e2010 as nems_scenario from nems_supply_curve_data_import where length(nems_region) is null
		) as letter_to_scenario_table
	where	substring(column_name from 1 for 1) = scenario_identifier
	;

	LOOP

	-- the loop through all columns we want to import
	select (select column_name from all_columns_to_import limit 1) into current_column_name;

		-- we must use PERFORM instead of select here because select will return the text string of the insert statement, which throws an error
		-- and we don't need it printed out (all we need is for the string to be fed through exec() to be executed


		PERFORM exec(
	    		'INSERT INTO nems_fuel_region_scenario_consumption_price_raw_data_import (fuel, nems_scenario, nems_region, simulation_year, consumption) '
	    		|| 'select fuel, nems_scenario, nems_region, simulation_year, cast('
	  			|| current_column_name
	  			|| ' as numeric) as consumption from all_columns_to_import, nems_supply_curve_data_import '
	  			|| 'where length(nems_region) is not null and column_name = '''
				|| current_column_name
				|| ''';'
			);


	delete from all_columns_to_import where column_name = current_column_name;

	EXIT WHEN ((select count(*) from all_columns_to_import) = 0);
	END LOOP;

delete from nems_supply_curve_data_import;

    END;
$$ LANGUAGE plpgsql;

-- actually copy all of the data by reading in one CSV and importing via the function pivot_natural_gas()
copy nems_supply_curve_data_import
from '/DatabasePrep/NG_supply_curve/nems_ng_consumption_raw_data_quadrillion_btu.csv'
with CSV HEADER;

-- excute the insert statements
-- this function also clears out the import table, making it ready for the next CSV
select pivot_natural_gas();
		
-- if we decide to import data for more scenarios, simply repeat the copy process and re-run the pivot_natural_gas function for each set of scenarios
--copy nems_supply_curve_data_import
--from '/DatabasePrep/NG_supply_curve/consumption_2.csv'
--with CSV HEADER;
--select pivot_natural_gas();


-- clean up
drop function pivot_natural_gas();
drop table if exists all_columns_to_import;


-- Update table nems_fuel_region_scenario_consumption_price_raw_data_import by inserting the values for price
 
 CREATE OR REPLACE RULE "replace_nems_fuel_region_scenario_consumption_price_raw_data_import" AS ON INSERT TO "nems_fuel_region_scenario_consumption_price_raw_data_import"
    WHERE
      EXISTS(SELECT 1 FROM nems_fuel_region_scenario_consumption_price_raw_data_import WHERE fuel= NEW.fuel and nems_region=NEW.nems_region and nems_scenario=NEW.nems_scenario and simulation_year=NEW.simulation_year)
    DO INSTEAD
       (UPDATE nems_fuel_region_scenario_consumption_price_raw_data_import SET price=NEW.price WHERE fuel= NEW.fuel and nems_region=NEW.nems_region and nems_scenario=NEW.nems_scenario and simulation_year=NEW.simulation_year);

-- now do some fancyish pivoting of the import table to update all of the price supply data

CREATE OR REPLACE FUNCTION exec(text) RETURNS text AS $$ BEGIN EXECUTE $1; RETURN $1; END $$ LANGUAGE plpgsql;

-- create the year-looping function
CREATE OR REPLACE FUNCTION pivot_natural_gas() RETURNS void AS $$

	declare current_column_name char(40);
 
    BEGIN

	drop table if exists all_columns_to_import;
	create table all_columns_to_import(
		column_name char(5) primary key,
		simulation_year int,
		nems_scenario varchar(40)
		);
		
	insert into all_columns_to_import (column_name, simulation_year)
		SELECT 	column_name,
				cast(substring(column_name from 2) as numeric) as simulation_year
		FROM information_schema.columns
		where table_name = 'nems_supply_curve_data_import'
		and column_name <> 'fuel'
		and column_name <> 'nems_region';

	update 	all_columns_to_import
	set		nems_scenario = letter_to_scenario_table.nems_scenario
	from 	(
		select 'a' as scenario_identifier, a2010 as nems_scenario from nems_supply_curve_data_import where length(nems_region) is null
			UNION
		select 'b' as scenario_identifier, b2010 as nems_scenario from nems_supply_curve_data_import where length(nems_region) is null
			UNION
		select 'c' as scenario_identifier, c2010 as nems_scenario from nems_supply_curve_data_import where length(nems_region) is null
			UNION
		select 'd' as scenario_identifier, d2010 as nems_scenario from nems_supply_curve_data_import where length(nems_region) is null
			UNION
		select 'e' as scenario_identifier, e2010 as nems_scenario from nems_supply_curve_data_import where length(nems_region) is null
		) as letter_to_scenario_table
	where	substring(column_name from 1 for 1) = scenario_identifier
	;

	LOOP

	-- the loop through all columns we want to import
	select (select column_name from all_columns_to_import limit 1) into current_column_name;

		-- we must use PERFORM instead of select here because select will return the text string of the insert statement, which throws an error
		-- and we don't need it printed out (all we need is for the string to be fed through exec() to be executed


		PERFORM exec(
		           'UPDATE nems_fuel_region_scenario_consumption_price_raw_data_import '
		            || 'SET price = cast( '
		            || current_column_name
		            || ' as numeric) from nems_supply_curve_data_import, all_columns_to_import ' 
		            || ' where nems_fuel_region_scenario_consumption_price_raw_data_import.nems_region = nems_supply_curve_data_import.nems_region and '
		            || ' nems_fuel_region_scenario_consumption_price_raw_data_import.fuel = nems_supply_curve_data_import.fuel and '
		            || ' nems_fuel_region_scenario_consumption_price_raw_data_import.nems_scenario = all_columns_to_import.nems_scenario and ' 
		            || ' nems_fuel_region_scenario_consumption_price_raw_data_import.simulation_year = all_columns_to_import.simulation_year and '
		            || ' length(nems_fuel_region_scenario_consumption_price_raw_data_import.nems_region) is not null and column_name = '''
		            ||current_column_name
		            || ''';'
		            );
	
			           		            
	delete from all_columns_to_import where column_name = current_column_name;

	EXIT WHEN ((select count(*) from all_columns_to_import) = 0);
	END LOOP;

delete from nems_supply_curve_data_import;

    END;
$$ LANGUAGE plpgsql;

-- actually copy all of the data by reading in one CSV and importing via the function pivot_natural_gas()

copy nems_supply_curve_data_import
from '/DatabasePrep/NG_supply_curve/nems_ng_price_raw_data_2009_dollars_per_mmbtu.csv'
with CSV HEADER;

-- excute the insert statements
-- this function also clears out the import table, making it ready for the next CSV
select pivot_natural_gas();
		
-- if we decide to import data for more scenarios, simply repeat the copy process and re-run the pivot_natural_gas function for each set of scenarios
--copy nems_supply_curve_data_import
--from '/DatabasePrep/NG_supply_curve/prices2.csv'
--with CSV HEADER;
--select pivot_natural_gas();

-- clean up
drop function pivot_natural_gas();
drop function exec(text);
drop table if exists all_columns_to_import;
drop table if exists nems_supply_curve_data_import;

-- create the table with correct units
-- NEMS consmption data imported is in quadrillion Btu (10^15) and the natural gas price is 2009 Dollars per million Btu
-- so we multiply the consumption by 10^9 to convert to MMBtu (10^6) and the price by 0.96 to convert to 2007 dollars

drop table if exists nems_supply_curve_data_import_final_unit_adjusted;
create table nems_supply_curve_data_import_final_unit_adjusted(
	fuel varchar(40),
	nems_scenario varchar(40),
	nems_region varchar(40),
	simulation_year int,
	price double precision,
	consumption double precision,
	primary key (fuel, nems_scenario, nems_region, simulation_year)
	);
	
insert into nems_supply_curve_data_import_final_unit_adjusted (fuel, nems_scenario, nems_region, simulation_year, price, consumption)
select 	fuel,
		nems_scenario,
      	nems_region,
       	simulation_year,
       	( price * 0.96 ) as price, 
      	consumption * 10^9 as consumption 
     	from nems_fuel_region_scenario_consumption_price_raw_data_import
      	order by fuel, nems_region, simulation_year;

-- MEXICO --
-- calculate total natural gas and coal consumption in Mexico (in all sectors) for the Reference case based on population
-- the population of Mexico in 2010 was 113,423,050 (Source: World Bank, World Development Indicators via Google)
-- the population of Chile in 2010 was 17,113,688 (Source: World Bank, World Development Indicators via Google)
-- the population of Baja in 2010 was 3,155,070 (Source: http://www.conapo.gob.mx/00cifras/proyecta50/02.xls)

-- insert fuel-scenario-year combinations for Mexico for fuels other than gas (if any) (gas is already imported) (not all combinations will be populated)
insert into nems_supply_curve_data_import_final_unit_adjusted
	select	distinct(fuel) as fuel,
			nems_scenario,
			'Mexico' as nems_region,
			simulation_year,
			cast(NULL as double precision) as price,
			cast(NULL as double precision) as consumption
	from	nems_supply_curve_data_import_final_unit_adjusted
	where	fuel not like 'Gas';

-- calculate fuel consumption for Mexico from Mexico/Chile data based on population
update nems_supply_curve_data_import_final_unit_adjusted
	set 	consumption = 113423050 * mexico_chile_consumption / (113423050 + 17113688)
	from	(	select fuel, simulation_year, consumption as mexico_chile_consumption
				from	nems_supply_curve_data_import_final_unit_adjusted
				where	nems_region = 'Mexico/Chile'
				and		nems_scenario = 'Reference' ) as mexico_chile_table
	where	nems_supply_curve_data_import_final_unit_adjusted.nems_region = 'Mexico'
	and		nems_supply_curve_data_import_final_unit_adjusted.nems_scenario = 'Reference'
	and 	nems_supply_curve_data_import_final_unit_adjusted.fuel = mexico_chile_table.fuel
	and		nems_supply_curve_data_import_final_unit_adjusted.simulation_year = mexico_chile_table.simulation_year;

-- insert fuel-scenario-year combinations for Mexico's electric sector (not all combinations will be populated)
insert into nems_supply_curve_data_import_final_unit_adjusted
	select	distinct(fuel) as fuel,
			nems_scenario,
			'Mexico_Electric' as nems_region,
			simulation_year,
			cast(NULL as double precision) as price,
			cast(NULL as double precision) as consumption
	from	nems_supply_curve_data_import_final_unit_adjusted;

-- calculate the amount of fuel consumed in the Mexico electric sector
-- we assume that the same fraction of total fuel is consumed in the electric sector as in the US
update	nems_supply_curve_data_import_final_unit_adjusted
set		consumption = electric_consumption_fraction * mexico_consumption
from	( 	select	us_total_consumption_table.fuel,
					us_total_consumption_table.nems_scenario,
					us_total_consumption_table.simulation_year,
					us_electric_sector_consumption / us_total_consumption as electric_consumption_fraction
				from	(	select	fuel, nems_scenario, simulation_year, consumption as us_electric_sector_consumption
							from	nems_supply_curve_data_import_final_unit_adjusted
							where	nems_region = 'US_Electric' ) as us_electric_sector_consumption_table,
						(	select	fuel, nems_scenario, simulation_year, consumption as us_total_consumption
							from	nems_supply_curve_data_import_final_unit_adjusted
							where	nems_region = 'US' ) as us_total_consumption_table
				where	us_electric_sector_consumption_table.fuel = us_total_consumption_table.fuel
				and		us_electric_sector_consumption_table.nems_scenario = us_total_consumption_table.nems_scenario
				and		us_electric_sector_consumption_table.simulation_year = us_total_consumption_table.simulation_year
							) as electric_consumption_fraction_table,
		(	select fuel, nems_scenario, simulation_year, consumption as mexico_consumption
				from 	nems_supply_curve_data_import_final_unit_adjusted
				where	nems_region = 'Mexico' ) as mexico_table
	where	nems_supply_curve_data_import_final_unit_adjusted.nems_region = 'Mexico_Electric'
	and		nems_supply_curve_data_import_final_unit_adjusted.fuel = electric_consumption_fraction_table.fuel
	and		nems_supply_curve_data_import_final_unit_adjusted.nems_scenario = electric_consumption_fraction_table.nems_scenario
	and		nems_supply_curve_data_import_final_unit_adjusted.simulation_year = electric_consumption_fraction_table.simulation_year
	and		nems_supply_curve_data_import_final_unit_adjusted.fuel = mexico_table.fuel
	and		nems_supply_curve_data_import_final_unit_adjusted.nems_scenario = mexico_table.nems_scenario
	and		nems_supply_curve_data_import_final_unit_adjusted.simulation_year = mexico_table.simulation_year;

-- now insert fuel-scenario-year combinations for Baja (not all combinations will be populated)
insert into nems_supply_curve_data_import_final_unit_adjusted
	select	distinct(fuel) as fuel,
			nems_scenario,
			'Baja_Mexico' as nems_region,
			simulation_year,
			cast(NULL as double precision) as price,
			cast(NULL as double precision) as consumption
	from	nems_supply_curve_data_import_final_unit_adjusted;

-- calculate electric sector fuel consumption in Baja based on Baja and Mexico's populations
update	nems_supply_curve_data_import_final_unit_adjusted
set		consumption = 3155070 * mexico_electric_consumption / 113423050
from	(	select	fuel,
					nems_scenario,
      				simulation_year,
       				consumption as mexico_electric_consumption
			from	nems_supply_curve_data_import_final_unit_adjusted
			where	nems_region = 'Mexico_Electric' ) as mexico_electric_table
where	nems_region = 'Baja_Mexico'
and		nems_supply_curve_data_import_final_unit_adjusted.fuel = mexico_electric_table.fuel
and		nems_supply_curve_data_import_final_unit_adjusted.nems_scenario = mexico_electric_table.nems_scenario
and		nems_supply_curve_data_import_final_unit_adjusted.simulation_year = mexico_electric_table.simulation_year;

-- update the Baja prices for natural gas with the Southwest prices
-- we don't use the Mexico import prices because they appear to be very low -- probably unrealistic to use those (there is only one bidirectional pipeline between Mexico and California/Arizona and very little imports from Mexico, meaning that there's likely no arbitrage)
update	nems_supply_curve_data_import_final_unit_adjusted
set		price = southwest_price
from	(select fuel, nems_scenario, simulation_year, price as southwest_price
		from	nems_supply_curve_data_import_final_unit_adjusted
		where	nems_region = 'Southwest' 
		and		fuel = 'Gas' ) as southwest_table
where	nems_supply_curve_data_import_final_unit_adjusted.nems_region = 'Baja_Mexico'
and		nems_supply_curve_data_import_final_unit_adjusted.fuel = 'Gas'
and		nems_supply_curve_data_import_final_unit_adjusted.simulation_year = southwest_table.simulation_year
and		nems_supply_curve_data_import_final_unit_adjusted.nems_scenario = southwest_table.nems_scenario;

-- finally, set consumption in non-reference scenarios for Baja and Mexico to have the same percent increase/decrease relative to the rest of the scenarios as the US electric sector and the US respectively
-- this will be used in determining the supply curve breakpoints and prices later
update	nems_supply_curve_data_import_final_unit_adjusted
set		consumption = change_in_us_consumption * reference_regional_consumption
from	(	select	fuel, nems_scenario, simulation_year, consumption / us_reference_consumption as change_in_us_consumption
			from	nems_supply_curve_data_import_final_unit_adjusted,
					(	select fuel as us_reference_fuel, nems_region as us_reference_region, nems_scenario as us_reference_scenario, simulation_year as us_reference_simulation_year, consumption as us_reference_consumption from nems_supply_curve_data_import_final_unit_adjusted
						where	nems_region = 'US'
						and		nems_scenario = 'Reference' ) as us_reference_table 
			where	nems_region = 'US'
			and		nems_supply_curve_data_import_final_unit_adjusted.fuel = us_reference_fuel
			and		nems_supply_curve_data_import_final_unit_adjusted.simulation_year = us_reference_simulation_year ) as change_in_consumption_table,
		(	select	fuel, nems_region, simulation_year, consumption as reference_regional_consumption
			from 	nems_supply_curve_data_import_final_unit_adjusted
			where	nems_region = 'Mexico'
			and		nems_scenario = 'Reference' ) as reference_regional_consumption_table
where	nems_supply_curve_data_import_final_unit_adjusted.nems_region = 'Mexico'
and		nems_supply_curve_data_import_final_unit_adjusted.nems_scenario not like 'Reference'
and 	nems_supply_curve_data_import_final_unit_adjusted.nems_region = reference_regional_consumption_table.nems_region
and		nems_supply_curve_data_import_final_unit_adjusted.fuel = change_in_consumption_table.fuel
and		nems_supply_curve_data_import_final_unit_adjusted.fuel = reference_regional_consumption_table.fuel
and		nems_supply_curve_data_import_final_unit_adjusted.nems_scenario = change_in_consumption_table.nems_scenario
and		nems_supply_curve_data_import_final_unit_adjusted.simulation_year = change_in_consumption_table.simulation_year
and		nems_supply_curve_data_import_final_unit_adjusted.simulation_year = reference_regional_consumption_table.simulation_year;

update	nems_supply_curve_data_import_final_unit_adjusted
set		consumption = change_in_us_consumption * reference_regional_consumption
from	(	select	fuel, nems_scenario, simulation_year, consumption / us_reference_consumption as change_in_us_consumption
			from	nems_supply_curve_data_import_final_unit_adjusted,
					(	select fuel as us_reference_fuel, nems_region as us_reference_region, nems_scenario as us_reference_scenario, simulation_year as us_reference_simulation_year, consumption as us_reference_consumption from nems_supply_curve_data_import_final_unit_adjusted
						where	nems_region = 'US_Electric'
						and		nems_scenario = 'Reference' ) as us_reference_table 
			where	nems_region = 'US_Electric'
			and		nems_supply_curve_data_import_final_unit_adjusted.fuel = us_reference_fuel
			and		nems_supply_curve_data_import_final_unit_adjusted.simulation_year = us_reference_simulation_year ) as change_in_consumption_table,
		(	select	fuel, nems_region, simulation_year, consumption as reference_regional_consumption
			from 	nems_supply_curve_data_import_final_unit_adjusted
			where	nems_region = 'Baja_Mexico'
			and		nems_scenario = 'Reference' ) as reference_regional_consumption_table
where	nems_supply_curve_data_import_final_unit_adjusted.nems_region = 'Baja_Mexico'
and		nems_supply_curve_data_import_final_unit_adjusted.nems_scenario not like 'Reference'
and 	nems_supply_curve_data_import_final_unit_adjusted.nems_region = reference_regional_consumption_table.nems_region
and		nems_supply_curve_data_import_final_unit_adjusted.fuel = change_in_consumption_table.fuel
and		nems_supply_curve_data_import_final_unit_adjusted.fuel = reference_regional_consumption_table.fuel
and		nems_supply_curve_data_import_final_unit_adjusted.nems_scenario = change_in_consumption_table.nems_scenario
and		nems_supply_curve_data_import_final_unit_adjusted.simulation_year = change_in_consumption_table.simulation_year
and		nems_supply_curve_data_import_final_unit_adjusted.simulation_year = reference_regional_consumption_table.simulation_year;
			

-- CANADA --
-- calculate consumption in Canada as well as British Columbia and Alberta (together named Canada_WECC) for the Reference case based on 2007 data for fuel use by electric utility thermal plants in Canada by province
-- total natural gas consumption for all of Canada was 9,872,471 thousands cubic meters
-- natural gas consumption for British Columbia was 535,439 thousands cubic meters
-- natural gas consumption for Alberta was 3,507,690 thousands cubic meters

-- first insert fuel-scenario-year combinations for Canada's electric sector consumption
insert into nems_supply_curve_data_import_final_unit_adjusted
	select	distinct(fuel) as fuel,
			nems_scenario,
			'Canada_Electric' as nems_region,
			simulation_year,
			cast(NULL as double precision) as price,
			cast(NULL as double precision) as consumption
	from	nems_supply_curve_data_import_final_unit_adjusted;

-- calculate the amount of fuel consumed in Canada's electric sector
-- we assume that the same fraction of total fuel is consumed in the electric sector as in the US

update	nems_supply_curve_data_import_final_unit_adjusted
set		consumption = electric_consumption_fraction * canada_consumption
from	( 	select	us_total_consumption_table.fuel,
					us_total_consumption_table.nems_scenario,
					us_total_consumption_table.simulation_year,
					us_electric_sector_consumption / us_total_consumption as electric_consumption_fraction
				from	(	select	fuel, nems_scenario, simulation_year, consumption as us_electric_sector_consumption
							from	nems_supply_curve_data_import_final_unit_adjusted
							where	nems_region = 'US_Electric' ) as us_electric_sector_consumption_table,
						(	select	fuel, nems_scenario, simulation_year, consumption as us_total_consumption
							from	nems_supply_curve_data_import_final_unit_adjusted
							where	nems_region = 'US' ) as us_total_consumption_table
				where	us_electric_sector_consumption_table.fuel = us_total_consumption_table.fuel
				and		us_electric_sector_consumption_table.nems_scenario = us_total_consumption_table.nems_scenario
				and		us_electric_sector_consumption_table.simulation_year = us_total_consumption_table.simulation_year
							) as electric_consumption_fraction_table,
		(	select fuel, nems_scenario, simulation_year, consumption as canada_consumption
				from 	nems_supply_curve_data_import_final_unit_adjusted
				where	nems_region = 'Canada' ) as canada_table
	where	nems_supply_curve_data_import_final_unit_adjusted.nems_region = 'Canada_Electric'
	and		nems_supply_curve_data_import_final_unit_adjusted.fuel = electric_consumption_fraction_table.fuel
	and		nems_supply_curve_data_import_final_unit_adjusted.nems_scenario = electric_consumption_fraction_table.nems_scenario
	and		nems_supply_curve_data_import_final_unit_adjusted.simulation_year = electric_consumption_fraction_table.simulation_year
	and		nems_supply_curve_data_import_final_unit_adjusted.fuel = canada_table.fuel
	and		nems_supply_curve_data_import_final_unit_adjusted.nems_scenario = canada_table.nems_scenario
	and		nems_supply_curve_data_import_final_unit_adjusted.simulation_year = canada_table.simulation_year;

-- now insert fuel-scenario-year combinations for Canada_WECC (not all combinations will be populated)
insert into nems_supply_curve_data_import_final_unit_adjusted
	select	distinct(fuel) as fuel,
			nems_scenario,
			'Canada_WECC' as nems_region,
			simulation_year,
			cast(NULL as double precision) as price,
			cast(NULL as double precision) as consumption
	from	nems_supply_curve_data_import_final_unit_adjusted;	


-- calculate electric sector fuel consumption in Canada_WECC based on BC/Alberta and Mexico's population
update	nems_supply_curve_data_import_final_unit_adjusted
set		consumption = (535439 + 3507690) * canada_electric_consumption / 9872471
from	(	select	fuel,
					nems_scenario,
      				simulation_year,
       				consumption as canada_electric_consumption
			from	nems_supply_curve_data_import_final_unit_adjusted
			where	nems_region = 'Canada_Electric' ) as canada_electric_table
where	nems_region = 'Canada_WECC'
and		nems_supply_curve_data_import_final_unit_adjusted.fuel = canada_electric_table.fuel
and		nems_supply_curve_data_import_final_unit_adjusted.nems_scenario = canada_electric_table.nems_scenario
and		nems_supply_curve_data_import_final_unit_adjusted.simulation_year = canada_electric_table.simulation_year;


-- update the Canada_WECC prices for natural gas with the Canada NG import prices
-- these are a little lower than prices in the Pacific Northwest
-- Alberta produces 75 percent of Canadian natural gas (http://www.energy.alberta.ca/NaturalGas/726.asp), BC also has large reserves (http://www.fortisbc.com/NaturalGas/AboutNaturalGas/Pages/Natural-gas-in-BC.aspx) and exports NG. A lot of natural gas is exported to the US from Canada (about 99.8 percent of total imports in 2007, http://www.eia.gov/pub/oil_gas/natural_gas/analysis_publications/ngpipeline/impex.html), so there must be some arbitrage and assuming the import prices here seems reasonable, but we may need to revisit this assumption if we expand to the whole US/Canada
update	nems_supply_curve_data_import_final_unit_adjusted
set		price = canada_import_price
from	(select fuel, nems_scenario, simulation_year, price as canada_import_price
		from	nems_supply_curve_data_import_final_unit_adjusted
		where	nems_region = 'Canada' 
		and		fuel = 'Gas' ) as canada_table
where	nems_supply_curve_data_import_final_unit_adjusted.nems_region = 'Canada_WECC'
and		nems_supply_curve_data_import_final_unit_adjusted.fuel = 'Gas'
and		nems_supply_curve_data_import_final_unit_adjusted.simulation_year = canada_table.simulation_year
and		nems_supply_curve_data_import_final_unit_adjusted.nems_scenario = canada_table.nems_scenario;

-- finally, set consumption in non-reference scenarios for Baja and Mexico to have the same percent increase/decrease relative to the rest of the scenarios as the US electric sector and the US respectively
-- this will be used in determining the supply curve breakpoints and prices later
update	nems_supply_curve_data_import_final_unit_adjusted
set		consumption = change_in_us_consumption * reference_regional_consumption
from	(	select	fuel, nems_scenario, simulation_year, consumption / us_reference_consumption as change_in_us_consumption
			from	nems_supply_curve_data_import_final_unit_adjusted,
					(	select fuel as us_reference_fuel, nems_region as us_reference_region, nems_scenario as us_reference_scenario, simulation_year as us_reference_simulation_year, consumption as us_reference_consumption from nems_supply_curve_data_import_final_unit_adjusted
						where	nems_region = 'US'
						and		nems_scenario = 'Reference' ) as us_reference_table 
			where	nems_region = 'US'
			and		nems_supply_curve_data_import_final_unit_adjusted.fuel = us_reference_fuel
			and		nems_supply_curve_data_import_final_unit_adjusted.simulation_year = us_reference_simulation_year ) as change_in_consumption_table,
		(	select	fuel, nems_region, simulation_year, consumption as reference_regional_consumption
			from 	nems_supply_curve_data_import_final_unit_adjusted
			where	nems_region = 'Canada'
			and		nems_scenario = 'Reference' ) as reference_regional_consumption_table
where	nems_supply_curve_data_import_final_unit_adjusted.nems_region = 'Canada'
and		nems_supply_curve_data_import_final_unit_adjusted.nems_scenario not like 'Reference'
and 	nems_supply_curve_data_import_final_unit_adjusted.nems_region = reference_regional_consumption_table.nems_region
and		nems_supply_curve_data_import_final_unit_adjusted.fuel = change_in_consumption_table.fuel
and		nems_supply_curve_data_import_final_unit_adjusted.fuel = reference_regional_consumption_table.fuel
and		nems_supply_curve_data_import_final_unit_adjusted.nems_scenario = change_in_consumption_table.nems_scenario
and		nems_supply_curve_data_import_final_unit_adjusted.simulation_year = change_in_consumption_table.simulation_year
and		nems_supply_curve_data_import_final_unit_adjusted.simulation_year = reference_regional_consumption_table.simulation_year;

update	nems_supply_curve_data_import_final_unit_adjusted
set		consumption = change_in_us_consumption * reference_regional_consumption
from	(	select	fuel, nems_scenario, simulation_year, consumption / us_reference_consumption as change_in_us_consumption
			from	nems_supply_curve_data_import_final_unit_adjusted,
					(	select fuel as us_reference_fuel, nems_region as us_reference_region, nems_scenario as us_reference_scenario, simulation_year as us_reference_simulation_year, consumption as us_reference_consumption from nems_supply_curve_data_import_final_unit_adjusted
						where	nems_region = 'US_Electric'
						and		nems_scenario = 'Reference' ) as us_reference_table 
			where	nems_region = 'US_Electric'
			and		nems_supply_curve_data_import_final_unit_adjusted.fuel = us_reference_fuel
			and		nems_supply_curve_data_import_final_unit_adjusted.simulation_year = us_reference_simulation_year ) as change_in_consumption_table,
		(	select	fuel, nems_region, simulation_year, consumption as reference_regional_consumption
			from 	nems_supply_curve_data_import_final_unit_adjusted
			where	nems_region = 'Canada_WECC'
			and		nems_scenario = 'Reference' ) as reference_regional_consumption_table
where	nems_supply_curve_data_import_final_unit_adjusted.nems_region = 'Canada_WECC'
and		nems_supply_curve_data_import_final_unit_adjusted.nems_scenario not like 'Reference'
and 	nems_supply_curve_data_import_final_unit_adjusted.nems_region = reference_regional_consumption_table.nems_region
and		nems_supply_curve_data_import_final_unit_adjusted.fuel = change_in_consumption_table.fuel
and		nems_supply_curve_data_import_final_unit_adjusted.fuel = reference_regional_consumption_table.fuel
and		nems_supply_curve_data_import_final_unit_adjusted.nems_scenario = change_in_consumption_table.nems_scenario
and		nems_supply_curve_data_import_final_unit_adjusted.simulation_year = change_in_consumption_table.simulation_year
and		nems_supply_curve_data_import_final_unit_adjusted.simulation_year = reference_regional_consumption_table.simulation_year;
			

-------------------------------------
------- Project beyond 2035 ---------

-- add entries for 2036-2060
insert into nems_supply_curve_data_import_final_unit_adjusted (fuel, nems_scenario, nems_region, simulation_year)
      select  fuel,
      		  nems_scenario,
              nems_region,
              (max_simulation_year + generate_series(1,25)) as simulation_year
         from (select fuel, nems_scenario, nems_region, max(simulation_year) as max_simulation_year 
              		from nems_supply_curve_data_import_final_unit_adjusted
              		group by fuel, nems_scenario, nems_region) as max_year_table;
              		
-- Extrapolate the fuel data beyond 2035
drop table if exists fuel_2060_extrapolation_slope_intercept;
create table fuel_2060_extrapolation_slope_intercept(
	fuel varchar(40),
	nems_scenario varchar(40),
	nems_region varchar(40),
	price_slope double precision,
	price_intercept double precision,
	consumption_slope double precision,
	consumption_intercept double precision,
	primary key (fuel, nems_scenario, nems_region)
	);

-- only use the last ten years (2026-2035) forecasted by NEMS to emphasize the trend toward the end of the forecasted period
insert into fuel_2060_extrapolation_slope_intercept (fuel, nems_region, nems_scenario, price_slope, price_intercept, consumption_slope, consumption_intercept)
	select 	fuel,
			nems_region,
			nems_scenario,
			regr_slope(price, simulation_year),
			regr_intercept(price, simulation_year),
			regr_slope(consumption, simulation_year),
			regr_intercept(consumption, simulation_year)	
			from nems_supply_curve_data_import_final_unit_adjusted
			where simulation_year > 2025
			group by fuel, nems_region, nems_scenario
			order by fuel, nems_region;

-- now populate the linear regression values to 2060
update nems_supply_curve_data_import_final_unit_adjusted
set		price = price_intercept + price_slope * simulation_year,
		consumption = consumption_intercept + consumption_slope * simulation_year
from 	fuel_2060_extrapolation_slope_intercept
	where	simulation_year > 2035
		and nems_supply_curve_data_import_final_unit_adjusted.fuel = fuel_2060_extrapolation_slope_intercept.fuel
		and nems_supply_curve_data_import_final_unit_adjusted.nems_region = fuel_2060_extrapolation_slope_intercept.nems_region
		and nems_supply_curve_data_import_final_unit_adjusted.nems_scenario = fuel_2060_extrapolation_slope_intercept.nems_scenario;


--------------------------------------------------------
--------- Create supply curves by fuel -----------------

-- calculate the consumption by fuel and scenario for the WECC and the rest of the United States
drop table if exists wecc_and_rest_of_north_america_fuel_price_consumption;
create table wecc_and_rest_of_north_america_fuel_price_consumption(
	fuel varchar(40),
	nems_scenario varchar(40),
	simulation_year int,
	total_north_america_consumption double precision,
	wecc_nems_projected_consumption double precision,
	fraction_change_in_wecc_projected_consumption double precision,
	ng_wellhead_price_after_change_in_wecc_consumption double precision,
	primary key (fuel, nems_scenario, simulation_year, fraction_change_in_wecc_projected_consumption)
	);

-- create table with fraction changes in wecc consumption that we will use as breakpoints
drop table if exists wecc_consumption_fraction_change_table;
create table wecc_consumption_fraction_change_table(
	id serial,
	wecc_consumption_fraction_change double precision,
	unique (id, wecc_consumption_fraction_change)
);

-- assume breakpoints between 0 and 200 percent of projection in steps of 10 percent
insert into wecc_consumption_fraction_change_table (wecc_consumption_fraction_change)
	VALUES (0.1 * generate_series(-10, 10, 1));

-- insert fuel-scenario-year-fraction_change combinations
insert into wecc_and_rest_of_north_america_fuel_price_consumption (fuel, nems_scenario, simulation_year, fraction_change_in_wecc_projected_consumption)
	select	distinct(fuel),
			nems_scenario,
			simulation_year,
			wecc_consumption_fraction_change
	from	nems_supply_curve_data_import_final_unit_adjusted, wecc_consumption_fraction_change_table
	order by fuel, simulation_year, nems_scenario;

-- calculate the total consumption in all of North America
update	wecc_and_rest_of_north_america_fuel_price_consumption
set		total_north_america_consumption = us_consumption + mexico_consumption + canada_consumption
from	(	select	fuel, nems_scenario, simulation_year, consumption as us_consumption
			from	nems_supply_curve_data_import_final_unit_adjusted
			where	nems_region = 'US' ) as us_table,
		(	select	fuel, nems_scenario, simulation_year, consumption as canada_consumption
			from	nems_supply_curve_data_import_final_unit_adjusted
			where	nems_region = 'Canada' ) as canada_table,
		(	select	fuel, nems_scenario, simulation_year, consumption as mexico_consumption
			from	nems_supply_curve_data_import_final_unit_adjusted
			where	nems_region = 'Mexico' ) as mexico_table
where	wecc_and_rest_of_north_america_fuel_price_consumption.fuel = us_table.fuel
	and	wecc_and_rest_of_north_america_fuel_price_consumption.nems_scenario = us_table.nems_scenario
	and wecc_and_rest_of_north_america_fuel_price_consumption.simulation_year = us_table.simulation_year
	and wecc_and_rest_of_north_america_fuel_price_consumption.fuel = canada_table.fuel
	and	wecc_and_rest_of_north_america_fuel_price_consumption.nems_scenario = canada_table.nems_scenario
	and wecc_and_rest_of_north_america_fuel_price_consumption.simulation_year = canada_table.simulation_year
	and wecc_and_rest_of_north_america_fuel_price_consumption.fuel = mexico_table.fuel
	and	wecc_and_rest_of_north_america_fuel_price_consumption.nems_scenario = mexico_table.nems_scenario
	and wecc_and_rest_of_north_america_fuel_price_consumption.simulation_year = mexico_table.simulation_year;
;

-- calculate the total consumption in the WECC as projected by NEMS
update	wecc_and_rest_of_north_america_fuel_price_consumption
set		wecc_nems_projected_consumption = calculated_wecc_consumption
from	( select fuel, nems_scenario, simulation_year, sum(consumption) as calculated_wecc_consumption
								from nems_supply_curve_data_import_final_unit_adjusted
									where ( nems_region = 'NWPP' or nems_region = 'Rockies' or nems_region = 'Southwest' or nems_region = 'Baja_Mexico' or nems_region = 'Canada_WECC' or nems_region = 'CA' )
									group by fuel, nems_scenario, simulation_year 
									order by fuel, nems_scenario, simulation_year) as wecc_consumption_table
where	wecc_consumption_table.fuel = wecc_and_rest_of_north_america_fuel_price_consumption.fuel
	and	wecc_consumption_table.nems_scenario = wecc_and_rest_of_north_america_fuel_price_consumption.nems_scenario
	and wecc_consumption_table.simulation_year = wecc_and_rest_of_north_america_fuel_price_consumption.simulation_year;

-- calculate the price at different WECC consumption levels assuming a consumption level for the rest of North America
-- price elasticity of 1.2 is assumed (i.e. 1 percent change in quantity results in 1.2 percent change in price) for natural gas based on the median value from Wiser, Bolinger, and Claire (2005), 'Easing the natural gas crisis: reducing natural gas prices through increased deployment of renewable energy and energy efficiency,' LBNL-56756
-- prices are calculated based on the average US price
update wecc_and_rest_of_north_america_fuel_price_consumption
set		ng_wellhead_price_after_change_in_wecc_consumption = ( 1 + 1.2 * fraction_change_in_wecc_projected_consumption * wecc_nems_projected_consumption / total_north_america_consumption ) * price
from	nems_supply_curve_data_import_final_unit_adjusted
where	nems_region = 'US'
	and	wecc_and_rest_of_north_america_fuel_price_consumption.fuel = 'Gas'
	and		wecc_and_rest_of_north_america_fuel_price_consumption.fuel = nems_supply_curve_data_import_final_unit_adjusted.fuel
	and 	wecc_and_rest_of_north_america_fuel_price_consumption.nems_scenario = nems_supply_curve_data_import_final_unit_adjusted.nems_scenario
	and		wecc_and_rest_of_north_america_fuel_price_consumption.simulation_year = nems_supply_curve_data_import_final_unit_adjusted.simulation_year;


-- create the final supply curve table
drop table if exists fuel_supply_curves;
create table fuel_supply_curves(
	fuel varchar(40),
	nems_scenario varchar(40),
	simulation_year int,
	wecc_consumption_breakpoint double precision,
	price_actual double precision,
	price_surplus_adjusted double precision
	);

-- now insert ordered records into fuel_supply_curves table
insert into fuel_supply_curves (fuel, nems_scenario, simulation_year, wecc_consumption_breakpoint, price_actual)
select		fuel,
			nems_scenario,
			simulation_year,
			wecc_nems_projected_consumption + fraction_change_in_wecc_projected_consumption * wecc_nems_projected_consumption as wecc_consumption_breakpoint,
			ng_wellhead_price_after_change_in_wecc_consumption as price_actual
from		wecc_and_rest_of_north_america_fuel_price_consumption
order by	fuel, nems_scenario, simulation_year, wecc_consumption_breakpoint;

alter table fuel_supply_curves
add column row_id serial;

alter table fuel_supply_curves
add column	breakpoint_id int;

-- update the breakpoint_id values; breakpoint_id = 0 is the price without any consumption in the WECC and will be excluded on export
update fuel_supply_curves
set breakpoint_id = row_id - min_row_id
from (select fuel, nems_scenario, simulation_year, min(row_id) as min_row_id
		from fuel_supply_curves
		group by fuel, nems_scenario, simulation_year) as min_row_table
where 	min_row_table.fuel = fuel_supply_curves.fuel
and		min_row_table.nems_scenario = fuel_supply_curves.nems_scenario
and		min_row_table.simulation_year = fuel_supply_curves.simulation_year;

-- add primary key to make sure fuel-scenario-year-breakpoint combinations are unique
alter table fuel_supply_curves
add primary key (fuel, nems_scenario, simulation_year, breakpoint_id);


-- calculate the surplus adjusted price for each breakpoint
drop table if exists n_minus_1_table;
create temporary table n_minus_1_table(
	fuel varchar(40),
	nems_scenario varchar(40),
	simulation_year int,
	consumption_breakpoint_n_minus_1 double precision,
	price_n_minus_1 double precision,
	breakpoint_id int
	);

insert into n_minus_1_table (fuel, nems_scenario, simulation_year, consumption_breakpoint_n_minus_1, price_n_minus_1, breakpoint_id)
select 	fuel,
		nems_scenario,
		simulation_year,
		wecc_consumption_breakpoint,
		price_actual,
		breakpoint_id + 1
from 	fuel_supply_curves;

update fuel_supply_curves
set		price_surplus_adjusted = 0
where	breakpoint_id = 0;

update fuel_supply_curves
set		price_surplus_adjusted = price_actual
where	breakpoint_id = 1;

-- the producer surplus from the previous breakpoint for going to a higher price is added here and distributed across the consumption in the next breakpoint
-- P_adjusted[n] = 
-- if n = 1, then P[1]
-- if n > 1, then ( breakpoint[n-1] * ( P[n] - P[n-1] ) + ( breakpoint[n] - breakpoint[n-1] ) * P[n] ) / ( breakpoint[n] - breakpoint[n-1] )
update fuel_supply_curves
set		price_surplus_adjusted =
			(	consumption_breakpoint_n_minus_1 * ( price_actual - price_n_minus_1 ) 
			 +	( wecc_consumption_breakpoint - consumption_breakpoint_n_minus_1 ) * price_actual
			 )
			 / ( wecc_consumption_breakpoint - consumption_breakpoint_n_minus_1 )
from	n_minus_1_table,
		( select max(breakpoint_id) as max_breakpoint_id from fuel_supply_curves ) as max_breakpoint_id_table
where	fuel_supply_curves.fuel = n_minus_1_table.fuel
and		fuel_supply_curves.nems_scenario = n_minus_1_table.nems_scenario
and		fuel_supply_curves.simulation_year = n_minus_1_table.simulation_year
and		fuel_supply_curves.breakpoint_id = n_minus_1_table.breakpoint_id
and		fuel_supply_curves.breakpoint_id > 1
and		fuel_supply_curves.breakpoint_id <= max_breakpoint_id;

-- add the last breakpoint to formulate piecewise linear supply curve in AMPL
insert into fuel_supply_curves (fuel, nems_scenario, simulation_year, breakpoint_id, price_surplus_adjusted)
	select 	fuel,
			nems_scenario,
			simulation_year,
			max(breakpoint_id) + 1 as break_point_id,
			99999 as price_surplus_adjusted
	from	fuel_supply_curves
	group by fuel, nems_scenario, simulation_year
	order by fuel, nems_scenario, simulation_year; 

--exports supply curves as CSV file
COPY 
(select fuel,
		nems_scenario,
		simulation_year,
		breakpoint_id,
		round(cast(wecc_consumption_breakpoint as numeric), 4) as wecc_consumption_breakpoint,
		round(cast(price_surplus_adjusted as numeric), 4) as price_surplus_adjusted
from fuel_supply_curves
where breakpoint_id > 0
order by fuel, nems_scenario, simulation_year, breakpoint_id)
TO '/DatabasePrep/NG_supply_curve/natural_gas_supply_curve.csv'
WITH CSV HEADER;

--------------------------------------------------
------ Calculate region-specific costs -----------

-- figure out the regional price adders by year for each scenario
-- by fuel, region, scenario, and simulation year
drop table if exists fuel_regional_price_adders;
create table fuel_regional_price_adders(
	fuel varchar(40),
	nems_region varchar(40),
	nems_scenario varchar(40),
	simulation_year int,
	regional_price_adder double precision,
	primary key (fuel, nems_region, nems_scenario, simulation_year)
	);

insert into fuel_regional_price_adders (fuel, nems_region, nems_scenario, simulation_year)
	select 		distinct(fuel),
				nems_region,
				nems_scenario,
				simulation_year
	from 		nems_supply_curve_data_import_final_unit_adjusted
	where		( nems_region = 'NWPP' or nems_region = 'Rockies' or nems_region = 'Southwest' or nems_region = 'Baja_Mexico' or nems_region = 'Canada_WECC' or nems_region = 'CA' )
		order by 	fuel, nems_region, nems_scenario, simulation_year;

update			fuel_regional_price_adders
	set			regional_price_adder = regional_table.price - us_table.price
	from		(select fuel, nems_region, nems_scenario, simulation_year, price
					from nems_supply_curve_data_import_final_unit_adjusted) as regional_table,
				(select fuel, nems_region, nems_scenario, simulation_year, price
					from nems_supply_curve_data_import_final_unit_adjusted
					where nems_region = 'US' ) as us_table
	where		regional_table.fuel = us_table.fuel 
		and 	regional_table.fuel = fuel_regional_price_adders.fuel
		and 	us_table.fuel = fuel_regional_price_adders.fuel
		and		regional_table.nems_scenario = us_table.nems_scenario 
		and 	regional_table.nems_scenario = fuel_regional_price_adders.nems_scenario
		and 	us_table.nems_scenario = fuel_regional_price_adders.nems_scenario
		and		regional_table.simulation_year = us_table.simulation_year
		and 	regional_table.simulation_year = fuel_regional_price_adders.simulation_year
		and 	us_table.simulation_year = fuel_regional_price_adders.simulation_year
		and		fuel_regional_price_adders.nems_region = regional_table.nems_region;
		
COPY 
(select fuel,
		nems_region,
		nems_scenario,
		simulation_year,
		round(cast(regional_price_adder as numeric), 4) as regional_price_adder
from fuel_regional_price_adders
order by fuel, nems_region, nems_scenario, simulation_year)
TO '/DatabasePrep/NG_supply_curve/natural_gas_regional_price_adders.csv'
WITH CSV HEADER;
