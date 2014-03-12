-- imports and massages the biomass supply curve data from the POLYSIS model.
-- this data is from 2007 and is used in NEMS (in perhaps slightly updated form)

-- also adds Municipal Solid Waste from Nathan Parker's work at UC Davis (see futher below for the import)
-- as the POLYSIS dataset doesn't have this feedstock
-- his dataset is a static picture for 2020... we'll add this as a constant to all the different years from the POLYSIS model

-- the POLYSIS dataset has many different scenarios... descriptions of these can be found in the excel spreadsheet
-- /Volumes/1TB_RAID/Models/GIS/Biomass_Resource_Supply_Module_NEMS_2007/EIA\ Dataset/EIA\ Scenarios\ List.xls
-- the first letter of each scenario (generally in caps) denotes which energy demand and crop productivity scenario we're looking at
-- whereas the second letter of each scenario (generally in lower case) denotes the price level of each model run
-- from $20/t to $100/t in $5/t steps... this is 2007 and the dollars seem to be current to that year, so we'll assume that this data is in $2007

-- to import all of the data from all of the scenarios, I opened up the csv that contains data for all the scenarios
-- /Volumes/1TB_RAID/Models/GIS/Biomass_Resource_Supply_Module_NEMS_2007/EIA2/SMEIAREGP.CSV
-- to format correctly for the import, do search and replace in bbedit for
-- ',([A-Z,a-z]*) ([A-Z,a-z]*),' to ',\1_\2,' (without the single quotes) to make names with underscores instead of spaces for each of the crop types
-- ' ' to '' to delete unnecessary spaces (takes a while)
-- ',$' to '' to delete the commas at the end of the line
-- '^Sim.*\r' to '' to remove unnecessary headers (copy the header such that you can reinsert in after the search and replace)
-- '^.Allunits.*\r' to '' to remove units declarations


-- units in the supply curve are: 'million dry tons except for corn which is in million bushels'
-- soybeans are also in million bushels
-- there are 39.36 bushels of corn in a metric ton (http://www.smallgrains.org/springwh/June03/weights/weights.htm)
-- there are 36.74 bushels of soybean in a metric ton (http://www.ussec.org/resources/conversions.html)

-- also, conversion efficiencies from dry ton to MMBtu can be found in
-- Volumes/1TB_RAID/Models/GIS/Biomass_Resource_Supply_Module_NEMS_2007/EIA\ Dataset/BtuFeedstock.xls


-- IMPORT TO POSTGRESQL --------------------------------------------
-- First, import the Agricultural Statistical Districts (ASD) shapefile to postgresql from the command line
-- shp2pgsql -s 4326 /Volumes/1TB_RAID/Models/GIS/Biomass_Resource_Supply_Module_NEMS_2007/POLYSIS_Shapefiles/POLYSIS.dbf biomass_asd_polygons | psql -h switch-db2.erg.berkeley.edu -U jimmy -d switch_gis

-- create a geometry index for easy intersection queries later
CREATE INDEX Biomass_ASDs_geom_index
  ON biomass_asd_polygons
  USING gist
  (the_geom);
  
drop table if exists biomass_polysis_supply_curve_import;
create table biomass_polysis_supply_curve_import(
	simulation_id character(2),
	biomass_type character varying(11),
	asd_id integer,
	quantity_2006 double precision,
	quantity_2007 double precision,
	quantity_2008 double precision,
	quantity_2009 double precision,
	quantity_2010 double precision,
	quantity_2011 double precision,
	quantity_2012 double precision,
	quantity_2013 double precision,
	quantity_2014 double precision,
	quantity_2015 double precision,
	quantity_2016 double precision,
	quantity_2017 double precision,
	quantity_2018 double precision,
	quantity_2019 double precision,
	quantity_2020 double precision,
	quantity_2021 double precision,
	quantity_2022 double precision,
	quantity_2023 double precision,
	quantity_2024 double precision,
	quantity_2025 double precision,
	quantity_2026 double precision,
	quantity_2027 double precision,
	quantity_2028 double precision,
	quantity_2029 double precision,
	quantity_2030 double precision,
	primary key (simulation_id, biomass_type, asd_id)
);

CREATE INDEX simulation_id_idx on biomass_polysis_supply_curve_import (simulation_id);

copy biomass_polysis_supply_curve_import
from '/Volumes/1TB_RAID/Models/GIS/Biomass_Resource_Supply_Module_NEMS_2007/EIA2/SMEIAREGP.CSV'
with csv header;

alter table biomass_polysis_supply_curve_import
add column price_per_dry_ton integer;


-- extract the prices from the simulation_id
drop table if exists price_id_table;
create temporary table price_id_table(
	simulation_id character(2) primary key, 
	price int);
	
insert into price_id_table (simulation_id)
select distinct simulation_id from biomass_polysis_supply_curve_import;

update 	price_id_table
set price = price_conversion
from (select 	simulation_id,
		CASE
			WHEN substring(simulation_id FROM 2 FOR 1) like 'a' THEN 20
			WHEN substring(simulation_id FROM 2 FOR 1) like 'b' THEN 25
			WHEN substring(simulation_id FROM 2 FOR 1) like 'c' THEN 30
			WHEN substring(simulation_id FROM 2 FOR 1) like 'd' THEN 35
			WHEN substring(simulation_id FROM 2 FOR 1) like 'e' THEN 40
			WHEN substring(simulation_id FROM 2 FOR 1) like 'f' THEN 45
			WHEN substring(simulation_id FROM 2 FOR 1) like 'g' THEN 50
			WHEN substring(simulation_id FROM 2 FOR 1) like 'h' THEN 55
			WHEN substring(simulation_id FROM 2 FOR 1) like 'i' THEN 60
			WHEN substring(simulation_id FROM 2 FOR 1) like 'j' THEN 65
			WHEN substring(simulation_id FROM 2 FOR 1) like 'k' THEN 70
			WHEN substring(simulation_id FROM 2 FOR 1) like 'l' THEN 75
			WHEN substring(simulation_id FROM 2 FOR 1) like 'm' THEN 80
			WHEN substring(simulation_id FROM 2 FOR 1) like 'n' THEN 85
			WHEN substring(simulation_id FROM 2 FOR 1) like 'o' THEN 90
			WHEN substring(simulation_id FROM 2 FOR 1) like 'p' THEN 95
 			WHEN substring(simulation_id FROM 2 FOR 1) like 'q' THEN 100
		END as price_conversion
		from price_id_table) as tmp
where tmp.simulation_id = price_id_table.simulation_id;

update biomass_polysis_supply_curve_import
set price_per_dry_ton = price_id_table.price
from price_id_table
where biomass_polysis_supply_curve_import.simulation_id = price_id_table.simulation_id;

  					


-- make the final table
-- NOTE: mmbtu = million BTU... it's a stupid convention to put two 'm's when they mean one. (m = lower case form of M = 10^6)
drop table if exists biomass_polysis_supply_curve;
create table biomass_polysis_supply_curve(
	polysis_simulation_id char(1),
	asd_id int,
	biomass_type character varying(11),
	price_per_dry_ton float,
	year int,
	quantity_million_dry_tons_per_year float,
	price_dollars_per_mmbtu float,
	total_mmbtu_per_year float,
	PRIMARY KEY (polysis_simulation_id, asd_id, biomass_type, year, price_per_dry_ton)
	);

COMMENT on COLUMN biomass_polysis_supply_curve.polysis_simulation_id IS 'energy demand and crop productivity scenario... the price levels are specified by price_per_dry_ton instead of a letter (as is done in the import csv)';
	
	
-- now do some fancyish pivoting of the import table to insert all of the supply curve data


-- this is a dummy function that will excecute an sql statement inserted into it in the form of text
-- we'll create this text string below by concating parts of an insert statement together
-- with a variable that runs through all of the years we're interested in
CREATE OR REPLACE FUNCTION exec(text) RETURNS text AS $$ BEGIN EXECUTE $1; RETURN $1; END $$ LANGUAGE plpgsql;

-- create the year-looping function
CREATE OR REPLACE FUNCTION pivot_biomass() RETURNS void AS $$

	declare year_var integer;
	
    BEGIN

	-- the loop goes from year 2006 to 2030
	select 2006 into year_var;

	LOOP

		-- we must use PERFORM instead of select here because select will return the text string of the insert statement, which throws an error
		-- and we don't need it printed out (all we need is for the string to be fed through exec() to be executed
		PERFORM exec(
	    		'INSERT INTO biomass_polysis_supply_curve (polysis_simulation_id, asd_id, biomass_type, price_per_dry_ton, year, quantity_million_dry_tons_per_year) '
	    		|| 'select substring(simulation_id FROM 1 FOR 1) as polysis_simulation_id, asd_id, biomass_type, price_per_dry_ton, '
	  			|| year_var
	  			|| 'as year, CASE WHEN biomass_type like ''Corn_Prdctn'' THEN quantity_'
				|| year_var
	  			|| ' / 39.36 WHEN biomass_type like ''Soyb_Prdctn'' THEN quantity_'
				|| year_var
				|| ' / 36.74 ELSE quantity_'
				|| year_var
				|| ' END as quantity_million_dry_tons_per_year FROM biomass_polysis_supply_curve_import'
		);

		select year_var + 1 into year_var;

	EXIT WHEN year_var > 2030;
	END LOOP;

    END;
$$ LANGUAGE plpgsql;

-- excute the insert statements
-- took about 10 min total
select pivot_biomass();

-- clean up
drop function pivot_biomass();
drop function exec(text);


-- they ran polysis in nominal dollars(!) from 2007 to 2016, then in $2016 from then on  
-- see: /Volumes/1TB_RAID/Models/GIS/Biomass_Resource_Supply_Module_NEMS_2007/EIA\ Dataset/Bill\ Morrow\'s\ biomass\ supply\ documentation.doc
-- using the standard inflation rate of 3% per year, we correct the prices to real $2007.
-- takes another ~10min
update biomass_polysis_supply_curve
set price_per_dry_ton = price_per_dry_ton * ( CASE WHEN year < 2016 THEN 0.97 ^ (year - 2007)
											ELSE 0.97 ^ (2016 - 2007) END ) ;

-- convert dry tons to mmbtu using the assumptions in
-- Volumes/1TB_RAID/Models/GIS/Biomass_Resource_Supply_Module_NEMS_2007/EIA\ Dataset/BtuFeedstock.xls
-- all quantities in the import are in million dry tonnes (hence the 1000000 below) ... convert them to million Btu here
update biomass_polysis_supply_curve
set price_dollars_per_mmbtu = 
	price_per_dry_ton /
	CASE
		WHEN biomass_type like 'Switchgrass' then 14.68
		WHEN biomass_type like 'Forest_Resd' then 15.07
		WHEN biomass_type like 'Forest_Thin' then 15.07
		WHEN biomass_type like 'Corn_Prdctn' then 19.56
		WHEN biomass_type like 'Corn_Stover' then 14.31
		WHEN biomass_type like 'Wheat_Straw' then 13.56
		WHEN biomass_type like 'Soyb_Prdctn' then 14.11
	END;

update biomass_polysis_supply_curve
set total_mmbtu_per_year = 
	quantity_million_dry_tons_per_year * 1000000 * 
	CASE
		WHEN biomass_type like 'Switchgrass' then 14.68
		WHEN biomass_type like 'Forest_Resd' then 15.07
		WHEN biomass_type like 'Forest_Thin' then 15.07
		WHEN biomass_type like 'Corn_Prdctn' then 19.56
		WHEN biomass_type like 'Corn_Stover' then 14.31
		WHEN biomass_type like 'Wheat_Straw' then 13.56
		WHEN biomass_type like 'Soyb_Prdctn' then 14.11
	END;



-- AGGREGATE TO LOAD AREAS --------------------------------------------

-- divides up agricultural stastical districts (ASDs) by land area in each load area
-- in order to partition ASD biomass potentials into each load area.
-- there may be tiny amounts of shapefile overlap between the counties and the load areas that aren't in the US,
-- so we don't include non-US biomass potentials because the data is only for the US

-- NOTE: should use geography instead of geometry here to do areas...
-- the error is likely minimal because ASDs and load aren't that large and we're taking area ratios, not absolute areas
drop table if exists biomass_polysis_asd_to_load_area;
create table biomass_polysis_asd_to_load_area(
	load_area character varying(11),
	asd_id integer,
	asd_area double precision,
	asd_area_fraction_in_load_area double precision,
	PRIMARY KEY (load_area, asd_id)
	);

insert into biomass_polysis_asd_to_load_area (load_area, asd_id, asd_area, asd_area_fraction_in_load_area)
	select	load_area,
			biomass_asd_polygons.polysis as asd_id,
			area(biomass_asd_polygons.the_geom) as asd_area,
			area(intersection(biomass_asd_polygons.the_geom, wecc_load_areas.polygon_geom))/area(biomass_asd_polygons.the_geom) as asd_area_fraction_in_load_area
	from 	biomass_asd_polygons,
			wecc_load_areas
	where  	intersects(wecc_load_areas.polygon_geom, biomass_asd_polygons.the_geom)
	and		wecc_load_areas.polygon_geom && biomass_asd_polygons.the_geom
	and 	load_area not like 'MEX%'
	and 	load_area not like 'CAN%';


-- sum together all of the biomass potentials from each asd by load area
-- to get the total biomass potential by feedstock in each load area

-- NOTE: we're using scenario A, the base case scenario as our biomass potentials
-- the other scenarios have increasing levels of technological advancement and extra energy demand
-- Bill Morrow from LBNL (the source of the data) suggested that these may be too optimistic to constitute a baseline scenario
drop table if exists biomass_solid_supply_curve_by_load_area;
create table biomass_solid_supply_curve_by_load_area(
	load_area char(11),
	biomass_type char(20),
	year int,
	price_dollars_per_ton double precision,
	marginal_tons_per_year double precision,
	total_tons_per_year double precision,
	price_dollars_per_mmbtu double precision,
	marginal_mmbtu_per_year double precision,
	total_mmbtu_per_year double precision,
	PRIMARY KEY (load_area, biomass_type, year, price_dollars_per_ton)
);

CREATE INDEX bio_la ON biomass_solid_supply_curve_by_load_area (load_area);
CREATE INDEX bio_type ON biomass_solid_supply_curve_by_load_area (biomass_type);
CREATE INDEX bio_yr ON biomass_solid_supply_curve_by_load_area (year);
CREATE INDEX bio_price ON biomass_solid_supply_curve_by_load_area (price_dollars_per_ton);


-- solid biomass supply curve ( will be used in dedicated turbines and (eventually) to cofire )
-- Soyb_Prdctn and Corn_Prdctn will likely go to biofuels (or food!) in the future, so we exclude them here from the supply curve
insert into biomass_solid_supply_curve_by_load_area
	(load_area, biomass_type, year, price_dollars_per_ton, total_tons_per_year, price_dollars_per_mmbtu, total_mmbtu_per_year)
select * from (
	SELECT	load_area,
			biomass_type,
			year,
			price_per_dry_ton as price_dollars_per_ton,
			sum( quantity_million_dry_tons_per_year * 1000000 * asd_area_fraction_in_load_area ) as total_tons_per_year,
			price_dollars_per_mmbtu,
			sum( total_mmbtu_per_year * asd_area_fraction_in_load_area  ) as total_mmbtu_per_year
	from	biomass_polysis_asd_to_load_area
	join	biomass_polysis_supply_curve using (asd_id)
	where	polysis_simulation_id = 'A'
	and		biomass_type <> 'Soyb_Prdctn'
	and		biomass_type <> 'Corn_Prdctn'
	group by load_area, biomass_type, year, price_per_dry_ton, price_dollars_per_mmbtu
	) as polysis_supply_curve
where total_mmbtu_per_year >= 100;


-- NATHAN PARKER'S UC DAVIS BIOMASS SUPPLY CURVES -----------------------------
-- this data is from Nathan Parkers's Ph.D work at UC Davis
-- his thesis describing the data can be found in /Volumes/1TB_RAID/Models/GIS/Biomass_UC_Davis_2011_Nathan_Parker/Final\ Dissertation.pdf

-- here is some explanation of his data from an email he sent:
-- I'm [NATHAN] attaching a xlsx file with 6 columns and two shapefiles (county
-- and places).  The columns are as follows...
-- 
-- qid | type | price_lev | quant | State fips | price
-- 
-- qid - Location identifier, generally this is the fips code preceded by
-- S for county sources, M for municipal sources and there may be some
-- odd items in there as well.  The municipal sources should link to the
-- places shapefile (you might need to change M to D to get it to work)
-- while the county sources link to the county shapefile.
-- 
-- type - this is the feedstock type.  Some codes that aren't easy to guess... hec=switchgrass (herbaceous energy crop), ovw=orchard and vineyard waste (woody prunnings)
-- price_lev - discrete price level identifier, I've added the price column to be more explicit.
-- quant - the marginal quantity available at the given location and price level (dry tons (US) per year)
-- State fips - the state fips code for aggregation purposes
-- price - the price of biomass for the given price level ($/dry ton)

-- First, import the Agricultural Statistical Districts (ASD) shapefile to postgresql from the command line
-- this data isn't in a standard srid so we'll have to add it here
-- got info about this srid from http://spatialreference.org/ref/esri/102004/proj4js/
-- and https://casil.ucdavis.edu/scm/viewvc.php/make-db/trunk/configure.mk?r1=7&r2=24&pathrev=24&sortby=date&root=bioenergy
insert into spatial_ref_sys (srid, auth_name, auth_srid, srtext, proj4text) values
	(102004, 'ESRI', 102004,
	'PROJCS["USA_Contiguous_Lambert_Conformal_Conic",GEOGCS["GCS_North_American_1983",DATUM["D_North_American_1983",SPHEROID["GRS_1980",6378137,298.257222101]],PRIMEM["Greenwich",0],UNIT["Degree",0.017453292519943295]],PROJECTION["Lambert_Conformal_Conic"],PARAMETER["False_Easting",0],PARAMETER["False_Northing",0],PARAMETER["Central_Meridian",-96],PARAMETER["Standard_Parallel_1",33],PARAMETER["Standard_Parallel_2",45],PARAMETER["Latitude_Of_Origin",39],UNIT["Meter",1]]',
	'+proj=lcc +lat_1=33 +lat_2=45 +lat_0=39 +lon_0=-96 +x_0=0 +y_0=0 +ellps=GRS80 +datum=NAD83 +units=m +no_defs');

-- shp2pgsql -s 102004 /Volumes/1TB_RAID/Models/GIS/Biomass_UC_Davis_2011_Nathan_Parker/place.dbf biomass_ucd_places | psql -h switch-db2.erg.berkeley.edu -U jimmy -d switch_gis

-- now do the SRID transformation to make everything line up with other SWITCH shapefiles
SELECT AddGeometryColumn ('public','biomass_ucd_places','place_geom',4326,'POINT',2);

update biomass_ucd_places
set place_geom = ST_Transform(the_geom, 4326);

alter table biomass_ucd_places drop column the_geom;
delete from geometry_columns where f_table_name = 'biomass_ucd_places' and srid <> 4326;

CREATE INDEX biomass_ucd_places_index
  ON biomass_ucd_places
  USING gist
  (place_geom);

-- also, as per Nathan's email above, update the 'D' at the start of the qid to an 'M'
update biomass_ucd_places set qid = overlay(qid placing 'M' from 1 for 1);
alter table biomass_ucd_places rename column qid to location_id;


-- now import the supply curve data
drop table if exists biomass_ucd_supply_curve_import;
create table biomass_ucd_supply_curve_import(
	location_id character varying(8),
	biomass_type character varying(20),
	price_level_id character varying(10),
	quantity_dry_tons float,
	state_fips character(2),
	price_dollars_per_dry_ton float,
	PRIMARY KEY (location_id, biomass_type, price_dollars_per_dry_ton)
);

copy biomass_ucd_supply_curve_import
from '/Volumes/1TB_RAID/Models/GIS/Biomass_UC_Davis_2011_Nathan_Parker/all\ baseline\ supplies.csv'
with csv header;


-- in this dataset, the biomass_ucd_places shapefile corresponds to feedstocks of municipal solid waste (MSW), animal fat, and grease
-- animal fat and grease aren't likely to be used in the electric power sector (probably they will be used for biofuels)
-- so they're excluded here (by biomass_type like 'msw%')
-- this document http://www.p2pays.org/ref/11/10603.pdf (also in the Biomass_UC_Davis_2011_Nathan_Parker folder)
-- gives values for the energy content of msw_paper and msw_wood as 7000 and 8000 Btu/lb respectively
-- so to get from these values to million btu/metric ton, multiply by 2.20462262 lbs/kg and 10^3 kg/t and 10-6 Mbtu/btu

-- also, we assume that the same potential for these biomass feedstocks is the same from year to year
-- the values in the UC Davis supply curve are marginal values, so they're inserted in the marginal_mmbtu_per_year column here
insert into biomass_solid_supply_curve_by_load_area
	(load_area, biomass_type, year, price_dollars_per_ton, marginal_tons_per_year, price_dollars_per_mmbtu, marginal_mmbtu_per_year)
select 	load_area,
		biomass_type,
		year,
		price_dollars_per_ton,
		marginal_tons_per_year,
		price_dollars_per_mmbtu,
		marginal_mmbtu_per_year
	from
	(select distinct year from biomass_solid_supply_curve_by_load_area) as year_table,
	(select load_area,
			biomass_type,
			price_dollars_per_dry_ton as price_dollars_per_ton,
			sum( quantity_dry_tons ) as marginal_tons_per_year,
			price_dollars_per_dry_ton /
				CASE	WHEN biomass_type = 'msw_paper' THEN 7000 * 2.20462262 * 0.001
						WHEN biomass_type = 'msw_wood'	THEN 8000 * 2.20462262 * 0.001
				END as price_dollars_per_mmbtu,
			sum( quantity_dry_tons *
				CASE	WHEN biomass_type = 'msw_paper' THEN 7000 * 2.20462262 * 0.001
						WHEN biomass_type = 'msw_wood'	THEN 8000 * 2.20462262 * 0.001
				END) as marginal_mmbtu_per_year
	from 	wecc_load_areas,
			biomass_ucd_supply_curve_import
	join 	biomass_ucd_places using (location_id)
	where 	intersects(wecc_load_areas.polygon_geom, biomass_ucd_places.place_geom)
	and 	wecc_load_areas.polygon_geom && biomass_ucd_places.place_geom
	and biomass_type in ('msw_paper', 'msw_wood')
	group by load_area, biomass_type, price_dollars_per_ton, price_dollars_per_mmbtu
	) as msw_uc_davis_table
where marginal_mmbtu_per_year > 100
order by load_area, biomass_type, year, price_dollars_per_ton, price_dollars_per_mmbtu;

-- check to see if we've double counted anything from the intersection (which would happen if any of the points were on a line).
-- If nothing comes up here, proceed down the script!
-- I also looked at the map to see that we didn't lose cities in the pacific ocean... only one really minor town in Washington... no big deal
-- select * from wecc_load_areas, biomass_ucd_places
-- where 	intersects(st_boundary(wecc_load_areas.polygon_geom), biomass_ucd_places.place_geom)
-- and 	st_boundary(wecc_load_areas.polygon_geom) && biomass_ucd_places.place_geom;


-- HACK AT MEXICAN BIOMASS (MSW ONLY)-----------------------
-- don't know of any data on Mexican biomass supply... they don't have that much in Baja though
-- however they do make MSW, so we'll assume that the supply curve is shaped like the US
-- but the potential will be scaled by GDP and population
-- (the amount of MSW depends on the amount of stuff produced/bought, which depends on GDP and population)

-- mexico baja population: http://en.wikipedia.org/wiki/List_of_Mexican_states_by_GDP (Baja in 2007 --> $32,161,000,000 / 2,846,500 people = $11298.44/person)
-- and US:http://www.prb.org/Publications/Datasheets/2007/2007WorldPopulationDataSheet.aspx
-- US 2007 GDP estimate is $43800 (http://www.photius.com/rankings/economy/gdp_per_capita_2007_0.html)

-- the cast(.. as numeric) makes it such that postgresql doesn't do integer math
insert into biomass_solid_supply_curve_by_load_area
	(load_area, biomass_type, year, price_dollars_per_ton, marginal_tons_per_year, price_dollars_per_mmbtu, marginal_mmbtu_per_year)
select 	'MEX_BAJA' as load_area,
		biomass_type,
		year,
		price_dollars_per_ton,
		marginal_tons_per_year * scale_mex_baja_to_usa as marginal_tons_per_year,
		price_dollars_per_mmbtu,
		marginal_mmbtu_per_year * scale_mex_baja_to_usa as marginal_mmbtu_per_year
	from
	(select ( cast(2846500 as numeric) / 302200000 ) * ( cast(11298 as numeric) / 43800 ) as scale_mex_baja_to_usa) as scale_table,
	(select distinct year from biomass_solid_supply_curve_by_load_area) as year_table,
	(select 	biomass_type,
			price_dollars_per_dry_ton as price_dollars_per_ton,
			sum( quantity_dry_tons ) as marginal_tons_per_year,
			price_dollars_per_dry_ton /
				CASE	WHEN biomass_type = 'msw_paper' THEN 7000 * 2.20462262 * 0.001
						WHEN biomass_type = 'msw_wood'	THEN 8000 * 2.20462262 * 0.001
				END as price_dollars_per_mmbtu,
			sum( quantity_dry_tons *
				CASE	WHEN biomass_type = 'msw_paper' THEN 7000 * 2.20462262 * 0.001
						WHEN biomass_type = 'msw_wood'	THEN 8000 * 2.20462262 * 0.001
				END) as marginal_mmbtu_per_year
	from 		biomass_ucd_supply_curve_import
	where biomass_type in ('msw_paper', 'msw_wood')
	group by biomass_type, price_dollars_per_ton, price_dollars_per_mmbtu
	) as msw_uc_davis_table
where marginal_mmbtu_per_year > 100
order by load_area, biomass_type, year, price_dollars_per_ton, price_dollars_per_mmbtu;


-- UC DAVIS COUNTY DATA ------------------
-- we also get orchard and vineyard wastes from the UC Davis data
-- as well as pulpwood and unused mill wastes

-- import the county shapefiles to match county-level data
-- the county shapefile imported here doesn't have all of the shapefiles for each county for unknown reasons
-- but the county fips were crossreferenced with the county fips from ventyx_counties_region
-- and all except some random pieces of water from the UC Davis counties (not real counties - denoted with fips of XX000) are there
-- so we can use the ventyx_counties_region shapefiles with the UC Davis counties table as a map table

-- shp2pgsql -s 102004 /Volumes/1TB_RAID/Models/GIS/Biomass_UC_Davis_2011_Nathan_Parker/county.dbf biomass_ucd_counties | psql -h switch-db2.erg.berkeley.edu -U jimmy -d switch_gis
alter table biomass_ucd_counties drop column the_geom;
alter table biomass_ucd_counties rename column qid to location_id;

-- divides up counties by land area in each load area to partition county biomass potentials into each load area.
-- Hawaii and Alaska are excluded to speed up the query.
-- there is a bit of shapefile overlap between the counties and the load areas that aren't in the US,
-- so we don't include non-US biomass potentials because the data is only for the US
drop table if exists biomass_county_to_load_area;
create table biomass_county_to_load_area(
	load_area character varying(11),
	state character(2),
	county character varying(30),
	county_fips character varying(15),
	county_area float,
	county_area_fraction_in_load_area float,
	PRIMARY KEY (load_area, county_fips)
	);

insert into biomass_county_to_load_area ( load_area, state, county, county_fips, county_area, county_area_fraction_in_load_area )
select * from
	(select load_area,
			ventyx_counties_region.st_abbr as state,
			ventyx_counties_region.county,
			ventyx_counties_region.cnty_fips as county_fips,
			area(ventyx_counties_region.the_geom) as county_area,
			area(intersection(ventyx_counties_region.the_geom, wecc_load_areas.polygon_geom))/area(ventyx_counties_region.the_geom) as county_area_fraction_in_load_area
	from 	ventyx_counties_region, wecc_load_areas
	where  	intersects(wecc_load_areas.polygon_geom, ventyx_counties_region.the_geom)
	and		wecc_load_areas.polygon_geom && ventyx_counties_region.the_geom
	and 	st_abbr not in ('AK', 'HI')
	and 	load_area not like 'MEX%'
	and 	load_area not like 'CAN%'
	) as county_area_table
where county_area_fraction_in_load_area > 10E-9
order by load_area, state, county_fips;

-- now actually insert the data to the supply curve
-- orchard and vineyard wastes are 'ovw', pulpwood is 'pulpwood'
-- unused mill residues are priced at $10/dry ton and labeled 'forest so the 'or' clause below selects these
-- these are all woody wastes, so we'll use the same conversion factor from tons to MMBtu (15.07)
-- as was used for the POLYSIS forest residues data 

insert into biomass_solid_supply_curve_by_load_area 
	(load_area, biomass_type, year, price_dollars_per_ton, marginal_tons_per_year, price_dollars_per_mmbtu, marginal_mmbtu_per_year)
select 	load_area,
		biomass_type,
		year,
		price_dollars_per_ton,
		marginal_tons_per_year,
		price_dollars_per_mmbtu,
		marginal_mmbtu_per_year
	from
	(select distinct year from biomass_solid_supply_curve_by_load_area) as year_table,
	(select load_area,
			biomass_type,
			price_dollars_per_dry_ton as price_dollars_per_ton,
			sum( county_area_fraction_in_load_area * quantity_dry_tons ) as marginal_tons_per_year,
			price_dollars_per_dry_ton / 15.07 as price_dollars_per_mmbtu,
			sum( county_area_fraction_in_load_area * quantity_dry_tons * 15.07 ) as marginal_mmbtu_per_year
	from 	biomass_ucd_supply_curve_import
	join 	biomass_ucd_counties using (location_id)
	join	ventyx_counties_region on (fips = cnty_fips)
	join	biomass_county_to_load_area on (cnty_fips = county_fips)
	where 	( biomass_type in ('ovw', 'pulpwood') or ( biomass_type = 'forest' and price_dollars_per_dry_ton = 10 ) )
	group by load_area, biomass_type, price_dollars_per_ton, price_dollars_per_mmbtu
	) as ucd_county_supply
where marginal_mmbtu_per_year > 100
order by load_area, biomass_type, year, price_dollars_per_ton, price_dollars_per_mmbtu;

-- make OrchardVineyardWaste and mill residues have nicer names
update biomass_solid_supply_curve_by_load_area set biomass_type = 'OrchardVineyardWaste' where biomass_type = 'ovw';
update biomass_solid_supply_curve_by_load_area set biomass_type = 'Mill_Residue' where biomass_type = 'forest';


-- MILL RESIDUES: FUEL AND OTHER-------------------------------
-- Nathan Parker's data above has mill wastes for the fiber part of the waste stream (pulpwood)
-- and the unused mill wastes (forest)

-- there are also potentially available mill wastes currently used for fuel and 'other'
-- these are estimated by US Forest Service (?) region
-- by "Kumarappan et al. (2009) Biomass supply estimates,” BioResources 4(3), 1070-1087."
-- I (Jimmy) got the raw data from them ( kumarapp@msu.edu = Subbu)
-- it can be found in the folder /Volumes/1TB_RAID/Models/GIS/Biomass_Canada_Supply_Curve
-- prices are in $2008 US (not Canadian dollars!)

-- They assume that 'fuel' can be made available at $28.65 * 0.96  (the 0.96 converts from $2008 --> $2007)
-- and that 'other' can be made available at $21 * 0.96
-- each US Forest Service region has a different fraction of mill wastes that are used for fuel and other
-- data can be found in /Volumes/1TB_RAID/Models/GIS/Biomass_Canada_Supply_Curve/Canada\ Forestry/CA\ Mill\ Residues.xls
drop table if exists us_fs_region_fuel_other;
create temporary table us_fs_region_fuel_other(
	region char(25) primary key,
	fuel_fraction double precision,
	other_fraction double precision );

-- it would appear that there aren't any significant mill residues in the great plains	
insert into us_fs_region_fuel_other (region, fuel_fraction, other_fraction) values
	('Northeast', 0.32487226, 0.363936047),
	('North_Central', 0.45521711, 0.301879456),
	('South_East', 0.425437019, 0.147399468),
	('South_Central', 0.501070942, 0.103751542),
	('Rocky_Mountain', 0.170909091, 0.341818182),
	('Intermountain', 0.300321723, 0.057210799),
	('Alaska', 0.124444444, 0),
	('Pacific_Northwest', 0.318268924, 0.09733312),
	('Pacific_Southwest', 0.473978851, 0.079203815);
	
-- the US Forest Service regions roughly correspond to states... we'll only map the western ones for now....
-- roughly the correct regions are here http://www.fs.usda.gov/wps/portal/fsinternet/!ut/p/c4/04_SB8K8xLLM9MSSzPy8xBz9CP0os3gDfxMDT8MwRydLA1cj72DTUE8TAwjQL8h2VAQAMtzFUw!!/?navtype=BROWSEBYSUBJECT&cid=stelprdb5150028&navid=160100000000000&pnavid=160000000000000&ss=110801&position=Welcome.Html&ttype=detailfull&pname=National%20Forests%20In%20Alabama%20-%20Recreation%20Passes
drop table if exists us_fs_state_map_table;
create temporary table us_fs_state_map_table(
	region char(25),
	state_abbrv char(2),
	primary key (region, state_abbrv) );

insert into us_fs_state_map_table (region, state_abbrv) values
	('Pacific_Northwest', 'OR'),
	('Pacific_Northwest', 'WA'),
	('Pacific_Southwest', 'CA'),
	('Intermountain', 'ID'),
	('Intermountain', 'NV'),
	('Intermountain', 'UT'),
	('Intermountain', 'AZ'),
	('Intermountain', 'NM'),
	('Rocky_Mountain', 'MT'),
	('Rocky_Mountain', 'ND'),
	('Rocky_Mountain', 'SD'),
	('Rocky_Mountain', 'NE'),
	('Rocky_Mountain', 'KS'),
	('Rocky_Mountain', 'WY'),
	('Rocky_Mountain', 'CO');

-- the total supply of primary mill waste is found at the county level from 
-- Milbrandt, A. (2005). Geographic Perspective on the Current Biomass Resource Availability in the United States. 70 pp.; NREL Report No. TP-560-39181.
-- the data of which is included in the ventyx dataset in the county shapefiles
-- we also assume that secondary mill residues would be available at the 'other' price level, so we add them in here
insert into biomass_solid_supply_curve_by_load_area
	(load_area, biomass_type, year, price_dollars_per_ton, marginal_tons_per_year, price_dollars_per_mmbtu, marginal_mmbtu_per_year)
select 	load_area,
		biomass_type,
		year,
		price_dollars_per_ton,
		marginal_tons_per_year,
		price_dollars_per_mmbtu,
		marginal_mmbtu_per_year
	from
	(select distinct year from biomass_solid_supply_curve_by_load_area) as year_table,
	(select	load_area,
			cast('Mill_Residue' as text) as biomass_type,
			21 * 0.96 as price_dollars_per_ton,
			sum( ( primmill * other_fraction + secmill ) * county_area_fraction_in_load_area ) as marginal_tons_per_year,	
			21 * 0.96 / 15.07 as price_dollars_per_mmbtu,
			sum( ( primmill * other_fraction + secmill ) * county_area_fraction_in_load_area ) * 15.07 as marginal_mmbtu_per_year
	from 	ventyx_counties_region
	join	biomass_county_to_load_area on (cnty_fips = county_fips)
	join	us_fs_state_map_table on (state_abbrv = state)
	join 	us_fs_region_fuel_other using (region)
	group by load_area
	) as other_mill_residue_supply
where marginal_mmbtu_per_year > 100
order by load_area, biomass_type, year, price_dollars_per_ton, price_dollars_per_mmbtu;

-- now add biomass used for fuel
insert into biomass_solid_supply_curve_by_load_area
	(load_area, biomass_type, year, price_dollars_per_ton, marginal_tons_per_year, price_dollars_per_mmbtu, marginal_mmbtu_per_year)
select 	load_area,
		biomass_type,
		year,
		price_dollars_per_ton,
		marginal_tons_per_year,
		price_dollars_per_mmbtu,
		marginal_mmbtu_per_year
	from
	(select distinct year from biomass_solid_supply_curve_by_load_area) as year_table,
	(select	load_area,
			28.65 * 0.96 as price_dollars_per_ton,
			sum( primmill * fuel_fraction * county_area_fraction_in_load_area ) as marginal_tons_per_year,	
			cast('Mill_Residue' as text) as biomass_type,
			28.65 * 0.96 / 15.07 as price_dollars_per_mmbtu,
			sum( primmill * fuel_fraction * county_area_fraction_in_load_area ) * 15.07 as marginal_mmbtu_per_year
	from 	ventyx_counties_region
	join	biomass_county_to_load_area on (cnty_fips = county_fips)
	join	us_fs_state_map_table on (state_abbrv = state)
	join 	us_fs_region_fuel_other using (region)
	group by load_area
	) as other_mill_residue_supply
where marginal_mmbtu_per_year > 100
order by load_area, biomass_type, year, price_dollars_per_ton, price_dollars_per_mmbtu;



-- CANADA BIOMASS SUPPLY--------------------------------
-- data is from "Kumarappan et al. (2009) Biomass supply estimates,” BioResources 4(3), 1070-1087."
-- I (Jimmy) got the raw data from them ( kumarapp@msu.edu = Subbu)
-- it can be found in the folder /Volumes/1TB_RAID/Models/GIS/Biomass_Canada_Supply_Curve
-- prices are in $2008 US (not Canadian dollars!)

drop table if exists biomass_canada_supply_curve;
create table biomass_canada_supply_curve(
	province_abbreviation character(2),
	load_area character varying(11),
	biomass_type character varying(20),
	price_dollars_per_ton float,
	marginal_tons_per_year float,
	price_dollars_per_mmbtu float,
	marginal_mmbtu_per_year float,
	PRIMARY KEY (province_abbreviation, biomass_type, price_dollars_per_ton)
	);

-- add forest residues from /Volumes/1TB_RAID/Models/GIS/Biomass_Canada_Supply_Curve/Canada\ Forestry/CA\ Forest\ Residue\ Availability.xls
insert into biomass_canada_supply_curve
	( province_abbreviation, biomass_type, price_dollars_per_ton, marginal_tons_per_year ) values
('BC','Forest_Resd',49.06027113,8698811),
('AB','Forest_Resd',50.44483108,2725782),
('NT','Forest_Resd',51.49413673,495),
('YT','Forest_Resd',52.31533278,822),
('SK','Forest_Resd',52.43710397,539794),
('QC','Forest_Resd',54.16243321,4553485 ),
('MB','Forest_Resd',54.33140837,235542),
('ON','Forest_Resd',54.88159165,2911588),
('NS','Forest_Resd',55.04541212,720022),
('NB','Forest_Resd',55.91979247,1257805),
('NL','Forest_Resd',56.28722381,287931),
('PE','Forest_Resd',56.83143377,53394);

-- add mill residues from /Volumes/1TB_RAID/Models/GIS/Biomass_Canada_Supply_Curve/Canada\ Forestry/CA\ Forest\ Residue\ Availability.xls
insert into biomass_canada_supply_curve
	( province_abbreviation, biomass_type, price_dollars_per_ton, marginal_tons_per_year ) values
('BC','Mill_Residue',5,181786.499),
('AB','Mill_Residue',5,56963.01463),
('NT','Mill_Residue',5,10.34941385),
('YT','Mill_Residue',5,17.19594917),
('SK','Mill_Residue',5,11280.54266),
('QC','Mill_Residue',5,95158.08373),
('MB','Mill_Residue',5,4922.340451),
('ON','Mill_Residue',5,60845.95549),
('NS','Mill_Residue',5,15046.93319),
('NB','Mill_Residue',5,26285.44131),
('NL','Mill_Residue',5,6017.149215),
('PE','Mill_Residue',5,1115.826035),
('BC','Mill_Residue',21,1195847.324),
('AB','Mill_Residue',21,374720.1743),
('NT','Mill_Residue',21,68.08161731),
('YT','Mill_Residue',21,113.1202257),
('SK','Mill_Residue',21,74206.86805),
('QC','Mill_Residue',21,625979.0489),
('MB','Mill_Residue',21,32380.6646),
('ON','Mill_Residue',21,400263.3497),
('NS','Mill_Residue',21,98983.3397),
('NB','Mill_Residue',21,172913.6916),
('NL','Mill_Residue',21,39582.6523),
('PE','Mill_Residue',21,7340.245756),
('BC','Mill_Residue',28.65,3554343.551),
('AB','Mill_Residue',28.65,1113757.759),
('NT','Mill_Residue',28.65,202.3548096),
('YT','Mill_Residue',28.65,336.220299),
('SK','Mill_Residue',28.65,220560.5161),
('QC','Mill_Residue',28.65,1860559.079),
('MB','Mill_Residue',28.65,96243.06058),
('ON','Mill_Residue',28.65,1189678.17),
('NS','Mill_Residue',28.65,294202.101),
('NB','Mill_Residue',28.65,513940.7453),
('NL','Mill_Residue',28.65,117649.0863),
('PE','Mill_Residue',28.65,21816.96162),
('BC','Mill_Residue',41,3467524.653),
('AB','Mill_Residue',41,1086552.954),
('NT','Mill_Residue',41,197.4120624),
('YT','Mill_Residue',41,328.0077344),
('SK','Mill_Residue',41,215173.0738),
('QC','Mill_Residue',41,1815112.8),
('MB','Mill_Residue',41,93892.21398),
('ON','Mill_Residue',41,1160618.923),
('NS','Mill_Residue',41,287015.8789),
('NB','Mill_Residue',41,501387.156),
('NL','Mill_Residue',41,114775.3731),
('PE','Mill_Residue',41,21284.05743);

-- I wasn't able to sort out the MSW data from the supply curves given in the folder Biomass_Canada_Supply_Curve
-- and the data contained in the paper.  I've therefore used the shape of their supply curve for MSW for all of Canada (Fig. 2 and Table 2 of the paper)
-- combined with the province level potentials from /Volumes/1TB_RAID/Models/GIS/Biomass_Canada_Supply_Curve/Summary.xls
-- for each province.  this approach may over or under estimate the cost of MSW for a certain province,
-- but this cost is likely distribution within each province anyway
-- and MSW might be somewhat similar across Canada (people make similar junk), so this isn't a bad hack at all.
drop table if exists canada_msw_supply_levels;
create temporary table canada_msw_supply_levels(
	price_dollars_per_ton double precision,
	marginal_million_tons_per_year double precision);
	
insert into canada_msw_supply_levels (price_dollars_per_ton, marginal_million_tons_per_year) values
	(3, 0.4),
	(5, 0.8),
	(33, 1.2),
	(45, 0.6),
	(53, 0.7),
	(55, 0.7),
	(64, 0.4),
	(74, 1.2),
	(85, 1);

drop table if exists canada_msw_supply_quantities_by_province;
create temporary table canada_msw_supply_quantities_by_province(
	province_abbreviation char(2),
	total_million_tons_per_year double precision);

insert into canada_msw_supply_quantities_by_province ( province_abbreviation, total_million_tons_per_year ) values
	('BC',0.67),
	('AB',0.86),
	('NT',0.02),
	('YT',0.01),
	('SK',0.27),
	('QC',2.06),
	('MB',0.35),
	('ON',2.46),
	('NS',0.05),
	('NB',0.10),
	('NL',0.12),
	('PE',0.03);


-- cross the canada_msw_supply_levels and canada_msw_supply_quantities_by_province,
-- giving each province the same shape supply curve from canada_msw_supply_levels
-- that totals the amount of MSW in canada_msw_supply_quantities_by_province
insert into biomass_canada_supply_curve
	( province_abbreviation, biomass_type, price_dollars_per_ton, marginal_tons_per_year )

	select 	province_abbreviation,
			'MSW' as biomass_type,
			price_dollars_per_ton,
			total_million_tons_per_year * 1000000 * ( marginal_million_tons_per_year / sum_million_tons_per_year ) as marginal_tons_per_year
	from 	canada_msw_supply_quantities_by_province,
			canada_msw_supply_levels,
			( select sum(marginal_million_tons_per_year) as sum_million_tons_per_year
				from canada_msw_supply_levels ) as total_table;
	
-- Energy Crops
-- backcalculated in Volumes/1TB_RAID/Models/GIS/Biomass_Canada_Supply_Curve/Canada\ Energy\ Crops.xls
-- using the assumptions in the paper.
insert into biomass_canada_supply_curve
	( province_abbreviation, biomass_type, price_dollars_per_ton, marginal_tons_per_year ) values
	('AB','Switchgrass',97.66816548,5.790056455),
	('AB','Switchgrass',103.1925608,1.37769126),
	('BC','Switchgrass',96.03789356,0.137934623),
	('BC','Switchgrass',104.3541362,0.005587045),
	('BC','Switchgrass',121.0911115,0.011174089),
	('MB','Switchgrass',97.62008942,3.664419858),
	('MB','Switchgrass',103.1925608,0.859032693),
	('ON','Switchgrass',117.2151001,1.534194358),
	('ON','Switchgrass',121.099115,0.553519553),
	('PE','Switchgrass',103.1925608,0.0075555),
	('QC','Switchgrass',130.1747391,0.622843738),
	('SK','Switchgrass',90.05713224,12.56908807),
	('SK','Switchgrass',94.25480377,4.233201578),
	('SK','Switchgrass',112.1418361,0.012731305);

-- the above are in million_tons_per_year.. convert them to dry tons per year
update biomass_canada_supply_curve set marginal_tons_per_year = marginal_tons_per_year * 1000000 where biomass_type = 'Switchgrass';

-- Agricultural Residues
-- calculated in Volumes/1TB_RAID/Models/GIS/Biomass_Canada_Supply_Curve/Canada\ Ag\ Residues.xls
insert into biomass_canada_supply_curve
	( province_abbreviation, biomass_type, price_dollars_per_ton, marginal_tons_per_year ) values
	('NL','Ag_Residues',29.72,0.16),
	('PE','Ag_Residues',87.54,0.03),
	('PE','Ag_Residues',92.68,0.01),
	('NS','Ag_Residues',28.86,0.01),
	('NS','Ag_Residues',74.22,0.09),
	('QC','Ag_Residues',29.51,0.05),
	('QC','Ag_Residues',35.04,0.06),
	('QC','Ag_Residues',40.88,0.14),
	('QC','Ag_Residues',59.39,2.62),
	('QC','Ag_Residues',61.62,0.13),
	('ON','Ag_Residues',29.79,0.03),
	('ON','Ag_Residues',34.63,0.21),
	('ON','Ag_Residues',37.32,0.10),
	('ON','Ag_Residues',41.59,5.19),
	('MB','Ag_Residues',25.00,0.36),
	('MB','Ag_Residues',37.76,5.12),
	('MB','Ag_Residues',39.42,0.50),
	('SK','Ag_Residues',25.01,2.35),
	('SK','Ag_Residues',32.29,9.91),
	('SK','Ag_Residues',35.81,4.61),
	('AB','Ag_Residues',27.34,3.18),
	('AB','Ag_Residues',31.42,0.22),
	('AB','Ag_Residues',34.22,9.86),
	('BC','Ag_Residues',29.60,0.04),
	('BC','Ag_Residues',140.49,0.21);

-- the above are in million_tons_per_year.. convert them to dry tons per year
update biomass_canada_supply_curve set marginal_tons_per_year = marginal_tons_per_year * 1000000 where biomass_type = 'Ag_Residues';

-- update prices to $2007 because all the Canadian data is in $2008
update biomass_canada_supply_curve set price_dollars_per_ton = 0.96 * price_dollars_per_ton;


-- add in the energy values of various feedstocks
-- the average of the energy density of msw_paper and msw_wood above is taken for MSW here = 16.5 MMBtu/dry_ton
-- Ag_Residues in Canada are largely wheat, so we'll use the wheat energy density here
update biomass_canada_supply_curve
set 	marginal_mmbtu_per_year = marginal_tons_per_year *
		CASE
			WHEN biomass_type like 'Switchgrass' then 14.68
			WHEN biomass_type like 'Forest_Resd' then 15.07
			WHEN biomass_type like 'Mill_Residue' then 15.07
			WHEN biomass_type like 'Ag_Residues' then 13.56
			WHEN biomass_type like 'MSW' then 16.5
		END,
	price_dollars_per_mmbtu = price_dollars_per_ton /
		CASE
			WHEN biomass_type like 'Switchgrass' then 14.68
			WHEN biomass_type like 'Forest_Resd' then 15.07
			WHEN biomass_type like 'Mill_Residue' then 15.07
			WHEN biomass_type like 'Ag_Residues' then 13.56
			WHEN biomass_type like 'MSW' then 16.5
		END;

-- add in load areas
update biomass_canada_supply_curve
set	load_area = CASE
					WHEN province_abbreviation = 'BC' THEN 'CAN_BC'
					WHEN province_abbreviation = 'AB' THEN 'CAN_ALB'
				ELSE null
				END;

-- add Canadian data to the load area supply curves
insert into biomass_solid_supply_curve_by_load_area
	(load_area, biomass_type, year, price_dollars_per_ton, marginal_tons_per_year, price_dollars_per_mmbtu, marginal_mmbtu_per_year)
select 	load_area,
		biomass_type,
		year,
		price_dollars_per_ton,
		marginal_tons_per_year,
		price_dollars_per_mmbtu,
		marginal_mmbtu_per_year
	from	biomass_canada_supply_curve,
			(select distinct year from biomass_solid_supply_curve_by_load_area) as year_table
	where load_area is not null
	and	marginal_mmbtu_per_year > 100
order by load_area, biomass_type, year, price_dollars_per_ton, price_dollars_per_mmbtu;


-- FILL IN TOTAL MMBTU PER YEAR VALUES FOR EACH BIOMASS TYPE------------------------------------------------------------
-- this procedure does a sum for each price point that doesn't have a total_mmbtu_per_year value

CREATE OR REPLACE FUNCTION sum_bio_potential() RETURNS VOID AS $$

DECLARE current_biomass_type char(20);
DECLARE current_load_area char(11);
DECLARE current_price_dollars_per_mmbtu double precision;
DECLARE current_year int;

BEGIN

-- create a table of all the possible bio_la_price_level_year combos that we want to fill in
drop table if exists bio_la_price_level_year;
create temporary table bio_la_price_level_year( 
	biomass_type char(20),
	load_area char(11),
	price_dollars_per_mmbtu double precision, 
	year int,
	primary key (biomass_type, load_area, price_dollars_per_mmbtu, year) );
	
insert into bio_la_price_level_year ( biomass_type, load_area, price_dollars_per_mmbtu, year )
	select 	distinct biomass_type, load_area, price_dollars_per_mmbtu, year 
		from biomass_solid_supply_curve_by_load_area
		where total_mmbtu_per_year is null;

-- make a table for the current bio_la_price_level_year combo
drop table if exists current_bio_la_price_level_year;
create temporary table current_bio_la_price_level_year( 
	biomass_type char(20),
	load_area char(11),
	price_dollars_per_mmbtu double precision, 
	year int,
	primary key (biomass_type, load_area, price_dollars_per_mmbtu, year) );

-- this loop will finish when we've filled in all the the possible bio_la_price_level_year combos that need filling in
WHILE ( ( select count(*) from bio_la_price_level_year ) > 0 ) LOOP

-- update all of the variables
delete from current_bio_la_price_level_year;
insert into current_bio_la_price_level_year
	select * from bio_la_price_level_year limit 1;
 
select biomass_type from current_bio_la_price_level_year into current_biomass_type;
select load_area from current_bio_la_price_level_year into current_load_area;
select price_dollars_per_mmbtu from current_bio_la_price_level_year	into current_price_dollars_per_mmbtu;
select year from current_bio_la_price_level_year into current_year;

-- sum up all marginal_mmbtu_per_year below or equal to the current price level to get
-- the total amount of biomass available at the current_price_dollars_per_mmbtu
update 	biomass_solid_supply_curve_by_load_area
	set total_tons_per_year = total_table.total_tons_per_year,
		total_mmbtu_per_year = total_table.total_mmbtu_per_year
	from (select 	sum(marginal_tons_per_year) as total_tons_per_year,
					sum(marginal_mmbtu_per_year) as total_mmbtu_per_year
			from 	biomass_solid_supply_curve_by_load_area
			where	biomass_type = current_biomass_type
			and		load_area = current_load_area
			and		year = current_year
			and		price_dollars_per_mmbtu <= current_price_dollars_per_mmbtu) as total_table
	where 	biomass_type = current_biomass_type
	and		load_area = current_load_area
	and		price_dollars_per_mmbtu = current_price_dollars_per_mmbtu
	and		year = current_year;
	
-- delete the current bio_la_price_level_year combo
delete from bio_la_price_level_year
where 	biomass_type = current_biomass_type
and		load_area = current_load_area
and 	price_dollars_per_mmbtu = current_price_dollars_per_mmbtu
and 	year = current_year;

END LOOP;

END;
$$ LANGUAGE 'plpgsql';

-- Actually call the function
SELECT sum_bio_potential();
drop function sum_bio_potential();


-- MARGINAL VALUES-------------------------------------------------------------------
-- fill in the marginal values that are currently missing from the biomass_solid_supply_curve_by_load_area table

-- the marginal value for the lowest price is just the total value, so fill it in first
update biomass_solid_supply_curve_by_load_area
set	marginal_tons_per_year = total_tons_per_year,
	marginal_mmbtu_per_year = total_mmbtu_per_year
from	(select biomass_type, load_area, year, min(price_dollars_per_mmbtu) as min_price_dollars_per_mmbtu
			from biomass_solid_supply_curve_by_load_area
			where marginal_mmbtu_per_year is null
			group by biomass_type, load_area, year
		) as marginal_equals_total_table
where	biomass_solid_supply_curve_by_load_area.biomass_type = marginal_equals_total_table.biomass_type
and		biomass_solid_supply_curve_by_load_area.load_area = marginal_equals_total_table.load_area
and		biomass_solid_supply_curve_by_load_area.year = marginal_equals_total_table.year
and		biomass_solid_supply_curve_by_load_area.price_dollars_per_mmbtu = marginal_equals_total_table.min_price_dollars_per_mmbtu
;


CREATE OR REPLACE FUNCTION marginalize_bio_potential() RETURNS VOID AS $$

DECLARE current_biomass_type char(20);
DECLARE current_load_area char(11);
DECLARE current_price_dollars_per_mmbtu double precision;
DECLARE current_price_dollars_per_mmbtu_one_level_below double precision;
DECLARE current_year int;

BEGIN

-- create a table of all the possible bio_la_price_level_year combos that we want to fill in
drop table if exists bio_la_price_level_year;
create temporary table bio_la_price_level_year( 
	biomass_type char(20),
	load_area char(11),
	year int,
	price_dollars_per_mmbtu double precision, 
	primary key (biomass_type, load_area, year, price_dollars_per_mmbtu) );
	
insert into bio_la_price_level_year ( biomass_type, load_area, year, price_dollars_per_mmbtu )
	select 	distinct biomass_type, load_area, year, price_dollars_per_mmbtu 
		from biomass_solid_supply_curve_by_load_area
		where marginal_mmbtu_per_year is null;

-- make a table for the current bio_la_price_level_year combo
drop table if exists current_bio_la_price_level_year;
create temporary table current_bio_la_price_level_year( 
	biomass_type char(20),
	load_area char(11),
	year int,
	price_dollars_per_mmbtu double precision, 
	primary key (biomass_type, load_area, price_dollars_per_mmbtu, year) );


-- this loop will finish when we've filled in all the the possible bio_la_price_level_year combos that need filling in
WHILE ( ( select count(*) from bio_la_price_level_year ) > 0 ) LOOP

-- update all of the variables
delete from current_bio_la_price_level_year;
insert into current_bio_la_price_level_year
	select * from bio_la_price_level_year limit 1;
 
select biomass_type from current_bio_la_price_level_year into current_biomass_type;
select load_area from current_bio_la_price_level_year into current_load_area;
select year from current_bio_la_price_level_year into current_year;
select price_dollars_per_mmbtu from current_bio_la_price_level_year	into current_price_dollars_per_mmbtu;

-- add in the current_price_dollars_per_mmbtu_one_level_below by finding the value of price_dollars_per_mmbtu
-- that is the smallest negative number ( max of a negative number ) where the current price is > the actual price
-- then add back in the current price to get the price one level below
select	( select max( price_dollars_per_mmbtu - current_price_dollars_per_mmbtu  ) + current_price_dollars_per_mmbtu
				from 	biomass_solid_supply_curve_by_load_area
				where	biomass_type = current_biomass_type
				and		load_area = current_load_area
				and		year = current_year
				and		current_price_dollars_per_mmbtu > price_dollars_per_mmbtu )
into current_price_dollars_per_mmbtu_one_level_below;


-- find the total_mmbtu_per_year at the price level one below the current price
update 	biomass_solid_supply_curve_by_load_area
	set marginal_tons_per_year = biomass_solid_supply_curve_by_load_area.total_tons_per_year - one_below_table.ttons_minus_one_level,
		marginal_mmbtu_per_year = biomass_solid_supply_curve_by_load_area.total_mmbtu_per_year - one_below_table.tmmbtu_minus_one_level
	from (select 	total_tons_per_year as ttons_minus_one_level,
					total_mmbtu_per_year as tmmbtu_minus_one_level
			from 	biomass_solid_supply_curve_by_load_area
			where	biomass_type = current_biomass_type
			and		load_area = current_load_area
			and		year = current_year
			and		price_dollars_per_mmbtu = current_price_dollars_per_mmbtu_one_level_below) as one_below_table
	where 	biomass_type = current_biomass_type
	and		load_area = current_load_area
	and		price_dollars_per_mmbtu = current_price_dollars_per_mmbtu
	and		year = current_year;
	
-- delete the current bio_la_price_level_year combo
delete from bio_la_price_level_year
where 	biomass_type = current_biomass_type
and		load_area = current_load_area
and 	price_dollars_per_mmbtu = current_price_dollars_per_mmbtu
and 	year = current_year;

END LOOP;

END;
$$ LANGUAGE 'plpgsql';

-- Actually call the function - takes about 5 minutes to run
SELECT marginalize_bio_potential();
drop function marginalize_bio_potential();

-- clean up
-- many marginal values come in as zero, a few come in as slightly negative, and a few come in as tiny... get rid of all of them here
delete from biomass_solid_supply_curve_by_load_area where marginal_mmbtu_per_year < 1;


-- AGGREGATE FEEDSTOCKS AND CALCULATE PRICES---------------------------------
-- to input the biomass supply curve into AMPL, we need the total biomass available up to an including each price level
-- we want to include the producer surplus in the price projections that we input into AMPL
-- because we're not doing a cost optimization of the bio sector explicitly,
-- so paying bio suppliers one market price for all biomass up to the quantity of consumption is what should be done
-- this is included below by adding the producer surplus added from moving
-- from a lower price of biomass [a] to a higher one [b] onto the price of the higher cost biomass [b]
-- think of it as including the rectangle (price[b]-price[a]) * total_mmbtu_per_year[a]


-- AMPL needs the total amount of biomass at each price point, not the marginal values
-- the below procedure does a sum for each price point to obtain the total values

-- to get the total biomass potential by feedstock in each load area
drop table if exists biomass_solid_supply_curve_breakpoints_prices;
create table biomass_solid_supply_curve_breakpoints_prices(
	price_level_la_yr_id serial,
	breakpoint_id int,
	load_area character varying(11),
	year int,
	price_dollars_per_mmbtu double precision,
	marginal_mmbtu_per_year double precision,
	breakpoint_mmbtu_per_year double precision,
	price_dollars_per_mmbtu_surplus_adjusted double precision,
	primary key (load_area, year, price_dollars_per_mmbtu),
	UNIQUE (breakpoint_id, load_area, year)
);

CREATE INDEX biobpla ON biomass_solid_supply_curve_breakpoints_prices (load_area);
CREATE INDEX biobpyr ON biomass_solid_supply_curve_breakpoints_prices (year);
CREATE INDEX biobpprice ON biomass_solid_supply_curve_breakpoints_prices (price_dollars_per_mmbtu);

-- sum up the total biomass available by load area
-- the order by is important here as it places the price levels at the right place with respect to price_level_la_id
-- which is then used to calculate the breakpoint_id below
insert into biomass_solid_supply_curve_breakpoints_prices (load_area, year, price_dollars_per_mmbtu, marginal_mmbtu_per_year)
	select	load_area,
			year,
			price_dollars_per_mmbtu,
			sum( marginal_mmbtu_per_year ) as marginal_mmbtu_per_year
	from	biomass_solid_supply_curve_by_load_area
	group by load_area, year, price_dollars_per_mmbtu
	order by load_area, year, price_dollars_per_mmbtu;

update biomass_solid_supply_curve_breakpoints_prices
set breakpoint_id = price_level_la_yr_id - min_price_level_la_yr_id + 1
from (select load_area, year, min(price_level_la_yr_id) as min_price_level_la_yr_id
		from biomass_solid_supply_curve_breakpoints_prices group by load_area, year) as min_id_table
where 	min_id_table.load_area = biomass_solid_supply_curve_breakpoints_prices.load_area
and		min_id_table.year = biomass_solid_supply_curve_breakpoints_prices.year;


-- the above table represents the amount of biomass that can be obtained at a certain price point for a certain year,
-- but for AMPL's piecewise linear cost forumlation, the total mmbtu_per_year is needed
-- this small procedure does a sum for each price point

CREATE OR REPLACE FUNCTION sum_load_area_bio_potential() RETURNS VOID
AS $$

DECLARE current_load_area character varying(11);
DECLARE current_year int;
DECLARE current_price_dollars_per_mmbtu double precision;

BEGIN

drop table if exists la_year_price_level;
create temporary table la_year_price_level as 
	select 	distinct load_area, year, price_dollars_per_mmbtu
		from biomass_solid_supply_curve_breakpoints_prices;

-- start the while loop to iterate over the grid_ids to make sure the farms don't have widely varying insolation
-- at the end of the loop, every gid from insolation_good_solar_land_grid should have been given a new polygon
-- so the while loop will stop after this becomes true
WHILE ( ( select count(*) from la_year_price_level ) > 0 ) LOOP

select load_area from la_year_price_level limit 1 into current_load_area;
select year from la_year_price_level
	where 	la_year_price_level.load_area = current_load_area limit 1
		into current_year;
select price_dollars_per_mmbtu from la_year_price_level
	where 	la_year_price_level.load_area = current_load_area
	and		la_year_price_level.year = current_year limit 1
		into current_price_dollars_per_mmbtu;

update 	biomass_solid_supply_curve_breakpoints_prices
	set breakpoint_mmbtu_per_year = bp_table.breakpoint_mmbtu_per_year
	from (select 	sum(marginal_mmbtu_per_year) as breakpoint_mmbtu_per_year
			from 	biomass_solid_supply_curve_breakpoints_prices
			where	load_area = current_load_area
			and		year = current_year
			and		price_dollars_per_mmbtu <= current_price_dollars_per_mmbtu) as bp_table
	where 	load_area = current_load_area
	and		year = current_year
	and	 	price_dollars_per_mmbtu = current_price_dollars_per_mmbtu;
	
-- delete the current load area and price level
delete from la_year_price_level
where 	load_area = current_load_area
and		year = current_year
and 	price_dollars_per_mmbtu = current_price_dollars_per_mmbtu;

END LOOP;

END;
$$ LANGUAGE 'plpgsql';

-- Actually call the function
SELECT sum_load_area_bio_potential();
drop function sum_load_area_bio_potential();


-- ADD PRODUCER SURPLUS-------------------------------------------------
drop table if exists biomass_solid_supply_curve_with_producer_surplus;
create table biomass_solid_supply_curve_with_producer_surplus(
	row_id serial,
	num_breakpoints_per_la_yr int,
	load_area character varying(11),
	year int,
	price_dollars_per_mmbtu double precision,
	marginal_mmbtu_per_year double precision,
	breakpoint_mmbtu_per_year double precision,
	price_dollars_per_mmbtu_surplus_adjusted double precision,
	surplus_error_total_cost double precision default 0,
	price_dollars_per_mmbtu_surplus_adjusted_increasing_only double precision,
	error_extra_cost_this_bp double precision default 0,
	price_dollars_per_mmbtu_surplus_adjusted_and_shifted double precision,
	primary key (num_breakpoints_per_la_yr, load_area, year, price_dollars_per_mmbtu)
);

CREATE UNIQUE INDEX _biorowid_ ON biomass_solid_supply_curve_with_producer_surplus (row_id);
CREATE INDEX _bionumbp_ ON biomass_solid_supply_curve_with_producer_surplus (num_breakpoints_per_la_yr);
CREATE INDEX _biobpla_ ON biomass_solid_supply_curve_with_producer_surplus (load_area);
CREATE INDEX _biobpyr_ ON biomass_solid_supply_curve_with_producer_surplus (year);
CREATE INDEX _biobpprice_ ON biomass_solid_supply_curve_with_producer_surplus (price_dollars_per_mmbtu);
CREATE INDEX _biolayrbp_ ON biomass_solid_supply_curve_with_producer_surplus (load_area, year, num_breakpoints_per_la_yr);

-- the below insert loop causes errors when there is a load area with only one breakpoint
-- because both insert statments try to insert the same breakpoint, causing a pkey error
-- the rule below is the postgresql version of mysql 'insert ignore'...
-- the 'DO INSTEAD (SELECT 1)' does nothing except for keeping it from inserting the row it was trying to insert
-- CREATE OR REPLACE RULE "insert_ignore_biomass_solid_supply_curve_with_producer_surplus" AS ON INSERT TO "biomass_solid_supply_curve_with_producer_surplus"
--     WHERE
--       EXISTS	(SELECT 1 FROM biomass_solid_supply_curve_with_producer_surplus
--       				WHERE num_breakpoints_per_la_yr=NEW.num_breakpoints_per_la_yr and load_area=NEW.load_area and year=NEW.year and price_dollars_per_mmbtu=NEW.price_dollars_per_mmbtu)
--     DO INSTEAD (SELECT 1);


-- create a function that aggregates the bio supply curve by different price points
-- with the goal of picking the one with the least producer surplus
CREATE OR REPLACE FUNCTION bio_producer_surplus() RETURNS VOID AS $$

DECLARE current_num_breakpoints_per_la_yr int;
DECLARE current_load_area character varying(11);
DECLARE current_price_dollars_per_mmbtu numeric;
DECLARE row_id_to_go_one_price_level_up int;
DECLARE current_year int;

BEGIN

-- enumerate all possible values of breakpoints per load area per year.. will exit the loop when this enumeration is done
select 0 into current_num_breakpoints_per_la_yr;

	LOOP

	select current_num_breakpoints_per_la_yr + 1 into current_num_breakpoints_per_la_yr;
	RAISE NOTICE 'current_num_breakpoints_per_la_yr is at %',current_num_breakpoints_per_la_yr;

	-- the insidemost select gets the cheapest biomass (min_price_la_yr)
	-- and the price stepsize as a function of the max and min price (min_price_la_yr)
	-- tmp_new_breakpoint_table sums up all of the biomass within the desired price range
	-- ( [min_price_la_yr + ( integer_val - 1 ) * breakpoint_price_step] to [min_price_la_yr + integer_val * breakpoint_price_step])
	-- and calculates the total cost for biomass within that range.
	-- This cost will be used to calculate a new price for the aggregated bio supply in the outermost select
	insert into biomass_solid_supply_curve_with_producer_surplus (num_breakpoints_per_la_yr, load_area, year, price_dollars_per_mmbtu, marginal_mmbtu_per_year, breakpoint_mmbtu_per_year)
	select distinct num_breakpoints_per_la_yr, load_area, year, price_dollars_per_mmbtu, marginal_mmbtu_per_year, breakpoint_mmbtu_per_year
	from (
			select	current_num_breakpoints_per_la_yr as num_breakpoints_per_la_yr,
					load_area,
					year,
					total_cost / marginal_mmbtu_new_breakpoint as price_dollars_per_mmbtu,
					marginal_mmbtu_new_breakpoint as marginal_mmbtu_per_year,
					breakpoint_mmbtu_new as breakpoint_mmbtu_per_year
			from
				(select load_area,
						year,
						min_price_la_yr + integer_val * breakpoint_price_step as max_price_in_breakpoint,
						sum( marginal_mmbtu_per_year ) as marginal_mmbtu_new_breakpoint,
						sum( marginal_mmbtu_per_year * price_dollars_per_mmbtu ) as total_cost,
						max( breakpoint_mmbtu_per_year ) as breakpoint_mmbtu_new
				from 
					(select generate_series(1,current_num_breakpoints_per_la_yr) as integer_val) as int_table,
					biomass_solid_supply_curve_breakpoints_prices
					join
						(select load_area,
								year,
								( max( price_dollars_per_mmbtu ) - min( price_dollars_per_mmbtu ) ) / current_num_breakpoints_per_la_yr as breakpoint_price_step,
								min( price_dollars_per_mmbtu ) as min_price_la_yr
							from biomass_solid_supply_curve_breakpoints_prices
							group by load_area, year
						) as breakpoint_price_step_table
					using (load_area, year)
				where 	price_dollars_per_mmbtu >= min_price_la_yr + ( integer_val - 1 ) * breakpoint_price_step
				and		price_dollars_per_mmbtu < min_price_la_yr + integer_val * breakpoint_price_step
				group by load_area, year, max_price_in_breakpoint
				) as tmp_new_breakpoint_table
		UNION
		-- the above code won't add the highest price marginal_mmbtu_per_year because it has (price_dollars_per_mmbtu < min_price_la_yr + integer_val * breakpoint_price_step)
		-- so we add the highest price marginal_mmbtu_per_year to the top of each curve here
		-- we union to the other select to make the row_ids correct because they're a serial column
			select	current_num_breakpoints_per_la_yr as num_breakpoints_per_la_yr,
					load_area,
					year,
					price_dollars_per_mmbtu,
					marginal_mmbtu_per_year,
					breakpoint_mmbtu_per_year
			from 	biomass_solid_supply_curve_breakpoints_prices
			join	(select load_area, year, max(price_dollars_per_mmbtu) as price_dollars_per_mmbtu
						from biomass_solid_supply_curve_breakpoints_prices group by load_area, year) as max_price_table
				using (load_area, year, price_dollars_per_mmbtu)
		) as all_values_for_current_bp_la_yr
		order by load_area, year, price_dollars_per_mmbtu, marginal_mmbtu_per_year, breakpoint_mmbtu_per_year;

	
	-- there isn't any producer surplus to add for the first breakpoint, so price_dollars_per_mmbtu_surplus_adjusted = price_dollars_per_mmbtu
	update biomass_solid_supply_curve_with_producer_surplus
	set		price_dollars_per_mmbtu_surplus_adjusted = price_dollars_per_mmbtu
	from	(select load_area, year, min(price_dollars_per_mmbtu) as min_price_dollars_per_mmbtu
				from biomass_solid_supply_curve_with_producer_surplus
				where num_breakpoints_per_la_yr = current_num_breakpoints_per_la_yr
				group by load_area, year
			) as no_producer_surplus_table
	where	biomass_solid_supply_curve_with_producer_surplus.load_area = no_producer_surplus_table.load_area
	and		biomass_solid_supply_curve_with_producer_surplus.year = no_producer_surplus_table.year
	and		biomass_solid_supply_curve_with_producer_surplus.price_dollars_per_mmbtu = no_producer_surplus_table.min_price_dollars_per_mmbtu
	and		num_breakpoints_per_la_yr = current_num_breakpoints_per_la_yr
	;
	
	-- the loop is done when we've enumerated all the possible combinations of breakpoints
	EXIT WHEN ( current_num_breakpoints_per_la_yr
				= ( select max(count_breakpoints) as max_count_breakpoints from
						(select load_area,
								year,
								count(*) as count_breakpoints
						from biomass_solid_supply_curve_breakpoints_prices
						group by load_area, year) as count_breakpoints_table ) );
	END LOOP;

	
END;
$$ LANGUAGE 'plpgsql';

-- Actually call the function
SELECT bio_producer_surplus();
drop function bio_producer_surplus();


	-- DELETE SUPERFLUOUS VALUES
	-- the above loop will add values for num_breakpoints_per_la_yr above the number of breakpoints actually in the load area
	-- instead of fixing the loop, it's easier to just delete the superfluous entries here:
	drop table if exists la_yr_bp_levels_to_delete;
	create temporary table la_yr_bp_levels_to_delete(
		load_area character varying(11),
		year int,
		num_breakpoints_per_la_yr int,
		primary key (load_area, year, num_breakpoints_per_la_yr)
		);
		
	-- the generate_series generates all num_breakpoints_per_la_yr values above the max one for that load_area-year
	insert into la_yr_bp_levels_to_delete (load_area, year, num_breakpoints_per_la_yr)
		select 	load_area,
				year,
				generate_series(count_breakpoints_la_yr + 1,max_count_breakpoints) as bps_to_delete
		from
			(select load_area, year, count(*) as count_breakpoints_la_yr
				from biomass_solid_supply_curve_breakpoints_prices group by load_area, year) as count_breakpoints_table,
			( select max(count_breakpoints) as max_count_breakpoints from
						(select load_area,
								year,
								count(*) as count_breakpoints
						from biomass_solid_supply_curve_breakpoints_prices
						group by load_area, year) as count_breakpoints_table) as max_count_breakpoints_table;

	-- also, it doesn't make sense to aggregate all of the breakpoints together into a really small number of breakpoints
	-- because while this might help to minimize the error in producer surplus, this increases the error of aggregation
	-- to fix this problem, well delete all breakpoint schemes that have aggregated more than half the breakpoints
	-- i.e. have num_breakpoints_per_la_yr <= count_breakpoints_la_yr/2
		insert into la_yr_bp_levels_to_delete (load_area, year, num_breakpoints_per_la_yr)
		select 	load_area,
				year,
				generate_series(1,cast(floor(count_breakpoints_la_yr/2) as integer)) as bps_to_delete
		from
			(select load_area, year, count(*) as count_breakpoints_la_yr
				from biomass_solid_supply_curve_breakpoints_prices group by load_area, year) as count_breakpoints_table;


	-- now delete all of the unnecessary entries
	delete from biomass_solid_supply_curve_with_producer_surplus ps USING la_yr_bp_levels_to_delete
		WHERE 	ps.load_area = la_yr_bp_levels_to_delete.load_area
		and		ps.year = la_yr_bp_levels_to_delete.year
		and		ps.num_breakpoints_per_la_yr = la_yr_bp_levels_to_delete.num_breakpoints_per_la_yr;


-- a tiny handful (200 out of hundreds of thousands) of rows have a redundant breakpoint_mmbtu_per_year... remove them here
delete from biomass_solid_supply_curve_with_producer_surplus
using					
			(select row_id from
			
				(select 	row_id as row_id_one_level_below,
								breakpoint_mmbtu_per_year as bp_mmbtu_one_level_below,
								price_dollars_per_mmbtu as price_one_level_below
						from 	biomass_solid_supply_curve_with_producer_surplus
					) as one_below_table, 
					biomass_solid_supply_curve_with_producer_surplus
			where 	biomass_solid_supply_curve_with_producer_surplus.row_id = row_id_one_level_below + 1
			and		price_dollars_per_mmbtu_surplus_adjusted is null
			and 	breakpoint_mmbtu_per_year = bp_mmbtu_one_level_below
			) as row_ids_to_delete
where biomass_solid_supply_curve_with_producer_surplus.row_id = row_ids_to_delete.row_id;


-- find the price level one below and calculate the price_dollars_per_mmbtu_surplus_adjusted
	-- the area of the rectangle of producer surplus from moving from the price below to the current price
	-- is the numerator of the second term in the update statement
	-- which is then divided by the change in quantity from moving from the price below to the current price
	-- to give the amount by which the current price increases due to producer surplus
update 	biomass_solid_supply_curve_with_producer_surplus
			set price_dollars_per_mmbtu_surplus_adjusted = 
						price_dollars_per_mmbtu
						+ (price_dollars_per_mmbtu - price_one_level_below) * bp_mmbtu_one_level_below
						/ (breakpoint_mmbtu_per_year - bp_mmbtu_one_level_below)				
			from 	(select 	row_id as row_id_one_level_below,
								breakpoint_mmbtu_per_year as bp_mmbtu_one_level_below,
								price_dollars_per_mmbtu as price_one_level_below
						from 	biomass_solid_supply_curve_with_producer_surplus
					) as one_below_table
			where 	biomass_solid_supply_curve_with_producer_surplus.row_id = row_id_one_level_below + 1
			and		price_dollars_per_mmbtu_surplus_adjusted is null;


-- CALCULATE THE ERROR INDUCED BY EACH BREAKPOINT SCHEME----------
-- we start with the highest price breakpoint (without surplus) in each load area for each year
-- and go down the supply curve until we find a place where 
-- price_dollars_per_ton_producer_surplus_adjusted[n] > price_dollars_per_ton_producer_surplus_adjusted[n+1]
-- when we find this place, update surplus_error_total_cost with the error this induces
-- and then move on down the price levels

drop table if exists row_bp_la_yr_map;
create table row_bp_la_yr_map(
	max_row_id int,
	min_row_id int primary key,
	max_price_dollars_per_mmbtu_surplus_adjusted double precision);

CREATE INDEX max_row_id ON row_bp_la_yr_map (max_row_id);
CREATE INDEX max_min_row_id ON row_bp_la_yr_map (min_row_id, max_row_id);

-- don't include values that only have one breakpoint... they would mess up the loop below and don't have any error anyway
-- we'll update these rows after the main procedure is done
insert into row_bp_la_yr_map (max_row_id, min_row_id, max_price_dollars_per_mmbtu_surplus_adjusted)
	select 	max_row_id,
			min_row_id,
			price_dollars_per_mmbtu_surplus_adjusted as max_price_dollars_per_mmbtu_surplus_adjusted
	from 	biomass_solid_supply_curve_with_producer_surplus
	join	( select 	num_breakpoints_per_la_yr,
						load_area,
						year,
						max(row_id) as max_row_id,
						min(row_id) as min_row_id
				from biomass_solid_supply_curve_with_producer_surplus
				group by num_breakpoints_per_la_yr, load_area, year
			) as row_id_table
	on (max_row_id = row_id)
	where max_row_id <> min_row_id
	order by max_row_id;


CREATE OR REPLACE FUNCTION calc_bio_surplus_error_total_cost() RETURNS VOID AS $$

DECLARE current_max_row_id int;
DECLARE current_min_row_id int;
DECLARE current_row_id int;
DECLARE current_price_dollars_per_mmbtu_surplus_adjusted double precision;

BEGIN


	LOOP

	select (select max_row_id from row_bp_la_yr_map limit 1) into current_max_row_id;
	select current_max_row_id into current_row_id;
	select (select max_price_dollars_per_mmbtu_surplus_adjusted from row_bp_la_yr_map where max_row_id = current_max_row_id)
		into current_price_dollars_per_mmbtu_surplus_adjusted;
	select (select min_row_id from row_bp_la_yr_map where max_row_id = current_max_row_id) into current_min_row_id;

	RAISE NOTICE 'row_bp_la_yr_map is at %',(select count(*) from row_bp_la_yr_map);
	
	-- the below loop won't fill in price_dollars_per_mmbtu_surplus_adjusted_increasing_only
	-- for the max_row_id breakpoint so do it here before the loop
	update biomass_solid_supply_curve_with_producer_surplus
	set price_dollars_per_mmbtu_surplus_adjusted_increasing_only = current_price_dollars_per_mmbtu_surplus_adjusted
	where row_id = current_row_id;

	
		LOOP

		-- find the price level one one below current_row_id and calculate the surplus_error_total_cost
		-- to remain linear in AMPL, supply curves must be strictly increasing in quanity-price.
		-- we're going to move excess producer surplus from any breakpoint that violates this condition
		-- the area of the rectangle that constitues the producer surplus we're not able to capture from any given load_area-year supply curve
		-- is given by the (price - price one level above) * (marginal_mmbtu_per_year from moving from price to price one level above)
		-- the update statement below will calculate negative and positive values - the positive values are the only ones we're interested in
		-- so negative values are zeroed out at the end of the procedure
		update 	biomass_solid_supply_curve_with_producer_surplus
			set surplus_error_total_cost = 
					( price_dollars_per_mmbtu_surplus_adjusted - current_price_dollars_per_mmbtu_surplus_adjusted )
						* marginal_mmbtu_per_year,
				price_dollars_per_mmbtu_surplus_adjusted_increasing_only =
					CASE WHEN ( price_dollars_per_mmbtu_surplus_adjusted > current_price_dollars_per_mmbtu_surplus_adjusted )
						THEN current_price_dollars_per_mmbtu_surplus_adjusted
						ELSE price_dollars_per_mmbtu_surplus_adjusted
						END
			where 	row_id = current_row_id - 1;

		-- update the current price 
		select (select price_dollars_per_mmbtu_surplus_adjusted_increasing_only
				from biomass_solid_supply_curve_with_producer_surplus
				where row_id = current_row_id - 1) 
		into current_price_dollars_per_mmbtu_surplus_adjusted;
	
		-- this updates our current row_id...
		-- this will cause us to leave the loop when we haven't updated the error on the min_row_id entry
		-- this entry can't have any error because it doesn't have any producer surplus...
		-- it's also default 0 in the table definition, so leaving the loop before updating error for min_row_id is OK
		select current_row_id - 1 into current_row_id;
		
		EXIT WHEN ( current_row_id = current_min_row_id );
		END LOOP;
		
	delete from row_bp_la_yr_map where min_row_id = current_row_id;
	
	-- the loop is done when we've enumerated all the possible combinations of breakpoints
	EXIT WHEN ( (select count(*) from row_bp_la_yr_map) = 0 );
	END LOOP;

	-- we do need to have values for places that have only one breakpoint, so update them here before we go any futher
	update biomass_solid_supply_curve_with_producer_surplus
		set	price_dollars_per_mmbtu_surplus_adjusted_increasing_only = price_dollars_per_mmbtu_surplus_adjusted,
			price_dollars_per_mmbtu_surplus_adjusted_and_shifted = price_dollars_per_mmbtu_surplus_adjusted
		where	price_dollars_per_mmbtu_surplus_adjusted_increasing_only is null;

	-- only the positive values of error have meaning here - the negative ones mean that there ISN'T error
	-- but we're interested in summing up the total error, so we eliminate the negative error values here
	update 	biomass_solid_supply_curve_with_producer_surplus
			set surplus_error_total_cost = CASE WHEN surplus_error_total_cost > 0 THEN surplus_error_total_cost ELSE 0 END;
	
END;
$$ LANGUAGE 'plpgsql';

-- Actually call the function
SELECT calc_bio_surplus_error_total_cost();
drop function calc_bio_surplus_error_total_cost();
drop table if exists row_bp_la_yr_map;



-- SPREAD PRODUCER SURPLUS ERROR OUT OVER ALL BREAKPOINTS ABOVE OR EQUAL TO THE OFFENDING BREAKPOINT
-- this makes sure that the producer surplus error that we couldn't include at the correct price level
-- from the AMPL necessity of strictly increasing price-quantity supply curves
-- is added to price levels after and including the correct price level

-- first create a map table that gets us all rows that we're going to need to add additional producer surplus to
-- because they're equal to or above a price that has surplus error
drop table if exists surplus_error_table_map;
create temporary table surplus_error_table_map(
	row_id_of_surplus_error int, 
	row_id_equal_to_or_above_surplus_error int,
	marginal_mmbtu_surplus_error double precision,
	extra_price_dollars_per_mmbtu_to_add double precision,
	primary key (row_id_of_surplus_error, row_id_equal_to_or_above_surplus_error)
	);

-- find all row_id >= row_id_of_surplus_error for each num_breakpoints_per_la_yr-load_area-year combo
insert into surplus_error_table_map (row_id_of_surplus_error, row_id_equal_to_or_above_surplus_error, marginal_mmbtu_surplus_error)
	select 	row_id_of_surplus_error,
			row_id as row_id_equal_to_or_above_surplus_error,
			marginal_mmbtu_per_year as marginal_mmbtu_surplus_error
		from biomass_solid_supply_curve_with_producer_surplus
		join	(select row_id as row_id_of_surplus_error,
						num_breakpoints_per_la_yr,
					load_area,
					year
				from biomass_solid_supply_curve_with_producer_surplus
				where surplus_error_total_cost > 0
				) as row_id_of_surplus_error_table
		using (num_breakpoints_per_la_yr, load_area, year)
		where row_id >= row_id_of_surplus_error;

-- create a table which will help calculate the total cost to spread out over all breakpoints at or above row_id_of_surplus_error
drop table if exists surplus_error_table_quantity;
create temporary table surplus_error_table_quantity(
	row_id_of_surplus_error int primary key, 
	total_mmbtu_equal_to_or_above_surplus_error double precision,
	extra_price_dollars_per_mmbtu_to_add double precision
	);

-- find the total_mmbtu_equal_to_or_above_surplus_error
insert into surplus_error_table_quantity (row_id_of_surplus_error, total_mmbtu_equal_to_or_above_surplus_error)
	select 	row_id_of_surplus_error,
			sum( marginal_mmbtu_per_year ) as total_mmbtu_equal_to_or_above_surplus_error
		from biomass_solid_supply_curve_with_producer_surplus
		join surplus_error_table_map on (row_id = row_id_equal_to_or_above_surplus_error)
		group by row_id_of_surplus_error;

-- find the extra_price_dollars_per_mmbtu_to_add
update surplus_error_table_quantity
	set extra_price_dollars_per_mmbtu_to_add = surplus_error_total_cost / total_mmbtu_equal_to_or_above_surplus_error
	from biomass_solid_supply_curve_with_producer_surplus
	where row_id = row_id_of_surplus_error;

-- map extra_price_dollars_per_mmbtu_to_add to each row_id
-- this adds extra_price_dollars_per_mmbtu_to_add to all row_ids equal to or above row_id_of_surplus_error for the bp-la-yr combo
update surplus_error_table_map
	set extra_price_dollars_per_mmbtu_to_add = surplus_error_table_quantity.extra_price_dollars_per_mmbtu_to_add
	from surplus_error_table_quantity
	where surplus_error_table_quantity.row_id_of_surplus_error = surplus_error_table_map.row_id_of_surplus_error;

-- add up the error row by row
update biomass_solid_supply_curve_with_producer_surplus
	set error_extra_cost_this_bp = sum_extra_price_dollars_per_mmbtu_to_add
	from
		(select row_id_equal_to_or_above_surplus_error as row_id,
				sum(extra_price_dollars_per_mmbtu_to_add) as sum_extra_price_dollars_per_mmbtu_to_add
			from surplus_error_table_map
			group by row_id_equal_to_or_above_surplus_error
		) as extra_table
	where biomass_solid_supply_curve_with_producer_surplus.row_id = extra_table.row_id;	

-- update the prices
update biomass_solid_supply_curve_with_producer_surplus
	set	price_dollars_per_mmbtu_surplus_adjusted_and_shifted =
			price_dollars_per_mmbtu_surplus_adjusted_increasing_only + error_extra_cost_this_bp;

-- CREATE FINAL SUPPLY CURVE!!!!!!!------------
-- now we pick the supply curve that induces the least producer surplus error for each load_area-year combo and we're done!

-- we picked a range of values for the # of breakpoints in order to pick the one with the smallest error in the end
-- this error come from the fact that we're going to move part of the producer surplus from breakpoints that come out with
-- price_dollars_per_ton_producer_surplus_adjusted[n] > price_dollars_per_ton_producer_surplus_adjusted[n+1]

-- this code picks the best number of breakpoints for each load_area-year supply curve
-- i.e. the one with the least amount of error induced by moving around part of the producer surplus

drop table if exists min_error_scheme_la_yr;
create temporary table min_error_scheme_la_yr(
		num_breakpoints_per_la_yr int,
		load_area character varying(11),
		year int,
		primary key (num_breakpoints_per_la_yr, load_area, year) );
		
		
insert into min_error_scheme_la_yr (num_breakpoints_per_la_yr, load_area, year)
	select	min(num_breakpoints_per_la_yr) as num_breakpoints_per_la_yr,
			load_area,
			year
	from	
		(select num_breakpoints_per_la_yr,
				min_error_table.load_area,
				min_error_table.year
		from	(select num_breakpoints_per_la_yr,
						load_area,
						year,
						sum(surplus_error_total_cost) as total_surplus_error_per_bp_scheme
					from biomass_solid_supply_curve_with_producer_surplus
					group by num_breakpoints_per_la_yr, load_area, year
				) as calc_total_error_table,
				(select load_area,
						year,
						min(total_surplus_error_per_bp_scheme) as min_error
				from
					(select num_breakpoints_per_la_yr,
							load_area,
							year,
							sum(surplus_error_total_cost) as total_surplus_error_per_bp_scheme
						from biomass_solid_supply_curve_with_producer_surplus
						group by num_breakpoints_per_la_yr, load_area, year
					) as calc_total_error_table 
				group by load_area, year
				) as min_error_table
		where	calc_total_error_table.load_area = min_error_table.load_area
		and		calc_total_error_table.year = min_error_table.year
		and		min_error = total_surplus_error_per_bp_scheme
		) as bp_schemes_that_have_minimum_error	
	group by load_area, year;


-- now join the schemes that have the minimum error up with their price supply curves	
drop table if exists biomass_solid_supply_curve_with_producer_surplus_final;
create table biomass_solid_supply_curve_with_producer_surplus_final(
	row_id serial,
	breakpoint_id int,
	load_area character varying(11),
	year int,
	price_dollars_per_mmbtu_surplus_adjusted numeric,
	breakpoint_mmbtu_per_year numeric,
	primary key (load_area, year, price_dollars_per_mmbtu_surplus_adjusted)
);

-- the order by properly sets the row_id for use below...
-- the price_dollars_per_mmbtu_surplus_adjusted_and_shifted and breakpoint_mmbtu_per_year must be strictly increasing
-- price_dollars_per_mmbtu_surplus_adjusted_and_shifted is used to group because there can be equal values of price
-- in the biomass_solid_supply_curve_with_producer_surplus table (at the higher breakpoint edge of a producer surplus total cost breakpoint)
-- but all this means is that we want to pick the highest breakpoint_mmbtu_per_year with the same price
insert into biomass_solid_supply_curve_with_producer_surplus_final
	(load_area, year, price_dollars_per_mmbtu_surplus_adjusted, breakpoint_mmbtu_per_year) 
	select 	load_area,
			year,
			price_dollars_per_mmbtu_surplus_adjusted_and_shifted,
			max(breakpoint_mmbtu_per_year) as breakpoint_mmbtu_per_year
		from biomass_solid_supply_curve_with_producer_surplus
		join min_error_scheme_la_yr using (num_breakpoints_per_la_yr, load_area, year)
	group by load_area, year, price_dollars_per_mmbtu_surplus_adjusted_and_shifted
	order by load_area, year, price_dollars_per_mmbtu_surplus_adjusted_and_shifted;

update biomass_solid_supply_curve_with_producer_surplus_final
set breakpoint_id = row_id - min_row_id_la_yr + 1
from (select load_area, year, min(row_id) as min_row_id_la_yr
		from biomass_solid_supply_curve_with_producer_surplus_final group by load_area, year) as min_id_table
where 	min_id_table.load_area = biomass_solid_supply_curve_with_producer_surplus_final.load_area
and		min_id_table.year = biomass_solid_supply_curve_with_producer_surplus_final.year;
		


-- add the last breakpoint
-- AMPL needs an extra price after the last breakpoint
-- as we don't have biomass data after the last, we'll use $999999999/MMBtu
-- biomass solid projects will be constrained to not go over the quantity value for the last breakpoint
insert into biomass_solid_supply_curve_with_producer_surplus_final (breakpoint_id, load_area, year, price_dollars_per_mmbtu_surplus_adjusted)
	select 	max(breakpoint_id) + 1 as breakpoint_id,
			load_area,
			year,
			999999999 as price_dollars_per_mmbtu_surplus_adjusted
	from	biomass_solid_supply_curve_with_producer_surplus_final
	group by load_area, year;

-- ADD YEARS AFTER 2030!!!!!
-- assume the amount of available biomass stays constant in years after we have data
-- this will keep the model working if we look out past 2030
insert into biomass_solid_supply_curve_with_producer_surplus_final
	(breakpoint_id, load_area, year, price_dollars_per_mmbtu_surplus_adjusted, breakpoint_mmbtu_per_year) 
	select	breakpoint_id,
			load_area,
			year + int_val as year,
			price_dollars_per_mmbtu_surplus_adjusted,
			breakpoint_mmbtu_per_year
	from	(select generate_series(1,40) as int_val) as int_val_table,
			biomass_solid_supply_curve_with_producer_surplus_final
	join
		(select load_area, max(year) as year
			from biomass_solid_supply_curve_with_producer_surplus_final
			group by load_area
		) as max_year_table
	using (load_area, year)
		order by load_area, year, breakpoint_mmbtu_per_year;


-- EXPORT BIOMASS SOLID SUPPLY CURVE TO MYSQL-----------------
COPY 
(select breakpoint_id,
		load_area,
		year,
		round(cast(price_dollars_per_mmbtu_surplus_adjusted as numeric), 4) as price_dollars_per_mmbtu,
		round(breakpoint_mmbtu_per_year) as breakpoint_mmbtu_per_year
from biomass_solid_supply_curve_with_producer_surplus_final
order by load_area, year, breakpoint_id)
TO 'DatabasePrep/biomass_solid_supply_curve_breakpoints_prices.csv'
WITH CSV HEADER;



-- BIO GAS-------------------------------
-- biogas potential comes from
-- Milbrandt, A. (2005). Geographic Perspective on the Current Biomass Resource Availability in the United States. 70 pp.; NREL Report No. TP-560-39181.
-- the data of which is included in the ventyx dataset in the county shapefiles
drop table if exists bio_gas_potential;
create table bio_gas_potential(
	load_area character varying(11) primary key,
	tons_methane_per_year double precision,
	mmbtu_per_year double precision );

-- conversion factor from tons methane per year to mmbtu per year:
-- the NREL data has the tonnes of methane, not of landfill gas, so this number can be directly converted
-- into energy using the energy content of natural gas.  The non-methane portions of landfill gas are effectively discarded
-- landfill gas/bio gas: 1031 Btu/ft^3 * ( 1 mbtu / 10^6 Btu ) * ( 1ft^3 /28.3168466 L ) * 22.4L/1mol * 1mol/16g * (10^6g/1t) = 51.0 mbtu/t

insert into bio_gas_potential (load_area, tons_methane_per_year, mmbtu_per_year)
select * from
	(SELECT load_area,
			sum( ( lndfil_ch4 + manure + wwtp_ch4 ) * county_area_fraction_in_load_area ) as tons_methane_per_year,
			sum( ( lndfil_ch4 + manure + wwtp_ch4 ) * county_area_fraction_in_load_area ) * 51.0 as mmbtu_per_year
	from	ventyx_counties_region
	join	biomass_county_to_load_area on (cnty_fips = county_fips)
	group by load_area) as biogas_potential_subtable
where mmbtu_per_year > 100
order by 1,2,3;

-- Canada + Mexico Biogas
-- we'll assume that the amount of biogas available is equal to the per-person amount of biogas available on average in the USA
-- multiplied by the GDP ratio of Mexico or Canada to the USA per person
-- (the amount of biogas depends on the amount of stuff produced/bought, which depends on GDP)
-- this assumes that the canadians make as much waste as USA folks do, and that they have about the same amount of cows (manure) per person
-- the manure fraction is about 10% of the USA number, so even if Canada or Mexico have a different amount of cows per person per GDP than the USA, it isn't likely to matter much

-- get the canadian provincial populations: http://en.wikipedia.org/wiki/List_of_Canadian_provinces_and_territories_by_population
-- and mexico: http://en.wikipedia.org/wiki/List_of_Mexican_states_by_GDP (Baja in 2007 --> $32,161,000,000 / 2,846,500 people = $11298.44/person)
-- and US:http://www.prb.org/Publications/Datasheets/2007/2007WorldPopulationDataSheet.aspx
-- US 2007 GDP estimate is $43800 (http://www.photius.com/rankings/economy/gdp_per_capita_2007_0.html)
-- Canada 2007 GDP is $35700
drop table if exists non_us_load_areas;
create temporary table non_us_load_areas as (select 'MEX_BAJA' as load_area UNION select 'CAN_BC' UNION select 'CAN_ALB');

-- the cast(.. as numeric) makes it such that postgresql doesn't do integer math
-- the cast(.. as numeric) makes it such that postgresql doesn't do integer math
insert into bio_gas_potential (load_area, tons_methane_per_year, mmbtu_per_year)
select 	load_area,
		CASE	WHEN load_area like 'MEX_BAJA' THEN us_biogas_tons_per_person * 2846500 * ( cast(11298 as numeric) / 43800 )
				WHEN load_area like 'CAN_BC' THEN us_biogas_tons_per_person * 4530960 * ( cast(35700 as numeric) / 43800 )
				WHEN load_area like 'CAN_ALB' THEN us_biogas_tons_per_person * 3720946 * ( cast(35700 as numeric) / 43800 )
		END as tons_methane_per_year,
		CASE	WHEN load_area like 'MEX_BAJA' THEN us_biogas_tons_per_person * 2846500 * ( cast(11298 as numeric) / 43800 )
				WHEN load_area like 'CAN_BC' THEN us_biogas_tons_per_person * 4530960 * ( cast(35700 as numeric) / 43800 )
				WHEN load_area like 'CAN_ALB' THEN us_biogas_tons_per_person * 3720946 * ( cast(35700 as numeric) / 43800 )
		END * 51.0 as mmbtu_per_year
	from	non_us_load_areas,
	( select total_us_biogas_tons / 302200000 as us_biogas_tons_per_person from
		( select 	sum( lndfil_ch4 + manure + wwtp_ch4 ) as total_us_biogas_tons
			from ventyx_counties_region ) as biogas_pop_sum_table
	) as us_biogas_tons_per_person_table;



-- the proposed_renewable_sites script sweeps up this table and adds Bio_Solid and Bio_Gas to the sites


