-- run after 'generating unit to load area map in postgresql.sql'

-- imports the ventyx plant data and the assigned load areas...
-- will get cut up by other scripts...
-- 'build proposed plants table.sql'

create database if not exists generator_info;
use generator_info;

drop table if exists ventyx_e_plants_with_load_areas;
create table ventyx_e_plants_with_load_areas(
	load_area varchar(11),
	plant_name varchar(75),
	plant_oper varchar(75),
	op_cap_mw double,
	pln_cap_mw double,
	ret_cap_mw double,
	can_cap_mw double,
	mth_cap_mw double,
	description varchar(130),
	city varchar(75),
	state varchar(20),
	county varchar(75),
	zip_code varchar(20),
	proposed varchar(1),
	loc_code varchar(2),
	source varchar(100),
	plant_id integer,
	plntoperid double,
	eia_id integer,
	rec_id integer primary key,
	INDEX eia_id (eia_id),
	INDEX plant_id (plant_id),
	INDEX load_area (load_area)
);

load data local infile
	'/Volumes/1TB_RAID/Models/Switch\ Input\ Data/Generators/ventyx_e_plants_with_load_areas.csv'
	into table ventyx_e_plants_with_load_areas
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;
	
drop table if exists ventyx_e_units_with_load_areas;
create table ventyx_e_units_with_load_areas(
	load_area varchar(11),
	unit varchar(100),
	plant_name varchar(100),
	pm_group varchar(30),
	statustype varchar(15),
	cap_mw double,
	fuel_type varchar(10),
	loc_code varchar(2),
	source varchar(100),
	unit_id integer primary key,
	plant_id integer,
	INDEX plant_id (plant_id),
	INDEX load_area (load_area)
);

load data local infile
	'/Volumes/1TB_RAID/Models/Switch\ Input\ Data/Generators/ventyx_e_units_with_load_areas.csv'
	into table ventyx_e_units_with_load_areas
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;
	
	
-- PROPOSED PROJECTS
-- also, import a table of renewable sites created in postgresql
drop table if exists proposed_projects;
create table proposed_projects(
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
	into table proposed_projects
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;	


-- BIOMASS SUPPLY CURVES

-- not used yet
-- Drop table if exists biomass_supply_curve_by_load_area;
-- Create table biomass_supply_curve_by_load_area(
-- 	load_area varchar(11),
-- 	fuel varchar(64),
-- 	price_dollars_per_Mbtu double,
-- 	Mbtus_per_year double,
-- 	INDEX la_bio_potential (load_area, fuel, price_dollars_per_Mbtu)
-- );
-- 
-- load data local infile
-- 	'/Volumes/1TB_RAID/Models/Switch\ Input\ Data/Generators/biomass_supply_curve_by_load_area.csv'
-- 	into table biomass_supply_curve_by_load_area
-- 	fields terminated by	','
-- 	optionally enclosed by '"'
-- 	ignore 1 lines;	
	

-- LOADS------------
use loads_wecc;

drop table if exists v1_wecc_load_areas_to_v2_wecc_load_areas;
create table v1_wecc_load_areas_to_v2_wecc_load_areas(
	v1_load_area varchar(11),
	v2_load_area varchar(11),
	population_fraction double,
	INDEX load_areas (v1_load_area, v2_load_area)
);

load data local infile
	'/Volumes/1TB_RAID/Models/GIS/v1_wecc_load_areas_to_v2_wecc_load_areas.csv'
	into table v1_wecc_load_areas_to_v2_wecc_load_areas
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;
	
	