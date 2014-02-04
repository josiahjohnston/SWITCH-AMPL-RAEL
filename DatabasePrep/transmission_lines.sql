SET search_path TO wecc_inputs, public;

-- dependent on Load Areas WECC v2.sql

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
