-- create a table of specific proposed projects (predominantly renewable)
-- with associated load areas, straight-line substation connection distances and substation ids
-- which exports easily for further processing in mysql
-- project id is the unique identifier from each of the tables that this data comes from

-- the capacity limit is either in MW if the capacity_limit_conversion is 1, or in other units if the capacity_limit_conversion is nonzero
-- so for CSP and central PV the limit is expressed in land area, not MW
drop table if exists proposed_projects;
create table proposed_projects (
	project_id serial primary key,
	technology character varying(30),
	original_dataset_id bigint,
	load_area character varying(11),
	capacity_limit double precision,
	capacity_limit_conversion double precision,
	connect_cost_per_mw double precision,
	substation_id int,
	location_id int
	);

create index original_dataset_id_index on proposed_projects (original_dataset_id);
SELECT AddGeometryColumn ('public','proposed_projects','the_geom',4326,'POLYGON',2);
SELECT AddGeometryColumn ('public','proposed_projects','substation_connection_geom',4326,'MULTILINESTRING',2);


CREATE INDEX proposed_projects_geom_index
  ON proposed_projects
  USING gist
  (the_geom);

CREATE INDEX proposed_projects_subgeom_index
  ON proposed_projects
  USING gist
  (substation_connection_geom);

-- WIND ----------------------

-- Onshore Wind...
-- there is one onshore farm centroid that is right on the coast in Washington
-- and doesn't quite intersect a load area polygon,
-- so the next insert statement selects one of the two wind points in this polygon 
-- and makes the geometry of that wind point the geometry of the whole (two point) wind farm.
insert into proposed_projects (technology, original_dataset_id, capacity_limit, capacity_limit_conversion, the_geom)
	select 	'Wind',
			wind_farm_id,
			max_mw,
			1 as capacity_limit_conversion,
			the_geom
	from wind_farm_polygons, wecc_load_areas
	where intersects(wecc_load_areas.polygon_geom, wind_farm_polygons.wind_farm_centroid_geom)
	and	wecc_load_areas.polygon_geom && wind_farm_polygons.wind_farm_centroid_geom
	and offshore_onshore like 'onshore';

insert into proposed_projects (technology, original_dataset_id, capacity_limit, capacity_limit_conversion, the_geom)
	select 	'Wind',
			wind_farm_polygons.wind_farm_id,
			wind_farm_polygons.max_mw,
			1 as capacity_limit_conversion,
			wind_farm_polygons.the_geom
	from wind_farm_polygons, wind_farm_points_map, wind_points, wecc_load_areas
	where intersects(wecc_load_areas.polygon_geom, wind_points.the_geom)
	and	wecc_load_areas.polygon_geom && wind_points.the_geom
	and wind_farm_polygons.wind_farm_id = wind_farm_points_map.wind_farm_id
	and wind_farm_points_map.wind_point = wind_points.wind_point
	and wind_points.wind_point = 29994;


-- offshore wind... first connect the farm to the shore with the shortest distance possible,
-- then use that shore point to connect each point to substations

-- the wecc load area polygons have some islands
-- so this makes seperate geometries for all of the different polygons,
-- i.e. it converts multipolygons to their constituent polygons
drop table if exists wecc_dumped_polygons;
create temporary table wecc_dumped_polygons as
		select load_area,
				cast((substring(cast(dump(wecc_load_areas.polygon_geom) as text) from '%,#"_*#"_' for '#')) as geometry) as the_geom
			from wecc_load_areas;

-- to identify the polygon that best represents the (onshore) load area, the one with the greatest area is taken here
drop table if exists onshore_load_area_polygons;
create temporary table onshore_load_area_polygons as
select wecc_dumped_polygons.load_area, wecc_dumped_polygons.the_geom
from wecc_dumped_polygons,
	(select load_area, max(area(the_geom)) as onshore_area
	from wecc_dumped_polygons
	group by load_area) as onshore_area_table
where wecc_dumped_polygons.load_area = onshore_area_table.load_area
and onshore_area_table.onshore_area = area(wecc_dumped_polygons.the_geom);

-- here we do a bunch of jazz to find the nearest point on the onshore polygon to the renewable resource
-- and then make a line from it to the renewable site
drop table if exists offshore_wind_connect_to_shore;
create table offshore_wind_connect_to_shore as
select 	onshore_load_area_polygons.load_area,
		wind_farm_id,
		st_line_interpolate_point(
			st_exteriorring( onshore_load_area_polygons.the_geom ),
			st_line_locate_point(
				st_exteriorring( onshore_load_area_polygons.the_geom ), wind_farm_polygons.wind_farm_centroid_geom ) )
			as shore_point_geom,
		st_makeline(
			st_line_interpolate_point(
				st_exteriorring( onshore_load_area_polygons.the_geom ),
				st_line_locate_point( st_exteriorring( onshore_load_area_polygons.the_geom ),
					wind_farm_polygons.wind_farm_centroid_geom ) ),
			wind_farm_polygons.wind_farm_centroid_geom)
			as connection_line_geom,
		st_distance_sphere(st_line_interpolate_point(st_exteriorring(onshore_load_area_polygons.the_geom), st_line_locate_point(st_exteriorring(onshore_load_area_polygons.the_geom), wind_farm_polygons.wind_farm_centroid_geom)), wind_farm_polygons.wind_farm_centroid_geom)/1000 as connection_length_km
from 	wind_farm_polygons,
		onshore_load_area_polygons
where offshore_onshore like 'offshore';

-- find which load area's shore is nearest to each offshore site
alter table offshore_wind_connect_to_shore add column min_distance_test boolean;
update offshore_wind_connect_to_shore
set min_distance_test = true
from (select wind_farm_id, min(connection_length_km) as min_distance from offshore_wind_connect_to_shore group by wind_farm_id) as minimum_distance_table
where offshore_wind_connect_to_shore.wind_farm_id = minimum_distance_table.wind_farm_id
and offshore_wind_connect_to_shore.connection_length_km = minimum_distance_table.min_distance;

delete from offshore_wind_connect_to_shore where min_distance_test is null;

-- the above works except for the Point Reyes wind point... not going to connect it to the head of Point Reyes
-- the below code moves it to Bolinas, as that is the next closest point
update offshore_wind_connect_to_shore
set 	load_area = wecc_load_areas.load_area,
		shore_point_geom = SETSRID(MakePoint(-122.72726, 37.904),4326),
		connection_line_geom = st_makeline(SETSRID(MakePoint(-123.008, 37.692),4326), SETSRID(MakePoint(-122.72726, 37.904),4326)),
		connection_length_km = st_distance_sphere(SETSRID(MakePoint(-123.008, 37.692),4326), SETSRID(MakePoint(-122.72726, 37.904),4326))/1000
from wecc_load_areas
where wind_farm_id = (select wind_farm_id from wind_farm_polygons where intersects(the_geom, SETSRID(MakePoint(-123.008, 37.692),4326)))
and intersects(expand(SETSRID(MakePoint(-122.72726, 37.904),4326), 0.01), wecc_load_areas.polygon_geom);

-- finally add the offshore wind sites to the proposed renewable sites table
-- the substation connection below is a bit more complicated for these sites as well
-- the expand makes the shore point a really really small polygon - we'll take the centroid again later
insert into proposed_projects (technology, original_dataset_id, capacity_limit, capacity_limit_conversion, the_geom)
	select 	'Offshore_Wind',
			wind_farm_polygons.wind_farm_id,
			max_mw,
			1 as capacity_limit_conversion,
			expand( shore_point_geom, 0.000000001 )
	from offshore_wind_connect_to_shore, wind_farm_polygons
	where offshore_wind_connect_to_shore.wind_farm_id = wind_farm_polygons.wind_farm_id;


-- CENTRAL STATION SOLAR ----------
insert into proposed_projects (technology, original_dataset_id, capacity_limit, capacity_limit_conversion, the_geom)
	select	distinct
			technology,
			insolation_solar_farm_polygons.solar_farm_id,
			total_area_km2,
			capacity_limit_conversion,
			insolation_solar_farm_polygons.the_geom
	from
			wecc_load_areas,
			insolation_solar_farm_polygons,
				(select insolation_solar_farm_map.technology,
						insolation_solar_farm_map.solar_farm_id,
						total_area_km2,
						sum( area_km2 * mw_per_km2 ) / total_area_km2 as capacity_limit_conversion
				from 	
						insolation_solar_farm_map,
						(select technology,
								solar_farm_id,
								sum( area_km2 ) as total_area_km2
						from insolation_solar_farm_map
						where technology in ( 'Central_PV', 'CSP_Trough_No_Storage', 'CSP_Trough_6h_Storage' )
						group by 1,2
						) as total_area_table
				where	insolation_solar_farm_map.technology = total_area_table.technology
				and		insolation_solar_farm_map.solar_farm_id = total_area_table.solar_farm_id
				group by 1,2,3
				) as capacity_limit_conversion_table
	where 	capacity_limit_conversion_table.solar_farm_id = insolation_solar_farm_polygons.solar_farm_id
	and 	intersects(wecc_load_areas.polygon_geom, insolation_solar_farm_polygons.the_geom)
	and		wecc_load_areas.polygon_geom && insolation_solar_farm_polygons.the_geom;



-- CSP_Trough_6h_Storage
-- this is a quick fix to add CSP_Trough_6h_Storage to the model before the cap factors get finished from SAM
-- TO BE REMOVED WHEN THE CAP_FACTORS ARE CALCULATED FROM SAM
-- calculated below, the mw_per_km2 * 0.61 takes into account the reduced mw_per_km2 for storage,
-- as more solar field is added for storage

-- select min(area_diff_fraction), max(area_diff_fraction), avg(area_diff_fraction), stddev(area_diff_fraction) from 
-- 	(select no_storage.grid_id, storage_6h.mw_per_km2/no_storage.mw_per_km2 as area_diff_fraction
-- 		from insolation_csp_field_aperture as no_storage, insolation_csp_field_aperture as storage_6h
-- 		where no_storage.csp_technology = 'CSP_Trough_No_Storage' and storage_6h.csp_technology = 'CSP_Trough_6h_Storage'
-- 		and no_storage.grid_id = storage_6h.grid_id) as area_diff_table;

-- some suny grid_ids are somewhat in two solar farms - here we arbitrarily take the max of the solar_farm_id to figure out which one should go where
-- and then scale up the potential of each individual grid cell to be that of the larger set
-- this is effectivly assuming that the output of the single cell will be like that of the aggregate
-- not quite true, but not too bad of an assumption

delete from proposed_projects where technology = 'CSP_Trough_6h_Storage';

insert into proposed_projects (technology, original_dataset_id, capacity_limit, capacity_limit_conversion, the_geom)
	select 	'CSP_Trough_6h_Storage',
			suny_grid_id,
			total_area_km2,
			sum( area_km2 * ( mw_per_km2 * 0.61 ) ) / total_area_km2 as capacity_limit_conversion,
			the_geom
		from 	insolation_solar_farm_map,
				insolation_solar_farm_polygons,
				(select technology,
						solar_farm_id,
						sum( area_km2 ) as total_area_km2
					from insolation_solar_farm_map
					where technology = 'CSP_Trough_No_Storage'
					group by 1,2
					) as total_area_table,
				(select csp_sites_3tier.id as suny_grid_id,
						max(solar_farm_id) as solar_farm_id
					from insolation_solar_farm_polygons,
						 csp_sites_3tier
					where 	intersects(insolation_solar_farm_polygons.the_geom, expand(csp_sites_3tier.the_geom,0.05))
					and 	insolation_solar_farm_polygons.the_geom && expand(csp_sites_3tier.the_geom,0.05)
					group by 1) as suny_grid_solar_farm_map_table
		where	insolation_solar_farm_map.technology = total_area_table.technology
		and		suny_grid_solar_farm_map_table.solar_farm_id = insolation_solar_farm_map.solar_farm_id
		and		suny_grid_solar_farm_map_table.solar_farm_id = total_area_table.solar_farm_id
		and		suny_grid_solar_farm_map_table.solar_farm_id = insolation_solar_farm_polygons.solar_farm_id
		group by 1,2,3,5
		;

delete from proposed_projects
	where technology = 'CSP_Trough_6h_Storage'
	and original_dataset_id not in (
			select distinct original_dataset_id from proposed_projects, wecc_load_areas
			where technology = 'CSP_Trough_6h_Storage'
			and intersects(proposed_projects.the_geom, wecc_load_areas.polygon_geom)
);


-- DISTRIBUTED PV ----------
-- the distinct is added here because some polygons touch two load areas
-- (they were divided on load area lines but some parts overlap a bit)
-- so we'll assign load areas below
insert into proposed_projects (technology, original_dataset_id, capacity_limit, capacity_limit_conversion, the_geom)
	select 	distinct
			insolation_solar_farm_map.technology,
			insolation_solar_farm_map.solar_farm_id,
			total_mw,
			1 as capacity_limit_conversion,
			the_geom
		from 	wecc_load_areas,
				insolation_solar_farm_map,
				insolation_distributed_pv_polygons,
				(select technology,
						solar_farm_id,
						sum( area_km2 * mw_per_km2 ) as total_mw
					from insolation_solar_farm_map
					where technology in ( 'Residential_PV', 'Commercial_PV' )
					group by 1,2
					) as total_area_table
		where	insolation_solar_farm_map.technology = total_area_table.technology
		and		insolation_solar_farm_map.solar_farm_id = total_area_table.solar_farm_id
		and		insolation_solar_farm_map.solar_farm_id = insolation_distributed_pv_polygons.solar_farm_id
		and 	intersects( wecc_load_areas.polygon_geom, insolation_distributed_pv_polygons.the_geom )
		and		wecc_load_areas.polygon_geom && insolation_distributed_pv_polygons.the_geom
		;

-- give the distributed PV farms load areas
update	proposed_projects
	set		load_area = wecc_load_areas.load_area
	from	wecc_load_areas,
			(select
					technology,
					original_dataset_id,
					max( area( intersection( wecc_load_areas.polygon_geom, proposed_projects.the_geom ) ) ) as intersection_area
				from	wecc_load_areas,
						proposed_projects
				where 	wecc_load_areas.polygon_geom && proposed_projects.the_geom
				and		technology in ( 'Residential_PV', 'Commercial_PV' )
				group by 1,2
			) as dist_pv_load_areas
	where	proposed_projects.technology = dist_pv_load_areas.technology
	and		proposed_projects.original_dataset_id = dist_pv_load_areas.original_dataset_id
	and		intersection_area = area( intersection( wecc_load_areas.polygon_geom, proposed_projects.the_geom ) )
	and		wecc_load_areas.polygon_geom && proposed_projects.the_geom
	;


-- BIOMASS ---------------------
insert into proposed_projects (technology, load_area, capacity_limit, capacity_limit_conversion)
	select 	'Biomass_IGCC',
			load_area,
			cap_mw,
			1 as capacity_limit_conversion
		from biomass_supply_by_load_area
		where fuel like 'Bio_Solid';

insert into proposed_projects (technology, load_area, capacity_limit, capacity_limit_conversion)
	select 	'Bio_Gas',
			load_area,
			cap_mw,
			1 as capacity_limit_conversion
		from biomass_supply_by_load_area
		where fuel like 'Bio_Gas';




-- GEOTHERMAL -------------------
-- we have to merge two datasets here
-- one from the ventyx folks and one from the wrez folks
-- there are some repeat sites, of which we take the one with higher capacity
-- ... but there are many sites unique to only one dataset

-- this query gets the likely list of similar projects
-- from a survey of the sites on a map, the expand(0.2) is about the furthest away duplicate projects are away from each other
-- select 	project as plant_name_wrez,
-- 		alt_name as alternate_name_wrez,
-- 		objectid_1 as plant_id_wrez,
-- 		mw as planned_mw_wrez,
-- 		ventyx_e_plants_point.plant_name as plant_name_ventyx,
-- 		ventyx_e_plants_point.plant_oper as plant_operator_ventyx,
-- 		ventyx_e_plants_point.plant_id as plant_id_ventyx,
-- 		planned_mw_ventyx
-- from 	geothermal_sites_wrez,
-- 		ventyx_e_plants_point,
-- 		(select plant_name, plant_id, sum(cap_mw) as planned_mw_ventyx
-- 			from ventyx_e_units_point
-- 			where fuel_type like 'GEO'
-- 			and statustype like 'Planned'
-- 			group by plant_name, plant_id) as ventyx_planned_capacity_table
-- where 	intersects(expand(geothermal_sites_wrez.the_geom, 0.2), ventyx_e_plants_point.the_geom)
-- and 	ventyx_planned_capacity_table.plant_id = ventyx_e_plants_point.plant_id
-- order by plant_id_wrez, plant_id_ventyx;

-- from a manual inspection of the query above, sites that should be deleted, followed by thier ids, are:
-- WREZ:
-- "McCoy", 18
-- "Cove Fort - Sulpherdale", 20
-- "Thermo HS", 25
-- "Raft River", 35
-- "Blue Mountain (aka Faulkner)", 44
-- "Geysers (incl Calistoga & Clear Lake [Sulphur Bank])", 46
-- "Buffalo Valley", 48
-- "Colado", 50
-- "Brawley (sum of Brawley, East Brawley, and South Brawley)", 57
-- "Empire (aka San Emidio)", 58
-- "Grass Valley  (Lander County)", 63
-- "Lee Hot Springs", 77
-- "North Valley (incl. Black Warrior, Fireball Ridge)", 81
-- "Pumpernickel Valley", 85
-- "Reese River (aka Shoshone)", 87
-- "Silver Peak", 91
-- "Soda Lake", 93
-- "Truckhaven (incl. San Felipe prospect)", 100
-- "Newberry Caldera", 114
-- "Neal Hot Springs (incl. Vale)", 130
-- "Crump's Hot Springs", 131
-- "Crystal-Madsen" ("Rennaissance Project, Davis #1 Well"), 138
-- VENTYX:
-- "Gerlach Geothermal", 750282
-- "Rye Patch", 587773
-- "Salt Wells Geothermal", 651008
-- "Salton Sea 6", 405326

-- create a table that merges the two datasets
drop table if exists geothermal_merge;
create table geothermal_merge(
	geothermal_id int,
	serial_id serial,
	plant_name character varying(256),
	ventyx_id int,
	wrez_id int,
	capacity_limit_mw double precision,
	the_geom geometry
);

insert into geothermal_merge (plant_name, ventyx_id, capacity_limit_mw, the_geom)
	select  plant_name, plant_id, sum(cap_mw), centroid(st_collect(the_geom))
			from ventyx_e_units_point
 			where fuel_type like 'GEO'
 			and statustype like 'Planned'
			and plant_id not in (750282, 587773, 651008, 405326)
 			group by plant_name, plant_id
 			order by plant_id;
 			
insert into geothermal_merge (plant_name, wrez_id, capacity_limit_mw, the_geom)
	select	project, objectid_1, mw, the_geom
			from geothermal_sites_wrez
			where objectid_1 not in (18, 20, 25, 35, 44, 46, 48, 50, 57, 58, 63, 77, 81, 85, 87, 91, 93, 100, 114, 130, 131, 138)
			order by objectid_1;

-- a few sites have the same geometry but different site names, so the geothermal_id corrects this problem
-- it will be used to export to proposed_plants, as the location_id column needs to be unique for the_geom
update geothermal_merge
	set geothermal_id = id_table.geothermal_id
	from (select min(serial_id) as geothermal_id, the_geom from geothermal_merge group by the_geom) as id_table
	where geothermal_merge.the_geom = id_table.the_geom;

-- now insert the geothermal sites into the larger renewable sites table
-- the expand makes each site a tiny tiny polygon ( to conform to the enforce geotype constraint of proposed_projects )
insert into proposed_projects (technology, original_dataset_id, capacity_limit, capacity_limit_conversion, the_geom)
	select 	'Geothermal',
			geothermal_id,
			sum(capacity_limit_mw) as capacity_limit,
			1 as capacity_limit_conversion,
			expand( geothermal_merge.the_geom, 0.00000001 )
		from geothermal_merge, wecc_load_areas
		where  	intersects(wecc_load_areas.polygon_geom, geothermal_merge.the_geom)
		and		wecc_load_areas.polygon_geom && geothermal_merge.the_geom
		group by geothermal_id, the_geom;


-- COMPRESSED AIR ENERGY STORAGE (CAES)
-- only aquifers for now - the 83.3333 is derived from Samir Succar's thesis on CAES... it might not be valid for all aquifer types
-- S. Succar, R. H. Williams, ÒCompressed Air Energy Storage: Theory, Resources, And Applications For Wind PowerÓ Princeton Environmental Institute Report, April 2008
-- TODO: include bedded and domal salt and find solid numbers for CAES potentials
-- TODO: Find maps for Canada and Mexico
-- capped at 100000 GW as sometimes cplex runs into problems with really large numbers
insert into proposed_projects (technology, load_area, capacity_limit, capacity_limit_conversion)
		select 
			'Compressed_Air_Energy_Storage' as technology,
			load_area,
			83.33333 * sum(area(transform(intersection(aquifers_us.the_geom, wecc_load_areas.polygon_geom), 2163))/1000000) as caes_potential_mw,
			1 as capacity_limit_conversion
		from aquifers_us, wecc_load_areas
		where intersects(aquifers_us.the_geom, wecc_load_areas.polygon_geom)
		and aquifers_us.the_geom && wecc_load_areas.polygon_geom
		and rock_type in (100, 300, 400, 500, 600)
		and load_area not like 'CAN%'
		and load_area not like 'MEX%'
		group by 1,2;

update proposed_projects set capacity_limit = 100000 where capacity_limit > 100000 and technology = 'Compressed_Air_Energy_Storage';

-- code for bedded salt and aquifers
-- more involved queries to get these potentials can be found in the CAES folder in the GIS directory
-- the potential ( 0.0281065 mw / km^2 ) is derived from the ReEDs potentials by summing up all the capacity across the US and dividing by the total polygon area of bedded salt
-- should get a better reference in the future

-- insert into proposed_projects (technology, load_area, capacity_limit, capacity_limit_conversion)
-- 	select 	'Compressed_Air_Energy_Storage' as technology,
-- 			load_area,
-- 			sum(caes_potential_mw),
-- 			1 as capacity_limit_conversion
-- 		from (
-- 		select 
-- 			load_area,
-- 			geology,
-- 			sum(area(transform(intersection(caes_geology.the_geom, wecc_load_areas.polygon_geom), 2163))/1000000) as total_area_km2,
-- 			CASE WHEN geology = 'bedded_salt'
-- 				THEN 0.0281065 * sum(area(transform(intersection(caes_geology.the_geom, wecc_load_areas.polygon_geom), 2163))/1000000)
-- 			END
-- 				 as caes_potential_mw
-- 		from caes_geology, wecc_load_areas
-- 		where intersects(caes_geology.the_geom, wecc_load_areas.polygon_geom)
-- 		and caes_geology.the_geom && wecc_load_areas.polygon_geom
-- 		and geology not like 'aquifers'
-- 		group by 1,2
-- 	UNION
-- 		select 
-- 			load_area,
-- 			'aquifers' as geology,
-- 			sum(area(transform(intersection(aquifers_us.the_geom, wecc_load_areas.polygon_geom), 2163))/1000000) as total_area_km2,
-- 			83.33333 * sum(area(transform(intersection(aquifers_us.the_geom, wecc_load_areas.polygon_geom), 2163))/1000000) as caes_potential_mw
-- 		from aquifers_us, wecc_load_areas
-- 		where intersects(aquifers_us.the_geom, wecc_load_areas.polygon_geom)
-- 		and aquifers_us.the_geom && wecc_load_areas.polygon_geom
-- 		and rock_type in (100, 300, 400, 500, 600)
-- 		group by 1,2
-- 		) as geology_specific_supply_curve
-- 		group by 2;



-- ALL RESOURCES ----------
-- load area, substations, timezone difference from utc


-- gets the distance from every renewable site to every bus >= 115 kV in WECC
-- and gets the load area of that bus such that the load area of the renewable site can be determined

-- for Offshore Wind, it does this from the nearest onshore point....
-- the connection distance and subsequently cost has to be corrected below

-- CONNECT TO SUBSTATIONS
-- distributed pv is excluded here becasue we don't connect them to substations (they're just on local roofs)
-- biomass is distributed througout load areas, so we don't have the resolution to connect it to substations - in AMPL it will get the generic connection cost.
drop table if exists renewable_site_to_substation;
create temporary table renewable_site_to_substation as
select 	proposed_projects.project_id,
		ventyx_e_substn_point.rec_id as substation_rec_id,
		wecc_load_areas.load_area,
		st_distance_sphere(
			st_line_interpolate_point(
				st_exteriorring( proposed_projects.the_geom ),
				st_line_locate_point(
					st_exteriorring( proposed_projects.the_geom ), ventyx_e_substn_point.the_geom )
				),
			ventyx_e_substn_point.the_geom ) / 1000 as distance_km,
		ventyx_e_substn_point.the_geom
from 	proposed_projects,
		ventyx_e_substn_point,
		wecc_load_areas
where 	ventyx_e_substn_point.mx_volt_kv >= 115
and 	ventyx_e_substn_point.proposed like 'In Service'
and		intersects(ventyx_e_substn_point.the_geom, wecc_load_areas.polygon_geom)
and		ventyx_e_substn_point.the_geom && wecc_load_areas.polygon_geom
and		technology <> 'Residential_PV'
and		technology <> 'Commercial_PV'
and 	technology <> 'Biomass_IGCC'
and		technology <> 'Bio_Gas'
and		technology <> 'Compressed_Air_Energy_Storage'
	;


-- updates the  sites with connection distances, load areas, substation hookups
-- and labels the ones that are in wecc
-- the connection cost is specified here as $1000/MW-km... should be more specific in the future
-- also, get better references from the Wiser LBNL report
update	proposed_projects
set 	connect_cost_per_mw = minimum_distance_table.min_distance * 1000,
		substation_id = renewable_site_to_substation.substation_rec_id,
		load_area = renewable_site_to_substation.load_area
from 	renewable_site_to_substation,
		(select project_id,
				min(distance_km) as min_distance
			from renewable_site_to_substation
			group by project_id) as minimum_distance_table
where 	proposed_projects.project_id = renewable_site_to_substation.project_id
and 	proposed_projects.project_id = minimum_distance_table.project_id
and		minimum_distance_table.min_distance = 		st_distance_sphere(
														st_line_interpolate_point(
															st_exteriorring( proposed_projects.the_geom ),
															st_line_locate_point(
																st_exteriorring( proposed_projects.the_geom ),
																renewable_site_to_substation.the_geom ) ),
														renewable_site_to_substation.the_geom ) / 1000
	;		



-- not strictly necessary, but nice to have and easy to do, 
-- we'll make a geometry linestring connecting each proposed renewable site to each substation
-- the connection for offshore wind gets updated below
-- the st_multi just makes what was a linestring into a multilinestring, which for single linestrings does nothing
-- it's only important because the offshore wind procedure returns a multilinestring (the ends don't quite match up)
update proposed_projects
set substation_connection_geom = st_multi(
									st_makeline( 
										ventyx_e_substn_point.the_geom,
										st_line_interpolate_point(
											st_exteriorring( proposed_projects.the_geom ),
											st_line_locate_point(
												st_exteriorring( proposed_projects.the_geom ),
												ventyx_e_substn_point.the_geom ) ) ) )
from ventyx_e_substn_point
where proposed_projects.substation_id = ventyx_e_substn_point.rec_id;



-- the connection process for offshore wind is different because we have to hit the shore first
-- then connect from the coast to the nearest substation.
-- here the offshore connection cost is assumed to be 5x the onshore connection cost... should try to find a reference though.
-- because the offshore/onshore connection point is a really small polygon instead of a point, there will be a small discontinuity in the connection geometry
update proposed_projects
set 	connect_cost_per_mw = proposed_projects.connect_cost_per_mw + 5 * 1000 * offshore_wind_connect_to_shore.connection_length_km,
		the_geom = wind_farm_polygons.the_geom,
		substation_connection_geom = st_union(proposed_projects.substation_connection_geom, offshore_wind_connect_to_shore.connection_line_geom)
from 	offshore_wind_connect_to_shore, wind_farm_polygons
where	offshore_wind_connect_to_shore.wind_farm_id = proposed_projects.original_dataset_id
and		offshore_wind_connect_to_shore.wind_farm_id = wind_farm_polygons.wind_farm_id
and		technology like 'Offshore_Wind';

drop table offshore_wind_connect_to_shore;


-- add location_ids, which will unique to each geometry and will be used to make a constraint over maximum land area usage
drop table if exists proposed_projects_location_ids;
create table proposed_projects_location_ids(
	location_id serial primary key);
	
SELECT AddGeometryColumn ('public','proposed_projects_location_ids','the_geom',4326,'POLYGON',2);

CREATE INDEX proposed_projects_location_ids_geom_index
  ON proposed_projects_location_ids
  USING gist
  (the_geom);

insert into proposed_projects_location_ids (the_geom)
	select distinct(the_geom) from proposed_projects where the_geom is not null;

update proposed_projects
	set location_id = proposed_projects_location_ids.location_id
	from proposed_projects_location_ids
	where proposed_projects.the_geom = proposed_projects_location_ids.the_geom
	and		proposed_projects.the_geom && proposed_projects_location_ids.the_geom;



-- export to csv to get back to mysql
-- could use ogr2ogr if desired....
COPY 
(select project_id,
		technology,
		original_dataset_id,
		load_area,
		capacity_limit,
		capacity_limit_conversion,
		connect_cost_per_mw,
		location_id
from proposed_projects )
TO '/Volumes/1TB_RAID/Models/Switch\ Input\ Data/Generators/proposed_projects.csv'
WITH 	CSV
		HEADER;




-- OLD CODE-----



-- no hydro builds yet
-- -- HYDRO (CONVENTIONAL) ---------
-- insert into proposed_projects (technology, original_dataset_id, capacity_limit, the_geom)
-- 	select conventional_hydro_sites_table.*
-- 		from wecc_load_areas,
-- 			(select  'Hydro', plant_id, sum(cap_mw) as capacity_limit, plant_name, centroid(st_collect(the_geom)) as the_geom
-- 				from ventyx_e_units_point
--  				where pm_group like 'Hydraulic Turbine'
--  				and plant_id not in (select plant_id from ventyx_e_plants_point where county like 'Offshore')
--  				and statustype like 'Planned'
--  				group by plant_name, plant_id
--  				order by plant_id) as conventional_hydro_sites_table
-- 		where (intersects(wecc_load_areas.polygon_geom, conventional_hydro_sites_table.the_geom));
-- 
-- 
-- -- HYDRO (PUMPED STORAGE) ---------
-- insert into proposed_projects (technology, original_dataset_id, capacity_limit, site_name_or_notes, the_geom)
-- 	select pumped_storage_hydro_sites_table.*
-- 		from wecc_load_areas,
-- 			(select  'Pumped_Storage', plant_id, sum(cap_mw) as capacity_limit, plant_name, centroid(st_collect(the_geom)) as the_geom
-- 				from ventyx_e_units_point
--  				where pm_group like 'Pumped Storage'
--  				and plant_id not in (select plant_id from ventyx_e_plants_point where county like 'Offshore')
--  				and statustype like 'Planned'
--  				group by plant_name, plant_id
--  				order by plant_id) as pumped_storage_hydro_sites_table
-- 		where (intersects(wecc_load_areas.polygon_geom, pumped_storage_hydro_sites_table.the_geom));
-- 




-- -- extra code to create a table of currently proposed capacity grouped by load area, primemover and fuel
-- -- such that these sites could be developed quickly at the start of the model if desires
-- -- this table is envisioned to be used as a maximum build constraint within the first investment period if it is close to the current year
-- -- I don't know to what fuel REF and WH refer, but they're both small, so I'll take them out.
-- drop table if exists proposed_capacity_by_load_area_generic;
-- create table proposed_capacity_by_load_area_generic with oids as
-- SELECT	load_area,
-- 		replace(pm_group, ' ', '_'),
-- 		fuel_type,
-- 		sum(cap_mw) as proposed_capacity_limit
-- 	FROM ventyx_e_units_point, wecc_load_areas
-- 	where 		statustype like 'Planned'
-- 		and 	intersects(wecc_load_areas.polygon_geom, ventyx_e_units_point.the_geom)
-- 		and		fuel_type not in ('REF', 'WH')
-- 		and 	plant_id not in (select plant_id from ventyx_e_plants_point where county like 'Offshore')
-- 	group by load_area, pm_group, fuel_type
--   	order by load_area, pm_group, fuel_type;
--   
-- drop table if exists offshore_proposed_tmp;
-- create temporary table offshore_proposed_tmp as 
-- select	load_area,
-- 		pm_group,
-- 		fuel_type,
-- 		sum(cap_mw) as proposed_capacity_limit
-- 	from wecc_load_areas, ventyx_e_units_point,
-- 		(select unit_id, min(ST_distance(wecc_load_areas.polygon_geom, ventyx_e_units_point.the_geom)) as min_distance
-- 		from wecc_load_areas, ventyx_e_units_point
-- 		where plant_id in (select plant_id from ventyx_e_plants_point where county like 'Offshore' and state in ('WA', 'OR', 'CA', 'BC'))
-- 		and statustype like 'Planned'
-- 		group by unit_id) as unit_id_load_area_distance_table
-- 	where min_distance = ST_distance(wecc_load_areas.polygon_geom, ventyx_e_units_point.the_geom)
-- 	and unit_id_load_area_distance_table.unit_id = ventyx_e_units_point.unit_id
-- 	group by load_area, pm_group, fuel_type;
-- 
-- insert into proposed_capacity_by_load_area_generic
-- 	select load_area, 'Offshore_Wind_Turbine', fuel_type, proposed_capacity_limit
-- 	from offshore_proposed_tmp
-- 	where pm_group like 'Wind Turbine';
-- 
-- insert into proposed_capacity_by_load_area_generic
-- 	select load_area,'Offshore_Hydraulic_Turbine', fuel_type, proposed_capacity_limit
-- 	from offshore_proposed_tmp
-- 	where pm_group like 'Hydraulic Turbine';
-- 
