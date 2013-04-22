-- create a table of solar proposed projects to export to mysql
-- with associated load areas, straight-line substation connection distances and substation ids
-- which exports easily for further processing in mysql
-- project id is the unique identifier from each of the tables that this data comes from

-- the capacity limit is either in MW if the capacity_limit_conversion is 1, or in other units if the capacity_limit_conversion is nonzero
-- so for CSP and central PV the limit is expressed in land area, not MW
alter user jimmy set search_path to public;

drop table if exists proposed_projects_solar_update;
create table proposed_projects_solar_update (
	project_id int primary key,
	technology varchar(64),
	original_dataset_id bigint,
	load_area character varying(11),
	capacity_limit double precision,
	capacity_limit_conversion double precision,
	connect_cost_per_mw double precision,
	substation_id int,
	location_id int,
	avg_capacity_factor double precision
	);

SELECT AddGeometryColumn ('public','proposed_projects_solar_update','the_geom',4326,'MULTIPOLYGON',2);
SELECT AddGeometryColumn ('public','proposed_projects_solar_update','centroid_geom',4326,'POINT',2);
SELECT AddGeometryColumn ('public','proposed_projects_solar_update','substation_connection_geom',4326,'MULTILINESTRING',2);

CREATE INDEX ON proposed_projects_solar_update USING gist (the_geom);
CREATE INDEX ON proposed_projects_solar_update USING gist (centroid_geom);
CREATE INDEX ON proposed_projects_solar_update USING gist (substation_connection_geom);


-- the distinct is added here because some polygons touch two load areas
insert into proposed_projects_solar_update (project_id, technology, original_dataset_id, capacity_limit, capacity_limit_conversion, avg_capacity_factor, the_geom, centroid_geom)
	select	distinct
			project_id,
			technology,
			project_id,
			CASE WHEN technology in ('Residential_PV', 'Commercial_PV') THEN area_km_2 * mw_per_km_2 ELSE area_km_2 END as capacity_limit,
			CASE WHEN technology in ('Residential_PV', 'Commercial_PV') THEN 1 ELSE mw_per_km_2 END as capacity_limit_conversion,
			capacity_factor,
			the_geom,
			ST_Centroid(the_geom)
	from	usa_can.solar_sites,
			wecc_load_areas
	where 	st_intersects(wecc_load_areas.polygon_geom, solar_sites.the_geom);


-- CONNECT TO SUBSTATIONS
-- distributed pv is excluded here because we don't connect them to substations (they're just on local roofs)
-- load area and substations

-- gets the distance from every central station solar site to every bus >= 115 kV in WECC
-- and gets the load area of that bus such that the load area of the renewable site can be determined
DROP TABLE IF EXISTS substation_load_area_table;
CREATE TEMPORARY TABLE substation_load_area_table (rec_id int primary key, load_area varchar(11));

INSERT INTO substation_load_area_table (rec_id, load_area)
SELECT rec_id, load_area
	FROM wecc_load_areas,
		 ventyx_may_2012.e_substn_point s
	where 	s.mx_volt_kv >= 115
	and 	s.proposed like 'In Service'
	and		ST_intersects(s.the_geom, polygon_geom);
		 
UPDATE proposed_projects_solar_update
SET 	substation_id = rec_id,
		load_area = substation_match_table.load_area
FROM
	( SELECT DISTINCT ON(project_id)  project_id, rec_id, la.load_area
		  	FROM 	proposed_projects_solar_update p,
		  	 		ventyx_may_2012.e_substn_point s
		  	JOIN	substation_load_area_table la USING (rec_id)
			where	technology not in ('Residential_PV', 'Commercial_PV')
	  		AND	    ST_DWithin(s.the_geom, centroid_geom, 5)
		    ORDER BY project_id, ST_Distance(s.the_geom::geography,centroid_geom::geography)
	) as substation_match_table
WHERE substation_match_table.project_id = proposed_projects_solar_update.project_id;

-- st_distance returns in meters, so divide by 1000 to turn into km, but then connection costs $1000/MW/km, so multiply by 1000
UPDATE 	proposed_projects_solar_update
SET 	connect_cost_per_mw = st_distance(s.the_geom::geography, centroid_geom::geography) / 1000 * 1000,
		substation_connection_geom = ST_Multi(st_makeline(s.the_geom, centroid_geom))
FROM	ventyx_may_2012.e_substn_point s
WHERE	substation_id = rec_id;





-- give the distributed PV sites load areas
update	proposed_projects_solar_update
	set		load_area = dist_load_area.load_area
	from	(SELECT distinct on (project_id) project_id, wecc_load_areas.load_area
					FROM  proposed_projects_solar_update,
						  wecc_load_areas
					WHERE technology in ( 'Residential_PV', 'Commercial_PV' )
				ORDER BY project_id, ST_Area(ST_Intersection(the_geom, polygon_geom))
			) as dist_load_area
	WHERE dist_load_area.project_id = proposed_projects_solar_update.project_id;




-- LOCATION IDS
-- add location_ids, which will be unique to each geometry and will be used to make a constraint over maximum land area usage
drop table if exists proposed_projects_solar_update_location_ids;
create table proposed_projects_solar_update_location_ids(
	location_id serial primary key);

ALTER SEQUENCE proposed_projects_solar_update_location_ids_location_id_seq RESTART WITH 100000;
	
SELECT AddGeometryColumn ('public','proposed_projects_solar_update_location_ids','centroid_geom',4326,'POINT',2);

CREATE INDEX ON proposed_projects_solar_update_location_ids USING gist (centroid_geom);

insert into proposed_projects_solar_update_location_ids (centroid_geom)
	select distinct(centroid_geom) from proposed_projects_solar_update where centroid_geom is not null;

update proposed_projects_solar_update
	set location_id = proposed_projects_solar_update_location_ids.location_id
	from proposed_projects_solar_update_location_ids
	where 	proposed_projects_solar_update.centroid_geom = proposed_projects_solar_update_location_ids.centroid_geom
	and 	proposed_projects_solar_update_location_ids.centroid_geom is not null;



-- export to csv to get back to mysql
COPY 
(select project_id,
		technology,
		original_dataset_id,
		load_area,
		capacity_limit,
		capacity_limit_conversion,
		connect_cost_per_mw,
		location_id,
		avg_capacity_factor
from proposed_projects_solar_update
order by project_id)
TO '/Volumes/switch/Models/USA_CAN/Solar/Mysql/proposed_projects_solar_update.csv'
WITH 	CSV
		HEADER;

-- timepoints in mysql start at 0 whereas in postgresql they start at 1... 
-- we're going into mysql, so move the timepoint_id back 1
COPY 
(select project_id,
		timepoint_id - 1 as timepoint_id,
		capacity_factor
from 	proposed_projects_solar_update
JOIN	solar_hourly_timeseries USING (project_id))
TO '/Volumes/switch/Models/USA_CAN/Solar/Mysql/solar_hourly_timeseries.csv'
WITH 	CSV
		HEADER;

