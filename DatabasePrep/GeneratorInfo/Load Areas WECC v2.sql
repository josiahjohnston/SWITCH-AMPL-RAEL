-- Load Area Shapefiles script

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
alter table wecc_load_areas add column economic_multiplier double precision;


-- IMPORT WECC LINK INFORMATION--------
-- should be updated once we get more FERC data.

-- a mysql query that matches teppc load areas to wecc links
-- (links are trans lines between busses)
-- this matching will help us locate transmission lines in postgresql
-- export this query to /Volumes/1TB_RAID/Models/GIS/New\ LoadZone\ Shape\ Files/wecc_transfer_cap.csv
-- so that it can be picked up by postgresql

-- select one_area_matched.*, area2 from (SELECT busnumber as busnumber2, TEPPC_Bus.area as area2 FROM grid.TEPPC_bus) as bar,
-- (select windsun.wecc_link_info.*, area1 from windsun.wecc_link_info,
-- (SELECT busnumber as busnumber1, TEPPC_Bus.area as area1 FROM grid.TEPPC_bus) as foo
-- where busnumber1 = bus1_id) as one_area_matched
-- where busnumber2 = bus2_id
-- order by area1, area2, bus1_kv;


-- in postgresql

-- import the above table made in mysql.
drop table if exists wecc_link_busses_in_teppc_areas;
CREATE TABLE wecc_link_busses_in_teppc_areas (
  link_id int NOT NULL primary key,
  bus1_id int,
  bus1_name character varying(8),
  bus1_kv double precision,
  bus2_id int,
  bus2_name character varying(8),
  bus2_kv double precision,
  rate1 double precision,
  rate2 double precision,
  resist double precision,
  length double precision,
  ext_id int,
  link_type character varying(10),
  cap_fromto double precision,
  cap_tofrom double precision,
  area1 character varying(10),
  area2 character varying(10)
);

CREATE INDEX bus1_name ON wecc_link_busses_in_teppc_areas (bus1_name);
CREATE INDEX bus2_name ON wecc_link_busses_in_teppc_areas (bus2_name);
CREATE INDEX bus1_kv ON wecc_link_busses_in_teppc_areas (bus1_kv);
CREATE INDEX bus2_kv ON wecc_link_busses_in_teppc_areas (bus2_kv);

copy wecc_link_busses_in_teppc_areas
from '/Volumes/1TB_RAID/Models/GIS/New\ LoadZone\ Shape\ Files/wecc_transfer_cap.csv'
with CSV HEADER;



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


-- finds the approximate existing transfer capacity between load areas
-- by finding the average transfer capacity per kV line from the WECC links
-- should use geolocated transfer data when we get it.
drop table if exists mw_transfer_cap_by_kv;
create temporary table mw_transfer_cap_by_kv as
SELECT bus1_kv as teppc_bus_kv, avg(cap_fromto) as avgcap
FROM public.wecc_link_busses_in_teppc_areas
where bus1_kv = bus2_kv
group by bus1_kv
order by bus1_kv desc;

-- the DC line from BPA to LADWP shows up as 800kv in Ventyx,
-- but no such high voltage line exists in the TEPPC database
-- the transfer capacity of this line is 3100 MW in the TEPPC database
-- so we'll set 800 kV = 3100 MW here
-- the intermountain DC line is 500 kV in Ventyx and has a similar transfer capacity
-- to 500 kV lines (1840 MW in TEPPC vs 2300 MW average) and it's schedule for an upgrade to 2400 MW,
-- so we'll leave in the 500 kV category here... good enough for now to determine the load area centers
insert into mw_transfer_cap_by_kv (teppc_bus_kv, avgcap)
values (800, 3100);

-- check on a map that there aren't any transmission lines that were missed in the creation of the wecc load area polygons

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
-- autumn should update with her code here...
drop table if exists wecc_trans_lines;
create table wecc_trans_lines(
	transmission_line_id serial primary key,
	load_area_start character varying(11),
	load_area_end	character varying(11),
	existing_transfer_capacity_mw double precision,
	transmission_length_km double precision,
	load_areas_border_each_other boolean
) with oids;

SELECT AddGeometryColumn ('public','wecc_trans_lines','the_geom',4326,'LINESTRING',2);

-- old... not used any more in favor of Autumn's code that measures the distance along existing lines
-- updated below
insert into wecc_trans_lines (load_area_start, load_area_end, transmission_length_km, the_geom)
select	la1,
		la2,
		st_distance_sphere(the_geom1, the_geom2)/1000,
		makeline(the_geom1, the_geom2)
from
(select load_area as la1, substation_geom as the_geom1 from wecc_load_area_substation_centers) as la1_table,
(select load_area as la2, substation_geom as the_geom2 from wecc_load_area_substation_centers) as la2_table
where la1 <> la2;



-- lines that completly match nicely are updated first
update wecc_trans_lines
set existing_transfer_capacity_mw = cap_mw
from (
	SELECT load_area_start, load_area_end, sum(rate1) as cap_mw
  		FROM wecc_trans_lines_that_cross_load_area_borders v, wecc_f715_branch_info_pk f
 		where v.bus_connection_id = f.bus_connection_id
		and v.bus_connection_id is not null
		and v.num_715_lines is null
		group by 1,2
		) as nice_match_table
where (
		( wecc_trans_lines.load_area_start = nice_match_table.load_area_start and wecc_trans_lines.load_area_end = nice_match_table.load_area_end)
	or
		( wecc_trans_lines.load_area_start = nice_match_table.load_area_end and wecc_trans_lines.load_area_end = nice_match_table.load_area_start)
	);

-- lines that have two entries in ventyx and only one in ferc (assume that ferc is correct so only insert one value per line)
-- the flag for this type of match is num_715_lines = 1
update wecc_trans_lines
set existing_transfer_capacity_mw = 
	(case when (nice_match_table.existing_transfer_capacity_mw IS NULL) 
		THEN rate1 ELSE (nice_match_table.existing_transfer_capacity_mw + nice_match_table.rate1) END )
from (
SELECT distinct mw_table.load_area_start, mw_table.load_area_end, w.existing_transfer_capacity_mw, mw_table.rate1
from (
	SELECT load_area_start, load_area_end, rate1
  		FROM wecc_trans_lines_that_cross_load_area_borders v, wecc_f715_branch_info_pk f
 		where v.bus_connection_id = f.bus_connection_id
		and v.bus_connection_id is not null
		and v.num_715_lines = 1
		) 
		as mw_table,
		wecc_trans_lines w
		where (
			( mw_table.load_area_start = w.load_area_start and mw_table.load_area_end = w.load_area_end)
			or
			( mw_table.load_area_start = w.load_area_end and mw_table.load_area_end = w.load_area_start)
		)
	) as nice_match_table
where (
		( wecc_trans_lines.load_area_start = nice_match_table.load_area_start and wecc_trans_lines.load_area_end = nice_match_table.load_area_end)
	or
		( wecc_trans_lines.load_area_start = nice_match_table.load_area_end and wecc_trans_lines.load_area_end = nice_match_table.load_area_start)
	);

-- lines that have many entries in FERC and fewer in ventyx
-- take the ferc number of lines and add up all the transfer capacites between the two busses at the voltage of the ventyx line
update wecc_trans_lines
set existing_transfer_capacity_mw = (case when (nice_match_table.existing_transfer_capacity_mw IS NULL) 
		THEN cap_mw ELSE (nice_match_table.existing_transfer_capacity_mw + nice_match_table.cap_mw) END )
from (select mw_table.load_area_start, mw_table.load_area_end, w.existing_transfer_capacity_mw, cap_mw
	from (select to_match.load_area_start, to_match.load_area_end, sum(w.rate1) as cap_mw
		from (select bus1_id, bus2_id, bus1_kv, load_area_start, load_area_end
			from	wecc_f715_branch_info_pk,
				(SELECT bus_connection_id, load_area_start, load_area_end 
				from wecc_trans_lines_that_cross_load_area_borders 
				where num_715_lines > 1) 
			as bus_connection_ids_of_interest
			where bus_connection_ids_of_interest.bus_connection_id = wecc_f715_branch_info_pk.bus_connection_id
		) as to_match, 
		wecc_f715_branch_info_pk w
		where (w.bus1_id = to_match.bus1_id) and (w.bus2_id = to_match.bus2_id) and (w.bus1_kv = to_match.bus1_kv)
		group by to_match.load_area_start, to_match.load_area_end
	) as mw_table,
	wecc_trans_lines w
	where (( mw_table.load_area_start = w.load_area_start and mw_table.load_area_end = w.load_area_end)
	or ( mw_table.load_area_start = w.load_area_end and mw_table.load_area_end = w.load_area_start)
	)
) as nice_match_table
where (
		( wecc_trans_lines.load_area_start = nice_match_table.load_area_start and wecc_trans_lines.load_area_end = nice_match_table.load_area_end)
	or
		( wecc_trans_lines.load_area_start = nice_match_table.load_area_end and wecc_trans_lines.load_area_end = nice_match_table.load_area_start)
	);


-- find the average transfer capacity per kV line from the WECC links for lines that we can't match between the Ventyx and FERC datasets
-- (generally only small ( < 230 kV ) lines
-- and then update the transfer capacity between load areas with these values for all unmatched lines
drop table if exists mw_transfer_cap_by_kv;
create temporary table mw_transfer_cap_by_kv as
SELECT bus1_kv as teppc_bus_kv, avg(cap_fromto) as avgcap
FROM public.wecc_link_busses_in_teppc_areas
where bus1_kv = bus2_kv
group by bus1_kv
order by bus1_kv desc;

update wecc_trans_lines
set existing_transfer_capacity_mw = (case when (grouped_trans_cap_table.existing_transfer_capacity_mw IS NULL) 
		THEN cap_mw ELSE (grouped_trans_cap_table.existing_transfer_capacity_mw + grouped_trans_cap_table.cap_mw) END )
from(select mw_table.load_area_start, mw_table.load_area_end, w.existing_transfer_capacity_mw, mw_table.existing_transfer_capacity_mw as cap_mw
from
	(select 	load_area_start,
				load_area_end,
				sum(existing_transfer_capacity_mw) as existing_transfer_capacity_mw
	from
		(
			select 	load_area_start,
					load_area_end,
					sum( avgcap * num_lines) as existing_transfer_capacity_mw
			from 	wecc_trans_lines_that_cross_load_area_borders,
					mw_transfer_cap_by_kv
			where 	wecc_trans_lines_that_cross_load_area_borders.voltage_kv = mw_transfer_cap_by_kv.teppc_bus_kv
			and 	wecc_trans_lines_that_cross_load_area_borders.volt_class not like 'DC Line'
			and		wecc_trans_lines_that_cross_load_area_borders.bus_connection_id is null
			group by load_area_start, load_area_end
		UNION
			select 	load_area_end,
					load_area_start,
					sum( avgcap * num_lines) as existing_transfer_capacity_mw
			from 	wecc_trans_lines_that_cross_load_area_borders,
					mw_transfer_cap_by_kv
			where 	wecc_trans_lines_that_cross_load_area_borders.voltage_kv = mw_transfer_cap_by_kv.teppc_bus_kv
			and 	wecc_trans_lines_that_cross_load_area_borders.volt_class not like 'DC Line'
			and		wecc_trans_lines_that_cross_load_area_borders.bus_connection_id is null
			group by load_area_start, load_area_end
		) as all_trans_cap_table
	group by 1,2
	) as mw_table,
	wecc_trans_lines w
	where (( mw_table.load_area_start = w.load_area_start and mw_table.load_area_end = w.load_area_end)
	or ( mw_table.load_area_start = w.load_area_end and mw_table.load_area_end = w.load_area_start)
	
	) as grouped_trans_cap_table
where 
	(
	(grouped_trans_cap_table.load_area_start = wecc_trans_lines.load_area_start
		and grouped_trans_cap_table.load_area_end = wecc_trans_lines.load_area_end)
	or
	(grouped_trans_cap_table.load_area_end = wecc_trans_lines.load_area_start
		and grouped_trans_cap_table.load_area_start = wecc_trans_lines.load_area_end)
	)
;

-- get the Pacific DC line and update its length
update wecc_trans_lines
set existing_transfer_capacity_mw = 3100,  distances_along_existing_lines_m = (580.437+264.593)*1000
from 
	(select load_area as load_area_start
		from ventyx_e_substn_point, wecc_load_areas
		where ventyx_e_substn_point.rec_id = 34019
		and intersects(wecc_load_areas.polygon_geom, ventyx_e_substn_point.the_geom)) as load_area_start_table,
	(select load_area as load_area_end
		from ventyx_e_substn_point, wecc_load_areas
		where ventyx_e_substn_point.rec_id = 24410
		and intersects(wecc_load_areas.polygon_geom, ventyx_e_substn_point.the_geom)) as load_area_end_table
where 	(wecc_trans_lines.load_area_end = load_area_end_table.load_area_end and
		wecc_trans_lines.load_area_start = load_area_start_table.load_area_start)
or
		(wecc_trans_lines.load_area_end = load_area_start_table.load_area_start
		and wecc_trans_lines.load_area_start = load_area_end_table.load_area_end)
;

-- get the Intermountain Utah-California line
update wecc_trans_lines
set existing_transfer_capacity_mw = 1920
from 
	(select load_area as load_area_start
		from ventyx_e_substn_point, wecc_load_areas
		where ventyx_e_substn_point.rec_id = 24230
		and intersects(wecc_load_areas.polygon_geom, ventyx_e_substn_point.the_geom)) as load_area_start_table,
	(select load_area as load_area_end
		from ventyx_e_substn_point, wecc_load_areas
		where ventyx_e_substn_point.rec_id = 34630
		and intersects(wecc_load_areas.polygon_geom, ventyx_e_substn_point.the_geom)) as load_area_end_table
where 	(wecc_trans_lines.load_area_end = load_area_end_table.load_area_end and
		wecc_trans_lines.load_area_start = load_area_start_table.load_area_start)
or
		(wecc_trans_lines.load_area_end = load_area_start_table.load_area_start
		and wecc_trans_lines.load_area_start = load_area_end_table.load_area_end)
;

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
-- 3 didn't have distances, so this makes a crappy fix.
--Autumn says: why are these needing distances in the first place?  
--There are no transmission lines between these places -- 1586 is CO_SW to CA_IID, 1237 is MEX_BAJA to CA_SMUD, and 558 is CA_SMUD to OR_WA_BPA

--update wecc_trans_lines
--set distances_along_existing_lines_m = 1.3 * 1000 * transmission_length_km
--where transmission_line_id in (1586, 1237, 558);

--Don't run this unless you want to wait for a while.  Also, if you're changing the inputs at all, you'll want to see <some other file I'm going to make>
select distances_along_translines('test_segment_start_end_dist_amp', 'test_segment_start_end_dist_amp_vertices', 'distances_along_existing_trans_lines');
update wecc_trans_lines set distances_along_existing_lines_m = ,
from distances_along_existing_trans_lines d where (d.load_area_start like wecc_trans_lines.load_area_start and d.load_area_end like wecc_trans_lines.load_area_end)  

-- Autumn should insert the script that outputs transline geoms here
SELECT AddGeometryColumn ('public','wecc_trans_lines','route_geom',4326,'MULTILINESTRING',2);
update wecc_trans_lines set route_geom = wecc_trans_lines_old.route_geom
from wecc_trans_lines_old
where 	wecc_trans_lines.load_area_start = wecc_trans_lines_old.load_area_start
and		wecc_trans_lines.load_area_end = wecc_trans_lines_old.load_area_end;

--Autumn: I'm going to change this to a new column instead--no sense losing the calculated distances every time.  
--But it's still going to be called distances_along_existing_lines_m.  The new column is called calculated_distances_along_existing_lines
-- if the distance along existing lines is double as long as the straight line distance between load areas,
-- set the distance to double the straight line distance, reflecting the high added cost and added length of making a new right of way

-- exports the wecc trans lines for pickup by mysql
-- the where clause gets all the lines that we're going to consider in this study
-- the case selects out lines which have really long distances along existing transmission lines
-- this effectivly limits their distance to 1.5 x that of the straight-line distance

-- calculate losses as 1 percent losses per 100 miles or 1 percent per 160.9344 km (reference from ReEDS Solar Vision Study documentation)
-- transmission lines with really short distances and therefore very high efficiencies were giving SWITCH problems with RPS runs
-- presumably because it was very difficult for the optimization to figure out how to send power around the network correctly.
-- as these very short lines are really a collection of many different lines, some of which are longer, we'll cap the transmission efficieny at 98.5 %,
-- the point at which it became computationally difficult for SWITCH.


drop table if exists wecc_trans_lines_for_export;
create table wecc_trans_lines_for_export(
	transmission_line_id serial primary key,
	load_area_start character varying(11),
	load_area_end	character varying(11),
	existing_transfer_capacity_mw double precision,
	transmission_length_km double precision,
	transmission_efficiency double precision,
	new_transmission_builds_allowed smallint default 1
);

SELECT AddGeometryColumn ('public','wecc_trans_lines_for_export','straightline_geom',4326,'LINESTRING',2);
SELECT AddGeometryColumn ('public','wecc_trans_lines_for_export','route_geom',4326,'MULTILINESTRING',2);

insert into wecc_trans_lines_for_export
			(transmission_line_id, load_area_start, load_area_end, existing_transfer_capacity_mw,
			transmission_length_km, transmission_efficiency, straightline_geom, route_geom)
	select	transmission_line_id,
			load_area_start,
			load_area_end,
			existing_transfer_capacity_mw,
			CASE WHEN ( distances_along_existing_lines_m / 1000 > 1.5 * transmission_length_km )
				THEN 1.5 * transmission_length_km
				ELSE distances_along_existing_lines_m/1000
			END as transmission_length_km,
			CASE 	WHEN ( 1 - (0.01 / 160.9344 * transmission_length_km) ) > 0.985
					THEN 0.985
					ELSE ( 1 - (0.01 / 160.9344 * transmission_length_km) )
			END as transmission_efficiency,
			the_geom,
			route_geom
 	from wecc_trans_lines
 	where (existing_transfer_capacity_mw > 0 or load_areas_border_each_other);

-- a handful of the transmission lines are redundant, so these are removed here
delete from wecc_trans_lines_for_export
where	(load_area_start like 'MT_SW' and load_area_end like 'WA_ID_AVA')
or		(load_area_start like 'CA_PGE_CEN' and load_area_end like 'CA_SCE_CEN')
or		(load_area_start like 'CA_SCE_CEN' and load_area_end like 'CA_SCE_SE')
or		(load_area_start like 'CO_E' and load_area_end like 'CO_NW')
;

-- now get the other direction
delete from wecc_trans_lines_for_export 
where (load_area_end, load_area_start) not in
	( select load_area_start, load_area_end from wecc_trans_lines_for_export);


-- a handful of existing long transmission lines are effectivly the combination of a few shorter ones in SWITCH,
-- so they are flagged here to prevent new builds along the longer corridors
update wecc_trans_lines_for_export
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
update wecc_trans_lines_for_export
set new_transmission_builds_allowed = 0
where (load_area_start, load_area_end) in
	( select load_area_end, load_area_start from wecc_trans_lines_for_export where new_transmission_builds_allowed = 0 );


COPY 
(select	transmission_line_id,
		load_area_start,
		load_area_end,
		existing_transfer_capacity_mw,
		transmission_length_km,
		transmission_efficiency,
		new_transmission_builds_allowed
	from 	wecc_trans_lines_for_export)
TO 		'/Volumes/1TB_RAID/Models/Switch\ Input\ Data/Transmission/wecc_trans_lines.csv'
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



-- REGIONAL ECONOMIC MULTIPLIER-------------------

-- finds each population density point inside each load area
drop table if exists us_population_density_to_load_area;
Create table us_population_density_to_load_area as 
	select us_population_density.gid, popdensity, load_area
	from us_population_density, wecc_load_areas
	where intersects(us_population_density.the_geom, wecc_load_areas.polygon_geom);
	
create index gid on us_population_density_to_load_area (gid);

-- finds each population density point inside each county.
-- no need to run multipule times because it takes a long time, unless the county shapefile is changed
drop table if exists us_population_density_to_county;
Create table us_population_density_to_county as 
	select us_population_density.gid, popdensity, cnty_fips
	from us_population_density, ventyx_counties_region
	where intersects(us_population_density.the_geom, ventyx_counties_region.the_geom);
	
create index gid on us_population_density_to_county (gid);

-- makes a table of regional economic multipliers calculated for each load area
-- by taking the sum of the population of each fraction of a county in a load area multiplied by its econ multiplier
-- and then dividing by the whole population of a load area
update wecc_load_areas
set economic_multiplier = multiplier_table.economic_multiplier
from
	(select 	load_area_population_table.load_area,
			sum(regional_economic_multiplier*population_load_area_county)/population_load_area as economic_multiplier
	from	regional_economic_multipliers,
	-- gets the total population of each load area for use above
		(select sum(popdensity) as population_load_area,
			load_area
		from us_population_density_to_load_area
		group by load_area) as load_area_population_table,
	-- finds the population of counties as divided across load area lines
	-- many counties are completly in one load area,
	-- but for those that aren't this one allocates population on either side of the load area line
		(select sum(us_population_density_to_load_area.popdensity) as population_load_area_county,
			load_area,
			cnty_fips
		from 	us_population_density_to_county,
				us_population_density_to_load_area
		where 	us_population_density_to_load_area.gid = us_population_density_to_county.gid
		group by load_area, cnty_fips) as county_load_area_population_table
	where 	regional_economic_multipliers.county_fips_code = cast(county_load_area_population_table.cnty_fips as int)
	and 	county_load_area_population_table.load_area = load_area_population_table.load_area
	and		load_area_population_table.load_area not like 'CAN%'
	and 	load_area_population_table.load_area not like 'MEX%'
	group by load_area_population_table.load_area, population_load_area) as multiplier_table
where multiplier_table.load_area = wecc_load_areas.load_area;

-- we don't have Canadian and Mexican values yet - these should be put here when they become available
-- right now they're educated guesses
update wecc_load_areas
set economic_multiplier = 0.85
where load_area like 'MEX%';

update wecc_load_areas
set economic_multiplier = 1.05
where load_area like 'CAN_BC';

update wecc_load_areas
set economic_multiplier = 1.1
where load_area like 'CAN_ALB';

-- RPS COMPLIANCE ENTITIES  -----------
-- define a map between load_area and rps_compliance_entity based on the structure
-- of utilities inside each state as shown in the ventyx data (manual matching)
-- and the DSIRE database (as of May 2011) www.dsireusa.org/
alter table wecc_load_areas add column rps_compliance_entity character varying(20);

update wecc_load_areas
set rps_compliance_entity =
	CASE	WHEN load_area in ('AZ_APS_N', 'AZ_APS_SW')	THEN 'AZ_APS'
			WHEN load_area like 'CA_PGE%' 				THEN 'CA_PGE'
			WHEN load_area like 'CA_SCE%' 				THEN 'CA_SCE'
			WHEN load_area in ('CO_DEN', 'CO_NW') 		THEN 'CO_PSC'
			WHEN load_area like 'NV_%' 					THEN 'NV_ENERGY'
			WHEN load_area like 'UT_%' 					THEN 'UT_PACE'
			ELSE load_area
	END;


-- import the proper rps_compliance_entity compliance targets from www.dsireusa.org/
drop table if exists rps_state_targets;
create table rps_state_targets(
	state character varying(10),
	compliance_year int,
	compliance_fraction float,
	PRIMARY KEY (state, compliance_year)
	);

copy rps_state_targets from
'/Volumes/1TB_RAID/Models/GIS/RPS/RPS_Compliance_WECC.csv'
with csv header;

-- divides rps state level targets by year into load area targets on the basis of population
-- does not go past 2035, as targets are not set that far out... 
drop table if exists rps_compliance_entity_targets;
create table rps_compliance_entity_targets(
	rps_compliance_entity character varying(20),
	compliance_year int,
	compliance_fraction float,
	PRIMARY KEY (rps_compliance_entity, compliance_year)
	);

-- do the US load areas
-- we're assuming that load (and thus compliance_fractions) are proportional to load
-- so this uses the population fraction across state lines for each rps_compliance_entity (as described by the nasty CASE)
-- to figure out how much of each state's target to include in each rps_compliance_entity
insert into rps_compliance_entity_targets
	select  compliance_entity_population_table.rps_compliance_entity,
			compliance_year,
			sum( compliance_fraction * compliance_entity_state_population / compliance_entity_population ) as compliance_fraction
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
		group by rps_compliance_entity,state
		) as compliance_entity_state_population_table
	where	rps_state_targets.state = compliance_entity_state_population_table.state
	and		compliance_entity_population_table.rps_compliance_entity = compliance_entity_state_population_table.rps_compliance_entity
	group by compliance_entity_population_table.rps_compliance_entity, compliance_year
	order by rps_compliance_entity, compliance_year;

-- the Navajo nation (AZ_NM_N) doesn't have to adhere to rps targets
update rps_compliance_entity_targets
set compliance_fraction = 0
where rps_compliance_entity = 'AZ_NM_N';

-- parts of Colorado (CO_E and CO_SW) are composed primarily of munis and coops...
-- they have a different target found in rps_state_targets as 'CO_MUNI'
-- they're all inside Colorado, so we don't have to worry about apportioning their compliance_fraction across state lines
update rps_compliance_entity_targets
set compliance_fraction = rps_state_targets.compliance_fraction
from rps_state_targets
where rps_compliance_entity in ('CO_E', 'CO_SW')
and rps_state_targets.state = 'CO_MUNI'
and rps_compliance_entity_targets.compliance_year = rps_state_targets.compliance_year;


-- at the moment Canada (Alberta and BC) and Mexico (Baja) don't have RPS-like targets, so zero them out for completeness
insert into rps_compliance_entity_targets
	select 	rps_compliance_entity,
			compliance_year,
			0 as compliance_fraction
	from 	(select rps_compliance_entity from wecc_load_areas where rps_compliance_entity not in
				(select distinct rps_compliance_entity from rps_compliance_entity_targets)
			) as compliance_entity_without_rps,
			(select distinct compliance_year from rps_compliance_entity_targets) as compliance_years
			order by 1,2;


-- export rps complaince info to mysql
copy 
(select	rps_compliance_entity,
 		compliance_year,
 		compliance_fraction
from	rps_compliance_entity_targets
order by rps_compliance_entity, compliance_year)
to '/Volumes/1TB_RAID/Models/GIS/RPS/rps_compliance_targets.csv'
with CSV HEADER;


-- EXPORT LOAD AREA INFO TO MYSQL-------
copy
(select	load_area,
 		primary_nerc_subregion,
 		primary_state,
  		economic_multiplier,
  		rps_compliance_entity
from	wecc_load_areas
order by load_area)
to '/Volumes/1TB_RAID/Models/GIS/wecc_load_area_info.csv'
with CSV HEADER;
