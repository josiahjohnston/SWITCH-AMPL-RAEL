-- build a table of data on existing plants in the USA and Canada and Baja Mexico

set search_path to usa_can, public;

-- first load in US data from EIA form 860 and 923

-- 860 Plant
drop table if exists eia_form_860_plant;
create table eia_form_860_plant(
	utility_id int,
	facility_code int primary key,
	plant_name varchar(100),
	street_address varchar(100),
	city varchar(50),
	county varchar(50),
	state char(2),
	zip5 int,
	name_of_water_source varchar(100),
	nerc varchar(4),
	primary_purpose int,
	ownertransdist varchar(100),
	ownertransid int,
	ownerstate char(2),
	gridvoltage numeric(5,2),
	regulatory_status char(2),
	sector_name varchar(50),
	sector int,
	ferc_cogen boolean,
	ferc_cogen_docket varchar(100),
	ferc_small_power boolean,
	ferc_small_power_docket varchar(100),
	ferc_exempt_wholesale boolean,
	ferc_exempt_wholesale_docket varchar(100),
	iso_rto boolean,
	iso_rto_code varchar(5)
);

copy eia_form_860_plant
from '/Volumes/switch/Models/USA_CAN/existing_plants/eia8602011/planty2011.txt'
with csv header DELIMITER E'\t';

-- 860 Generator
drop table if exists eia_form_860_generator;
create table eia_form_860_generator(
	utility_id int,
	utility_name varchar(100),
	facility_code int REFERENCES eia_form_860_plant,
	plant_name varchar(100),
	state char(2),
	county varchar(50),
	generator_id varchar(5),
	prime_mover char(2),
	status char(2),
	nameplate numeric(5,1),
	summer_capability numeric(5,1),
	winter_capability numeric(5,1),
	unit_code varchar(4),
	operating_month int,
	operating_year smallint,
	energy_source_1 varchar(3),
	energy_source_2 varchar(3),
	energy_source_3 varchar(3),
	energy_source_4 varchar(3),
	energy_source_5 varchar(3),
	energy_source_6 varchar(3),
	multiple_fuels boolean,
	deliver_power_transgrid boolean,
	synchronized_grid boolean,
	ownership char(1),
	turbines int,
	cogenerator boolean,
	sector_name varchar(50),
	sector int,
	topping_bottoming char(1),
	duct_burners boolean,
	planned_modifications boolean,
	planned_uprates_net_summer_cap numeric(5,1),
	planned_uprates_net_winter_cap numeric(5,1),
	planned_uprates_month int,
	planned_uprates_year smallint,
	planned_derates_net_summer_cap numeric(5,1),
	planned_derates_net_winter_cap numeric(5,1),
	planned_derates_month int,
	planned_derates_year smallint,
	planned_new_primemover char(2),
	planned_energy_source_1 varchar(3),
	planned_repower_month int,
	planned_repower_year smallint,
	other_mods boolean,
	other_mod_month int,
	other_mod_year smallint,
	planned_retirement_month int,
	planned_retirement_year smallint,
	sfg_system boolean,
	pulverized_coal boolean,
	fluidized_bed boolean,
	subcritical boolean,
	supercritical boolean,
	ultrasupercritical boolean,
	carboncapture boolean,
	startup_source_1 varchar(3),
	startup_source_2 varchar(3),
	startup_source_3 varchar(3),
	startup_source_4 varchar(3),
	PRIMARY KEY (facility_code, generator_id)
);

copy eia_form_860_generator
from '/Volumes/switch/Models/USA_CAN/existing_plants/eia8602011/generatory2011.txt'
with csv header DELIMITER E'\t';

-- 860 Interconnection
-- contains information about how much it costs to interconnect generation units
-- will be used to derive connect_cost_generic in generator_info
-- note that the cost columns are in THOUSANDS of $2011 dollars
drop table if exists eia_form_860_interconnection;
create table eia_form_860_interconnection(
	utility_id int,
	utility_name varchar(100),
	facility_code int,
	plant_name varchar(100),
	state char(2),
	county varchar(50),
	generator_id varchar(5),
	interconnection_month smallint,
	interconnection_year smallint,
	interconnection_request_month smallint,
	interconnection_request_year smallint,
	interconnection_city varchar(100),
	interconnection_state char(2),
	grid_voltage NUMERIC(5,2),
	transmission_ownername varchar(100),
	interconnection_cost NUMERIC(8,0),
	transmission_line boolean,
	transformer boolean,
	protective_devices boolean,
	substation boolean,
	other_equipment boolean,
	grid_enhancement_cost NUMERIC(8,0),
	grid_cost_repaid boolean,
	transmission_rights_secured boolean,
	PRIMARY KEY (facility_code, generator_id)
	);

copy eia_form_860_interconnection
from '/Volumes/switch/Models/USA_CAN/existing_plants/eia8602011/interconnectiony2011.txt'
with csv header DELIMITER E'\t';

-- delete a few entries that don't cross-reference with eia_form_860_generator, then make a fk
DELETE FROM eia_form_860_interconnection where (facility_code, generator_id) not in (select facility_code, generator_id from eia_form_860_generator);
ALTER TABLE eia_form_860_interconnection ADD FOREIGN KEY (facility_code, generator_id) REFERENCES eia_form_860_generator;

-- 923... contains information about monthly fuel use and electricity generation for each plant-primemover combo
-- will load data from 2004-2011 into this table
-- the 2011 data will be used to calculate heat rates and cogen thermal demand for thermal plants
-- the other years will be used for hydroelectric plants
drop table if exists eia_form_923_gen_fuel;
create table eia_form_923_gen_fuel(
	facility_code int,
	cogenerator boolean,
	nuclear_unit_id int default 0,
	plant_name varchar(100),
	operator_name varchar(100),
	operator_id int,
	state char(2),
	census_region varchar(4),
	nerc_region varchar(5),
	reserved1 int,
	naics_code int,
	eia_sector_number int,
	sector_name varchar(50),
	prime_mover char(2),
	reported_fuel_type_code varchar(3),
	aer_fuel_type_code varchar(3),
	reserved2 int,
	reserved3 int,
	physical_unit_label varchar(20),
	quantity_jan numeric(8,0),
	quantity_feb numeric(8,0),
	quantity_mar numeric(8,0),
	quantity_apr numeric(8,0),
	quantity_may numeric(8,0),
	quantity_jun numeric(8,0),
	quantity_jul numeric(8,0),
	quantity_aug numeric(8,0),
	quantity_sep numeric(8,0),
	quantity_oct numeric(8,0),
	quantity_nov numeric(8,0),
	quantity_dec numeric(8,0),
	elec_quantity_jan numeric(8,0),
	elec_quantity_feb numeric(8,0),
	elec_quantity_mar numeric(8,0),
	elec_quantity_apr numeric(8,0),
	elec_quantity_may numeric(8,0),
	elec_quantity_jun numeric(8,0),
	elec_quantity_jul numeric(8,0),
	elec_quantity_aug numeric(8,0),
	elec_quantity_sep numeric(8,0),
	elec_quantity_oct numeric(8,0),
	elec_quantity_nov numeric(8,0),
	elec_quantity_dec numeric(8,0),
	mmbtu_per_unit_jan numeric(6,2),
	mmbtu_per_unit_feb numeric(6,2),
	mmbtu_per_unit_mar numeric(6,2),
	mmbtu_per_unit_apr numeric(6,2),
	mmbtu_per_unit_may numeric(6,2),
	mmbtu_per_unit_jun numeric(6,2),
	mmbtu_per_unit_jul numeric(6,2),
	mmbtu_per_unit_aug numeric(6,2),
	mmbtu_per_unit_sep numeric(6,2),
	mmbtu_per_unit_oct numeric(6,2),
	mmbtu_per_unit_nov numeric(6,2),
	mmbtu_per_unit_dec numeric(6,2),
	tot_mmbtu_jan numeric(8,0),
	tot_mmbtu_feb numeric(8,0),
	tot_mmbtu_mar numeric(8,0),
	tot_mmbtu_apr numeric(8,0),
	tot_mmbtu_may numeric(8,0),
	tot_mmbtu_jun numeric(8,0),
	tot_mmbtu_jul numeric(8,0),
	tot_mmbtu_aug numeric(8,0),
	tot_mmbtu_sep numeric(8,0),
	tot_mmbtu_oct numeric(8,0),
	tot_mmbtu_nov numeric(8,0),
	tot_mmbtu_dec numeric(8,0),
	elec_mmbtus_jan numeric(8,0),
	elec_mmbtus_feb numeric(8,0),
	elec_mmbtus_mar numeric(8,0),
	elec_mmbtus_apr numeric(8,0),
	elec_mmbtus_may numeric(8,0),
	elec_mmbtus_jun numeric(8,0),
	elec_mmbtus_jul numeric(8,0),
	elec_mmbtus_aug numeric(8,0),
	elec_mmbtus_sep numeric(8,0),
	elec_mmbtus_oct numeric(8,0),
	elec_mmbtus_nov numeric(8,0),
	elec_mmbtus_dec numeric(8,0),
	netgen_jan numeric(8,0),
	netgen_feb numeric(8,0),
	netgen_mar numeric(8,0),
	netgen_apr numeric(8,0),
	netgen_may numeric(8,0),
	netgen_jun numeric(8,0),
	netgen_jul numeric(8,0),
	netgen_aug numeric(8,0),
	netgen_sep numeric(8,0),
	netgen_oct numeric(8,0),
	netgen_nov numeric(8,0),
	netgen_dec numeric(8,0),
	total_fuel_consumption_quantity numeric(10,0),
	electric_fuel_consumption_quantity numeric(10,0),
	total_fuel_consumption_mmbtus numeric(10,0),
	elec_fuel_consumption_mmbtus numeric(10,0),
	net_generation_mwh numeric(10,0),
	year smallint
);

-- load in all the data from 2004-2011
-- note: to get the data in the proper format, format cells for all of the numeric columns
-- starting at quantity_jan to zero decimal places and no comma spacer (make them look like nice ints)
-- also, don't forget to put a final return character at the end of file

-- a small generator on Kauai, HI was duplicated, so it was deleted before upload
copy eia_form_923_gen_fuel
from '/Volumes/switch/Models/USA_CAN/existing_plants/eia_form_923/2004/f906920_2004.txt'
with csv header DELIMITER E'\t';

copy eia_form_923_gen_fuel
from '/Volumes/switch/Models/USA_CAN/existing_plants/eia_form_923/2005/f906920_2005.txt'
with csv header DELIMITER E'\t';

copy eia_form_923_gen_fuel
from '/Volumes/switch/Models/USA_CAN/existing_plants/eia_form_923/2006/f906920_2006.txt'
with csv header DELIMITER E'\t';

copy eia_form_923_gen_fuel
from '/Volumes/switch/Models/USA_CAN/existing_plants/eia_form_923/2007/f906920_2007.txt'
with csv header DELIMITER E'\t';

copy eia_form_923_gen_fuel
from '/Volumes/switch/Models/USA_CAN/existing_plants/eia_form_923/2008/f923_2008_gen_fuel.txt'
with csv header DELIMITER E'\t';

copy eia_form_923_gen_fuel
from '/Volumes/switch/Models/USA_CAN/existing_plants/eia_form_923/2009/f923_2009_gen_fuel.txt'
with csv header DELIMITER E'\t';

copy eia_form_923_gen_fuel
from '/Volumes/switch/Models/USA_CAN/existing_plants/eia_form_923/2010/f923_2010_gen_fuel.txt'
with csv header DELIMITER E'\t';

copy eia_form_923_gen_fuel
from '/Volumes/switch/Models/USA_CAN/existing_plants/eia_form_923/2011/f923_2011_gen_fuel.txt'
with csv header DELIMITER E'\t';

-- the EIA has a code for not well reported generation... it's almost always quite small, so delete it here
delete from eia_form_923_gen_fuel where facility_code = 99999;

-- there are also a few plants that aren't in the master list of plants that also didn't generate anything...
-- delete here for 2011 (eia_form_860_plant is from 2011)
delete from eia_form_923_gen_fuel
WHERE net_generation_mwh = 0
AND plant_id not in (select facility_code from eia_form_860_plant)
AND year = 2011;


-- now we can add the primary key
UPDATE eia_form_923_gen_fuel SET nuclear_unit_id = 0 WHERE nuclear_unit_id IS NULL;
ALTER TABLE eia_form_923_gen_fuel ADD PRIMARY KEY
	(facility_code, nuclear_unit_id, cogenerator, prime_mover, eia_sector_number, reported_fuel_type_code, aer_fuel_type_code, year);
	
-- #################### GEOLOCATE EIA PLANTS ################
-- match EIA plants to the geolocated Ventyx data
SELECT addgeometrycolumn ('usa_can','eia_form_860_plant','the_geom',4326,'POINT',2);
CREATE INDEX ON eia_form_860_plant USING gist (the_geom);

-- from a search through the list of matches, it appears that we've got the correct location if
-- the eia_id from ventyx matches the facility_code from the EIA AND EITHER state or city match
-- some generators are on rivers that are state boundaries so the city or state might be wrong, but not the other
UPDATE eia_form_860_plant e
SET the_geom = p.the_geom
FROM ventyx_may_2012.e_plants_point p
WHERE facility_code = eia_id
AND NOT (p.state != e.state AND p.city != e.city);

-- match unmatched ones on plant_name, city, and state first
UPDATE eia_form_860_plant e
SET the_geom = p.the_geom
FROM ventyx_may_2012.e_plants_point p
WHERE e.plant_name = p.plant_name
AND e.city = p.city
AND e.state = p.state
AND e.the_geom is null;

-- next using plant_name and state but not city (some cities are blank)
UPDATE eia_form_860_plant e
SET the_geom = p.the_geom
FROM ventyx_may_2012.e_plants_point p
WHERE e.plant_name = p.plant_name
AND e.state = p.state
AND e.the_geom is null;

-- now match on city and state but only partial plant_name
-- the loop will get long matches first and reduce from there using left()
-- even if this creates some errors, they should be minor as they're in the same city and state
-- 6 is about the shortest meaningful length for this kind of name matching
CREATE OR REPLACE FUNCTION name_length_loop() RETURNS VOID AS $$

DECLARE current_length int;
BEGIN
select 20 into current_length;

WHILE ( ( select current_length ) >= 6 ) LOOP

	UPDATE eia_form_860_plant e
	SET the_geom = p.the_geom
	FROM ventyx_may_2012.e_plants_point p
	WHERE left(e.plant_name, current_length) = left(p.plant_name, current_length)
	AND e.city = p.city
	AND e.state = p.state
	AND e.the_geom is null;
	
	select current_length - 1 into current_length;

END LOOP;
END; $$ LANGUAGE 'plpgsql';

-- Actually call the function
SELECT name_length_loop();
drop function name_length_loop();

-- same as above but without city matches
-- only gives correct matches down to 13
CREATE OR REPLACE FUNCTION name_length_loop2() RETURNS VOID AS $$

DECLARE current_length int;
BEGIN
select 20 into current_length;

WHILE ( ( select current_length ) >= 13 ) LOOP

	UPDATE eia_form_860_plant e
	SET the_geom = p.the_geom
	FROM ventyx_may_2012.e_plants_point p
	WHERE left(e.plant_name, current_length) = left(p.plant_name, current_length)
	AND e.state = p.state
	AND e.the_geom is null;
	
	select current_length - 1 into current_length;

END LOOP;
END; $$ LANGUAGE 'plpgsql';

-- Actually call the function
SELECT name_length_loop2();
drop function name_length_loop2();


-- now for all the rest, we'll use the address that the EIA has on file.
-- there is a nice internet program that takes a list of addresses as inputs and outputs lat/lon coords
-- can be found here http://stevemorse.org/jcal/latlonbatch.html?direction=forward
-- the below code prints out the input addresses, then you copy and paste the output into the left window
-- and lat/lon will appear in the right window.  presto!

-- select street_address || ', ' || city || ', ' || state || ', ' || zip5 from eia_form_860_plant
-- where the_geom is null and street_address is not null and city is not null and state is not null and zip5 is not null and zip5 > 0

-- paste the results into excel in a new column along with the initial addresses,
-- then enclose the addresses in quotes in bbedit along with replacing tabs with commas
-- now we're ready to load the results back into postgresql
drop table if exists address_matches_tmp;
create table address_matches_tmp (address varchar(200), latitude double precision, longitude double precision);
copy address_matches_tmp
from '/home/jimmy/address_matches.csv'
with CSV;

-- the address matches got a few wrong... delete them here
DELETE FROM address_matches_tmp
WHERE ( longitude > -60 OR latitude < 19);

-- now we need to update the_geom with the addresses from address_matches_tmp
UPDATE eia_form_860_plant
SET the_geom = ST_SETSRID(ST_MakePoint(longitude, latitude),4326)
FROM address_matches_tmp
WHERE address = street_address || ', ' || city || ', ' || state || ', ' || zip5
AND the_geom is null and street_address is not null and city is not null and state is not null and zip5 is not null and zip5 > 0;

-- clean up
drop table address_matches_tmp;

-- as a last resort, join to city name from a table of cities to get the geometry of the city
UPDATE eia_form_860_plant p
SET the_geom = c.the_geom
FROM ventyx_may_2012.cities_point c
WHERE p.city = c.name
AND p.state = c.state
AND p.the_geom is null;

-- the eia_form_860_plant table has a few plants without geoms but none of them generated electricity in 2011
-- because this query gives zero results
-- select * from eia_form_860_plant join eia_form_923_gen_fuel using (facility_code) where the_geom is null and year = 2011;

-- ADD LOAD AREA-----------------------
alter table eia_form_860_plant add column load_area varchar(30) REFERENCES load_areas_usa_can (load_area) ON UPDATE CASCADE;

UPDATE eia_form_860_plant
SET	load_area = l.load_area
FROM load_areas_usa_can l
WHERE st_intersects(the_geom, polygon_geom);

-- don't forget plants off the coast that don't quite intersect with the load_areas_usa_can shapefile!
-- give them to the geographically nearest load area
UPDATE  eia_form_860_plant p
SET 	load_area = l.load_area
FROM	load_areas_usa_can l, 
		(select facility_code,
				min(st_distance_spheroid(the_geom, polygon_geom, 'SPHEROID["WGS 84",6378137,298.257223563]')) as min_distance
			from 	eia_form_860_plant p,
					load_areas_usa_can
			WHERE p.load_area is NULL
			AND p.the_geom is not NULL
			AND p.state not in ('AK', 'HI')
			group by facility_code) as min_distance_table		
where 	min_distance = st_distance_spheroid(the_geom, polygon_geom, 'SPHEROID["WGS 84",6378137,298.257223563]')
AND		p.facility_code = min_distance_table.facility_code
AND		p.load_area is NULL
AND 	p.the_geom is not NULL
AND 	p.state not in ('AK', 'HI');


-- ######################## CALCULATE EFFICIENCY AND AGGREGATE ########################
-- gets all of the plants in the USA... canada and mexico will be added below

-- dispatchable plants are non-cogen natural gas plants
-- flexible baseload plants are coal and biomass solid
-- baseload plants are all others
-- wind, solar, and hydro are handled seperatly

-- efficiency of plants (heat rate) is based on net_gen_mwh and elec_fuel_mbtu,
-- using the predominant fuel from 2011 generation

-- ########################

-- use EIA form 923 data calculate the efficiency (heat rate) of all plant-primemover-cogen-fuel combinations

-- This table will also be used to pick only the plant-primemover-cogen-fuel combination that generated the most electricity in 2011
-- (the assumption being that this plant will continue to use the same fuel as its primary fuel)

drop table if exists existing_plants_923;
create table existing_plants_923(
	facility_code int NOT NULL REFERENCES eia_form_860_plant (facility_code),
	prime_mover char(2) NOT NULL,
	cogenerator boolean NOT NULL,
	fuel varchar(20) NOT NULL,
	total_fuel_consumption_mmbtus double precision NOT NULL,
	elec_fuel_consumption_mmbtus double precision NOT NULL,
	net_generation_mwh double precision NOT NULL,
	heat_rate NUMERIC(7,3),
	cogen_thermal_demand_mmbtus_per_mwh NUMERIC(7,3),
	greatest_monthly_net_gen numeric(8,0),
	elec_fuel_consumption_mmbtus_in_greatest_month numeric(8,0),
	elec_mmbtus_jan numeric(8,0),
	elec_mmbtus_feb numeric(8,0),
	elec_mmbtus_mar numeric(8,0),
	elec_mmbtus_apr numeric(8,0),
	elec_mmbtus_may numeric(8,0),
	elec_mmbtus_jun numeric(8,0),
	elec_mmbtus_jul numeric(8,0),
	elec_mmbtus_aug numeric(8,0),
	elec_mmbtus_sep numeric(8,0),
	elec_mmbtus_oct numeric(8,0),
	elec_mmbtus_nov numeric(8,0),
	elec_mmbtus_dec numeric(8,0),
	netgen_jan numeric(8,0),
	netgen_feb numeric(8,0),
	netgen_mar numeric(8,0),
	netgen_apr numeric(8,0),
	netgen_may numeric(8,0),
	netgen_jun numeric(8,0),
	netgen_jul numeric(8,0),
	netgen_aug numeric(8,0),
	netgen_sep numeric(8,0),
	netgen_oct numeric(8,0),
	netgen_nov numeric(8,0),
	netgen_dec numeric(8,0),
	PRIMARY KEY (facility_code, prime_mover, cogenerator, fuel)
	);

-- aggregate to the fuel types used by SWITCH
-- make a fuel map table to make the aggregation easier
drop table if exists eia_fuel_map_table;
create table eia_fuel_map_table (
	reported_fuel_type_code varchar(3),
	fuel varchar(20),
	primary key (reported_fuel_type_code, fuel));
	
insert into eia_fuel_map_table (reported_fuel_type_code, fuel) VALUES
	('BIT', 'Coal'),
	('LIG', 'Coal'),
	('SUB', 'Coal'),
	('WC', 'Coal'),
	('SGC', 'Coal'),
	('PC', 'Coal'),
	('SGP', 'Coal'),
	('DFO', 'DistillateFuelOil'),
	('JF', 'DistillateFuelOil'),
	('KER', 'DistillateFuelOil'),
	('RFO', 'ResidualFuelOil'),
	('WO', 'ResidualFuelOil'),
	('NG', 'Gas'),
	('BFG', 'Gas'),
	('OG', 'Gas'),
	('PG', 'Gas'),
	('NUC', 'Uranium'),
	('AB', 'Bio_Solid'),
	('MSB', 'Bio_Solid'),
	('MSN', 'Bio_Solid'),
	('OBS', 'Bio_Solid'),
	('WDS', 'Bio_Solid'),
	('TDF', 'Bio_Solid'),
	('OBL', 'Bio_Liquid'),
	('BLQ', 'Bio_Liquid'),
	('SLW', 'Bio_Liquid'),
	('WDL', 'Bio_Liquid'),
	('LFG', 'Bio_Gas'),
	('OBG', 'Bio_Gas'),
	('GEO', 'Geothermal'),
	('WND', 'Wind'),
	('WAT', 'Water'),
	('SUN', 'Solar');

-- the fuels 'OTH', 'WH', 'PUR' are very minor and can't be handled by SWITCH yet

-- natural gas combined cycle plants are disaggregated in eia_form_923_gen_fuel but are aggregated in SWITCH
-- to get the efficiency of the combination, they are called prime_mover 'CC' here

-- if the plant didn't generate more than 1000 MWh in 2011 with the fuel in question,
-- then it's simply too small to include in SWITCH

-- also aggregate a few biogas plants whose primemovers are GTs or OTs instead of ICs...
-- they're functionally the same in Switch so we'll rename them here to IC

insert into existing_plants_923 (facility_code, prime_mover, cogenerator, fuel,
	total_fuel_consumption_mmbtus, elec_fuel_consumption_mmbtus, net_generation_mwh,
	elec_mmbtus_jan, elec_mmbtus_feb, elec_mmbtus_mar, elec_mmbtus_apr,
	elec_mmbtus_may, elec_mmbtus_jun, elec_mmbtus_jul, elec_mmbtus_aug,
	elec_mmbtus_sep, elec_mmbtus_oct, elec_mmbtus_nov, elec_mmbtus_dec,
	netgen_jan, netgen_feb, netgen_mar, netgen_apr, netgen_may, netgen_jun,
	netgen_jul, netgen_aug, netgen_sep, netgen_oct, netgen_nov, netgen_dec)
	SELECT 	facility_code,
			CASE 	WHEN prime_mover in ('CT', 'CA', 'CS') THEN 'CC'
					WHEN prime_mover in ('OT', 'GT', 'IC') AND fuel = 'Bio_Gas' THEN 'IC'
					WHEN prime_mover = 'IC' AND FUEL = 'Bio_Solid' THEN 'ST'
			-- relabel a single plant primemover... all for this plant appear to be combined cycles
					WHEN prime_mover = 'ST' AND facility_code = 50973 THEN 'CC'
					WHEN prime_mover = 'CP' THEN 'ST'
					ELSE prime_mover
			END as new_prime_mover,
			cogenerator,
			fuel,
			sum(total_fuel_consumption_mmbtus),
			sum(elec_fuel_consumption_mmbtus),
			sum(net_generation_mwh),
			sum(elec_mmbtus_jan),
			sum(elec_mmbtus_feb),
			sum(elec_mmbtus_mar),
			sum(elec_mmbtus_apr),
			sum(elec_mmbtus_may),
			sum(elec_mmbtus_jun),
			sum(elec_mmbtus_jul),
			sum(elec_mmbtus_aug),
			sum(elec_mmbtus_sep),
			sum(elec_mmbtus_oct),
			sum(elec_mmbtus_nov),
			sum(elec_mmbtus_dec),
			sum(netgen_jan),
			sum(netgen_feb),
			sum(netgen_mar),
			sum(netgen_apr),
			sum(netgen_may),
			sum(netgen_jun),
			sum(netgen_jul),
			sum(netgen_aug),
			sum(netgen_sep),
			sum(netgen_oct),
			sum(netgen_nov),
			sum(netgen_dec)
	FROM 	eia_form_923_gen_fuel
	JOIN	eia_fuel_map_table using (reported_fuel_type_code)
	WHERE	( net_generation_mwh > 1000 OR ( prime_mover = 'PS' AND net_generation_mwh != 0))
	AND		reported_fuel_type_code not in ('OTH', 'WH', 'PUR')
	AND		year = 2011
	GROUP BY facility_code, new_prime_mover, cogenerator, fuel;

-- remove primemover fuel combos that we can't deal with yet
DELETE FROM existing_plants_923
WHERE prime_mover = 'FC'
OR ( prime_mover = 'OT' AND fuel = 'Gas');

-- update for generators labeled cogen that didn't do any cogeneration (total fuel = fuel for electricity)
UPDATE existing_plants_923
SET cogenerator = false
WHERE total_fuel_consumption_mmbtus = elec_fuel_consumption_mmbtus
AND cogenerator = true;


-- the EIA data gives the fuel used per MWh produced
-- the problem with this metric is that it could include startup fuel
-- and also reduced efficiency from operating at part load
-- SWITCH needs the FULL LOAD heat rate for dispatchable plants
-- as it will increase fuel consumption when operating below full load or starting up
-- We'll get part of the way here to the full load heat rate by choosing the MONTH
-- of the year in which the plant generated the most electricity to calculate efficiency.
-- The assumption here is that is the plant was operating at full load more during this month than in others
-- This should be updated at some point because especially for fast ramping turbines this assumption might not be true

-- this doesn't correct for month length, but they are all close enough for our purposes here
UPDATE existing_plants_923
SET greatest_monthly_net_gen = 
	GREATEST(	netgen_jan, netgen_feb, netgen_mar, netgen_apr, netgen_may, netgen_jun,
				netgen_jul, netgen_aug, netgen_sep, netgen_oct, netgen_nov, netgen_dec);
				
UPDATE existing_plants_923
SET elec_fuel_consumption_mmbtus_in_greatest_month = 
CASE WHEN 	netgen_jan = greatest_monthly_net_gen THEN elec_mmbtus_jan
	 WHEN	netgen_feb = greatest_monthly_net_gen THEN elec_mmbtus_feb
	 WHEN	netgen_mar = greatest_monthly_net_gen THEN elec_mmbtus_mar
	 WHEN	netgen_apr = greatest_monthly_net_gen THEN elec_mmbtus_apr
	 WHEN	netgen_may = greatest_monthly_net_gen THEN elec_mmbtus_may
	 WHEN	netgen_jun = greatest_monthly_net_gen THEN elec_mmbtus_jun
	 WHEN	netgen_jul = greatest_monthly_net_gen THEN elec_mmbtus_jul
	 WHEN	netgen_aug = greatest_monthly_net_gen THEN elec_mmbtus_aug
	 WHEN	netgen_sep = greatest_monthly_net_gen THEN elec_mmbtus_sep
	 WHEN	netgen_oct = greatest_monthly_net_gen THEN elec_mmbtus_oct
	 WHEN	netgen_nov = greatest_monthly_net_gen THEN elec_mmbtus_nov
	 WHEN	netgen_dec = greatest_monthly_net_gen THEN elec_mmbtus_dec
END;

-- set heat rate and cogen thermal demand for non-thermal technologies to zero
UPDATE existing_plants_923
SET cogen_thermal_demand_mmbtus_per_mwh = 0,
	heat_rate = 0
WHERE fuel in ('Water', 'Wind') OR prime_mover = 'PV';

-- update the heat rate, taking the yearly heat rate for cogen,
-- and the monthly heat rate for the month in which the plant-prime_mover-cogen-fuel combo
-- generated the most electricity
-- unless the plant didn't generate much electricity at all during the year (less than 1MW avg or 8760MWh/yr),
-- in which case default back to the yearly heat rate
UPDATE existing_plants_923
SET cogen_thermal_demand_mmbtus_per_mwh = (total_fuel_consumption_mmbtus - elec_fuel_consumption_mmbtus) / net_generation_mwh,
	heat_rate = CASE WHEN (cogenerator OR (NOT cogenerator AND net_generation_mwh < 8760))
						THEN elec_fuel_consumption_mmbtus / net_generation_mwh
				ELSE elec_fuel_consumption_mmbtus_in_greatest_month / greatest_monthly_net_gen END
WHERE	heat_rate IS NULL;
				
-- there are a couple small generators that misreported their fuel consumption
-- such that they appear to generate electricity far too efficiently ... delete them here
DELETE FROM existing_plants_923
WHERE heat_rate < 6
AND NOT cogenerator
AND NOT (fuel in ('Water', 'Wind') OR prime_mover = 'PV');

-- EIA 860 GEN: Get primary fuel, start_year, capacity_mw -----------------------------

-- create the existing plants table for EIA form 860, which contains info about plants, and their generating units
-- here we insert a seperate line for each possible fuel that each plant-primemover-cogen combination could burn
-- then eventually aggregate the total capacity up to plant-primemover-cogen-fuel

-- existing generators that can't deliver power transgrid are included in existing plants here
-- BUT this means that their historical output should be ADDED to the load profile
-- because the load profile recorded by the utility/grid


-- below is going to be some messy sql - no primary key on this table because
-- we're going to do a lot of inserting and deleting before arriving at the desired table
-- at which time the primary key will be added
drop table if exists existing_plants_860_gen;
create table existing_plants_860_gen (
	facility_code int NOT NULL REFERENCES eia_form_860_plant (facility_code),
	generator_id varchar(5) NOT NULL,
	prime_mover char(2) NOT NULL,
	cogenerator boolean NOT NULL,
	fuel varchar(20) NOT NULL,
	start_year smallint NOT NULL,
	capacity_mw numeric(5,1)
	);

-- there are six columns for energy source - do a seperate select statement for each here
-- we're only going to use one of the possible six because we're going to determine the primary fuel for each unit
-- then aggregate to the plant-primemover-cogen-fuel level
-- we'll need to change around primemover and fuel... do this below
INSERT INTO existing_plants_860_gen (facility_code, generator_id, prime_mover, cogenerator, fuel, start_year, capacity_mw)
	SELECT 	facility_code, generator_id, prime_mover, cogenerator, energy_source_1 as fuel, Operating_Year, nameplate
		FROM  	eia_form_860_generator 
		WHERE	status != 'OS' and energy_source_1 is not null
	UNION
	SELECT 	facility_code, generator_id, prime_mover, cogenerator, energy_source_2 as fuel, Operating_Year, nameplate
		FROM  	eia_form_860_generator
		WHERE	status != 'OS' and energy_source_2 is not null
	UNION
	SELECT 	facility_code, generator_id, prime_mover, cogenerator, energy_source_3 as fuel, Operating_Year, nameplate
		FROM  	eia_form_860_generator
		WHERE	status != 'OS' and energy_source_3 is not null
	UNION
	SELECT 	facility_code, generator_id, prime_mover, cogenerator, energy_source_4 as fuel, Operating_Year, nameplate
		FROM  	eia_form_860_generator
		WHERE	status != 'OS' and energy_source_4 is not null
	UNION
	SELECT 	facility_code, generator_id, prime_mover, cogenerator, energy_source_5 as fuel, Operating_Year, nameplate
		FROM  	eia_form_860_generator
		WHERE	status != 'OS' and energy_source_5 is not null
	UNION
	SELECT 	facility_code, generator_id, prime_mover, cogenerator, energy_source_6 as fuel, Operating_Year, nameplate
		FROM  	eia_form_860_generator
		WHERE	status != 'OS' and energy_source_6 is not null
;	

-- the next three sql statements should line up with those above that create existing_plants_923
-- because we're going to do a join between existing_plants_923 and existing_plants_860_gen

-- this plant has purchased steam, presumably from gas
UPDATE existing_plants_860_gen SET fuel = 'Gas' WHERE facility_code = 50304 AND fuel = 'PUR';

-- delete the fuels we'll handle elsewhere or ignore
DELETE FROM existing_plants_860_gen WHERE fuel in ('OTH', 'WH', 'PUR');


-- update fuels to SWITCH fuels
-- this will make duplicate entries in the existing_plants_860_gen table
-- but these will be sorted out below using a distinct
UPDATE existing_plants_860_gen g
SET fuel = m.fuel
FROM eia_fuel_map_table m
WHERE g.fuel = reported_fuel_type_code;

UPDATE existing_plants_860_gen
SET prime_mover = CASE 	WHEN prime_mover in ('CT', 'CA', 'CS') THEN 'CC'
						WHEN prime_mover in ('OT', 'GT', 'IC') AND fuel = 'Bio_Gas' THEN 'IC'
						WHEN prime_mover = 'IC' AND FUEL = 'Bio_Solid' THEN 'ST'
						WHEN prime_mover = 'CP' THEN 'ST'
						ELSE prime_mover END;

-- delete primemover/fuel combos that we can't handle yet
DELETE FROM existing_plants_860_gen
WHERE prime_mover = 'FC'
OR ( prime_mover = 'OT' AND fuel = 'Gas');

-- now make the table contain only distinct entries for each combo of
-- facility_code-generator_id-prime_mover-cogenerator-fuel
-- start_year and capacity_mw come along for the ride
DROP TABLE IF EXISTS existing_plants_860_gen_tmp;
CREATE TEMPORARY TABLE existing_plants_860_gen_tmp AS 
	SELECT DISTINCT facility_code, generator_id, prime_mover, cogenerator, fuel, start_year, capacity_mw
	FROM existing_plants_860_gen;

DELETE FROM existing_plants_860_gen;

INSERT INTO existing_plants_860_gen
	SELECT * FROM existing_plants_860_gen_tmp;

ALTER TABLE existing_plants_860_gen ADD PRIMARY KEY (facility_code, generator_id, prime_mover, cogenerator, fuel);

-- CORRECT EIA 860 BEFORE 923 JOIN -----------
-- the EIA isn't quite consistent about how they label plants between the two forms
-- so we correct mistakes here before joining

-- a query to show the facility_code-prime_mover-cogenerator-fuel combos
-- in existing_plants_923 but not in existing_plants_860_gen
-- select * from existing_plants_923
-- where (facility_code, prime_mover, cogenerator, fuel) not in 
-- ( SELECT distinct facility_code, prime_mover, cogenerator, fuel from existing_plants_860_gen )

-- these ones were labeled cogen in existing_plants_860_gen but had zero for cogen_thermal_demand_mmbtus_per_mwh
-- only update if we're sure that there wasn't any cogeneration (the last NOT IN)
UPDATE existing_plants_860_gen
SET cogenerator = FALSE
WHERE (facility_code, prime_mover, fuel) IN 
		(SELECT facility_code, prime_mover, fuel
			FROM existing_plants_923
			WHERE cogenerator IS FALSE
			AND (facility_code, prime_mover, fuel) NOT IN 
				(SELECT facility_code, prime_mover, fuel
					FROM existing_plants_923
					WHERE cogenerator IS TRUE));

-- the opposite problem also occurs - combos that cogenerate in existing_plants_923
-- but don't aren't labeled as such in existing_plants_860_gen
UPDATE existing_plants_860_gen
SET cogenerator = TRUE
WHERE (facility_code, prime_mover, fuel) IN 
		(SELECT facility_code, prime_mover, fuel
			FROM existing_plants_923
			WHERE cogenerator IS TRUE
			AND (facility_code, prime_mover, fuel) NOT IN 
				(SELECT facility_code, prime_mover, fuel
					FROM existing_plants_923
					WHERE cogenerator IS FALSE));

-- another problem with the join is that energy_source_1 through 6 are actually not an exhaustive set of fuels
-- because fuels appear in existing_plants_923 that don't appear in energy_source_1 through 6
-- so we'll add entries for fuels that don't appear in existing_plants_860_gen for a facility_code-generator_id-prime_mover-cogenerator combo
-- but do appear in existing_plants_923
-- this won't result in double counting capacity because only one fuel will be chosen for each combo
INSERT INTO existing_plants_860_gen (facility_code, generator_id, prime_mover, cogenerator, fuel, start_year, capacity_mw)
	SELECT facility_code, generator_id, prime_mover, cogenerator,
			fuels_to_be_added.fuel, start_year, capacity_mw
		FROM	( SELECT facility_code, prime_mover, cogenerator, fuel
					FROM existing_plants_923
					WHERE (facility_code, prime_mover, cogenerator)
						IN (SELECT DISTINCT facility_code, prime_mover, cogenerator
								FROM existing_plants_860_gen)
					AND	(facility_code, prime_mover, cogenerator, fuel)
						NOT IN (SELECT DISTINCT facility_code, prime_mover, cogenerator, fuel
								FROM existing_plants_860_gen)
				) as fuels_to_be_added
		-- exclude fuels here in the distinct to only add rows for fuels that DON'T already exist in existing_plants_860_gen
		JOIN ( SELECT DISTINCT facility_code, generator_id, prime_mover, cogenerator, start_year, capacity_mw
				FROM existing_plants_860_gen) as gen_units_table
		USING (facility_code, prime_mover, cogenerator);
						

-- manual corrections....
UPDATE existing_plants_860_gen
SET prime_mover = CASE
	WHEN ( facility_code = 2062 AND prime_mover = 'IC') THEN 'GT'
	ELSE prime_mover
	END;



-- a few more that should exist in the initial EIA 860 table but didn't for various reasons
INSERT INTO existing_plants_860_gen (facility_code, generator_id, prime_mover, cogenerator, fuel, start_year, capacity_mw) VALUES
	(6100, 1, 'PS', false, 'Water', 1984, 351),
	(57281, 3, 'BT', false, 'Geothermal', 2009, 5.3),
	(50760, 1, 'ST', false, 'Geothermal', 1987, 3.6);
					
-- now delete facility_code-generator_id-prime_mover-cogenerator-fuel combos
-- that DIDN'T generate the most electricity for their combo in 2011

DELETE FROM existing_plants_860_gen
WHERE (facility_code, generator_id, prime_mover, cogenerator, fuel)
NOT IN ( SELECT facility_code, generator_id, prime_mover, cogenerator, fuel
		FROM	
		-- find max gen of any fuel type
		(SELECT facility_code, generator_id, prime_mover, cogenerator, max(net_generation_mwh) as net_generation_mwh
			FROM existing_plants_923
			JOIN existing_plants_860_gen USING (facility_code, prime_mover, cogenerator, fuel)
			GROUP BY facility_code, generator_id, prime_mover, cogenerator
		) as max_gen_table
		-- pick out the fuel that generated the most electricity with the join to existing_plants_923
		JOIN existing_plants_923
		USING (facility_code, prime_mover, cogenerator, net_generation_mwh)
		);

-- now check to make sure everything has gone OK by changing the primary key...
-- there should only be a single fuel so fuel is removed from the pkey
ALTER TABLE existing_plants_860_gen DROP CONSTRAINT existing_plants_860_gen_pkey;
ALTER TABLE existing_plants_860_gen ADD PRIMARY KEY (facility_code, generator_id, prime_mover, cogenerator);

-- now join to existing_plants_860_gen, existing_plants_923, and eia_form_860_plant
-- to finish with the EIA data for non-hydro, wind, or solar plants
-- we'll aggregate plants further down once canadian and mexican plants have been added
drop table if exists existing_plants_eia;
create table existing_plants_eia(
	load_area varchar(30) REFERENCES load_areas_usa_can (load_area) ON UPDATE CASCADE,	
	plant_name varchar(100) NOT NULL,
	facility_code int NOT NULL REFERENCES eia_form_860_plant,
	prime_mover varchar(2) NOT NULL,
	cogenerator boolean NOT NULL,
	fuel varchar(20) NOT NULL,
	start_year smallint NOT NULL,
	capacity_mw numeric(5,1) NOT NULL,
	heat_rate NUMERIC(7,3) NOT NULL,
	cogen_thermal_demand_mmbtus_per_mwh NUMERIC(7,3) NOT NULL,
	PRIMARY KEY (facility_code, prime_mover, cogenerator, fuel, start_year)
	);	

SELECT addgeometrycolumn ('usa_can','existing_plants_eia','the_geom',4326,'POINT',2);
CREATE INDEX ON existing_plants_eia USING gist (the_geom);

-- the sum here is to aggregate generator_id
INSERT INTO existing_plants_eia (load_area, plant_name, facility_code, prime_mover, cogenerator,
		fuel, start_year, capacity_mw, heat_rate, cogen_thermal_demand_mmbtus_per_mwh, the_geom)
SELECT 	p.load_area,
		p.plant_name,
		p.facility_code,
		g.prime_mover,
		g.cogenerator,
		g.fuel,
		g.start_year,
		sum(g.capacity_mw),
		m.heat_rate,
		m.cogen_thermal_demand_mmbtus_per_mwh,
		p.the_geom
FROM	eia_form_860_plant p
JOIN	existing_plants_860_gen g USING (facility_code)
JOIN	existing_plants_923 m USING (facility_code, prime_mover, cogenerator, fuel)
WHERE	load_area IS NOT NULL
GROUP BY load_area, plant_name, facility_code, prime_mover, cogenerator, fuel, start_year, heat_rate, cogen_thermal_demand_mmbtus_per_mwh, the_geom;

-- SWITCH doesn't differentiate between binary and steam turbine geothermal yet
-- so switch all existing binary turbines to steam
UPDATE existing_plants_eia SET prime_mover = 'ST' WHERE prime_mover = 'BT' AND fuel = 'Geothermal';


-- ################################# AVG HEAT RATES #################################
-- for mexico and canada, we don't have plant-specific heat rate data
-- so we'll use the capacity-weighted average US values as a good proxy
-- make a table here to hold the values for later use
DROP TABLE IF EXISTS existing_plants_avg_heat_rate;
CREATE TABLE existing_plants_avg_heat_rate(
	prime_mover varchar(2) NOT NULL,
	cogenerator boolean NOT NULL,
	fuel varchar(20) NOT NULL,
	avg_heat_rate NUMERIC(7,3) NOT NULL,
	avg_cogen_thermal_demand_mmbtus_per_mwh NUMERIC(7,3) NOT NULL,
	PRIMARY KEY (prime_mover, cogenerator, fuel));
	
INSERT INTO existing_plants_avg_heat_rate (prime_mover, cogenerator, fuel, avg_heat_rate, avg_cogen_thermal_demand_mmbtus_per_mwh)
SELECT 	prime_mover,
		cogenerator,
		fuel,
		sum(heat_rate * capacity_mw) / sum(capacity_mw) as avg_heat_rate,
		sum(cogen_thermal_demand_mmbtus_per_mwh * capacity_mw) / sum(capacity_mw) as avg_cogen_thermal_demand_mmbtus_per_mwh
FROM	existing_plants_eia
GROUP BY prime_mover, cogenerator, fuel;

-- ################################# CANADA AND MEXICO #################################
-- use ventyx data on generating units in Canada and Baja Mexico Norte,
-- there doesn't appear to be any cogeneration in Baja Mexico Norte, so leave the default false for cogenerator in place
-- use US average heat rate and cogen thermal demand by prime_mover, fuel, cogen

drop table if exists existing_units_canada_mexico;
create table existing_units_canada_mexico(
	load_area varchar(30) FOREIGN KEY (load_area) REFERENCES load_areas_usa_can (load_area) ON UPDATE CASCADE,
	plant_name varchar(100) NOT NULL,
	ventyx_plant_id int NOT NULL,
	generator_id varchar(15) NOT NULL,
	prime_mover varchar(30) NOT NULL,
	cogenerator boolean NOT NULL DEFAULT FALSE,
	fuel varchar(20) NOT NULL,
	start_year smallint,
	capacity_mw numeric(5,1) NOT NULL,
	heat_rate NUMERIC(7,3),
	cogen_thermal_demand_mmbtus_per_mwh NUMERIC(7,3),
	PRIMARY KEY (ventyx_plant_id, generator_id, prime_mover, cogenerator, fuel)
	);	

SELECT addgeometrycolumn ('usa_can','existing_units_canada_mexico','the_geom',4326,'POINT',2);
CREATE INDEX ON existing_units_canada_mexico USING gist (the_geom);

INSERT INTO existing_units_canada_mexico (plant_name, ventyx_plant_id, generator_id,
		prime_mover, fuel, capacity_mw, the_geom)
SELECT	u.plant_name,
		plant_id as ventyx_plant_id,
		unit as generator_id,
		pm_group as prime_mover,
		fuel_type as fuel,
		cap_mw,
		p.the_geom
FROM	ventyx_may_2012.e_units_point u
JOIN	ventyx_may_2012.e_plants_point p using (plant_id)
WHERE	statustype = 'Operating'
AND 	pm_group != 'Fuel Cell'
AND		NOT (pm_group = 'Internal Combustion Turbine' AND fuel_type = 'OTH')
-- we only include the Labrador part of Newfoundland and Labrador in SWITCH, and it's part of Quebec
-- so this where clause makes sure we only get the Labrador part
-- it also makes sure that we get plants off the coast of provinces by using 'state'
-- instead of intersecting directly with shapefiles (except for NL of course... check manually)
AND		( state IN ('AB', 'BC', 'BCN', 'MB', 'NB', 'NS', 'ON', 'PE', 'QC', 'SK')
			OR ( state = 'NL' AND plant_id IN
					(SELECT plant_id
						FROM 	ventyx_may_2012.e_plants_point,
								load_areas_usa_can
						WHERE 	st_intersects(the_geom, polygon_geom)
						AND		state = 'NL') ) )
	;


-- now that we have the correct set of plants from the above query,
-- use the load_areas_usa_can shapefile to place most of the plants in their proper load_area
UPDATE 	existing_units_canada_mexico
SET		load_area = l.load_area
FROM	load_areas_usa_can l
WHERE	st_intersects(the_geom, polygon_geom);

-- a few of the plants are off the coast of the shapefile... label their load_area here
UPDATE  existing_units_canada_mexico u
SET 	load_area = l.load_area
FROM	load_areas_usa_can l, 
		(select ventyx_plant_id,
				min(st_distance_spheroid(the_geom, polygon_geom, 'SPHEROID["WGS 84",6378137,298.257223563]')) as min_distance
			from 	existing_units_canada_mexico u,
					load_areas_usa_can
			WHERE 	u.load_area is NULL
			AND		country in ('Canada', 'Mexico')
			group by ventyx_plant_id) as min_distance_table		
WHERE 	min_distance = st_distance_spheroid(the_geom, polygon_geom, 'SPHEROID["WGS 84",6378137,298.257223563]')
AND		u.ventyx_plant_id = min_distance_table.ventyx_plant_id
AND		u.load_area is NULL
AND		l.country in ('Canada', 'Mexico');

-- add in the foreign key to make sure we've matched everything
ALTER TABLE existing_units_canada_mexico ALTER COLUMN load_area SET NOT NULL;
ALTER TABLE existing_units_canada_mexico ADD CONSTRAINT la_fk FOREIGN KEY (load_area) REFERENCES load_areas_usa_can (load_area) ON UPDATE CASCADE;

-- update ventyx primemovers to SWITCH primemovers
UPDATE existing_units_canada_mexico
SET prime_mover = 
		CASE WHEN 	prime_mover = 'Combined Cycle' THEN 'CC'
			 WHEN	prime_mover in ('Steam Turbine', 'Nuclear Reactor', 'Geothermal') THEN 'ST'
			 WHEN	prime_mover = 'Gas Turbine' THEN 'GT'
			 WHEN	prime_mover = 'Wind Turbine' THEN 'WT'
			 WHEN	prime_mover = 'Internal Combustion Turbine' THEN 'IC'
			 WHEN	prime_mover = 'Photovoltaic' THEN 'PV'
			 WHEN	prime_mover = 'Hydraulic Turbine' THEN 'HY'
			 WHEN	prime_mover = 'Pumped Storage' THEN 'PS'
		END;

-- update ventyx fuels to SWITCH fuels
UPDATE existing_units_canada_mexico
SET fuel = 
		CASE WHEN	fuel in ('NG', 'GAS-OTH', 'WH') THEN 'Gas'
			 WHEN 	fuel = 'OIL-OTH' AND prime_mover = 'GT' THEN 'Gas'
			 WHEN	fuel = 'OIL-LIT' THEN 'DistillateFuelOil'
			 WHEN	fuel = 'OIL-HVY' THEN 'ResidualFuelOil'
			 WHEN 	fuel = 'OIL-OTH' AND prime_mover = 'ST' THEN 'ResidualFuelOil'
			 WHEN	fuel in ('COL', 'COKE', 'BFG') THEN 'Coal'
			 WHEN	fuel = 'GEO' THEN 'Geothermal'
			 WHEN	fuel = 'WND' THEN 'Wind'
			 WHEN	fuel in ('BIO-GAS', 'GAS-LDF') THEN 'Bio_Gas'
			 WHEN	fuel = 'WAS' AND prime_mover = 'IC' THEN 'Bio_Gas'
			 WHEN	fuel = 'WDL' THEN 'Bio_Liquid'
			 WHEN	fuel = 'OTH' AND prime_mover = 'ST' AND plant_name NOT like '%Landfill%' THEN 'Bio_Liquid'
			 WHEN	fuel = 'OTH' AND prime_mover = 'ST' AND plant_name like '%Landfill%' THEN 'Bio_Solid'
			 WHEN	fuel in ('AGR', 'BIO-SOL', 'WDS') THEN 'Bio_Solid'
			 WHEN	fuel = 'WAS' AND prime_mover = 'ST' THEN 'Bio_Solid'
			 WHEN	fuel = 'SOL' THEN 'Solar'
			 WHEN	fuel = 'URA' THEN 'Uranium'
			 WHEN	fuel = 'WAT' THEN 'Water'
			 WHEN	fuel = 'WND' THEN 'Wind'
		END;

-- a few power stations, especially the First Nation stations, are off grid... delete them here
DELETE FROM existing_units_canada_mexico
WHERE plant_name in ('Brochet Powerhouse', 'Lac Brochet Station', 'Ah Sin Heek', 'Anahim Lake', 'Atlin',
	'Bella Bella', 'Dease Lake', 'Eddontenajon', 'Masset (Mas)', 'Sandspit (SPT)', 'Telegraph Creek',
	'Iles de La Madeleine 2', 'Hall Beach', 'Sandy Lake (Hydro One)', 'Sachigo')
OR	plant_name like '%First Nation%';

-- these are out of service or don't exist
DELETE FROM existing_units_canada_mexico
WHERE plant_name in ('Rankine Generating Station', 'Northeast Regional 1 39', 'Eastern Regional 1 38', 'Georgian Bay Regional 1 16');


-- now we need start_year and cogeneration status for all of the plants in Canada and Mexico
-- have to do this part manually as ventyx doesn't have this information
-- print out a spreadsheet of plant_name, generator_id, prime_mover, fuel
-- add add start_year and cogenerator columns manually
copy (SELECT * FROM existing_units_canada_mexico ORDER BY load_area, prime_mover, fuel, plant_name, generator_id)
to '/Volumes/switch/Models/USA_CAN/existing_plants/existing_units_canada_mexico_added_start_year_cogen.txt'
with csv header DELIMITER E'\t'; 


-- copy the filled out table back into postgresql
-- found start year and cogen status for most... the ones that I didn't find are in 'existing_units_canada_mexico_incomplete_info.txt'

-- add the start_year... reference = 2009 TEPPC Generators for Mexico
-- use Canada Electric Power Generating Stations 2000.pdf for many of the plants (last year before it became restricted by the canadian government)
-- and wikipedia's articles on Canadian power stations: http://en.wikipedia.org/wiki/List_of_power_stations_in_Alberta
-- (along with the all the other provinces)
-- windfarm info can be found here: http://www.canwea.ca/farms/wind-farms_e.php
-- ontario info can be found here: http://www.powerauthority.on.ca/current-electricity-contracts/hydroelectric
-- TransAlta plants here: http://www.transalta.com/facilities/plants-operation
-- some alberta plants here: http://www.energy.alberta.ca/Electricity/682.asp

DELETE FROM existing_units_canada_mexico;

copy existing_units_canada_mexico
from '/Volumes/switch/Models/USA_CAN/existing_plants/existing_units_canada_mexico_added_start_year_cogen.txt'
with csv header DELIMITER E'\t'; 


-- update a few prime_mover, fuel, cogen combo to make them SWITCH compliant
-- these plants are small and either unique or contain incorrect data (non-cogen bio liquid for example)
UPDATE existing_units_canada_mexico SET prime_mover = 'IC' WHERE plant_name = 'West Lorne Cogeneration';
UPDATE existing_units_canada_mexico SET prime_mover = 'ST' WHERE fuel = 'Bio_Solid' AND prime_mover in ('GT', 'IC');
UPDATE existing_units_canada_mexico SET cogenerator = TRUE WHERE fuel = 'Bio_Liquid' AND NOT cogenerator;


-- ventyx has the turbine capacity of Churchill Falls hydro very wrong... update it here... all the turbines have the same capacity
UPDATE existing_units_canada_mexico SET capacity_mw = 493.5 WHERE plant_name = 'Churchill Falls';

-- aggregate to facility_code-prime_mover-cogenerator-fuel-start_year level
drop table if exists existing_plants_canada_mexico;
create table existing_plants_canada_mexico(
	load_area varchar(30) NOT NULL REFERENCES load_areas_usa_can (load_area) ON UPDATE CASCADE,	
	plant_name varchar(100) NOT NULL,
	facility_code int NOT NULL,
	prime_mover varchar(2) NOT NULL,
	cogenerator boolean NOT NULL,
	fuel varchar(20) NOT NULL,
	start_year smallint NOT NULL,
	capacity_mw numeric(5,1) NOT NULL,
	heat_rate NUMERIC(7,3) NOT NULL,
	cogen_thermal_demand_mmbtus_per_mwh NUMERIC(7,3) NOT NULL,
	PRIMARY KEY (facility_code, prime_mover, cogenerator, fuel, start_year)
	);	

SELECT addgeometrycolumn ('usa_can','existing_plants_canada_mexico','the_geom',4326,'POINT',2);
CREATE INDEX ON existing_plants_canada_mexico USING gist (the_geom);

-- the sum here is to aggregate generator_id
INSERT INTO existing_plants_canada_mexico (load_area, plant_name, facility_code, prime_mover, cogenerator,
		fuel, start_year, capacity_mw, heat_rate, cogen_thermal_demand_mmbtus_per_mwh, the_geom)
SELECT 	load_area,
		plant_name,
		ventyx_plant_id,
		prime_mover,
		cogenerator,
		fuel,
		start_year,
		sum(capacity_mw),
		avg_heat_rate,
		avg_cogen_thermal_demand_mmbtus_per_mwh,
		the_geom
FROM	existing_units_canada_mexico
JOIN	existing_plants_avg_heat_rate USING (prime_mover, cogenerator, fuel)
GROUP BY load_area, plant_name, ventyx_plant_id, prime_mover, cogenerator, fuel, start_year, avg_heat_rate, avg_cogen_thermal_demand_mmbtus_per_mwh, the_geom;


-- ################################# HYDRO #################################
-- create montly generation profiles for each hydro plant

-- for now, we assume:
-- maximum flow is equal to the nameplate plant capacity
-- minimum flow is negative of the pumped storage capacity, if applicable, or 0.25 * average flow for simple hydro
-- TODO: find better estimates of minimum flow, e.g., by looking through remarks in the USGS datasheets, or looking
--   at the lowest daily average flow in each month.
-- daily average is equal to net historical production of power
-- look here for a good program that can download water flow data: http://www.hec.usace.army.mil/software/hec-dss/hecdssvue-download.htm
-- TODO: estimate net daily energy balance in the reservoir, not via netgen. i.e., avg_flow should be based on the
--   total flow of water (and its potential energy), not the net power generation, which includes losses from 
--   inefficiency on both the generation and storage sides 
--   (we ignore this for now, which is OK if net flow and net gen are both much closer to zero than max flow)
--   This could be done by fitting a linear model of water flow and efficiency to the eia energy consumption and net_gen
--   data and the USGS monthly water flow data, for pumped storage facilities. This model may be improved by looking up
--   the head height for each dam, to link water flows directly to power.

-- first, make a table that has the number of hours in each month for the years we're interested in
DROP TABLE IF EXISTS hours_in_month;
CREATE TABLE hours_in_month(
	historical_year smallint,
	month smallint,
	hours_in_month smallint,
	PRIMARY KEY (historical_year, month) );

-- uses the timepoints table.. see usa_can_load_areas.sql for definition
-- restrict the years to ones for which we have historical generation data
INSERT INTO hours_in_month (historical_year, month, hours_in_month)
	SELECT year, month_of_year, count(*) as hours_in_month
		FROM timepoints
		JOIN (SELECT DISTINCT year from eia_form_923_gen_fuel) g
		USING (year)
		GROUP BY year, month_of_year;
		






DROP TABLE IF EXISTS hydro_monthly_limits_plant;
CREATE TABLE hydro_monthly_limits_plant(
	facility_code_usa int default 0,
	facility_code_canada int default 0,
	prime_mover varchar(2) NOT NULL,
	historical_year smallint NOT NULL,
	month smallint NOT NULL,
	electricity_consumed_mwh numeric(8,0),
	net_generation_mwh numeric(8,0),
	capacity_mw numeric(5,1),
	avg_cap_factor numeric(5,4),
	avg_mw numeric(5,1),
	PRIMARY KEY (facility_code_usa, facility_code_canada, prime_mover, historical_year, month)
);


-- add all historical hydro generation data in the US from 2004 to 2011
-- elec_quantity for pumped hydro storage is in MWh as the data description says
INSERT INTO hydro_monthly_limits_plant (facility_code_usa, prime_mover, historical_year, month, electricity_consumed_mwh, net_generation_mwh)
	SELECT facility_code, prime_mover, year, 1, sum(elec_quantity_jan), sum(netgen_jan)
		FROM eia_form_923_gen_fuel WHERE prime_mover in ('HY', 'PS')
		AND	 ( net_generation_mwh > 1000 OR ( prime_mover = 'PS' AND net_generation_mwh != 0))
		GROUP BY facility_code, prime_mover, year
	UNION
	SELECT facility_code, prime_mover, year, 2, sum(elec_quantity_feb), sum(netgen_feb)
		FROM eia_form_923_gen_fuel WHERE prime_mover in ('HY', 'PS')
		AND	 ( net_generation_mwh > 1000 OR ( prime_mover = 'PS' AND net_generation_mwh != 0))
		GROUP BY facility_code, prime_mover, year
	UNION
	SELECT facility_code, prime_mover, year, 3, sum(elec_quantity_mar), sum(netgen_mar)
		FROM eia_form_923_gen_fuel WHERE prime_mover in ('HY', 'PS')
		AND	 ( net_generation_mwh > 1000 OR ( prime_mover = 'PS' AND net_generation_mwh != 0))
		GROUP BY facility_code, prime_mover, year
	UNION
	SELECT facility_code, prime_mover, year, 4, sum(elec_quantity_apr), sum(netgen_apr)
		FROM eia_form_923_gen_fuel WHERE prime_mover in ('HY', 'PS')
		AND	 ( net_generation_mwh > 1000 OR ( prime_mover = 'PS' AND net_generation_mwh != 0))
		GROUP BY facility_code, prime_mover, year
	UNION
	SELECT facility_code, prime_mover, year, 5, sum(elec_quantity_may), sum(netgen_may)
		FROM eia_form_923_gen_fuel WHERE prime_mover in ('HY', 'PS')
		AND	 ( net_generation_mwh > 1000 OR ( prime_mover = 'PS' AND net_generation_mwh != 0))
		GROUP BY facility_code, prime_mover, year
	UNION
	SELECT facility_code, prime_mover, year, 6, sum(elec_quantity_jun), sum(netgen_jun)
		FROM eia_form_923_gen_fuel WHERE prime_mover in ('HY', 'PS')
		AND	 ( net_generation_mwh > 1000 OR ( prime_mover = 'PS' AND net_generation_mwh != 0))
		GROUP BY facility_code, prime_mover, year
	UNION
	SELECT facility_code, prime_mover, year, 7, sum(elec_quantity_jul), sum(netgen_jul)
		FROM eia_form_923_gen_fuel WHERE prime_mover in ('HY', 'PS')
		AND	 ( net_generation_mwh > 1000 OR ( prime_mover = 'PS' AND net_generation_mwh != 0))
		GROUP BY facility_code, prime_mover, year
	UNION
	SELECT facility_code, prime_mover, year, 8, sum(elec_quantity_aug), sum(netgen_aug)
		FROM eia_form_923_gen_fuel WHERE prime_mover in ('HY', 'PS')
		AND	 ( net_generation_mwh > 1000 OR ( prime_mover = 'PS' AND net_generation_mwh != 0))
		GROUP BY facility_code, prime_mover, year
	UNION
	SELECT facility_code, prime_mover, year, 9, sum(elec_quantity_sep), sum(netgen_sep)
		FROM eia_form_923_gen_fuel WHERE prime_mover in ('HY', 'PS')
		AND	 ( net_generation_mwh > 1000 OR ( prime_mover = 'PS' AND net_generation_mwh != 0))
		GROUP BY facility_code, prime_mover, year
	UNION
	SELECT facility_code, prime_mover, year, 10, sum(elec_quantity_oct), sum(netgen_oct)
		FROM eia_form_923_gen_fuel WHERE prime_mover in ('HY', 'PS')
		AND	 ( net_generation_mwh > 1000 OR ( prime_mover = 'PS' AND net_generation_mwh != 0))
		GROUP BY facility_code, prime_mover, year
	UNION
	SELECT facility_code, prime_mover, year, 11, sum(elec_quantity_nov), sum(netgen_nov)
		FROM eia_form_923_gen_fuel WHERE prime_mover in ('HY', 'PS')
		AND	 ( net_generation_mwh > 1000 OR ( prime_mover = 'PS' AND net_generation_mwh != 0))
		GROUP BY facility_code, prime_mover, year
	UNION
	SELECT facility_code, prime_mover, year, 12, sum(elec_quantity_dec), sum(netgen_dec)
		FROM eia_form_923_gen_fuel WHERE prime_mover in ('HY', 'PS')
		AND	 ( net_generation_mwh > 1000 OR ( prime_mover = 'PS' AND net_generation_mwh != 0))
		GROUP BY facility_code, prime_mover, year
	;

-- there are a few null values in the dataset above... replace them with zeros here
UPDATE hydro_monthly_limits_plant SET electricity_consumed_mwh = 0 WHERE electricity_consumed_mwh IS NULL;
UPDATE hydro_monthly_limits_plant SET net_generation_mwh = 0 WHERE net_generation_mwh IS NULL;


-- the above didn't select out plants that we don't have in the existing_plants_eia table... mainly hydro in alaska and hawaii
-- delete them here
DELETE FROM hydro_monthly_limits_plant
WHERE	(facility_code_usa, prime_mover) NOT IN (SELECT facility_code, prime_mover FROM existing_plants_eia);

-- plant-primemover combos that came online within a certain year will get removed here in the year they came online
-- for all months in which they didn't generate
-- they'll be added back in later with averages from nearby hydro plants
-- only do for non-pumped hydro... no pumped units came online between 2004 and 2011
DELETE FROM hydro_monthly_limits_plant
	WHERE 	(net_generation_mwh = 0 AND prime_mover = 'HY')
	AND		(facility_code_usa, prime_mover, historical_year) IN
		(	SELECT facility_code, prime_mover, min(start_year) as min_start_year
						FROM existing_plants_eia
						WHERE prime_mover = 'HY'
				group by facility_code, prime_mover);

-- now get the plant capacity of the hydro project in the historical year we're looking at
-- hydro capacity doesn't change too much by years, but it makes it easier down the line to tally the online capacity in each year now...
UPDATE 	hydro_monthly_limits_plant p
SET		capacity_mw = sum_cap_mw
FROM (	SELECT 	facility_code, prime_mover, historical_year, sum(capacity_mw) as sum_cap_mw
		FROM	existing_plants_eia,
				(SELECT DISTINCT historical_year from hydro_monthly_limits_plant) as historical_year_table
		WHERE 	prime_mover in ('HY', 'PS')
		AND		start_year <= historical_year
		GROUP BY facility_code, prime_mover, historical_year
		) as s
WHERE	p.facility_code_usa = s.facility_code
AND		p.prime_mover = s.prime_mover
AND		p.historical_year = s.historical_year;


-- now calculate capacity factors for all plant-primemover-historical_year-month combos for which we have data in hydro_monthly_limits_plant
-- a handful of capacity factors are over 1, but most are for small dams and most are not that far over 1, so set them to 1 here
UPDATE 	hydro_monthly_limits_plant p
SET		avg_cap_factor = CASE WHEN ( net_generation_mwh / hours_in_month) / capacity_mw > 1
							THEN 1
							ELSE ( net_generation_mwh / hours_in_month) / capacity_mw
							END
FROM	hours_in_month h
WHERE	h.historical_year = p.historical_year
AND		h.month = p.month;

-- GO FROM HISTORICAL TO FUTURE HYDRO
-- now we have a pretty accurate record of what dams generated what when, in the PAST.
-- we need to input into SWITCH the amount that the dams WOULD HAVE generated in historical years,
-- had the current online capacity been online in the previous years.

-- first, the above data will be missing rows for generators that weren't online yet in the past but are now online
-- fill in these rows here, leaving avg_cap_factor, and avg_mw to be filled in later
INSERT INTO hydro_monthly_limits_plant (facility_code_usa, facility_code_canada, prime_mover, historical_year, month)
	SELECT facility_code_usa, facility_code_canada, prime_mover, historical_year, month
		FROM
		(SELECT facility_code_usa, 0 as facility_code_canada, prime_mover, historical_year, month
		FROM	(select distinct facility_code_usa, prime_mover FROM hydro_monthly_limits_plant) h,
				hours_in_month
		) as all_possible_combos
		FULL OUTER JOIN hydro_monthly_limits_plant
		USING (facility_code_usa, facility_code_canada, prime_mover, historical_year, month)
		WHERE	avg_cap_factor IS NULL;


-- now fill in the avg_cap_factor for dams that were inserted in the above query
-- using the capacity weighted average capacity factor from the load area in which the dam resides
-- only do for non-pumped hydro as the avg_cap_factor for one facility for pumped hydro
-- may not correlate well to other nearby plants due to different usage patterns and upstream flows
UPDATE 	hydro_monthly_limits_plant p
SET		avg_cap_factor = avg_cap_factor_in_load_area
FROM	(SELECT facility_code as facility_code_usa, prime_mover, historical_year, month, avg_cap_factor_in_load_area
			FROM	(SELECT 	load_area,
								prime_mover,
								historical_year,
								month,
								sum(capacity_mw * avg_cap_factor) / sum(capacity_mw) as avg_cap_factor_in_load_area
						FROM 	eia_form_860_plant
						JOIN 	hydro_monthly_limits_plant on (facility_code_usa = facility_code)
						WHERE	avg_cap_factor IS NOT NULL
						AND		prime_mover = 'HY'
						GROUP BY load_area, prime_mover, historical_year, month
						) as la_agg
			JOIN	(SELECT DISTINCT facility_code, prime_mover, load_area
						FROM 	hydro_monthly_limits_plant
						JOIN	existing_plants_eia
						USING	(prime_mover)
						WHERE 	facility_code_usa = facility_code
						AND		prime_mover = 'HY'
						AND		avg_cap_factor IS NULL) as plants_to_update
			USING (load_area, prime_mover)
		) as la_cap
WHERE	avg_cap_factor IS NULL
AND		la_cap.facility_code_usa = p.facility_code_usa
AND		la_cap.prime_mover = p.prime_mover
AND		la_cap.historical_year = p.historical_year
AND		la_cap.month = p.month;
;

-- a very small handful of plant-primemovers weren't updated above...
-- use the average from other years from the same plant-primemover to approximate

-- for PUMPED hydro we need the historical electricity_consumed_mwh and net_generation_mwh
-- which doesn't yet exist for a handful of facility-year combos
-- as the capacity of these facilities didn't change between 2004 and 2011, use the historical averages
UPDATE 	hydro_monthly_limits_plant p
SET		electricity_consumed_mwh = electricity_consumed_mwh_other_years,
		net_generation_mwh = net_generation_mwh_other_years,
		avg_cap_factor = avg_cap_factor_other_years
FROM	(SELECT 	facility_code_usa,
					prime_mover,
					month,
					avg(electricity_consumed_mwh) as electricity_consumed_mwh_other_years,
					avg(net_generation_mwh) as net_generation_mwh_other_years,
					avg(avg_cap_factor) as avg_cap_factor_other_years
			FROM	hydro_monthly_limits_plant
			JOIN	(SELECT 	DISTINCT facility_code_usa, prime_mover
						FROM 	hydro_monthly_limits_plant
						WHERE	avg_cap_factor IS NULL ) as average_these_plants
			USING	(facility_code_usa, prime_mover)
			GROUP BY facility_code_usa, prime_mover, month ) as a
WHERE	a.facility_code_usa = p.facility_code_usa
AND		a.prime_mover = p.prime_mover
AND		a.month = p.month
AND		avg_cap_factor IS NULL;


-- now update the capacity_mw and avg_mw output from historical to future, leaving the cap_factor intact
-- because we're going to assume that if a new turbine was installed, it would have generated with the same cap factor
UPDATE 	hydro_monthly_limits_plant p
SET		capacity_mw = current_cap_mw
FROM 	( SELECT facility_code, prime_mover, sum(capacity_mw) as current_cap_mw
			FROM existing_plants_eia
			WHERE prime_mover in ('HY', 'PS')
			GROUP BY facility_code, prime_mover ) c
WHERE	c.facility_code = p.facility_code_usa
AND		c.prime_mover = p.prime_mover;


-- PUMPED HYDRO
-- for pumped hydro, the avg_mw represents the average mw of generation that come from
-- UPSTREAM water only, NOT including energy or losses resulting from pumping water
-- in other words you can think of avg_mw as the amount of energy added to the system if
-- the upstream water were allowed to flow through the turbine and no pumping was done
-- to determine the net energy from upstream water for pumped hydro projects,
-- two approximations must be made, as the EIA does not give enough data to determine this number directly

-- first, that the total stock of water doesn't change that much from month to month
-- this is more likely to be more true for for pumped hydro than regular hydro because
-- much of the utility of pumped hydro is reducing daily or weekly peaking requirements

-- second, that the efficiency of pumped hydro projects is 74% for all turbines
-- source:  Samir Succar and Robert H. Williams: Compressed Air Energy Storage: Theory, Resources, And Applications For Wind Power, p. 39
-- if this 74% value is changed here, then it should also be changed in generator_info

-- using the above assumptions, do some stock and flow math...
-- the last term represents the pumping losses because on net, the net of pumping is just the losses incurred
-- net_generation_mwh = upstream_water_mwh - electricity_consumed_mwh * ( 1 - pumped_hydro_efficiency )
-- rearrange...
-- upstream_water_mwh = net_generation_mwh + electricity_consumed_mwh * ( 1 - pumped_hydro_efficiency )

UPDATE 	hydro_monthly_limits_plant p
SET		avg_mw = CASE 	WHEN prime_mover = 'HY' THEN capacity_mw * avg_cap_factor
						WHEN prime_mover = 'PS'	THEN ( net_generation_mwh + electricity_consumed_mwh 
											* ( 1 - ( SELECT storage_efficiency FROM generator_info WHERE technology = 'Hydro_Pumped_EP' ) ) )
											/ hours_in_month
							END
FROM	hours_in_month h
WHERE	h.historical_year = p.historical_year
AND		h.month = p.month;

-- the above leaves a few non-pumped and pumped hydro stations having small negative avg_mw in a few months
-- and a few have outputs above their turbine capacities in a few months
-- correct these out here...
UPDATE 	hydro_monthly_limits_plant
SET 	avg_mw = CASE WHEN avg_mw < 0 THEN 0
					  WHEN avg_mw > capacity_mw THEN capacity_mw
					  ELSE avg_mw END;







-- CANADIAN HYDRO------------------------------
-- downloaded Canadian historical hydro data broken down by province and month
-- source: CANSIM table  127-0001 and 127-0002
-- which can be found on the Statistics Canada webpage, http://www5.statcan.gc.ca/cansim/a26 and http://www5.statcan.gc.ca/cansim/a47
-- Prince Edward Island didn't have any columns because they don't have any hydro


-- MUST DO PROPER JOIN WITH PROVINCE ABBREVIATIONS
DROP TABLE IF EXISTS hydro_canada_monthly_historical_import;
CREATE TABLE hydro_canada_monthly_historical_import(
	historical_year smallint,
	month smallint,
	newfoundland_and_labrador bigint,
	nova_soctia bigint,
	new_brunswick bigint,
	quebec bigint,
	ontario bigint,
	manitoba bigint,
	saskatchewan bigint,
	alberta bigint,
	british_columbia bigint,
	yukon bigint,
	northwest_territories bigint,
	nunavut bigint,
	PRIMARY KEY (historical_year, month));
	
copy hydro_canada_monthly_historical_import
from '/Volumes/switch/Models/USA_CAN/existing_plants/canada_hydro_monthly_2004_to_2012.csv'
with csv header;

-- pivot the data
DROP TABLE IF EXISTS hydro_canada_monthly_historical;
CREATE TABLE hydro_canada_monthly_historical(
	province char(2),
	historical_year smallint,
	month smallint,
	net_generation_mwh NUMERIC(10,0),
	capacity_mw NUMERIC(6,1),
	avg_cap_factor NUMERIC(5,4),
	PRIMARY KEY (province, historical_year, month));
	
INSERT INTO hydro_canada_monthly_historical (province, historical_year, month, net_generation_mwh)
	SELECT 'NL', historical_year, month, newfoundland_and_labrador FROM hydro_canada_monthly_historical_import UNION
	SELECT 'NS', historical_year, month, nova_soctia FROM hydro_canada_monthly_historical_import UNION
	SELECT 'NB', historical_year, month, new_brunswick FROM hydro_canada_monthly_historical_import UNION
	SELECT 'QC', historical_year, month, quebec FROM hydro_canada_monthly_historical_import UNION
	SELECT 'ON', historical_year, month, ontario FROM hydro_canada_monthly_historical_import UNION
	SELECT 'MB', historical_year, month, manitoba FROM hydro_canada_monthly_historical_import UNION
	SELECT 'SK', historical_year, month, saskatchewan FROM hydro_canada_monthly_historical_import UNION
	SELECT 'AB', historical_year, month, alberta FROM hydro_canada_monthly_historical_import UNION
	SELECT 'BC', historical_year, month, british_columbia FROM hydro_canada_monthly_historical_import UNION
	SELECT 'YK', historical_year, month, yukon FROM hydro_canada_monthly_historical_import UNION
	SELECT 'NT', historical_year, month, northwest_territories FROM hydro_canada_monthly_historical_import UNION
	SELECT 'NU', historical_year, month, nunavut FROM hydro_canada_monthly_historical_import;

-- get rid of the import table
DROP TABLE IF EXISTS hydro_canada_monthly_historical_import;


-- now get the plant capacity of all of the hydro projects in the province in the historical year we're looking at
-- this is made complicated by the inclusion of Labrador (but not Newfoundland) in the Quebec load area
-- also because Ventyx got the capacity of Churchill Falls quite wrong
-- the first select gets they hydro capacity of each province by year except for NL,
-- and the second select gets it for NL.  

UPDATE hydro_canada_monthly_historical h
SET capacity_mw = total_hydro_cap
FROM
	( SELECT state as province, historical_year, sum(capacity_mw) as total_hydro_cap
		FROM 	(SELECT DISTINCT historical_year from hours_in_month) as historical_year_table,
				existing_plants_canada_mexico
		JOIN 
			(SELECT plant_id as facility_code, state
				FROM 	ventyx_may_2012.e_plants_point
				JOIN	ventyx_may_2012.states_region ON (state=abbrev)
				WHERE 	country = 'Canada' ) as plant_state_table
		USING (facility_code)
		WHERE 	prime_mover = 'HY'
		AND		start_year <= historical_year
		AND		state != 'NL'
		GROUP BY state, historical_year
	UNION
	SELECT state as province, historical_year, sum(CASE WHEN plant_name = 'Churchill Falls' then 493.5 ELSE cap_mw END) as total_hydro_cap
		FROM	ventyx_may_2012.e_units_point u
		JOIN	ventyx_may_2012.e_plants_point p using (plant_id, plant_name),
				(SELECT DISTINCT historical_year from hours_in_month) as historical_year_table
		WHERE state = 'NL'
		AND fuel_type = 'WAT'
		AND statustype = 'Operating'
		GROUP BY state, historical_year
	) as c
WHERE 	h.province = c.province
AND		h.historical_year = c.historical_year;

-- there are more years and provinces in the historical monthly dataset than we simulate in SWITCH 
-- delete 2012 and the northern provinces here
DELETE FROM hydro_canada_monthly_historical WHERE capacity_mw IS NULL;

-- now add average cap factor			
UPDATE hydro_canada_monthly_historical m
SET		avg_cap_factor = CASE WHEN ( net_generation_mwh / hours_in_month) / capacity_mw > 1
							THEN 1
							ELSE ( net_generation_mwh / hours_in_month) / capacity_mw
							END
FROM	hours_in_month h
WHERE	h.historical_year = m.historical_year
AND		h.month = m.month;


-- add canadian hydro to the hydro_monthly_limits_plant table
-- the columns electricity_consumed_mwh and net_generation_mwh aren't filled out here as they're used for the USA only
-- take the present (not the historical) capacity as capacity_mw
-- the grouping by avg_cap_factor is redundant because avg_cap_factor is dependent on province, historical_year, and month

-- Ontario has a pumped hydro station (Sir Adam Beck Pump Generating Station) but it doesn't appear
-- to have much upstream flow as it diverts water from the non-pumped part of Sir Adam Beck dam
-- it's unclear whether the Canadian hydro data includes the pumping electricity or not, but either way the capacity of
-- this pumped storage station is small enough that losses are negligible relative to Ontario's hydro generation
INSERT INTO hydro_monthly_limits_plant ( facility_code_canada, prime_mover, historical_year, month, capacity_mw, avg_cap_factor, avg_mw)
	SELECT	facility_code as facility_code_canada,
			prime_mover,
			historical_year,
			month,
			SUM(e.capacity_mw),
			CASE WHEN prime_mover = 'HY' THEN avg_cap_factor ELSE 0 END as avg_cap_factor,
			CASE WHEN prime_mover = 'HY' THEN SUM(e.capacity_mw) * avg_cap_factor ELSE 0 END as avg_mw
	FROM	existing_plants_canada_mexico e
	JOIN 	load_areas_usa_can USING (load_area)
	JOIN	hydro_canada_monthly_historical ON (primary_state = province)
	WHERE	country = 'Canada'
	AND		prime_mover in ('HY', 'PS')
	GROUP BY facility_code_canada, prime_mover, historical_year, month, avg_cap_factor;

-- the above included the Labrador dams (mainly Churchill Falls), but used Quebec's average monthly flow
-- update to Labrador's flow
UPDATE 	hydro_monthly_limits_plant p
SET		avg_cap_factor = nl.avg_cap_factor,
		avg_mw = p.capacity_mw * nl.avg_cap_factor
FROM	hydro_canada_monthly_historical nl
WHERE	province = 'NL'
AND		nl.historical_year = p.historical_year
AND		nl.month = p.month
AND		facility_code_canada in (select plant_id from ventyx_may_2012.e_plants_point WHERE state = 'NL');

DROP TABLE hours_in_month;





-- MERGE INTO MYSQL EXISTING PLANTS (UPDATE UPON USA_CAN COMPLETION)--------------------
-- NOTE: make sure that there aren't overlaping facility_codes from canmex <--> usa (there aren't at the time of writing)
-- and that the block of project ids between 5000000 and 6000000 aren't taken (also true at the time of writing)
drop table if exists existing_plants_hydro_for_mysql;
CREATE TABLE existing_plants_hydro_for_mysql(
	ep_id serial PRIMARY KEY,
	technology varchar(64) NOT NULL,
	load_area varchar(11) NOT NULL,
	plant_name varchar(100) NOT NULL,
	eia_id int NOT NULL CHECK (eia_id >= 0),
	start_year smallint NOT NULL,
	prime_mover varchar(4) NOT NULL,
	cogen smallint NOT NULL default 0,
	fuel varchar(64)  NOT NULL,
	capacity_MW float NOT NULL,
	heat_rate float default 0,
	cogen_thermal_demand_mmbtus_per_mwh float default 0,
	UNIQUE (plant_name, eia_id, prime_mover, cogen, fuel, start_year)
);

-- give hydro the block of ids starting with 5000000
ALTER SEQUENCE existing_plants_hydro_for_mysql_ep_id_seq RESTART WITH 5000000;

-- USA first
INSERT INTO existing_plants_hydro_for_mysql (technology, load_area, plant_name, eia_id, start_year, prime_mover, fuel, capacity_MW)
	SELECT 	CASE WHEN prime_mover = 'HY' THEN 'Hydro_NonPumped'
				 WHEN prime_mover = 'PS' THEN 'Hydro_Pumped' END as technology,
			wecc_load_areas.load_area,
			replace(replace(replace(plant_name, ' ', '_'), '(', ''), ')', '') as plant_name,
			facility_code as eia_id,
			start_year,
			prime_mover,
			fuel,
			sum(capacity_mw) as capacity_mw
	FROM existing_plants_eia,
		 wecc_load_areas
	WHERE ST_Intersects(polygon_geom, the_geom)
	AND	prime_mover in ('PS', 'HY')
	GROUP BY technology, wecc_load_areas.load_area, plant_name, eia_id, start_year, prime_mover, fuel
	order by load_area, plant_name, prime_mover;

-- Canada next
INSERT INTO existing_plants_hydro_for_mysql (technology, load_area, plant_name, eia_id, start_year, prime_mover, fuel, capacity_MW)
	SELECT 	CASE WHEN prime_mover = 'HY' THEN 'Hydro_NonPumped'
				 WHEN prime_mover = 'PS' THEN 'Hydro_Pumped' END as technology,
			wecc_load_areas.load_area,
			replace(replace(replace(plant_name, ' ', '_'), '(', ''), ')', '') as plant_name,
			facility_code as eia_id,
			start_year,
			prime_mover,
			fuel,
			sum(capacity_mw) as capacity_mw
	FROM existing_plants_canada_mexico,
		 wecc_load_areas
	WHERE ST_Intersects(polygon_geom, the_geom)
	AND	prime_mover in ('PS', 'HY')
	GROUP BY technology, wecc_load_areas.load_area, plant_name, eia_id, start_year, prime_mover, fuel
	order by load_area, plant_name, prime_mover;

	
-- AVERAGE monthly limits
-- now that we've calculated the montly limits for hydro for each historical year,
-- average the values to input the monthly to input into SWITCH
DROP TABLE IF EXISTS hydro_monthly_average_output_mysql;
CREATE TABLE hydro_monthly_average_output_mysql(
	ep_id int NOT NULL REFERENCES existing_plants_hydro_for_mysql,
	month smallint NOT NULL CHECK (month BETWEEN 1 and 12),
	avg_mw numeric(10,5) CHECK (avg_mw BETWEEN 0 AND 10000),
	PRIMARY KEY (ep_id, month)
);

-- USA first			
INSERT INTO hydro_monthly_average_output_mysql (ep_id, month, avg_mw)
	SELECT ep_id, month, avg_capacity_factor_hydro * capacity_mw
	FROM
	(SELECT facility_code_usa as eia_id, prime_mover, month, AVG(avg_mw / capacity_mw) as avg_capacity_factor_hydro
		FROM hydro_monthly_limits_plant
		WHERE facility_code_usa != 0 AND facility_code_canada = 0
		GROUP BY facility_code_usa, prime_mover, month ) as avg_mw_table
	JOIN existing_plants_hydro_for_mysql
	USING (eia_id, prime_mover);
	
-- Canada next			
INSERT INTO hydro_monthly_average_output_mysql (ep_id, month, avg_mw)
	SELECT ep_id, month, avg_capacity_factor_hydro * capacity_mw
	FROM
	(SELECT facility_code_canada as eia_id, prime_mover, month, AVG(avg_mw / capacity_mw) as avg_capacity_factor_hydro
		FROM hydro_monthly_limits_plant
		WHERE facility_code_usa = 0 AND facility_code_canada != 0
		GROUP BY facility_code_canada, prime_mover, month ) as avg_mw_table
	JOIN existing_plants_hydro_for_mysql
	USING (eia_id, prime_mover);



copy (SELECT * FROM existing_plants_hydro_for_mysql ORDER BY load_area, plant_name, prime_mover)
TO '/Volumes/switch/Models/USA_CAN/existing_plants/existing_plants_hydro_for_mysql.csv'
with csv header;

-- the WECC version of SWITCH needs specific years of hydro data to be backwards compatible
-- we'll use the average for any given year, so just populate with the same data from years 2004, 2005, and 2006
copy (SELECT ep_id, year, month, avg_mw FROM hydro_monthly_average_output_mysql,
		(SELECT 2004 as year UNION SELECT 2005 UNION SELECT 2006) as all_years
			ORDER BY ep_id, month)
TO '/Volumes/switch/Models/USA_CAN/existing_plants/hydro_monthly_average_output_mysql.csv'
with csv header;





-- ------------------------
-- NOT DONE YET!!!!!!!!!!!!!!!

-- aggregate the plants as much as possible and convert names to SWITCH names
-- all units in MW, MWh and MBtu terms

drop table if exists existing_plant_technologies;
create table existing_plant_technologies (
	technology varchar(64),
	fuel varchar(64),
	primemover varchar(4),
	cogen boolean,
	PRIMARY KEY (fuel, primemover, cogen),
	INDEX tech (technology) );
	
insert into existing_plant_technologies (technology, fuel, primemover, cogen) values
	('DistillateFuelOil_Combustion_Turbine_EP', 'DistillateFuelOil', 'GT', 0),
	('DistillateFuelOil_Internal_Combustion_Engine_EP', 'DistillateFuelOil', 'IC', 0),
	('Gas_Steam_Turbine_EP', 'Gas', 'ST', 0),
	('Gas_Steam_Turbine_Cogen_EP', 'Gas', 'ST', 1),
	('Gas_Combustion_Turbine_EP', 'Gas', 'GT', 0),
	('Gas_Combustion_Turbine_Cogen_EP', 'Gas', 'GT', 1),
	('Gas_Internal_Combustion_Engine_EP', 'Gas', 'IC', 0),
	('Gas_Internal_Combustion_Engine_Cogen_EP', 'Gas', 'IC', 1),
	('CCGT_EP', 'Gas', 'CC', 0),
	('CCGT_Cogen_EP', 'Gas', 'CC', 1),
	('Coal_Steam_Turbine_EP', 'Coal', 'ST', 0),
	('Coal_Steam_Turbine_Cogen_EP', 'Coal', 'ST', 1),
	('Nuclear_EP', 'Uranium', 'ST', 0),
	('Geothermal_EP', 'Geothermal', 'ST', 0),
	('Geothermal_EP', 'Geothermal', 'BT', 0),
	('Wind_EP', 'Wind', 'WND', 0),
	('Hydro_NonPumped', 'Water', 'HY', 0),
	('Hydro_Pumped', 'Water', 'PS', 0),
	('Bio_Gas_Internal_Combustion_Engine_EP', 'Bio_Gas', 'IC', 0),
	('Bio_Gas_Internal_Combustion_Engine_Cogen_EP', 'Bio_Gas', 'IC', 1),
	('Bio_Gas_Steam_Turbine_EP', 'Bio_Gas', 'ST', 0),
	('Bio_Liquid_Steam_Turbine_Cogen_EP', 'Bio_Liquid', 'ST', 1),
	('Bio_Solid_Steam_Turbine_EP', 'Bio_Solid', 'ST', 0),
	('Bio_Solid_Steam_Turbine_Cogen_EP', 'Bio_Solid', 'ST', 1)
	;


drop table if exists existing_plants_agg;
CREATE TABLE existing_plants_agg(
	ep_id mediumint unsigned PRIMARY KEY AUTO_INCREMENT,
	technology varchar(64) NOT NULL,
	load_area varchar(11) NOT NULL,
	plant_name varchar(64) NOT NULL,
	eia_id varchar(64) default 0,
	start_year year(4) NOT NULL,
	primemover varchar(4) NOT NULL,
	cogen boolean NOT NULL,
	fuel varchar(64)  NOT NULL,
	capacity_MW float NOT NULL,
	heat_rate float default 0,
	cogen_thermal_demand_mmbtus_per_mwh float default 0,
	UNIQUE (plant_name, eia_id, primemover, cogen, fuel, start_year)
);

-- add existing US windfarms
insert into existing_plants_agg (technology, load_area, plant_name, eia_id, start_year,
								primemover, cogen, fuel, capacity_MW, heat_rate, cogen_thermal_demand_mmbtus_per_mwh)
select 	'Wind_EP' as technology,
		load_area,
		concat('Wind_EP', '_', 3tier.windfarms_existing_info_wecc.windfarm_existing_id) as plant_name,
		0 as eia_id,
		year_online as start_year,
		'WND' as primemover,
		0 as cogen,
		'Wind' as fuel,
		capacity_MW,
		0 as heat_rate,
		0 as cogen_thermal_demand_mmbtus_per_mwh
from 	3tier.windfarms_existing_info_wecc;

-- add existing Canada windfarms
-- made in script 'canadian_wind.sql' - see this script to change existing canadian wind
load data local infile
	'/Volumes/switch/Models/GIS/Canada_Wind_AWST/windfarms_canada_existing_info.csv'
	into table existing_plants_agg
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines
	(technology, load_area, plant_name, eia_id, start_year, primemover, cogen, fuel, capacity_mw, heat_rate, cogen_thermal_demand_mmbtus_per_mwh);


-- add hydro to existing plants
-- we don't define an id for canadian plants (default 0) - they do have a name at least 
insert into existing_plants_agg (technology, load_area, plant_name, eia_id, start_year,
								primemover, cogen, fuel, capacity_MW, heat_rate, cogen_thermal_demand_mmbtus_per_mwh)
	select 	distinct
			technology,
			load_area,
			plant_name,
			eia_id,
			start_year,
			primemover,
			0 as cogen,
			'Water' as fuel,
			capacity_mw,
			0 as heat_rate,
			0 as cogen_thermal_demand_mmbtus_per_mwh
	from hydro_monthly_limits
	join existing_plant_technologies using (primemover);
  

-- USA existing plants - wind and hydro excluded
insert into existing_plants_agg (technology, load_area, plant_name, eia_id, start_year,
								primemover, cogen, fuel, capacity_MW, heat_rate, cogen_thermal_demand_mmbtus_per_mwh)
	select 	technology,
			load_area,
  			replace(plntname, " ", "_") as plant_name,
  			plntcode as eia_id,
  			start_year,
			primemover,
			cogen,
  			fuel, 
			capacity_MW,
			heat_rate,
			cogen_thermal_demand_mmbtus_per_mwh
	from	existing_plants join existing_plant_technologies using (primemover, fuel, cogen);

	
-- add Canada and Mexico
insert into existing_plants_agg (technology, load_area, plant_name, eia_id, start_year,
								primemover, cogen, fuel, capacity_MW, heat_rate, cogen_thermal_demand_mmbtus_per_mwh)
	select 	technology,
			load_area,
  			replace(name, " ", "_") as plant_name,
  			0 as eia_id,
   			start_year,
 			primemover,
  			cogen, 
  			fuel,
  			capacity_MW,
  			heat_rate,
  			cogen_thermal_demand_mmbtus_per_mwh
  from canmexgen join existing_plant_technologies using (fuel, primemover, cogen);
  
