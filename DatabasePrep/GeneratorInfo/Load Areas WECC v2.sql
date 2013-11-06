-- Load Area Shapefiles script

CREATE SCHEMA wecc_inputs AUTHORIZATION jimmy;
ALTER USER jimmy SET SEARCH_PATH TO wecc_inputs, public;

-- a script that does all of the non-generator queries to make working load areas for WECC.
-- whole script should be run after any change in the wecc load area polygon shapefile.

-- first, load up the latest wecc load area shapefile into postgresql...
-- modify the .dbf file to the one you want to load
-- shp2pgsql -s 4326 /Volumes/1TB_RAID-1/Models/GIS/New\ LoadZone\ Shape\ Files/wecc_load_areas_10_3_09_5.dbf wecc_load_areas | psql -h xserve-rael.erg.berkeley.edu -U postgres -d switch_gis

-- add all the necessary columns (done at the top such that running parts of the script becomes easier)
SELECT AddGeometryColumn ('public','wecc_load_areas','polygon_geom',4326,'MULTIPOLYGON',2);
update wecc_load_areas set polygon_geom = the_geom;
alter table wecc_load_areas drop column the_geom;
CREATE INDEX polygon_geom_index ON wecc_load_areas USING gist (polygon_geom);


alter table wecc_load_areas add column substation_center_rec_id bigint;
SELECT AddGeometryColumn ('public','wecc_load_areas','substation_center_geom',4326,'POINT',2);
alter table wecc_load_areas add column primary_nerc_subregion character varying(20);
alter table wecc_load_areas add column primary_state character varying(20);
alter table wecc_load_areas add column economic_multiplier numeric(3,2) default null;
alter table wecc_load_areas add column ccs_distance_km numeric(5,2) default 0;


-- TRANSMISION LINES THAT CROSS BORDERS---------
-- finds all the transmssion lines that cross load area borders
-- the number_of_points_in_each_linestring_table is a work around that lets us select the first and last point
-- from the transmission linestring geometry
-- takes ~ 10min as it has to go through 50000 trans lines
drop table if exists wecc_trans_lines_that_cross_load_area_borders;
create table wecc_trans_lines_that_cross_load_area_borders as
	select 	ventyx_e_transln_polyline.*,
			la1.load_area as load_area_start,
			la2.load_area as load_area_end
	from 	wecc_load_areas as la1,
	 		wecc_load_areas as la2,
			ventyx_e_transln_polyline
	where	intersects(la1.polygon_geom, startpoint(ventyx_e_transln_polyline.the_geom))
	and 	intersects(la2.polygon_geom, endpoint(ventyx_e_transln_polyline.the_geom))
	and 	la1.load_area <> la2.load_area
	and		proposed like 'In Service';

alter table wecc_trans_lines_that_cross_load_area_borders add primary key (gid);
CREATE INDEX to_sub ON wecc_trans_lines_that_cross_load_area_borders (to_sub);
CREATE INDEX from_sub ON wecc_trans_lines_that_cross_load_area_borders (from_sub);
CREATE INDEX voltage_kv ON wecc_trans_lines_that_cross_load_area_borders (voltage_kv);

-- this bit of code adds transline_geom to the geometry columns table,
-- which allows map programs to be able to find the column to map
SELECT AddGeometryColumn ('public','wecc_trans_lines_that_cross_load_area_borders','transline_geom',4326,'MULTILINESTRING',2);
update wecc_trans_lines_that_cross_load_area_borders set transline_geom = the_geom;
alter table wecc_trans_lines_that_cross_load_area_borders drop column the_geom;


-- LOAD AREA SUBSTATION CENTERS--------------
-- finding load area centers by highest capacity substation
-- takes about 20 min total

-- there isn't any way in the ventyx data to directly link trans lines and substations,
-- so we do it here through the intersection
-- some of the lines have a voltage of -99 becasue Ventyx hasn't determined their voltage yet,
-- but these are generally small lines, so we just take them out here
-- also, ventyx didn't link up all of the trans line start and end geometries with their substation points
-- so the expand inside the intersects moves a small bit out from each substation to try to grab the correct end of the trans line
-- the indexing is necessary because this query took forever without it


-- first locate substations in load areas
drop table if exists wecc_substation_load_area_map;
create temporary table wecc_substation_load_area_map as
select 	ventyx_e_substn_point.rec_id,
		wecc_load_areas.load_area,
		expand(ventyx_e_substn_point.the_geom, 0.0001) as expanded_substation_geom
from 	ventyx_e_substn_point,
		wecc_load_areas
where  	proposed like 'In Service'
and		mx_volt_kv > 100
and		intersects(ventyx_e_substn_point.the_geom, wecc_load_areas.polygon_geom);

CREATE INDEX rec_id ON wecc_substation_load_area_map (rec_id);
CREATE INDEX expanded_substation_geom ON wecc_substation_load_area_map USING gist (expanded_substation_geom);

-- create a table of start and end points of each trans line segment
drop table if exists transline_start_end_points;
create temporary table transline_start_end_points as
select 	ventyx_e_transln_polyline.rec_id,
		ventyx_e_transln_polyline.voltage_kv,
		ventyx_e_transln_polyline.num_lines,
		endpoint(ventyx_e_transln_polyline.the_geom) as endpoint_geom,
		startpoint(ventyx_e_transln_polyline.the_geom) as startpoint_geom
from 	ventyx_e_transln_polyline
where	ventyx_e_transln_polyline.proposed like 'In Service'
and		ventyx_e_transln_polyline.voltage_kv > 0;

CREATE INDEX startpoint ON transline_start_end_points USING gist (startpoint_geom);
CREATE INDEX endpoint ON transline_start_end_points USING gist (endpoint_geom);
CREATE INDEX transline_rec_id ON transline_start_end_points (rec_id);
CREATE INDEX voltage_kv ON transline_start_end_points (voltage_kv);

-- sum up the total amount of mw into and out of each bus
drop table if exists substation_total_mw;
create temporary table substation_total_mw as
select 	wecc_substation_load_area_map.rec_id as substation_rec_id,
		sum( num_lines * avgcap) as total_mw
from	wecc_substation_load_area_map,
		mw_transfer_cap_by_kv,
		transline_start_end_points
where 	(intersects(expanded_substation_geom, startpoint_geom) OR intersects(expanded_substation_geom, endpoint_geom))
and		transline_start_end_points.voltage_kv = teppc_bus_kv
group by substation_rec_id;

CREATE INDEX substation_rec_id_total_mw ON substation_total_mw (substation_rec_id);
CREATE INDEX total_mw ON substation_total_mw (total_mw);


-- find the load area center by picking the bus with the highest sum of transfer capacity
update wecc_load_areas
set substation_center_rec_id = substation_rec_id,
	substation_center_geom = the_geom
from
	(select wecc_substation_load_area_map.load_area, 
 		substation_rec_id,
		ventyx_e_substn_point.the_geom
	from	substation_total_mw,
			wecc_substation_load_area_map,
			ventyx_e_substn_point,
			(select	load_area,
					max(total_mw) as max_total_mw
				from wecc_substation_load_area_map, substation_total_mw
				where	substation_total_mw.substation_rec_id = wecc_substation_load_area_map.rec_id
				group by load_area) as max_total_mw_table
	where	substation_total_mw.substation_rec_id = ventyx_e_substn_point.rec_id
	and	substation_total_mw.substation_rec_id = wecc_substation_load_area_map.rec_id
	and		substation_total_mw.total_mw = max_total_mw_table.max_total_mw
	and		wecc_substation_load_area_map.load_area = max_total_mw_table.load_area) as substation_center_table
where substation_center_table.load_area = wecc_load_areas.load_area;



-- the above code produces acceptable results for most load areas
-- but for some it puts the load area center too close to one side of the load area
-- which would make it too easy to transfer power to some load areas and too hard to transfer to others
-- the below code moves some of those centers closer to the geographic center of the load area

-- the substation_geom values were taken from the_geom of the ventyx_e_substn_point table
-- where a substation with many high voltage connections nearer to the center of the load area was found



-- OR_W center becomes 'Alvey', which is near Eugene
update wecc_load_areas
set substation_center_rec_id = ventyx_e_substn_point.rec_id,
	substation_center_geom = ventyx_e_substn_point.the_geom
from ventyx_e_substn_point
where ventyx_e_substn_point.rec_id = 494
and load_area like 'OR_W';

-- WA_ID_AVA center becomes 'Bell', which is near Spokane
update wecc_load_areas
set substation_center_rec_id = ventyx_e_substn_point.rec_id,
	substation_center_geom = ventyx_e_substn_point.the_geom
from ventyx_e_substn_point
where ventyx_e_substn_point.rec_id = 473
and load_area like 'WA_ID_AVA';

-- WY_NE center becomes 'Wyodak', which is in the center of the zone
update wecc_load_areas
set substation_center_rec_id = ventyx_e_substn_point.rec_id,
	substation_center_geom = ventyx_e_substn_point.the_geom
from ventyx_e_substn_point
where ventyx_e_substn_point.rec_id = 45860
and load_area like 'WY_NE';

-- WY_SE center becomes 'Laramie River', which is in the center of the zone
update wecc_load_areas
set substation_center_rec_id = ventyx_e_substn_point.rec_id,
	substation_center_geom = ventyx_e_substn_point.the_geom
from ventyx_e_substn_point
where ventyx_e_substn_point.rec_id = 41245
and load_area like 'WY_SE';

-- CA_PGE_N center becomes 'Table Mountain', which is roughly in the center of the area and has many 500 and 230kV connections
update wecc_load_areas
set substation_center_rec_id = ventyx_e_substn_point.rec_id,
	substation_center_geom = ventyx_e_substn_point.the_geom
from ventyx_e_substn_point
where ventyx_e_substn_point.rec_id = 22300
and load_area like 'CA_PGE_N';

-- AZ_NW center becomes 'Peacock'
update wecc_load_areas
set substation_center_rec_id = ventyx_e_substn_point.rec_id,
	substation_center_geom = ventyx_e_substn_point.the_geom
from ventyx_e_substn_point
where ventyx_e_substn_point.rec_id = 41605
and load_area like 'AZ_NW';

-- NM_S_TX_EPE center becomes 'Newman', which is just outside of El Paso
update wecc_load_areas
set substation_center_rec_id = ventyx_e_substn_point.rec_id,
	substation_center_geom = ventyx_e_substn_point.the_geom
from ventyx_e_substn_point
where ventyx_e_substn_point.rec_id = 41490
and load_area like 'NM_S_TX_EPE';

-- CA_SCE_SE center becomes 'Eagle Mountain'
update wecc_load_areas
set substation_center_rec_id = ventyx_e_substn_point.rec_id,
	substation_center_geom = ventyx_e_substn_point.the_geom
from ventyx_e_substn_point
where ventyx_e_substn_point.rec_id = 24259
and load_area like 'CA_SCE_SE';




-- TRANS LINES------------------
-- make transmission lines between the load areas
drop table if exists wecc_trans_lines;
create table wecc_trans_lines(
	transmission_line_id serial primary key,
	load_area_start character varying(11),
	load_area_end character varying(11),
	load_areas_border_each_other boolean,
	straightline_distance_km double precision,
	distances_along_existing_lines_km double precision,
	transmission_length_km double precision,
	existing_transfer_capacity_mw NUMERIC(5,0) default 0,
	transmission_efficiency double precision,
	new_transmission_builds_allowed smallint default 1,
	first_line_direction int default 0,
	is_dc_line smallint default 0,
	terrain_multiplier NUMERIC(4,3) CHECK (terrain_multiplier BETWEEN 0.5 AND 4),
	is_new_path smallint CHECK (is_new_path = 0 or is_new_path = 1)
);

SELECT AddGeometryColumn ('public','wecc_trans_lines','straightline_geom',4326,'LINESTRING',2);
SELECT AddGeometryColumn ('public','wecc_trans_lines','existing_lines_geom',4326,'MULTILINESTRING',2);
SELECT AddGeometryColumn ('public','wecc_trans_lines','route_geom',4326,'MULTILINESTRING',2);
CREATE INDEX ON wecc_trans_lines USING GIST (straightline_geom);
CREATE INDEX ON wecc_trans_lines USING GIST (existing_lines_geom);
CREATE INDEX ON wecc_trans_lines USING GIST (route_geom);


-- first add straightline_distance_km
insert into wecc_trans_lines (load_area_start, load_area_end, straightline_distance_km, straightline_geom)
select	la1,
		la2,
		st_distance_sphere(the_geom1, the_geom2)/1000,
		makeline(the_geom1, the_geom2)
from
(select load_area as la1, substation_geom as the_geom1 from wecc_load_area_substation_centers) as la1_table,
(select load_area as la2, substation_geom as the_geom2 from wecc_load_area_substation_centers) as la2_table
where la1 <> la2;

-- test to see if the load areas border each other
update wecc_trans_lines
set load_areas_border_each_other = intersection
	from
		(select 	a.load_area as load_area_start,
					b.load_area as load_area_end,
					st_intersects(a.polygon_geom, b.polygon_geom) as intersection
			FROM 	wecc_load_areas as a,
					wecc_load_areas as b
			where 	a.load_area <> b.load_area) as intersection_table
where 	intersection_table.load_area_start = wecc_trans_lines.load_area_start
and 	intersection_table.load_area_end = wecc_trans_lines.load_area_end;


-- note... Autumn should fill in all values for distances_along_existing_lines_m
-- and the creation of this column
--Autumn: I'm going to change this to a new column instead--no sense losing the calculated distances every time.  
--But it's still going to be called distances_along_existing_lines_m.  The new column is called calculated_distances_along_existing_lines
-- if the distance along existing lines is double as long as the straight line distance between load areas,
-- set the distance to double the straight line distance, reflecting the high added cost and added length of making a new right of way

--Don't run this unless you want to wait for a while.  Also, if you're changing the inputs at all, you'll want to see <some other file I'm going to make>
select distances_along_translines('test_segment_start_end_dist_amp', 'test_segment_start_end_dist_amp_vertices', 'distances_along_existing_trans_lines');
update wecc_trans_lines set distances_along_existing_lines_km = distances_along_existing_trans_lines.distance/1000
from distances_along_existing_trans_lines d where (d.load_area_start like wecc_trans_lines.load_area_start and d.load_area_end like wecc_trans_lines.load_area_end)  

-- Autumn should insert the script that outputs transline geoms here
update wecc_trans_lines set existing_lines_geom = wecc_trans_lines_old.route_geom
from wecc_trans_lines_old
where 	wecc_trans_lines.load_area_start = wecc_trans_lines_old.load_area_start
and		wecc_trans_lines.load_area_end = wecc_trans_lines_old.load_area_end;

-- Intermountain doesn't have quite the correct existing_lines_geom, but add something here that is almost correct
update wecc_trans_lines
set existing_lines_geom = transline_geom
from (select transline_geom from wecc_trans_lines_that_cross_load_area_borders where load_area_end = 'UT_S' and load_area_start = 'CA_SCE_CEN') as intermountain_geom
where ( load_area_start = 'UT_S' and load_area_end = 'CA_SCE_CEN') or ( load_area_end = 'UT_S' and load_area_start = 'CA_SCE_CEN');

-- TRANSFER CAPACITY
-- add transfer capacites for lines that cross load area borders
-- run bus_matches_wecc.sql to match ventyx and ferc 715 data

-- bus_matches_wecc.sql doesn't get DC lines, so add them first
-- get the Pacific DC line capacity and length
update wecc_trans_lines
set existing_transfer_capacity_mw = 3100, 
	is_dc_line = 1
where 	( load_area_start = 'OR_WA_BPA' and load_area_end = 'CA_LADWP');

-- get the Intermountain Utah-California line
update wecc_trans_lines
set existing_transfer_capacity_mw = 1920, 
	is_dc_line = 1
where 	( load_area_start = 'UT_S' and load_area_end = 'CA_SCE_CEN');

update  wecc_trans_lines
set		existing_transfer_capacity_mw = rating_mva
from (	select load_area_start, load_area_end, sum(rating_mva) as rating_mva
		from	trans_wecc_ferc_ventyx
		group by load_area_start, load_area_end
	) as rating_table
where	wecc_trans_lines.load_area_start = rating_table.load_area_start
and		wecc_trans_lines.load_area_end = rating_table.load_area_end
and		is_dc_line = 0;


-- each line needs to have the same capacity in both directions, which is the sum of the lines in each direction
-- (the 'direction' of each line is arbitrary - power can flow either way on any line)
update wecc_trans_lines w1
set existing_transfer_capacity_mw = w1.existing_transfer_capacity_mw + w2.existing_transfer_capacity_mw,
	is_dc_line = case when ( w1.is_dc_line = 1 or w2.is_dc_line = 1 ) then 1 else 0 end
from wecc_trans_lines w2
where 	w1.load_area_start = w2.load_area_end
and		w1.load_area_end = w2.load_area_start;

-- to reduce the number of decision variables, delete all transmission lines that aren't existing paths or that don't have load areas that border each other
delete from wecc_trans_lines where (existing_transfer_capacity_mw = 0 and not load_areas_border_each_other);

-- route_geom is the actual geometry that SWITCH is going to assume connects two load areas
-- in most cases it will be along existing lines, unless the path represents a new path (existing_transfer_capacity_mw = 0)
-- in which case we'll assume a straight line path between the two load areas if existing lines don't connect the two load areas
-- at a distance <= 1.5x of the straightline distance
-- this straightline path will get a terrain_multiplier of whatever terrain is in its way...
-- might not be the optimal route, but in exchange it gets the shortest distance

-- below also updates transmission_length_km to be consistent with the length of route_geom

-- update the transmission_length_km to be along existing lines whenever possible
-- the case selects out lines which have really long distances along existing transmission lines
-- this effectivly limits their distance to 1.5 x that of the straight-line distance
update wecc_trans_lines
set   is_new_path = CASE WHEN distances_along_existing_lines_km > 1.5 * straightline_distance_km AND existing_transfer_capacity_mw = 0 THEN 1
						 WHEN distances_along_existing_lines_km is null THEN 1
						 ELSE 0 END;

-- we're going to derive the transmission length for new paths from that of existing paths, so set new path transmission distances to null for now
update wecc_trans_lines
SET		route_geom = CASE WHEN is_new_path = 1 THEN ST_Multi(straightline_geom) ELSE existing_lines_geom END,
		transmission_length_km = CASE WHEN is_new_path = 0 THEN distances_along_existing_lines_km ELSE NULL END;

-- now derive the length for new paths... this came out to ~1.3x the straightline distance
UPDATE 	wecc_trans_lines
SET 	transmission_length_km = straightline_distance_km * length_multiplier
FROM	(SELECT sum(distances_along_existing_lines_km) / sum(straightline_distance_km) as length_multiplier
			FROM wecc_trans_lines
			WHERE is_new_path = 0
		) AS length_multiplier_table
WHERE	transmission_length_km IS NULL;

-- calculate losses as 1 percent losses per 100 miles or 1 percent per 160.9344 km (reference from ReEDS Solar Vision Study documentation)
update wecc_trans_lines set transmission_efficiency = 1 - (0.01 / 160.9344 * transmission_length_km);

-- a handful of existing long transmission lines are effectivly the combination of a few shorter ones in SWITCH,
-- so they are flagged here to prevent new builds along the longer corridors
update wecc_trans_lines
set new_transmission_builds_allowed = 0
where	(load_area_start like 'AZ_APS_N' and load_area_end like 'NV_S')
or		(load_area_start like 'AZ_APS_SW' and load_area_end like 'CA_SCE_S')
or		(load_area_start like 'AZ_APS_SW' and load_area_end like 'NV_S')
or		(load_area_start like 'CA_LADWP' and load_area_end like 'OR_WA_BPA')
or		(load_area_start like 'CA_PGE_CEN' and load_area_end like 'CA_PGE_N')
or		(load_area_start like 'CA_PGE_N' and load_area_end like 'OR_W')
or		(load_area_start like 'CA_SCE_CEN' and load_area_end like 'UT_S')
or		(load_area_start like 'CAN_BC' and load_area_end like 'MT_NW')
or		(load_area_start like 'CO_E' and load_area_end like 'WY_SE')
or		(load_area_start like 'MT_NW' and load_area_end like 'MT_NE')
or		(load_area_start like 'WA_N_CEN' and load_area_end like 'WA_SEATAC')
;

-- now get the other direction
update wecc_trans_lines
set new_transmission_builds_allowed = 0
where (load_area_start, load_area_end) in
	( select load_area_end, load_area_start from wecc_trans_lines where new_transmission_builds_allowed = 0 );


-- a handful of new transmission lines (ones without existing capacity) are redundant, so these are removed here
delete from wecc_trans_lines
where	(load_area_start like 'MT_SW' and load_area_end like 'WA_ID_AVA')
or		(load_area_start like 'CA_PGE_CEN' and load_area_end like 'CA_SCE_CEN')
or		(load_area_start like 'CA_SCE_CEN' and load_area_end like 'CA_SCE_SE')
or		(load_area_start like 'CO_E' and load_area_end like 'CO_NW')
;

-- now get the other direction
delete from wecc_trans_lines 
where (load_area_end, load_area_start) not in
	( select load_area_start, load_area_end from wecc_trans_lines_for_export);


-- add a flag for if one direction of a line's transmission_line_id is less than the other direction
-- this will be used to define DC load flow constraints in AMPL 
update wecc_trans_lines
set first_line_direction = 1
from
	(select load_area_start,
			load_area_end,
			min(transmission_line_id) as transmission_line_id
		from
		(	select 	load_area_start,
 					load_area_end,
 					transmission_line_id
 				from wecc_trans_lines
			UNION
			select 	load_area_end as load_area_start,
 					load_area_start as load_area_end,
 					transmission_line_id
 				from wecc_trans_lines
		) as id_table
	group by load_area_start, load_area_end
	order by 3) as min_id_table
where wecc_trans_lines.transmission_line_id = min_id_table.transmission_line_id;


-- now run transmission_terrain.sql to create a transmission terrain map of WECC
-- that will be used to calculate the terrain_multiplier
-- the transmission costs that we use in SWITCH for transmission already have a default multiplier embedded
-- which evaluates to roughly 1.5, so divide by 1.5 to give the correct multiplicative factor to the $/MW-km value that we presently use
update wecc_trans_lines
set terrain_multiplier = multiplier/1.5
FROM	
	(SELECT transmission_line_id,
			sum(	m.terrain_multiplier
					* ST_Length(ST_Intersection(m.the_geom, route_geom)::geography, false)
					/ ST_Length(route_geom::geography, false)
				) as multiplier
	FROM wecc_trans_lines,
	 	 transmission_terrain_multiplier m
	where 	ST_Intersects(m.the_geom, route_geom)
	GROUP BY transmission_line_id
) calc_multiplier
WHERE calc_multiplier.transmission_line_id = wecc_trans_lines.transmission_line_id;


-- now add a derating factor that accounts for contingencies, loop flows, stability, etc constraints on transmission
-- this value is different for AC and DC, and is calculated in /Volumes/switch/Models/USA_CAN/Transmission/_switchwecc_path_matches_thermal.xlsx
-- the value is 0.59 for AC lines and 0.91 for DC lines
ALTER TABLE wecc_trans_lines ADD COLUMN transmission_derating_factor float default 0.59;
UPDATE wecc_trans_lines SET transmission_derating_factor = 0.91 WHERE is_dc_line = 1;

-- export the data to mysql
COPY 
(select	transmission_line_id,
		load_area_start,
		load_area_end,
		existing_transfer_capacity_mw,
		transmission_length_km,
		transmission_efficiency,
		new_transmission_builds_allowed,
		first_line_direction,
		is_dc_line,
		transmission_derating_factor,
		terrain_multiplier
	from 	wecc_trans_lines
	order by load_area_start, load_area_end)
TO 		'/Volumes/switch/Models/USA_CAN/Transmission/_SWITCH_WECC/wecc_trans_lines.csv'
WITH 	CSV
		HEADER;


-- NERC SUBREGIONS---------------
-- EIA projections are for NERC subregions, so this gets the primary NERC subregion for each load area
-- I unfortunally had to use the historical nerc subregions shapefile because the current nerc subregions shapefile
-- kept throwing GEOS errors when the below intersections were done.
-- the only significant difference in the west between the two is a bit of southern NV...
-- this script still correctly assigns NV_S to AZNMSNV instead of NWPP, so all is well
-- but if the shapefiles are updated, it would be worth trying the current nerc subregion shapefile again.
-- takes 1 min
drop table if exists area_intersection_table;
create temporary table area_intersection_table as
select load_area,
	abbrev as nerc_subregion,
	area(intersection(ventyx_nercsub_hist_region.the_geom, wecc_load_areas.polygon_geom)) as intersection_area
from ventyx_nercsub_hist_region, wecc_load_areas;

update 	wecc_load_areas
set 	primary_nerc_subregion = nerc_subregion
from 	area_intersection_table,
		(select load_area,
				max(intersection_area) as max_intersection_area
		from area_intersection_table
		group by load_area) as max_area_table
where 	wecc_load_areas.load_area = area_intersection_table.load_area
and		area_intersection_table.load_area = max_area_table.load_area
and 	max_intersection_area = intersection_area;

-- found an error or two... CA_IID gets assigned to AZNMSNV... change it here to CA
update wecc_load_areas set primary_nerc_subregion = 'CA' where load_area = 'CA_IID';
-- also, canada needs caps for later joins
update wecc_load_areas set primary_nerc_subregion = 'NWPP_CAN' where load_area like 'CAN%';

-- PRIMARY STATE FOR EACH LOAD AREA
-- does US states by population fraction of each state in each load area
-- does Canada and Mexico by area fraction

drop table if exists population_load_area_state_table;
create temporary table population_load_area_state_table as
SELECT	sum(population_load_area_county) as population_load_area_state,
	load_area,
	st_abbr as state
FROM
	ventyx_counties_region,
	(select sum(us_population_density_to_load_area.popdensity) as population_load_area_county,
		load_area,
		cnty_fips
	from 	us_population_density_to_county,
			us_population_density_to_load_area
	where 	us_population_density_to_load_area.gid = us_population_density_to_county.gid
	group by load_area, cnty_fips) as county_load_area_population_table
where county_load_area_population_table.cnty_fips = ventyx_counties_region.cnty_fips
group by load_area, st_abbr
order by load_area, st_abbr;

update	wecc_load_areas
set	primary_state = state
from	population_load_area_state_table,
	(select max(population_load_area_state) as max_load_area_population_by_state, load_area
	FROM
	population_load_area_state_table
	group by load_area) as max_load_area_population_by_state_table
where 	population_load_area_state_table.population_load_area_state = max_load_area_population_by_state_table.max_load_area_population_by_state
and	population_load_area_state_table.load_area = max_load_area_population_by_state_table.load_area
and	population_load_area_state_table.load_area = wecc_load_areas.load_area
and	population_load_area_state_table.load_area not like 'CAN%'
and population_load_area_state_table.load_area not like 'MEX%';

-- Canada and Mexico
drop table if exists area_intersection_table;
create temporary table area_intersection_table as
select load_area,
	abbrev as state,
	area(intersection(ventyx_states_region.the_geom, wecc_load_areas.polygon_geom)) as intersection_area
from ventyx_states_region, wecc_load_areas
where country in ('Canada', 'Mexico')
and (load_area like 'CAN%' or load_area like 'MEX%');

update 	wecc_load_areas
set 	primary_state = state
from 	area_intersection_table,
		(select load_area,
				max(intersection_area) as max_intersection_area
		from area_intersection_table
		group by load_area) as max_area_table
where 	wecc_load_areas.load_area = area_intersection_table.load_area
and		area_intersection_table.load_area = max_area_table.load_area
and 	max_intersection_area = intersection_area
and 	(wecc_load_areas.load_area like 'CAN%' or wecc_load_areas.load_area like 'MEX%');


-- REGIONAL ECONOMIC MULTIPLIER---------------------
-- import a table of generator capital costs broken down by region
-- here they're specificed by nearest city, so we'll a distance query below to match city to load area
-- Source: 2010 EIA Beck plant costs: Updated Capital Cost Estimated for Electricity Generation Plants. Nov 2010, US Energy Information Agency.
-- PDF in the same folder as the regional_capital_costs.csv
-- also, SWITCH doesn't yet have capabilties to change the regional multipler by technology,
-- so we'll assume the average for all techs - could be changed/improved in the future

DROP TABLE IF EXISTS regional_capital_costs_import;
CREATE TABLE regional_capital_costs_import(
	generator_type varchar(100),
	state varchar(50),
	city varchar(50),
	base_cost_dollars2010_per_kw int,
	location_percent_variation NUMERIC(4,2),
	delta_cost_difference_dollars2010_per_kw int,
	total_location_project_cost_dollars2010_per_kw int,
	PRIMARY KEY (generator_type, state, city)
	);

copy regional_capital_costs_import
from '/Volumes/switch/Models/Switch_Input_Data/regional_economic_multiplier/regional_capital_costs.csv'
with csv header;

DROP TABLE IF EXISTS regional_capital_costs;
CREATE TABLE regional_capital_costs(
	state varchar(50),
	city varchar(50),
	average_location_cost_multiplier NUMERIC(4,2),
	PRIMARY KEY (state, city)
	);

SELECT addgeometrycolumn ('wecc_inputs','regional_capital_costs','the_geom',4326,'POINT',2);
CREATE INDEX ON regional_capital_costs USING gist (the_geom);

INSERT INTO regional_capital_costs
	SELECT 	state,
			city,
			1 + avg(location_percent_variation)/100 as average_location_cost_multiplier
	FROM	regional_capital_costs_import
	WHERE 	base_cost_dollars2010_per_kw > 0
	GROUP BY state, city;

-- get the actual locations from a table of cities
UPDATE regional_capital_costs r
SET the_geom = m.the_geom
FROM
	(select name, state, the_geom from ventyx_may_2012.cities_point
		JOIN 
	(select name, max(pop_98) as pop_98
		from ventyx_may_2012.cities_point
		WHERE NOT (name = 'Concord' and state = 'CA')
		AND NOT (name = 'Portland' and state = 'ME')
		AND NOT (name = 'Burlington' and state = 'NC')
		group by name) as max_table
		USING (name, pop_98)) m
WHERE r.city = m.name;

-- get Portland, ME
UPDATE regional_capital_costs r
set the_geom = m.the_geom
FROM ventyx_may_2012.cities_point m
WHERE m.name = 'Portland' and m.state = 'ME'
AND	r.city = 'Portland' and r.state = 'Maine';

-- normalized average_location_cost_multiplier to an average of 1
-- can't directly use the multipliers as our actual capital costs come from Black and Veatch, not EIA Beck plantcosts.
-- also, exclude states that aren't in the continental US.
UPDATE regional_capital_costs
SET average_location_cost_multiplier = average_location_cost_multiplier / normalization_factor
FROM
	(SELECT avg(average_location_cost_multiplier) as normalization_factor
		FROM 	regional_capital_costs
		WHERE 	state NOT IN ('Alaska', 'Hawaii', 'Puerto Rico')
		) as normalization_factor_table;
		
-- update wecc_load_areas with the proper multiplier,
-- based on minimum distance from the city specified in regional_capital_costs to the primary_substation_geom of wecc_load_areas
UPDATE wecc_load_areas
SET economic_multiplier = average_location_cost_multiplier
FROM 
	(SELECT load_area, city, average_location_cost_multiplier
		FROM 	regional_capital_costs,
				wecc_load_areas
			JOIN
			( SELECT load_area, min(st_distance_spheroid(substation_center_geom, the_geom, 'SPHEROID["WGS 84",6378137,298.257223563]')) as min_distance
				FROM regional_capital_costs, wecc_load_areas
				GROUP BY load_area ) as min_distance_table
			USING (load_area)
		WHERE 	min_distance = st_distance_spheroid(substation_center_geom, the_geom, 'SPHEROID["WGS 84",6378137,298.257223563]')
		) as match_table
WHERE match_table.load_area = wecc_load_areas.load_area;

-- update a few where the match isn't quite right due to the relative position of city and primary substation
UPDATE wecc_load_areas
	SET economic_multiplier = 
		CASE WHEN load_area = 'CAN_ALB' THEN
				(SELECT economic_multiplier FROM wecc_load_areas WHERE load_area = 'CAN_BC')
			WHEN load_area = 'MEX_BAJA' THEN
				(SELECT economic_multiplier FROM wecc_load_areas WHERE load_area = 'AZ_APS_SW')
			WHEN load_area = 'AZ_NW' THEN
				(SELECT economic_multiplier FROM wecc_load_areas WHERE load_area = 'AZ_NM_N')
			WHEN load_area = 'NV_N' THEN
				(SELECT economic_multiplier FROM wecc_load_areas WHERE load_area = 'NV_S')
			WHEN load_area = 'CA_PGE_CEN' THEN
				(SELECT economic_multiplier FROM wecc_load_areas WHERE load_area = 'CA_SMUD')
		ELSE economic_multiplier
		END;


-- CCS PIPELINE DISTANCE COST ADDER -------------------------
-- ccs projects have a cost adder (calculated here) for not being in a load area that has CCS sinks
-- should update data at some point to new CCS atlas
  
-- first make a table of all polygon geoms of viable sinks
-- (ones with vol_high > 0 and not ( assessed = 1 and suitable = 0 )
drop table if exists ccs_sinks_all;
create table ccs_sinks_all(
	gid serial primary key,
	sink_type character varying (30),
	native_dataset_gid int,
	vol_high numeric );

SELECT AddGeometryColumn ('wecc_inputs','ccs_sinks_all','the_geom',4326,'POLYGON',2);
CREATE INDEX ccs_sinks_all_index ON ccs_sinks_all USING gist (the_geom);

insert into ccs_sinks_all (sink_type, native_dataset_gid, vol_high, the_geom)
	select 	'ccs_unmineable_coal_areas' as sink_type,
			gid as native_dataset_gid,
			vol_high,
			(ST_Dump(polygon_geom)).geom
	from 	ccs_unmineable_coal_areas
	where 	vol_high > 0
	and		not ( assessed = 1 and suitable = 0 );
	
insert into ccs_sinks_all (sink_type, native_dataset_gid, vol_high, the_geom)
	select 	'ccs_saline_formations' as sink_type,
			gid as native_dataset_gid,
			vol_high,
			(ST_Dump(polygon_geom)).geom
	from 	ccs_saline_formations
	where 	vol_high > 0
	and		not ( assessed = 1 and suitable = 0 );

insert into ccs_sinks_all (sink_type, native_dataset_gid, vol_high, the_geom)
	select 	'ccs_oil_and_gas_reservoirs' as sink_type,
			gid as native_dataset_gid,
			vol_high,
			(ST_Dump(polygon_geom)).geom
	from 	ccs_oil_and_gas_reservoirs
	where 	vol_high > 0
	and		not ( assessed = 1 and suitable = 0 );


-- draw distances from the substation_center_geom of each load area without a ccs sink to the nearest sink
-- the fancy geometry finds the point along the edge of the sink polygon that's closest to substation_center_geom
-- and then calculates the distance between those two points
-- the subquery past 'not in' gives all load_areas DO have sinks (so the 'not in' excludes these from the distance calculation)
drop table if exists ccs_sink_to_load_area;
create table ccs_sink_to_load_area as
select 	load_area,
		st_distance_sphere(
			st_line_interpolate_point(
				st_exteriorring( the_geom ),
				st_line_locate_point(
					st_exteriorring( the_geom ), substation_center_geom )
				),
			substation_center_geom ) / 1000 as distance_km
from 	ccs_sinks_all,
		wecc_load_areas
where load_area not in 
	(select distinct load_area
		from  	wecc_load_areas,
				ccs_sinks_all
		where ST_Intersects(polygon_geom, the_geom));

drop table if exists ccs_tmp;
create temporary table ccs_tmp as 
select load_area, min(distance_km) as min_distance_km from ccs_sink_to_load_area group by load_area;

delete from ccs_sink_to_load_area;
insert into ccs_sink_to_load_area select * from ccs_tmp;

UPDATE wecc_load_areas
SET ccs_distance_km = distance_km
FROM ccs_sink_to_load_area
WHERE ccs_sink_to_load_area.load_area = wecc_load_areas.load_area;

drop table ccs_sink_to_load_area;


-- RPS COMPLIANCE ENTITIES  -----------
-- define a map between load_area and rps_compliance_entity based on the structure
-- of utilities inside each state as shown in the ventyx data (manual matching)
-- and the DSIRE database (as of May 2011) www.dsireusa.org/

-- customer sited targets
-- a few states have customer cited generation targets, generally but not always geared towards distributed PV
-- as distributed PV is the only distributed resource in SWITCH currently, we'll meet these targets exclusivly with distributed PV
-- these targets are tabulated by dsire.org and can be found in the folder /Volumes/1TB_RAID/Models/Switch_Input_Data/RPS
-- the distributed_compliance_fraction represents the % of total load that must be met by distributed resources

alter table wecc_load_areas add column rps_compliance_entity character varying(20);

update wecc_load_areas
set rps_compliance_entity =
	CASE	WHEN load_area in ('AZ_APS_N', 'AZ_APS_SW')	THEN 'AZ_APS'
			WHEN load_area like 'CA_PGE%' 				THEN 'CA_PGE'
			WHEN load_area like 'CA_SCE%' 				THEN 'CA_SCE'
			WHEN load_area in ('CO_DEN', 'CO_NW') 		THEN 'CO_PSC'
			WHEN load_area like 'NV_%' 					THEN 'NV_ENERGY'
			ELSE load_area
	END;


-- import the proper rps_compliance_entity compliance targets from www.dsireusa.org/
drop table if exists rps_state_targets;
create table rps_state_targets(
	state character varying (10),
	rps_compliance_type character varying(20),
	rps_compliance_year int,
	rps_compliance_fraction float,
	PRIMARY KEY (state, rps_compliance_type, rps_compliance_year)
	);

copy rps_state_targets from
'/Volumes/1TB_RAID/Models/Switch_Input_Data/RPS/rps_compliance_targets.csv'
with csv header;

-- divides rps state level targets by year into load area targets on the basis of population
-- does not go past 2035, as targets are not set that far out... 
drop table if exists rps_compliance_entity_targets;
create table rps_compliance_entity_targets(
	rps_compliance_entity character varying(20),
	rps_compliance_type character varying(20),
	rps_compliance_year int,
	rps_compliance_fraction float,
	PRIMARY KEY (rps_compliance_entity, rps_compliance_type, rps_compliance_year)
	);

-- do the US load areas
-- we're assuming that load (and thus compliance fractions) are proportional to load
-- so this uses the population fraction across state lines for each rps_compliance_entity (as described by the nasty CASE)
-- to figure out how much of each state's target to include in each rps_compliance_entity
insert into rps_compliance_entity_targets (rps_compliance_entity, rps_compliance_type, rps_compliance_year, rps_compliance_fraction)
	select  compliance_entity_population_table.rps_compliance_entity,
			rps_compliance_type,
			rps_compliance_year,
			sum( rps_compliance_fraction * compliance_entity_state_population / compliance_entity_population ) as rps_compliance_fraction
	from	rps_state_targets,
		(select rps_compliance_entity,
				sum(popdensity) as compliance_entity_population
		from	us_population_density,
				wecc_load_areas
		where	intersects(wecc_load_areas.polygon_geom, us_population_density.the_geom)
		and	wecc_load_areas.polygon_geom && us_population_density.the_geom
		and	load_area <> 'CAN_ALB'
		and	load_area <> 'CAN_BC'
		and	load_area <> 'MEX_BAJA'
		group by rps_compliance_entity
		) as compliance_entity_population_table,
		(select	rps_compliance_entity,
				abbrev as state,
				sum(popdensity) as compliance_entity_state_population
		from	ventyx_states_region,
				us_population_density,
				wecc_load_areas
		where	intersects(ventyx_states_region.the_geom, us_population_density.the_geom)
		and	ventyx_states_region.the_geom && us_population_density.the_geom
		and	intersects(wecc_load_areas.polygon_geom, us_population_density.the_geom)
		and	wecc_load_areas.polygon_geom && us_population_density.the_geom
		and	load_area <> 'CAN_ALB'
		and	load_area <> 'CAN_BC'
		and	load_area <> 'MEX_BAJA'
		group by rps_compliance_entity, state
		) as compliance_entity_state_population_table
	where	rps_state_targets.state = compliance_entity_state_population_table.state
	and		compliance_entity_population_table.rps_compliance_entity = compliance_entity_state_population_table.rps_compliance_entity
	group by compliance_entity_population_table.rps_compliance_entity, rps_compliance_type, rps_compliance_year
	order by rps_compliance_entity, rps_compliance_type, rps_compliance_year;

-- the Navajo nation (AZ_NM_N) doesn't have to adhere to rps targets
update rps_compliance_entity_targets
set rps_compliance_fraction = 0
where rps_compliance_entity = 'AZ_NM_N';

-- parts of Colorado (CO_E and CO_SW) are composed primarily of munis and coops...
-- they have a different target found in rps_state_targets as 'CO_MUNI'
-- they're all inside Colorado, so we don't have to worry about apportioning their compliance_fraction across state lines
-- colorado non-munis have a distributed energy carveout, but munis don't have a similar target (hence the CASE)
delete from rps_compliance_entity_targets where rps_compliance_entity in ('CO_E', 'CO_SW');
update rps_compliance_entity_targets
set rps_compliance_fraction = rps_state_targets.rps_compliance_fraction
from rps_state_targets
where rps_compliance_entity in ('CO_E', 'CO_SW')
and rps_state_targets.state = 'CO_MUNI'
and rps_compliance_entity_targets.rps_compliance_year = rps_state_targets.rps_compliance_year
and rps_state_targets.rps_compliance_type = 'Primary';

-- via the population fraction apportionment above, a few rps_compliance_fractions are tiny... zero them out here
update rps_compliance_entity_targets
set rps_compliance_fraction = 0
where rps_compliance_fraction < 0.0001;

-- this rule is equal to 'INSERT IGNORE' in mysql
CREATE RULE 'rps_compliance_entity_targets_insert_ignore' AS ON INSERT TO 'rps_compliance_entity_targets'
  WHERE EXISTS(SELECT 1 FROM rps_compliance_entity_targets
  		WHERE (rps_compliance_entity, rps_compliance_type, rps_compliance_year)
  				= (NEW.rps_compliance_entity, NEW.rps_compliance_type, NEW.rps_compliance_year))
  DO INSTEAD NOTHING;

-- zero out all other year/rps target type combos for completeness (including canada and mexico)
-- the insert ignore rule above will make it such that this insert statement doens't write over targets > 0
insert into rps_compliance_entity_targets (rps_compliance_entity, rps_compliance_type, rps_compliance_year, rps_compliance_fraction)
	select 	rps_compliance_entity,
			rps_compliance_type,
			rps_compliance_year,
			0 as rps_compliance_fraction
	from 	(select distinct rps_compliance_entity from wecc_load_areas) as rce,
			(select distinct rps_compliance_type from rps_compliance_entity_targets) as rct,
			(select distinct rps_compliance_year from rps_compliance_entity_targets) as rcy;

DROP RULE 'rps_compliance_entity_targets_insert_ignore' ON 'rps_compliance_entity_targets';


-- RPS targets are assumed to go on in the future, so targets out to 2080 are added here
-- at the compliance fraction of the last year
insert into rps_compliance_entity_targets (rps_compliance_entity, rps_compliance_type, rps_compliance_year, rps_compliance_fraction)
	select 	rps_compliance_entity,
			rps_compliance_type,
			generate_series(1, 2080 - rps_compliance_year) + rps_compliance_year as rps_compliance_year,
			compliance_fraction_in_max_year as rps_compliance_fraction
	from	(select rps_compliance_entity_targets.rps_compliance_entity,
					rps_compliance_type,
					rps_compliance_year,
					rps_compliance_fraction as compliance_fraction_in_max_year
			from	( select rps_compliance_entity, rps_compliance_type, max(rps_compliance_year) as rps_compliance_year
						from rps_compliance_entity_targets group by rps_compliance_entity, rps_compliance_type ) as max_year_table
			join	rps_compliance_entity_targets using (rps_compliance_entity, rps_compliance_type, rps_compliance_year)
			) as compliance_fraction_in_max_year_table
	;

-- export rps complaince info to mysql
copy 
(select	rps_compliance_entity,
  		rps_compliance_type,
		rps_compliance_year,
 		rps_compliance_fraction
from	rps_compliance_entity_targets
order by rps_compliance_entity, rps_compliance_type, rps_compliance_year)
to '/Volumes/1TB_RAID/Models/GIS/RPS/rps_compliance_targets.csv'
with CSV HEADER;


-- EXPORT LOAD AREA INFO TO MYSQL-------
copy
(select	load_area,
 		primary_nerc_subregion,
 		primary_state,
  		economic_multiplier,
  		rps_compliance_entity,
  		ccs_distance_km
from	wecc_load_areas
order by load_area)
to '/Volumes/switch/Models/GIS/wecc_load_area_info.csv'
with CSV HEADER;
