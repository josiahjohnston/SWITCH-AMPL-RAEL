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
	existing_transfer_capacity_mw double precision default 0,
	transmission_efficiency double precision,
	new_transmission_builds_allowed smallint default 1
	dc_line smallint default 0
);

SELECT AddGeometryColumn ('public','wecc_trans_lines','straightline_geom',4326,'LINESTRING',2);
SELECT AddGeometryColumn ('public','wecc_trans_lines','route_geom',4326,'MULTILINESTRING',2);

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
update wecc_trans_lines set route_geom = wecc_trans_lines_old.route_geom
from wecc_trans_lines_old
where 	wecc_trans_lines.load_area_start = wecc_trans_lines_old.load_area_start
and		wecc_trans_lines.load_area_end = wecc_trans_lines_old.load_area_end;

-- update the transmission_length_km to be along existing lines whenever possible
-- the case selects out lines which have really long distances along existing transmission lines
-- this effectivly limits their distance to 1.5 x that of the straight-line distance
update wecc_trans_lines	set transmission_length_km = 
	CASE WHEN ( distances_along_existing_lines_km > 1.5 * straightline_distance_km or distances_along_existing_lines_km is null )
			THEN 1.5 * straightline_distance_km
		ELSE distances_along_existing_lines_km END;


-- TRANSFER CAPACITY AND SUSCEPTANCE -----
-- add approximate single circuit transfer capacites for lines that cross load area borders
-- this data comes primarly from the WREZ excel transmission planning model which can be found at
-- /Volumes/1TB_RAID/Models/Switch_Input_Data/Transmission/GTMWG\ Version\ 2_0\ June\ 2009.xlsm
-- also, data for <230kV class transfer capacities is found at
-- http://www.idahopower.com/pdfs/AboutUs/PlanningForFuture/ProjectNews/wrep/PresentationTransmissionParamMar2207.pdf
-- a copy of which is in the same folder as above

drop table if exists transmission_line_average_rated_capacities;
create table transmission_line_average_rated_capacities (
	voltage_kv int primary key,
	volt_class character varying(10),
	rated_capacity_mw double precision,
	resistance_ohms_per_km double precision,
	reactance_ohms_per_km double precision);
	
insert into transmission_line_average_rated_capacities (voltage_kv, volt_class, rated_capacity_mw) values
	(69, 'Under 100', 50),
	(115, '100-161', 100),
	(138, '100-161', 150),
	(230, '230-287', 400),
	(345, '345', 750),
	(500, '500', 1500);
	

-- now add in the average reactance and resistance values per km from ferc 715 data
-- 100MVA system base, so to convert reactances from per unit quantities to ohms, multiply by Zbase= voltage^2/MVAbase,
-- st is 'in service'
-- dividing by 1.609344 converts from miles (the native unit of length here) to km
update transmission_line_average_rated_capacities 
set resistance_ohms_per_km = f715_resist_react.resistance_ohms_per_km,
	reactance_ohms_per_km = f715_resist_react.reactance_ohms_per_km
from
	( select * from 
		(select bus1_kv as voltage_kv,
			avg(resist*(bus1_kv*1000)^2/(length*100000000))/1.609344 as resistance_ohms_per_km,
			avg(react*(bus1_kv*1000)^2/(length*100000000))/1.609344 as reactance_ohms_per_km,
			count(*) as cnt
		from wecc_f715_branch_info_pk
		where rate1 > 0
		and length > 10
		and react > 0
		and resist > 0
		and st = 1
		group by bus1_kv order by bus1_kv) as foo
		where cnt > 10 ) as f715_resist_react
where transmission_line_average_rated_capacities.voltage_kv = f715_resist_react.voltage_kv
	;

-- dc lines won't match on voltage
-- get the Pacific DC line capacity and length
update wecc_trans_lines
set existing_transfer_capacity_mw = 3100, 
	distances_along_existing_lines_km = (580.437+264.593),
	transmission_length_km = (580.437+264.593),
	dc_line = 1
where 	( load_area_start = 'OR_WA_BPA' and load_area_end = 'CA_LADWP');

-- get the Intermountain Utah-California line
update wecc_trans_lines
set existing_transfer_capacity_mw = 1920, 
	dc_line = 1
where 	( load_area_start = 'UT_S' and load_area_end = 'CA_SCE_CEN');

-- Intermountain doesn't have quite the correct route_geom, but add something here that is almost correct
update wecc_trans_lines
set route_geom = transline_geom
from (select transline_geom from wecc_trans_lines_that_cross_load_area_borders where load_area_end = 'UT_S' and load_area_start = 'CA_SCE_CEN') as intermountain_geom
where ( load_area_start = 'UT_S' and load_area_end = 'CA_SCE_CEN') or ( load_area_end = 'UT_S' and load_area_start = 'CA_SCE_CEN');

-- now update capacites and that match on voltage_kv
update wecc_trans_lines
set existing_transfer_capacity_mw = existing_transfer_capacity_mw_voltage_kv
from 
	( select 	load_area_start,
				load_area_end,
				sum( num_lines * rated_capacity_mw ) as existing_transfer_capacity_mw_voltage_kv
	from wecc_trans_lines_that_cross_load_area_borders
	join transmission_line_average_rated_capacities using (voltage_kv)
	where wecc_trans_lines_that_cross_load_area_borders.volt_class != 'DC Line'
	group by load_area_start, load_area_end ) as cap_voltage_kv
where 	wecc_trans_lines.load_area_start = cap_voltage_kv.load_area_start
and		wecc_trans_lines.load_area_end = cap_voltage_kv.load_area_end;

-- now update capacites that match on volt_class but not voltage_kv
update wecc_trans_lines
set existing_transfer_capacity_mw = existing_transfer_capacity_mw + existing_transfer_capacity_mw_volt_class
from 
	( select 	load_area_start,
				load_area_end,
				sum(rated_capacity_mw * num_lines) as existing_transfer_capacity_mw_volt_class
	from wecc_trans_lines_that_cross_load_area_borders
	join (select volt_class, avg(rated_capacity_mw) as rated_capacity_mw from transmission_line_average_rated_capacities group by volt_class) as volt_class_agg using (volt_class)
	where wecc_trans_lines_that_cross_load_area_borders.voltage_kv not in (select voltage_kv from transmission_line_average_rated_capacities)
	and	wecc_trans_lines_that_cross_load_area_borders.volt_class != 'DC Line'
	group by load_area_start, load_area_end) as cap_volt_class
where 	wecc_trans_lines.load_area_start = cap_volt_class.load_area_start
and		wecc_trans_lines.load_area_end = cap_volt_class.load_area_end;

-- each line needs to have the same capacity in both directions, which is the sum of the lines in each direction
-- (the 'direction' of each line is arbitrary - power can flow either way on any line)
update wecc_trans_lines w1
set existing_transfer_capacity_mw = w1.existing_transfer_capacity_mw + w2.existing_transfer_capacity_mw,
	dc_line = case when ( w1.dc_line = 1 or w2.dc_line = 1 ) then 1 else 0 end
from wecc_trans_lines w2
where 	w1.load_area_start = w2.load_area_end
and		w1.load_area_end = w2.load_area_start;



-- calculate losses as 1 percent losses per 100 miles or 1 percent per 160.9344 km (reference from ReEDS Solar Vision Study documentation)
update wecc_trans_lines set transmission_efficiency = 1 - (0.01 / 160.9344 * transmission_length_km);

-- to reduce the number of decision variables, delete all transmission lines that aren't existing paths or that don't have load areas that border each other
delete from wecc_trans_lines where (existing_transfer_capacity_mw = 0 and not load_areas_border_each_other);


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






COPY 
(select	transmission_line_id,
		load_area_start,
		load_area_end,
		existing_transfer_capacity_mw,
		transmission_length_km,
		transmission_efficiency,
		new_transmission_builds_allowed
	from 	wecc_trans_lines
	order by load_area_start, load_area_end)
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
  		rps_compliance_entity
from	wecc_load_areas
order by load_area)
to '/Volumes/1TB_RAID/Models/GIS/wecc_load_area_info.csv'
with CSV HEADER;
