-- build a set of solar farms from central station (PV and CSP), as well as distributed PV.

-- CENTRAL STATION SOLAR--------------------------
-- use shapefiles of land cover, exclusion zones, and slope to define sites for central station solar

-- LAND COVER
-- From: http://bioval.jrc.ec.europa.eu/products/glc2000/products.php
-- Global Land Cover 2000
-- has 1 km resolution of land cover

-- load into the database on the command line
-- raster2pgsql -d -C -t 50x50 -s 4326 -I /Volumes/switch/Models/USA_CAN/Solar/Land_Cover/Bil/namerica_v2.bil usa_can.land_cover_north_america_1km | psql -d switch_gis

-- CLASSIFICATIONS------------
-- 1Tropical or Sub-tropical Broadleaved Evergreen Forest - Closed Canopy,
-- 2Tropical or Sub-tropical Broadleaved Deciduous Forest - Closed Canopy,
-- 3Temperate or Sub-polar Broadleaved Deciduous Forest - Closed Canopy,
-- 4Temperate or Sub-polar Needleleaved Evergreen Forest - Closed Canopy,
-- 5Temperate or Sub-polar Needleleaved Evergreen Forest - Open Canopy,
-- 6Temperate or Sub-polar Needleleaved Mixed Forest - Closed Canopy,
-- 7Temperate or Sub-polar Mixed Broadleaved or Needleleaved Forest - Closed Canopy,
-- 8Temperate or Sub-polar Mixed Broaddleleaved or Needleleaved Forest - Open Canopy,
-- 9Temperate or Subpolar Broadleaved Evergreen Shrubland - Closed Canopy,
-- 10Temperate or Subpolar Broadleaved Deciduous Shrubland - Open Canopy,
-- 11Temperate or Subpolar Needleleaved Evergreen Shrubland - Open Canopy,
-- 12Temperate or Sub-polar Mixed Broadleaved and Needleleaved Dwarf-Shrubland - Open Canopy,
-- 13Temperate or Subpolar Grassland,
-- 14Temperate or Subpolar Grassland with a Sparse Tree Layer,
-- 15Temperate or Subpolar Grassland with a Sparse Shrub Layer,
-- 16Polar Grassland with a Sparse Shrub Layer,
-- 17Polar Grassland with a Dwarf-Sparse Shrub Layer,
-- 18Cropland,
-- 19Cropland and Shrubland/woodland,
-- 20Subpolar Needleleaved Evergreen Forest Open Canopy -  lichen understory,
-- 21Unconsolidated Material Sparse Vegetation (old burnt or other disturbance),
-- 22Urban and Built-up,
-- 23 Consolidated Rock Sparse Vegetation,
-- 24Water bodies,
-- 25Burnt area (resent burnt area),
-- 26Snow and Ice,
-- 27Wetlands,
-- 28Herbaceous Wetlands,
-- 29Tropical or Sub-tropical Broadleaved Evergreen Forest - Open Canopy

-- We'll consider the classification types: 12, 13, 14, 15, 16, 17, 21, 23
-- to be acceptable for solar development
-- dwarf shrubland (#12) is what covers most of the desert southwest




DROP TABLE IF EXISTS land_cover_rid_to_states_map;
CREATE TABLE land_cover_rid_to_states_map (
	rid int,
	state varchar(3),
	rid_is_across_state_borders boolean DEFAULT FALSE,
	PRIMARY KEY (rid, state) );

SELECT addgeometrycolumn ('usa_can','land_cover_rid_to_states_map','the_geom',4326,'MULTIPOLYGON',2);
CREATE INDEX ON land_cover_rid_to_states_map USING gist (the_geom);

INSERT INTO land_cover_rid_to_states_map (rid, state, the_geom)
SELECT rid, state, ST_Multi(ST_Union(the_geom)) FROM (
	SELECT 	rid,
			abbrev as state,
			ST_CollectionExtract(ST_Multi((ST_Intersection(rast, the_geom)).geom),3) as the_geom
	FROM 	land_cover_north_america_1km,
			ventyx_may_2012.states_region
	WHERE	ST_Intersects(rast, the_geom)
	) as intersection_table
GROUP BY rid, state;


UPDATE 	land_cover_rid_to_states_map
SET 	rid_is_across_state_borders = TRUE
FROM 	(SELECT rid, count(*) as num_states FROM land_cover_rid_to_states_map GROUP BY rid) as num_states_table
WHERE	land_cover_rid_to_states_map.rid = num_states_table.rid
AND		num_states > 1;

-- create a table of acceptable land cover, broken up by raster tile for easier manipulation
DROP TABLE IF EXISTS solar_central_station_acceptable_land_cover;
CREATE TABLE solar_central_station_acceptable_land_cover (
	rid int,
	state varchar(3),
	PRIMARY KEY (rid, state) );
	
SELECT addgeometrycolumn ('usa_can','solar_central_station_acceptable_land_cover','the_geom',4326,'MULTIPOLYGON',2);
CREATE INDEX ON solar_central_station_acceptable_land_cover USING gist (the_geom);

-- first, insert land cover from raster tiles that don't cross state borders
-- this means that we don't have to do an intersection with the state geom for these tiles,
-- thereby saving a lot of computation time
INSERT INTO solar_central_station_acceptable_land_cover (rid, state, the_geom)
SELECT rid,
			state,
			ST_Multi(ST_Union(the_geom)) as the_geom
	FROM	(	SELECT 	rid,
						state,
						(ST_DumpAsPolygons(rast)).val as classification_type,
						(ST_DumpAsPolygons(rast)).geom as the_geom
				FROM	land_cover_north_america_1km
				JOIN	land_cover_rid_to_states_map USING (rid)
				WHERE	NOT rid_is_across_state_borders
			) as pixel_to_polygon_table
	WHERE classification_type IN (12, 13, 14, 15, 16, 17, 21, 23)
	GROUP BY rid, state;

-- the above query hasn't cut land area around the coasts correctly
-- do an update here to cut off pixels that go into the sea
-- the ST_CollectionExtract..., 3 returns multipolygons out of the intersection - we don't want point or line intersections
UPDATE 	solar_central_station_acceptable_land_cover l
SET 	the_geom = ST_CollectionExtract(ST_Multi(ST_Intersection(l.the_geom, s.the_geom)),3)
FROM 	ventyx_may_2012.states_region s 
WHERE	s.abbrev = l.state;


-- now do the intersection with state polygons for tiles that cross state borders
INSERT INTO solar_central_station_acceptable_land_cover (rid, state, the_geom)
	SELECT 	rid,
			state,
			ST_Multi(ST_Union(the_geom)) as the_geom
	FROM	(	SELECT 	rid,
						state,
						(ST_Intersection(rast, the_geom)).val as classification_type,
						(ST_Intersection(rast, the_geom)).geom as the_geom
				FROM	land_cover_north_america_1km
				JOIN	land_cover_rid_to_states_map USING (rid)
				WHERE	rid_is_across_state_borders
			) as pixel_to_polygon_table
	WHERE 	classification_type IN (12, 13, 14, 15, 16, 17, 21, 23)
	AND		ST_Dimension(the_geom) = 2
	GROUP BY rid, state;







-- EXCLUDE EXCLUSION ZONES
-- postgis has runtime problems with taking the difference between the large and complex shapefiles
-- solar_central_station_acceptable_land_cover and solar_central_station_exclusion_zones


DROP TABLE IF EXISTS solar_central_station_exclusion_zones;
CREATE TABLE solar_central_station_exclusion_zones (
	land_id serial PRIMARY KEY);

SELECT AddGeometryColumn ('usa_can','solar_central_station_exclusion_zones','the_geom',4326,'POLYGON',2);
CREATE INDEX ON solar_central_station_exclusion_zones USING gist (the_geom);



DROP TABLE IF EXISTS solar_central_station_land_cover_minus_exclusion_zones;
CREATE TABLE solar_central_station_land_cover_minus_exclusion_zones (
	rid int,
	state varchar(3),
	PRIMARY KEY (rid, state));

SELECT AddGeometryColumn ('usa_can','solar_central_station_land_cover_minus_exclusion_zones','the_geom',4326,'MULTIPOLYGON',2);
CREATE INDEX ON solar_central_station_land_cover_minus_exclusion_zones USING gist (the_geom);

-- first add all acceptable land.  This land will be subtracted from using ST_Difference wherever it falls within an exclusion zone
INSERT INTO solar_central_station_land_cover_minus_exclusion_zones (rid, state, the_geom)
	SELECT 	* FROM	solar_central_station_acceptable_land_cover;



CREATE OR REPLACE FUNCTION exclusion_zones() RETURNS VOID AS $$ BEGIN

DROP TABLE IF EXISTS solar_central_station_exclusion_zones_grid;
CREATE TABLE solar_central_station_exclusion_zones_grid (
	rid int,
	state varchar(3),
	PRIMARY KEY (rid, state) );

PERFORM AddGeometryColumn ('usa_can','solar_central_station_exclusion_zones_grid','the_geom',4326,'MULTIPOLYGON',2);
CREATE INDEX ON solar_central_station_exclusion_zones_grid USING gist (the_geom);

-- divide up exclusion zone polygons by rid and state to speed up ST_Difference below
INSERT INTO solar_central_station_exclusion_zones_grid (rid, state, the_geom)
	SELECT  rid,
			state,
			ST_Multi(ST_Union(the_geom))
	FROM (
		SELECT 	rid,
				state,
				ST_CollectionExtract((ST_Dump(ST_Intersection(e.the_geom, l.the_geom))).geom,3) as the_geom
		FROM	solar_central_station_exclusion_zones e,
				land_cover_rid_to_states_map l
		WHERE	ST_Intersects(e.the_geom, l.the_geom)
		) as intersection_table
	GROUP BY rid, state;

-- remove polygons from the exclusions zone table to prepare the function for the next layer of exclusion zones
DELETE FROM solar_central_station_exclusion_zones;

-- update any geometry that has been reduced by st_difference
UPDATE 	solar_central_station_land_cover_minus_exclusion_zones s
SET		the_geom = diff_geom
FROM 	(SELECT rid,
				state,
				ST_CollectionExtract(ST_Multi(ST_Difference(l.the_geom, e.the_geom)),3) as diff_geom
		FROM	solar_central_station_acceptable_land_cover l
		JOIN	solar_central_station_exclusion_zones_grid e		
		USING	(rid, state)
		) as diff_table
WHERE	s.rid = diff_table.rid
AND		s.state = diff_table.state;

END; $$ LANGUAGE 'plpgsql';

-- the st_buffer in the next queries corrects invalid geometries (they had self-intersections)

-- ventyx_lakes_region... everything... solar doesn't walk on water... at least not yet.
-- had to union then dump the shapefile because it was causing problems later down the script with ST_Union
insert into solar_central_station_exclusion_zones (the_geom)
	select 	ST_Buffer((ST_Dump(ST_Union(the_geom))).geom,0)
		from ventyx_may_2012.lakes_region;

SELECT exclusion_zones();

-- ventyx_fed_lands_region
-- exclude everything except: type in ('Public Domain Land BLM', 'Indian Reservation')
-- and some random "Bureau of Reclamation BOR" squares in Nevada that don't seem to have any purpose (they're good ol' Nevada desert)
-- which are denoted by not having anything in the "name" column
insert into solar_central_station_exclusion_zones (the_geom)
	select 	ST_Buffer((ST_Dump(ST_Union(the_geom))).geom,0)
		from ventyx_may_2012.fed_lands_region
		where (type not in ('Public Domain Land BLM', 'Indian Reservation')
				or (type like 'Bureau of Reclamation BOR' and "name" is not null));

SELECT exclusion_zones();

-- ventyx_urb_area_region... everything... rooftop PV and wholesale distributed pv data will come from elsewhere
-- gave problems with ST_Union, so didn't union...
insert into solar_central_station_exclusion_zones (the_geom)
	select 	ST_Buffer((ST_Dump(the_geom)).geom,0)
		from ventyx_may_2012.urb_area_region;

SELECT exclusion_zones();

-- exclude/avoid areas from the Western Renewable Energy Zones project (wrez)
-- load into postgres on the command line:
-- shp2pgsql -s 4326 -d -I -g the_geom /Volumes/switch/Models/GIS/wrez_exclude_avoid_areas/Exclusion_Areas.dbf usa_can.wrez_exclude_avoid_areas | psql -h switch-db1.erg.berkeley.edu -U jimmy -d switch_gis
-- gave problems with ST_Union, so didn't union...
insert into solar_central_station_exclusion_zones (the_geom)
	select 	ST_Buffer((ST_Dump(the_geom)).geom,0)
		from usa_can.wrez_exclude_avoid_areas;

SELECT exclusion_zones();

-- clean up
DROP FUNCTION exclusion_zones();
DROP TABLE solar_central_station_exclusion_zones_grid;
DROP TABLE solar_central_station_exclusion_zones;



-- SLOPE -------------------------------------------
-- done in ARCMAP because postgis 2.0 raster is pretty primitive 

-- this one is a pain for many reasons... mainly due to ArcMap
-- I decided to slope at 1km resolution because 90m SRTM elevation data was taking far too long to process
-- and the insolation data is 10km, so 1km is already much better than this.

-- I downloaded the four GTOPO30 elevation files for North America from
-- http://eros.usgs.gov/products/elevation/gtopo30/README.html
-- this website describes how to process these files in ArcMap... it's not trivial
-- http://www.geo.utexas.edu/courses/371c/Labs/Software_Tips/GTOPO30_import.htm

-- I'll summarize here...
-- First I renamed the .DEM files to .bil, then loaded them into Arcmap
-- then did Mosiac to New Raster (?... I think I remember correctly) on the four files to create Calculation,
-- on which set some of the ocean values to -9999 and others to 55537
-- so then on the new layer, under Spatial Analyst Toolbar, I went to Options and set the extent to the Union of inputs
-- then went to Raster Calculator on the same tab and typed
-- setnull([Calculation] == -9999, [Calculation])
-- then on the new raster Calculation2
-- setnull([Calculation2] == 55537, [Calculation2])
-- which has now turned the ocean into null values (which is desired)

-- next, I projected the elevation grid into a Lambert Conformal Conic (LCC) projection to do slope calculations
-- because a proper projection (not the native WGS84) is needed to do slope
-- this was done using Project Raster under the Data Managment > Projections and Transformations
-- with NAD_1983_to_WGS_1984_1 as the conversion method (this one is best for large North American rasters)

-- then under Spatial Analyst > Surface > Slope
-- I calculated the percent rise of the LCC raster ( z=1 because LCC is in meters)
-- the LCC slope raster was then converted back to WGS84 with a cell size of 0.00833333 ( the same as a 1km raster in WGS84)
-- using Project Raster under the Data Managment > Projections and Transformations

-- to select the best solar sites, i.e. the ones with slope <= 1%
-- from this slope raster, I went to Spatial Analyst > Raster Calculator and typed in
-- setnull([NASlope1km.img] > 1, [NASlope1km.img])

-- now load into postgresql:
-- raster2pgsql -d -C -t 50x50 -s 4326 -I /Volumes/switch/Models/USA_CAN/Solar/Slope/NASlope1km.img usa_can.slope_usa_can | psql -d switch_gis



DROP TABLE IF EXISTS slope_usa_can_less_than_one_percent;
CREATE TABLE slope_usa_can_less_than_one_percent (
	rid int,
	state varchar(3),
	PRIMARY KEY (rid, state) );

SELECT addgeometrycolumn ('usa_can','slope_usa_can_less_than_one_percent','the_geom',4326,'MULTIPOLYGON',2);
CREATE INDEX ON slope_usa_can_less_than_one_percent USING gist (the_geom);
CREATE INDEX ON slope_usa_can_less_than_one_percent (rid);
CREATE INDEX ON slope_usa_can_less_than_one_percent (state);

-- took 7h, though the database server had medium-high load
-- the ST_Buffer(, 0.000001) fixes a floating point precision problem that spits out polygons
-- that should have identical vertices but instead are seperated by a *really* small margin 
INSERT INTO slope_usa_can_less_than_one_percent (rid, state, the_geom)
	SELECT 	rid,
			state,
			ST_Multi(ST_Union(the_geom)) as the_geom
	FROM	(	SELECT 	l.rid,
						state,
						(ST_DumpAsPolygons(rast)).val as percent_slope,
						ST_Intersection(ST_Buffer((ST_DumpAsPolygons(rast)).geom, 0.000001), the_geom) as the_geom
				FROM	usa_can.slope_usa_can,
						land_cover_rid_to_states_map l
				WHERE	ST_Intersects(rast, the_geom)
			) as pixel_to_polygon_table
	WHERE 	percent_slope <= 1
	AND		ST_Dimension(the_geom) = 2
	GROUP BY rid, state;




-- CREATE FINAL CENTRAL STATION SOLAR SITES TABLE
-- intersect the layers slope_usa_can_less_than_one_percent AND solar_central_station_land_cover_minus_exclusion_zones
-- to get the acceptable land for solar development
-- the solar_central_station_land_cover_minus_exclusion_zones layer had tiny numerical inconsistencies, so use buffer to correct
DROP TABLE IF EXISTS solar_central_station_polygons_rid_state;
CREATE TABLE solar_central_station_polygons_rid_state (
	rid int,
	state varchar(3),
	area_km_2 int,
	PRIMARY KEY (rid, state));

SELECT AddGeometryColumn ('usa_can','solar_central_station_polygons_rid_state','the_geom',4326,'MULTIPOLYGON',2);
CREATE INDEX ON solar_central_station_polygons_rid_state USING gist (the_geom);

INSERT INTO solar_central_station_polygons_rid_state (rid, state, the_geom)
	SELECT 	rid,
			state,
			ST_Multi(ST_CollectionExtract(ST_Union(ST_Intersection(s.the_geom, ST_Buffer(e.the_geom,0.000001))),3)) as the_geom
	FROM 	slope_usa_can_less_than_one_percent s
	JOIN	solar_central_station_land_cover_minus_exclusion_zones e
	USING 	(rid, state)
	GROUP BY rid, state;




-- intersect the land good for central station solar (solar_central_station_polygons)
-- with the suny grid cells to find out which cells to simulate from our downloaded weather data

-- load up the grid cell maps first
-- shp2pgsql -s 4326 -d -I -g the_geom /Volumes/switch/Models/USA_CAN/Solar/NREL_avg_maps/us9809_ghi_updated/us9809_ghi_updated.shp usa_can.solar_nrel_avg_ghi | psql -h switch-db1.erg.berkeley.edu -U jimmy -d switch_gis
-- shp2pgsql -s 4326 -d -I -g the_geom /Volumes/switch/Models/USA_CAN/Solar/NREL_avg_maps/us9809_dni_updated/us9809_dni_updated.shp usa_can.solar_nrel_avg_dni | psql -h switch-db1.erg.berkeley.edu -U jimmy -d switch_gis
-- shp2pgsql -s 4326 -d -I -g the_geom /Volumes/switch/Models/USA_CAN/Solar/NREL_avg_maps/us9809_latilt_updated/us9809_latilt_updated.shp usa_can.solar_nrel_avg_latitudetilt | psql -h switch-db1.erg.berkeley.edu -U jimmy -d switch_gis
ALTER TABLE solar_nrel_avg_latitudetilt DROP COLUMN id;
ALTER TABLE solar_nrel_avg_latitudetilt DROP COLUMN gid;
ALTER TABLE solar_nrel_avg_latitudetilt ALTER COLUMN gridcode TYPE int;
ALTER TABLE solar_nrel_avg_latitudetilt ADD PRIMARY KEY (gridcode);

ALTER TABLE solar_nrel_avg_ghi DROP COLUMN id;
ALTER TABLE solar_nrel_avg_ghi DROP COLUMN gid;
ALTER TABLE solar_nrel_avg_ghi ALTER COLUMN gridcode TYPE int;
ALTER TABLE solar_nrel_avg_ghi ADD PRIMARY KEY (gridcode);
ALTER TABLE solar_nrel_avg_ghi ADD COLUMN intersects_solar_land BOOLEAN DEFAULT FALSE;
ALTER TABLE solar_nrel_avg_dni DROP COLUMN id;
ALTER TABLE solar_nrel_avg_dni DROP COLUMN gid;
ALTER TABLE solar_nrel_avg_dni ALTER COLUMN gridcode TYPE int;
ALTER TABLE solar_nrel_avg_dni ADD PRIMARY KEY (gridcode);
ALTER TABLE solar_nrel_avg_dni ADD COLUMN intersects_solar_land BOOLEAN DEFAULT FALSE;

SELECT AddGeometryColumn ('usa_can','solar_nrel_avg_dni','centroid_geom',4326,'POINT',2);
CREATE INDEX ON solar_nrel_avg_dni USING gist (centroid_geom);
UPDATE solar_nrel_avg_dni SET centroid_geom = ST_Centroid(the_geom);

UPDATE 	solar_nrel_avg_ghi
SET		intersects_solar_land = TRUE
FROM	(SELECT DISTINCT gridcode
			FROM 	solar_nrel_avg_ghi n,
					solar_central_station_polygons_rid_state s
			WHERE ST_Intersects(n.the_geom, s.the_geom)
			) intersection_table
WHERE solar_nrel_avg_ghi.gridcode = intersection_table.gridcode;

UPDATE solar_nrel_avg_dni d
SET intersects_solar_land = g.intersects_solar_land
FROM solar_nrel_avg_ghi g
where g.gridcode = d.gridcode;

-- the nrel solar prospector hourly data had a substantial number of errors along timezone boundaries
-- we'll add a flag here for tiles that intersect these boundary and exclude these tiles from the simulations
ALTER TABLE solar_nrel_avg_dni ADD COLUMN timezone_line_of_doom BOOLEAN DEFAULT FALSE;
UPDATE 	solar_nrel_avg_dni
SET 	timezone_line_of_doom = TRUE
FROM	(
			(SELECT DISTINCT gridcode
				FROM	solar_nrel_avg_dni s,
						ventyx_may_2012.timezones_region t
				WHERE	time_zone = 'Pacific'
				AND		ST_Intersects(t.the_geom, ST_Expand(s.the_geom, 0.1))
			) as p_border
			JOIN
			(SELECT DISTINCT gridcode
				FROM	solar_nrel_avg_dni s,
						ventyx_may_2012.timezones_region t
				WHERE	time_zone = 'Mountain'
				AND		ST_Intersects(t.the_geom, ST_Expand(s.the_geom, 0.1))
			) as m_border
			USING (gridcode)
		) as timezone_line_table
WHERE 	timezone_line_table.gridcode = solar_nrel_avg_dni.gridcode;

UPDATE 	solar_nrel_avg_dni
SET 	timezone_line_of_doom = TRUE
FROM	(
			(SELECT DISTINCT gridcode
				FROM	solar_nrel_avg_dni s,
						ventyx_may_2012.timezones_region t
				WHERE	time_zone = 'Central'
				AND		ST_Intersects(t.the_geom, ST_Expand(s.the_geom, 0.1))
			) as p_border
			JOIN
			(SELECT DISTINCT gridcode
				FROM	solar_nrel_avg_dni s,
						ventyx_may_2012.timezones_region t
				WHERE	time_zone = 'Mountain'
				AND		ST_Intersects(t.the_geom, ST_Expand(s.the_geom, 0.1))
			) as m_border
			USING (gridcode)
		) as timezone_line_table
WHERE 	timezone_line_table.gridcode = solar_nrel_avg_dni.gridcode;

UPDATE 	solar_nrel_avg_dni
SET 	timezone_line_of_doom = TRUE
FROM	(
			(SELECT DISTINCT gridcode
				FROM	solar_nrel_avg_dni s,
						ventyx_may_2012.timezones_region t
				WHERE	time_zone = 'Central'
				AND		ST_Intersects(t.the_geom, ST_Expand(s.the_geom, 0.1))
			) as p_border
			JOIN
			(SELECT DISTINCT gridcode
				FROM	solar_nrel_avg_dni s,
						ventyx_may_2012.timezones_region t
				WHERE	time_zone = 'Eastern'
				AND		ST_Intersects(t.the_geom, ST_Expand(s.the_geom, 0.1))
			) as m_border
			USING (gridcode)
		) as timezone_line_table
WHERE 	timezone_line_table.gridcode = solar_nrel_avg_dni.gridcode;

ALTER TABLE solar_nrel_avg_latitudetilt ADD COLUMN timezone_line_of_doom BOOLEAN DEFAULT FALSE;
UPDATE solar_nrel_avg_latitudetilt tilt
SET timezone_line_of_doom = dni.timezone_line_of_doom
FROM solar_nrel_avg_dni dni
WHERE tilt.gridcode = dni.gridcode;

ALTER TABLE solar_nrel_avg_ghi ADD COLUMN timezone_line_of_doom BOOLEAN DEFAULT FALSE;
UPDATE solar_nrel_avg_ghi ghi
SET timezone_line_of_doom = dni.timezone_line_of_doom
FROM solar_nrel_avg_dni dni
WHERE ghi.gridcode = dni.gridcode;


-- CREATE FARMS------
-- an algorithm to create polygons 'solar farms' from discrete points for which we have timeseries data,
-- ensuring that the resultant solar farms are composed of points within an allowed standard deviation of capacity factor

CREATE OR REPLACE FUNCTION solar_farms(allowed_std_dev double precision) RETURNS void AS $$ 
DECLARE number_of_polygons_left int;

BEGIN 

DROP TABLE IF EXISTS solar_central_station_polygons;
CREATE TABLE solar_central_station_polygons (
	solar_farm_id serial primary key,
	cnty_fips varchar(15),
	avg_dni double precision,
	max_dni double precision,
	min_dni double precision,
	standard_deviation double precision,
	updated_with_available_land_geom BOOLEAN default FALSE,
	nrel_gridcode int REFERENCES solar_nrel_avg_dni (gridcode),
	timezone_diff_from_utc smallint CHECK (timezone_diff_from_utc BETWEEN -23 AND 23),
	area_km_2 double precision CHECK (area_km_2 > 0)
);
	
PERFORM AddGeometryColumn ('usa_can','solar_central_station_polygons','the_geom',4326,'MULTIPOLYGON',2);
CREATE INDEX ON solar_central_station_polygons USING gist (the_geom);
CREATE INDEX ON solar_central_station_polygons (nrel_gridcode);
CREATE INDEX ON solar_central_station_polygons (solar_farm_id, nrel_gridcode);
CREATE INDEX ON solar_central_station_polygons (nrel_gridcode, timezone_diff_from_utc);

-- make sure we enter the loop using a dummy value
SELECT 99999 INTO number_of_polygons_left;

WHILE (number_of_polygons_left > 0 ) LOOP 

-- the first time around the loop this will create polygons that encompass all the siteids (the NOT IN won't return anything)
-- subsequent times around the loop it will get new polygons that don't contain any of the polygons with acceptable standard deviations
-- We'll use them as a new set of polygons to slice and dice until we've setteled on a set that all have acceptable standard deviations
-- We'll also use counties to divide polygons
INSERT INTO solar_central_station_polygons (cnty_fips, the_geom)
	SELECT 	cnty_fips,
			ST_Multi((ST_Dump(union_geom)).geom)
	FROM	(SELECT cnty_fips,
					ST_Union(d.the_geom) as union_geom
				FROM	solar_nrel_avg_dni d,
						ventyx_may_2012.counties_region c
				WHERE	intersects_solar_land
				AND		ST_Intersects(d.centroid_geom, c.the_geom)
				AND		gridcode NOT IN
					(SELECT gridcode	
					FROM 	solar_central_station_polygons p,
							solar_nrel_avg_dni d
					WHERE 	ST_Intersects(d.centroid_geom, p.the_geom)
					AND		intersects_solar_land)
				GROUP BY cnty_fips
			) as union_geom_table;

-- get the avg, max, and min_dni, and the standard_deviation for the new polygons just inserted
-- gives nulls for standard_deviation for polygons with only one point
UPDATE 	solar_central_station_polygons p
SET 	avg_dni = avg_table.avg_dni,
		max_dni = avg_table.max_dni,
		min_dni = avg_table.min_dni,
		standard_deviation = avg_table.standard_deviation
FROM	(SELECT solar_farm_id,
				AVG(ann_dni) as avg_dni,
				MAX(ann_dni) as max_dni,
				MIN(ann_dni) as min_dni,
				stddev_samp(ann_dni) as standard_deviation
			FROM	solar_central_station_polygons p,
					solar_nrel_avg_dni n
			WHERE	ST_Intersects(centroid_geom, p.the_geom)
			AND		intersects_solar_land
			AND		avg_dni IS NULL
			GROUP BY solar_farm_id ) as avg_table
WHERE	avg_table.solar_farm_id = p.solar_farm_id;

-- update number_of_polygons_left
SELECT count(*) FROM solar_central_station_polygons WHERE standard_deviation > allowed_std_dev INTO number_of_polygons_left;
RAISE NOTICE 'number_of_polygons_left is %',number_of_polygons_left;

-- now break up polygons with too large of standard deviation as picked by the input allowed_std_dev
-- the inner most select creates a series of steps of capacity factor on which
-- the farm with standard_deviation > allowed_std_dev will be broken up
-- the size of the step is dependent on the allowed_std_dev
-- and the number of steps on the spread of cap factors ( max_dni - min_dni )
-- inidividual grid cells are grouped using the average DNI (ann_dni)
-- the final broken up polygons are then inserted into the main table solar_central_station_polygons after the parent polygon is deleted
DROP TABLE IF EXISTS polygons_to_insert;
CREATE TEMPORARY TABLE polygons_to_insert AS
	SELECT 	solar_farm_id,
			cnty_fips,
			ST_Multi((ST_Dump(union_geom)).geom) as the_geom
	FROM (	SELECT 	solar_farm_id,
					cnty_fips,
					step_num,
					ST_Union(n.the_geom) as union_geom
			FROM	solar_nrel_avg_dni n,
					solar_central_station_polygons p
			JOIN	(SELECT solar_farm_id,
							generate_series(0,CEILING(( max_dni - min_dni ) / allowed_std_dev)::int) as step_num
						FROM solar_central_station_polygons
						WHERE standard_deviation > allowed_std_dev
					) as number_of_steps_table
			USING 	(solar_farm_id)
			WHERE 	ST_Intersects(centroid_geom, p.the_geom)
			AND		intersects_solar_land
			AND		ann_dni >= min_dni + allowed_std_dev * step_num
			AND 	ann_dni < min_dni + allowed_std_dev * ( step_num + 1 )
			GROUP BY solar_farm_id, cnty_fips, step_num ) as union_geom_table;
	
DELETE FROM solar_central_station_polygons WHERE solar_farm_id in (SELECT distinct solar_farm_id from polygons_to_insert);

INSERT INTO solar_central_station_polygons (cnty_fips, the_geom)
	SELECT cnty_fips, the_geom FROM polygons_to_insert;

END LOOP;

-- here we're finished making the polygon geometries... only one step left
-- now reset the serial id column so the ids are continuous
DROP TABLE IF EXISTS change_solar_farm_ids_table;
CREATE TEMPORARY TABLE change_solar_farm_ids_table
	AS SELECT cnty_fips, avg_dni, max_dni, min_dni, standard_deviation, the_geom FROM solar_central_station_polygons;
DELETE FROM solar_central_station_polygons;

ALTER SEQUENCE solar_central_station_polygons_solar_farm_id_seq RESTART WITH 1;
INSERT INTO solar_central_station_polygons (cnty_fips, avg_dni, max_dni, min_dni, standard_deviation, the_geom)
	SELECT cnty_fips, avg_dni, max_dni, min_dni, standard_deviation, the_geom
	FROM change_solar_farm_ids_table ORDER BY avg_dni;

END; $$ LANGUAGE 'plpgsql';

-- setting the allowed_std_dev to 0.12 dni in combination with disaggregation by county made farms of reasonable size and diversity
SELECT solar_farms(0.12);
DROP FUNCTION solar_farms(double precision);
	
-- cut out the acceptable solar land from the nrel polygons
-- don't include any chunk of land less than 1km^2... while these might be good sites for solar, they're too small for us to look at
UPDATE 	solar_central_station_polygons
SET		the_geom = union_geom,
		updated_with_available_land_geom = TRUE
FROM	
( SELECT	solar_farm_id,
			ST_Multi(ST_Union(intersection_geom)) as union_geom
	FROM (	SELECT 	solar_farm_id,
					ST_CollectionExtract(ST_Intersection(s.the_geom, p.the_geom), 3) as intersection_geom
			FROM	solar_central_station_polygons p,
					solar_central_station_polygons_rid_state s
			WHERE	ST_Intersects(p.the_geom, s.the_geom)
		) as intersection_table
	WHERE	ST_Area(intersection_geom::geography, TRUE)/1000000.0 >= 1
	GROUP BY solar_farm_id
) as union_table
WHERE	union_table.solar_farm_id = solar_central_station_polygons.solar_farm_id;

-- the above didn't delete rows that consist of land less than 1km^2
DELETE FROM solar_central_station_polygons WHERE updated_with_available_land_geom IS FALSE;
ALTER TABLE solar_central_station_polygons DROP COLUMN updated_with_available_land_geom;

-- add in the map between solar_farm_id and nrel_gridcode by picking the gridcode
-- with the closest DNI to the average of the farm
-- don't include any points on timezone borders because their hourly solar data is presently incorrect
UPDATE 	solar_central_station_polygons
SET		nrel_gridcode = gridcode
FROM	
(	SELECT DISTINCT ON(solar_farm_id) solar_farm_id, n.gridcode
  	  FROM 	solar_central_station_polygons s,
			solar_nrel_avg_dni n
	  WHERE	ST_Intersects(n.the_geom, s.the_geom)
	  AND NOT 	ST_Touches(n.the_geom, s.the_geom)
	  AND NOT timezone_line_of_doom
	  AND n.gridcode NOT IN (114453645, 114653675, 114753675)
      ORDER BY solar_farm_id, ABS(avg_dni - ann_dni)
) as map_table
WHERE	map_table.solar_farm_id = solar_central_station_polygons.solar_farm_id;

-- due to the timezone_line_of_doom exclusion, a few farms didn't directly intersect an acceptable nrel_gridcode tile
-- we'll therefore find the closest one not on the timezone line of doom
UPDATE 	solar_central_station_polygons
SET		nrel_gridcode = gridcode
FROM	
(	SELECT DISTINCT ON(solar_farm_id) solar_farm_id, n.gridcode
  	  FROM 	solar_central_station_polygons s,
			solar_nrel_avg_dni n
	  WHERE	s.nrel_gridcode IS NULL
	  AND	ST_DWithin(s.the_geom, n.the_geom, 1)
	  AND NOT timezone_line_of_doom
	  AND n.gridcode NOT IN (114453645, 114653675, 114753675)
      ORDER BY solar_farm_id, ST_Distance(s.the_geom::geography,n.the_geom::geography)
) as map_table
WHERE	map_table.solar_farm_id = solar_central_station_polygons.solar_farm_id;


-- CAN MEX
-- we don't have insolation data for the correct years for canada and mexico
-- so we'll have to use the USA data... this isn't too bad of an approximation
-- because most of canada's sun is at the US border and Baja Mexico is very close to CA
INSERT INTO solar_central_station_polygons (nrel_gridcode, the_geom)
SELECT gridcode, the_geom
FROM (
	SELECT	gridcode,
			state,
			ST_Union(the_geom) as the_geom
	FROM	solar_central_station_polygons_rid_state
	JOIN	
		(	SELECT 	DISTINCT ON (rid, state)
					rid,
					state,
					n.gridcode
	  		  FROM 	solar_nrel_avg_dni n,
  			  		solar_central_station_polygons_rid_state s
  			  JOIN	ventyx_may_2012.states_region ON (state = abbrev)
  			  WHERE ST_DWithin(s.the_geom, n.the_geom, 1)
  			  AND NOT timezone_line_of_doom
  			  AND n.gridcode NOT IN (114453645, 114653675, 114753675)
			  AND	( country = 'Canada' OR (country = 'Mexico' and abbrev = 'BCN') )
   		   ORDER BY rid, state, ST_Distance(s.the_geom::geography,n.the_geom::geography)
		) as tiles_near_border_table
	USING (rid, state)
	GROUP BY gridcode, state
	) as union_table;

SELECT AddGeometryColumn ('usa_can','solar_central_station_polygons','centroid_geom',4326,'POINT',2);
CREATE INDEX ON solar_central_station_polygons USING gist (centroid_geom);
			
UPDATE solar_central_station_polygons SET centroid_geom = ST_Centroid(the_geom);
UPDATE solar_central_station_polygons SET area_km_2 = ST_Area(the_geom::geography, TRUE)/1000000;
DELETE FROM solar_central_station_polygons WHERE area_km_2 < 1;






-- now that we have all the possible nrel gridcodes that we would like to simulate for central station solar
-- we can print them out to a jobs file and get SAM started on the simulations
COPY (SELECT 	'/Volumes/switch/Models/USA_CAN/Solar/Hourly_Weather_Inputs/2006/'
				|| CASE WHEN LENGTH(nrel_gridcode) = 8 THEN '0' || nrel_gridcode ELSE nrel_gridcode END
				|| '_2006.tm2.gz'
		FROM (SELECT  	DISTINCT
						nrel_gridcode::text as nrel_gridcode,
						nrel_gridcode as order_clause
				FROM solar_central_station_polygons) g
		ORDER BY order_clause DESC)
TO '/Volumes/switch/Models/USA_CAN/Solar/Jobs/Central_PV.txt';




-- DISTRIBUTED PV SITES--------------------------
DROP TABLE IF EXISTS solar_distributed_sites;
CREATE TABLE solar_distributed_sites(
	id serial primary key,
	area_id smallint references load_areas_usa_can,
	area_km_2 double precision CHECK (area_km_2 > 0),
	population int );

SELECT addgeometrycolumn ('usa_can','solar_distributed_sites','the_geom',4326,'POLYGON',2);
CREATE INDEX ON solar_distributed_sites USING gist (the_geom);

-- the population tiles can span load area borders and we don't want to double count tiles
-- so assign each tile to a single load area
DROP TABLE IF EXISTS intersection_area_table;
CREATE TABLE intersection_area_table (
	tile_id int,
	area_id smallint,
	intersection_area double precision,
	PRIMARY KEY (tile_id, area_id));
	
INSERT INTO intersection_area_table (tile_id, area_id, intersection_area)
	 SELECT tile_id,
			area_id,
			ST_Area(ST_Intersection(polygon_geom, the_geom)::geography, TRUE) as intersection_area
		FROM 	population_vector_table,
				load_areas_usa_can			
		WHERE	total_population > 1000
		AND 	ST_Intersects(polygon_geom, the_geom);
		
		
INSERT INTO solar_distributed_sites (area_id, the_geom)
	SELECT 	area_id, 
			(ST_Dump(the_geom)).geom as the_geom
	FROM
		(SELECT  	area_id,
					ST_Union(ST_Expand(the_geom, 0.0001)) as the_geom
			FROM	(SELECT tile_id, MAX(intersection_area) as intersection_area
						FROM intersection_area_table
						GROUP BY tile_id) AS max_intersection_area_table
			JOIN 	intersection_area_table USING (tile_id, intersection_area)
			JOIN	population_vector_table USING (tile_id)
			GROUP BY area_id
		) as union_table;


UPDATE solar_distributed_sites
SET population = total_pop
FROM (SELECT id, sum(total_population) as total_pop
		FROM solar_distributed_sites s,
			 population_vector_table p
		WHERE ST_Intersects(s.the_geom, ST_Centroid(p.the_geom))
		GROUP BY id) pop_sum_table
WHERE solar_distributed_sites.id = pop_sum_table.id;

-- we'll remove smaller towns (<10000 people) from the set of distributed PV projects to reduce the number of decision variables
DELETE FROM solar_distributed_sites WHERE population < 10000;

DROP TABLE IF EXISTS intersection_area_table;

UPDATE solar_distributed_sites SET area_km_2 = ST_Area(the_geom::geography, TRUE)/1000000;

-- intersect with the suny grid cells to find out which cells to simulate from our downloaded weather data

DROP TABLE IF EXISTS solar_distributed_polygon_grid_cell_map;
CREATE TABLE solar_distributed_polygon_grid_cell_map(
	polygon_id int references solar_distributed_sites (id),
	nrel_gridcode int references solar_nrel_avg_latitudetilt (gridcode),
	timezone_diff_from_utc smallint CHECK (timezone_diff_from_utc BETWEEN -23 AND 23),
	mw_per_km_2 NUMERIC(6,2) CHECK (mw_per_km_2 > 0),
	fraction_of_nrel_gridcode_in_polygon_id double precision CHECK (fraction_of_nrel_gridcode_in_polygon_id BETWEEN 0 AND 1),
	PRIMARY KEY (nrel_gridcode, polygon_id) );

-- the sum here is over population tiles from population_vector_table
-- the seemingly redundant intersections with geometry and geometry centroid are for speed... the one we care about is the centroid
-- because we're trying to locate population points WITHIN nrel and solar_distributed_sites polygons
-- but ST_Intersects will go quickly if it has bounding boxes to work with, hence the non-centroid intersections
-- as was the case with the central station polygons, we'll exclude nrel tiles along timezone borders due hourly insolation errors in the weather files
INSERT INTO solar_distributed_polygon_grid_cell_map (polygon_id, nrel_gridcode, fraction_of_nrel_gridcode_in_polygon_id)
SELECT 	s.id as polygon_id,
		n.gridcode as nrel_gridcode,
		ROUND(sum(total_population))/(population::numeric) as pop_fraction
	FROM solar_distributed_sites s,
		 population_vector_table p,
		 solar_nrel_avg_latitudetilt n
	WHERE 	ST_Intersects(s.the_geom, p.the_geom)
	AND		ST_Intersects(s.the_geom, ST_Centroid(p.the_geom))
	AND		ST_Intersects(n.the_geom, p.the_geom)
	AND		ST_Intersects(n.the_geom, ST_Centroid(p.the_geom) )
	AND NOT timezone_line_of_doom
	AND n.gridcode NOT IN (114453645, 114653675, 114753675)
	GROUP BY s.id, n.gridcode;

-- the nrel grid cells are for the USA only but we need canadian and mexican solar
-- luckily the part of baja mexico we simulate is very close to the us border
-- and almost all of canada lives along the us border, so we'll simply use the closest nrel grid cell to the border
-- to represent the power output of canadian and mexican solar... add these mappings here
-- the ST_DWithin(, 10) here limits the search distance to 10 lat/lon degrees (a long way!) to speed up the query
-- this should also grab distributed sites that are on a timezone boundary
INSERT INTO solar_distributed_polygon_grid_cell_map (polygon_id, nrel_gridcode, fraction_of_nrel_gridcode_in_polygon_id)
	SELECT DISTINCT ON(s.id)  s.id, n.gridcode, 1
  	  FROM 	solar_distributed_sites s,
			solar_nrel_avg_latitudetilt n   
	  WHERE s.id NOT IN (SELECT DISTINCT polygon_id FROM solar_distributed_polygon_grid_cell_map)
	  AND	ST_DWithin(s.the_geom, n.the_geom, 10)
	  AND NOT timezone_line_of_doom
	  AND n.gridcode NOT IN (114453645, 114653675, 114753675)
      ORDER BY s.id, ST_Distance(s.the_geom::geography,n.the_geom::geography);

-- a few distributed polygons overlap with the nrel grid a bit but not fully
-- thereby giving sum(fraction_of_nrel_gridcode_in_polygon_id) < 1 for these polygons
-- correct here...
UPDATE 	solar_distributed_polygon_grid_cell_map m
SET 	fraction_of_nrel_gridcode_in_polygon_id = fraction_of_nrel_gridcode_in_polygon_id / normalization_factor
FROM	(SELECT polygon_id, sum(fraction_of_nrel_gridcode_in_polygon_id) as normalization_factor
			FROM solar_distributed_polygon_grid_cell_map
			GROUP BY polygon_id ) as norm_table
WHERE	m.polygon_id = norm_table.polygon_id;




-- export grid cells to a jobs text file that lists all the grid cells to be simulated by the System Advisor Model (SAM)
-- the names of the jobs files have to match the names of SAM cases.
COPY (SELECT 	'/Volumes/switch/Models/USA_CAN/Solar/Hourly_Weather_Inputs/2006/'
				|| CASE WHEN LENGTH(nrel_gridcode) = 8 THEN '0' || nrel_gridcode ELSE nrel_gridcode END
				|| '_2006.tm2.gz'
		FROM (SELECT DISTINCT nrel_gridcode::text as nrel_gridcode, nrel_gridcode as order_clause FROM solar_distributed_polygon_grid_cell_map) g
		ORDER BY order_clause DESC)
TO '/Volumes/switch/Models/USA_CAN/Solar/Jobs/Residential_PV.txt';

COPY (SELECT 	'/Volumes/switch/Models/USA_CAN/Solar/Hourly_Weather_Inputs/2006/'
				|| CASE WHEN LENGTH(nrel_gridcode) = 8 THEN '0' || nrel_gridcode ELSE nrel_gridcode END
				|| '_2006.tm2.gz'
		FROM (SELECT DISTINCT nrel_gridcode::text as nrel_gridcode, nrel_gridcode as order_clause FROM solar_distributed_polygon_grid_cell_map) g
		ORDER BY order_clause DESC)
TO '/Volumes/switch/Models/USA_CAN/Solar/Jobs/Commercial_PV.txt';



-- CALCULATE ROOF AREA FOR DISTRIBUTED---------------



-- the population tiles can span state borders and we don't want to double count tiles
-- so assign each tile to a single state
DROP TABLE IF EXISTS intersection_area_table;
CREATE TABLE intersection_area_table (
	tile_id int,
	state varchar(3),
	intersection_area double precision,
	PRIMARY KEY (tile_id, state));
	
INSERT INTO intersection_area_table (tile_id, state, intersection_area)
	 SELECT tile_id,
			abbrev as state,
			ST_Area(ST_Intersection(p.the_geom,s.the_geom)::geography, TRUE) as intersection_area
		FROM 	population_vector_table p,
				ventyx_may_2012.states_region s		
		WHERE	ST_Intersects(p.the_geom,s.the_geom);

-- first make a table of the roof area per person by state for the lower 48 US states
-- the 92903.04 converts from milion square feet to m^2
drop table if exists solar_pv_roof_area_per_person_by_state;
create table solar_pv_roof_area_per_person_by_state(
	state varchar(3) PRIMARY KEY,
	state_population double precision,
	residential_roof_area_km_2 double precision,
	small_commercial_roof_area_km_2 double precision,
	large_commercial_roof_area_km_2 double precision,
	residential_roof_area_km_2_per_person double precision,
	commercial_roof_area_km_2_per_person double precision
);
		
INSERT INTO solar_pv_roof_area_per_person_by_state (state, state_population)
	SELECT 	state,
			sum(total_population) as state_population
	FROM	population_vector_table
	JOIN	(SELECT DISTINCT ON (tile_id) tile_id, state 
				FROM intersection_area_table
				ORDER BY tile_id, intersection_area DESC ) as tile_state_table
	USING	(tile_id)
	GROUP BY state;
		
DROP TABLE IF EXISTS intersection_area_table;


-- State level roof area data comes from a 2004 Navigant Consulting report found at
-- http://www.ef.org/documents/EF-Final-Final2.pdf
-- the 2025 roof area was used as solar is likley to be installed in Switch more in later years.
-- this roof area data already takes into account the shading and roof availablity numbers,
-- 65% for commercial and 22% for residential.  The residential number includes 8% of flat roofed buildings
-- but these could have mounting hardware for the PV panels, so this doesn't really create problems

-- the Navigant data was saved as a csv and is imported here.
-- roof areas are in Million Square Feet, so to convert to square meters,
-- multiply Mft^2 by 0.092903 to get km^2
drop table if exists solar_pv_roof_area_by_state;
create temporary table solar_pv_roof_area_by_state(
	state_name varchar(30) PRIMARY KEY,
	state_abbreviation varchar(3),
	residential_roof_area double precision,
	small_commercial_roof_area double precision,
	large_commercial_roof_area double precision
);

COPY solar_pv_roof_area_by_state
FROM '/Volumes/switch/Models/USA_Can/Solar/Solar Roof Area.csv'
WITH 	CSV HEADER;
		
-- to estimate the available roof area from the total roof area, this NREL document is used
-- "Supply Curves for Rooftop Solar PV-Generated Electricity for the United States"
-- by Paul Denholm and Robert Margolis, 2008
-- http://www.nrel.gov/docs/fy09osti/44073.pdf
-- it is assumed that 20% of residential roof area is available for PV deployment
-- as NREL estimates 22-27% for all orientations, so for our single, south facing systems, this is likely reduced a bit more.
-- for commercial systems, we use their low end 60% estimate of roof space.
UPDATE 	solar_pv_roof_area_per_person_by_state
SET		residential_roof_area_km_2 = res,
		small_commercial_roof_area_km_2 = small_com,
		large_commercial_roof_area_km_2 = large_com,
		residential_roof_area_km_2_per_person = res / state_population,
		commercial_roof_area_km_2_per_person = ( small_com + large_com ) / state_population
FROM	(SELECT state_abbreviation,
				sum(residential_roof_area) * 0.092903 as res,
				sum(small_commercial_roof_area) * 0.092903 as small_com,
				sum(large_commercial_roof_area) * 0.092903 as large_com
			FROM solar_pv_roof_area_by_state
			GROUP BY state_abbreviation
			) as roof_area_state
WHERE	roof_area_state.state_abbreviation = solar_pv_roof_area_per_person_by_state.state;

-- the above didn't get canada or mexico distributed PV... add here
-- ratio of Mexico to US GDP (0.26) will be used as a proxy for rooftop space
-- whereas we'll assume that Canadian rooftop space is similar per person to the US average
UPDATE 	solar_pv_roof_area_per_person_by_state
SET		residential_roof_area_km_2 = res * state_population,
		small_commercial_roof_area_km_2 = small_com * state_population,
		large_commercial_roof_area_km_2 = large_com * state_population,
		residential_roof_area_km_2_per_person = res,
		commercial_roof_area_km_2_per_person = small_com + large_com
FROM	(SELECT SUM(residential_roof_area_km_2) / SUM(state_population) as res,
				SUM(small_commercial_roof_area_km_2) / SUM(state_population) as small_com,
				SUM(large_commercial_roof_area_km_2) / SUM(state_population) as large_com
			FROM	solar_pv_roof_area_per_person_by_state
			JOIN	ventyx_may_2012.states_region ON (abbrev = state)
			WHERE	country = 'United States of America'
			AND		state NOT IN ('AK', 'HI')
		) as roof_area,
		ventyx_may_2012.states_region s	
WHERE	s.abbrev = solar_pv_roof_area_per_person_by_state.state
AND		country != 'United States of America';

UPDATE solar_pv_roof_area_per_person_by_state
SET		residential_roof_area_km_2 = residential_roof_area_km_2 * 0.26,
		small_commercial_roof_area_km_2 = small_commercial_roof_area_km_2 * 0.26,
		large_commercial_roof_area_km_2 = large_commercial_roof_area_km_2 * 0.26,
		residential_roof_area_km_2_per_person = residential_roof_area_km_2_per_person * 0.26,
		commercial_roof_area_km_2_per_person = commercial_roof_area_km_2_per_person * 0.26
WHERE	state = 'BCN';

-- delete states that aren't in SWITCH
DELETE 	FROM solar_pv_roof_area_per_person_by_state
USING	ventyx_may_2012.states_region s	
WHERE	s.abbrev = solar_pv_roof_area_per_person_by_state.state
AND		country = 'Mexico'
AND		abbrev != 'BCN';

DELETE 	FROM solar_pv_roof_area_per_person_by_state
WHERE 	state in ('HI', 'AK', 'YT', 'NL', 'NU', 'NT')

-- CREATE SOLAR SITES TABLE------------------
DROP TABLE IF EXISTS solar_sites;
CREATE TABLE solar_sites (
	project_id SERIAL PRIMARY KEY CHECK (project_id >= 1000000),
	technology varchar(64) REFERENCES technology_to_id_map (technology),
	technology_id smallint REFERENCES technology_to_id_map (technology_id),
	distributed_site_id int REFERENCES solar_distributed_sites (id),
	central_station_farm_id int REFERENCES solar_central_station_polygons (solar_farm_id),
	area_km_2 NUMERIC(7,2) CHECK (area_km_2 > 0),
	mw_per_km_2 NUMERIC(6,2) CHECK (mw_per_km_2 > 0),
	capacity_mw NUMERIC(7,2) CHECK (capacity_mw > 0),
	capacity_factor double precision CHECK (capacity_factor BETWEEN 0 AND 1),
	hourly_timeseries_imported BOOLEAN DEFAULT FALSE,
	UNIQUE (technology_id, distributed_site_id),
	UNIQUE (technology_id, central_station_farm_id));

ALTER SEQUENCE solar_sites_project_id_seq RESTART WITH 1000000;
CREATE INDEX ON solar_sites (capacity_factor);

SELECT addgeometrycolumn ('usa_can','solar_sites','the_geom',4326,'MULTIPOLYGON',2);
CREATE INDEX ON solar_sites USING gist (the_geom);
CREATE INDEX ON solar_sites (distributed_site_id);
CREATE INDEX ON solar_sites (central_station_farm_id);
CREATE INDEX ON solar_sites (hourly_timeseries_imported);
CREATE INDEX ON solar_sites (project_id, hourly_timeseries_imported);

-- Distributed
INSERT INTO solar_sites (technology, technology_id, distributed_site_id, area_km_2, the_geom)
	SELECT 	technology,
			technology_id,
			id as distributed_site_id,
			CASE WHEN technology = 'Residential_PV' THEN residential_roof_area_km_2_per_person
				 WHEN technology = 'Commercial_PV' THEN commercial_roof_area_km_2_per_person END
				 * population as area_km_2,
			ST_Multi(s.the_geom)
	FROM 	(SELECT technology, technology_id from technology_to_id_map
		 		WHERE technology in ('Residential_PV', 'Commercial_PV')) as tech_table,
		 	solar_distributed_sites s,
			solar_pv_roof_area_per_person_by_state
	JOIN	ventyx_may_2012.states_region v
	ON		(abbrev = state)
	WHERE	ST_Intersects(ST_Centroid(s.the_geom), v.the_geom);

-- a few didn't intersect on centroid, so here is the non-centroid version
INSERT INTO solar_sites (technology, technology_id, distributed_site_id, area_km_2, the_geom)
	SELECT 	technology,
			technology_id,
			id as distributed_site_id,
			CASE WHEN technology = 'Residential_PV' THEN residential_roof_area_km_2_per_person
				 WHEN technology = 'Commercial_PV' THEN commercial_roof_area_km_2_per_person END
				 * population as area_km_2,
			ST_Multi(s.the_geom)
	FROM 	(SELECT technology, technology_id from technology_to_id_map
		 		WHERE technology in ('Residential_PV', 'Commercial_PV')) as tech_table,
		 	solar_distributed_sites s,
			solar_pv_roof_area_per_person_by_state
	JOIN	ventyx_may_2012.states_region v
	ON		(abbrev = state)
	WHERE	ST_Intersects(s.the_geom, v.the_geom)
	AND 	id not in (select distinct distributed_site_id from solar_sites);

-- Central Station
ALTER SEQUENCE solar_sites_project_id_seq RESTART WITH 1100000;

INSERT INTO solar_sites (technology, technology_id, central_station_farm_id, area_km_2, the_geom)
	SELECT 	technology,
			technology_id,
			solar_farm_id as central_station_farm_id,
			area_km_2,
			ST_Multi(the_geom)
	FROM 	(SELECT technology, technology_id from technology_to_id_map
		 		WHERE technology in ('Central_PV', 'CSP_Trough_No_Storage', 'CSP_Trough_6h_Storage')) as tech_table,
		 	solar_central_station_polygons;



-- NOW CALCULATE HOURLY CAP FACTORS WITH SAM AND RUN THE IMPORT SCRIPT!!!!



-- to make fast joins, we make a map table between weather.timepoints and the imported hourly solar capacity factors
	-- here we take the weighted average of power production for a solar farm for a given hour
	-- the capacity factor value represents the integrated average capacity factor for the hour previous to the timestamp

-- each hourly simulation was performed in local time (without DST) - this timezone is recorded and used to translate back to UTC below
-- the solar output starts at hour 1 of a given year, whereas the weather.timepoints table labels the hour of new years as hour 0 of the new year
-- this means that year_sam won't equal year weather.timepoints for the midnight between Dec 31/Jan 1
DROP TABLE IF EXISTS solar_timepoint_map;
CREATE TABLE solar_timepoint_map (
	year smallint,
	hour_of_year_sam smallint,
	timezone_diff_from_utc smallint,
	timepoint_id int REFERENCES weather.timepoints,
	PRIMARY KEY (year, hour_of_year_sam, timezone_diff_from_utc) );

CREATE INDEX ON solar_timepoint_map (year);
CREATE INDEX ON solar_timepoint_map (hour_of_year_sam);
CREATE INDEX ON solar_timepoint_map (timezone_diff_from_utc);


-- timezones go from -4 to -8 UTC, so those are the only ones we're interested in.	
INSERT INTO solar_timepoint_map (year, hour_of_year_sam, timezone_diff_from_utc, timepoint_id)
	SELECT  year,
			generate_series(0, num_hours_per_year-1) + 1 as hour_of_year_sam,
			timezone_diff_from_utc,
			first_hour_sam_timepoint_id + generate_series(0, num_hours_per_year-1) as timepoint_id
	FROM	
			(SELECT num_hours_per_year_table.year,
					timezone_diff_from_utc,
					num_hours_per_year,
					MIN(timepoint_id) as first_hour_sam_timepoint_id
			FROM 	(SELECT generate_series(-8, -4) as timezone_diff_from_utc) as all_possible_timezones_table,
					(SELECT year, count(*) as num_hours_per_year from weather.timepoints WHERE YEAR <= 2014 GROUP BY year) as num_hours_per_year_table,
					weather.timepoints
			WHERE	EXTRACT( YEAR FROM timepoint - interval '1 HOUR' + interval '1 HOUR' * timezone_diff_from_utc) = num_hours_per_year_table.year
			GROUP BY num_hours_per_year_table.year, timezone_diff_from_utc, num_hours_per_year
			) as utc_first_hour_table;
	

-- create the table in which the final hourly cap factors are going to reside
-- extra indicies and constraints are added at the bottom in order to speed up import
CREATE TABLE IF NOT EXISTS solar_hourly_timeseries(
	project_id int,
	timepoint_id int,
	capacity_factor double precision,
	PRIMARY KEY (project_id, timepoint_id));
	


	
-- now copy the hourly data into postgresql
-- there are two slightly different functions - one for central station and one from distributed
-- CENTRAL STATION------------------------
CREATE OR REPLACE FUNCTION import_solar_central_station_timeseries(current_project_id integer, technology character varying, year_var integer)
  RETURNS void AS $$
DECLARE gridcode int;
DECLARE gridcode_text CHAR(9);
DECLARE import_path varchar(256);
BEGIN 

SELECT nrel_gridcode
	FROM solar_sites
	JOIN solar_central_station_polygons ON (central_station_farm_id = solar_farm_id)
	WHERE project_id = current_project_id
		INTO gridcode;

SELECT CASE WHEN length(gridcode::text) = 8 THEN '0' || gridcode::text ELSE gridcode::text END INTO gridcode_text;

  RAISE NOTICE 'Current import is: technology %, gridcode_text %, year_var %',technology, gridcode_text, year_var;

-- first, we need to update the timezone_diff_from_utc field of solar_central_station_polygons,
-- as we get this from the weather data (in case there are any difficulties assigning timezones along the timezone line)
DROP TABLE IF EXISTS tz_table;
CREATE TEMPORARY TABLE tz_table (tz smallint);

  SELECT '/Volumes/switch/Models/USA_CAN/Solar/Timezone_Grid/'
	|| gridcode_text
	|| '.csv'
	INTO import_path;

  EXECUTE 'COPY tz_table FROM ' || quote_literal(import_path) || ' WITH CSV';

UPDATE solar_central_station_polygons SET timezone_diff_from_utc = tz FROM tz_table WHERE nrel_gridcode = gridcode;

-- second, we need to update the mw_per_km_2 field of solar_sites, as we get this from calcluations within SAM 
DROP TABLE IF EXISTS mw_per_km_2_table;
CREATE TEMPORARY TABLE mw_per_km_2_table (mw_km_2 double precision);

  SELECT '/Volumes/switch/Models/USA_CAN/Solar/Land_Area/'
	|| technology
	|| '/'
	|| gridcode_text
	|| '.csv'
	INTO import_path;

  EXECUTE 'COPY mw_per_km_2_table FROM ' || quote_literal(import_path) || ' WITH CSV';

UPDATE solar_sites SET mw_per_km_2 = mw_km_2 FROM mw_per_km_2_table WHERE project_id = current_project_id;


-- now make a temporary import table and insert into the final solar_hourly_timeseries table
DROP TABLE IF EXISTS solar_hourly_timeseries_import;
CREATE TEMPORARY TABLE solar_hourly_timeseries_import (hour_of_year_sam SERIAL PRIMARY KEY, capacity_factor double precision);

  SELECT '/Volumes/switch/Models/USA_CAN/Solar/Hourly_Outputs/'
	|| technology
	|| '/'
	|| gridcode_text
	|| '_'
	|| year_var
	|| '.csv'
  INTO import_path;

  EXECUTE 'COPY solar_hourly_timeseries_import (capacity_factor) FROM ' || quote_literal(import_path) || ' WITH CSV';

	-- insert into the final table
INSERT INTO solar_hourly_timeseries (project_id, timepoint_id, capacity_factor)
	SELECT project_id, timepoint_id, solar_hourly_timeseries_import.capacity_factor
		FROM solar_sites
		JOIN solar_central_station_polygons ON (central_station_farm_id = solar_farm_id)
		JOIN solar_timepoint_map USING (timezone_diff_from_utc)
		JOIN solar_hourly_timeseries_import USING (hour_of_year_sam)
		WHERE project_id = current_project_id
		AND	  year = year_var;

-- mark the project we're importing as finished
UPDATE solar_sites SET hourly_timeseries_imported = TRUE WHERE project_id = current_project_id;

END; $$ LANGUAGE 'plpgsql';

DROP FUNCTION import_solar_central_station_timeseries(int, varchar(64), int);





-- DISTRIBUTED------------------------
CREATE OR REPLACE FUNCTION import_solar_distributed_timeseries(current_project_id int, technology varchar(64), year_var int) RETURNS void AS $$ 
DECLARE current_distributed_site_id int;
DECLARE gridcode int;
DECLARE gridcode_text CHAR(9);
DECLARE import_path varchar(256);
BEGIN 

SELECT distributed_site_id FROM solar_sites WHERE project_id = current_project_id INTO current_distributed_site_id;

DROP TABLE IF EXISTS solar_hourly_timeseries_distributed_tmp;
CREATE TEMPORARY TABLE solar_hourly_timeseries_distributed_tmp(
	nrel_gridcode int,
	timepoint_id int,
	weighted_capacity_factor double precision,
	PRIMARY KEY (nrel_gridcode, timepoint_id));

CREATE INDEX ON solar_hourly_timeseries_distributed_tmp (nrel_gridcode);

DROP TABLE IF EXISTS mw_per_km_2_table;
CREATE TEMPORARY TABLE mw_per_km_2_table (nrel_gridcode int UNIQUE, mw_per_km_2 double precision);

WHILE ((SELECT COUNT(*)
			FROM solar_distributed_polygon_grid_cell_map
			WHERE polygon_id = current_distributed_site_id
			AND nrel_gridcode NOT IN (SELECT DISTINCT nrel_gridcode FROM solar_hourly_timeseries_distributed_tmp)
		) > 0) LOOP
		
-- there are multiple nrel_gridcodes per distributed site,
-- so we have to load them all before adding hourly data into solar_hourly_timeseries
SELECT nrel_gridcode
	FROM solar_distributed_polygon_grid_cell_map
	WHERE polygon_id = current_distributed_site_id
	AND nrel_gridcode NOT IN (SELECT DISTINCT nrel_gridcode FROM solar_hourly_timeseries_distributed_tmp)
	LIMIT 1
		INTO gridcode;

SELECT CASE WHEN length(gridcode::text) = 8 THEN '0' || gridcode::text ELSE gridcode::text END INTO gridcode_text;

  RAISE NOTICE 'Current import is: project_id %, technology %, gridcode_text %, year_var %',current_project_id, technology, gridcode_text, year_var;

-- first, we need to update the timezone_diff_from_utc field of solar_distributed_polygon_grid_cell_map,
-- as we get this from the weather data (in case there are any difficulties assigning timezones along the timezone line)
DROP TABLE IF EXISTS tz_table;
CREATE TEMPORARY TABLE tz_table (tz smallint);

  SELECT '/Volumes/switch/Models/USA_CAN/Solar/Timezone_Grid/'
	|| gridcode_text
	|| '.csv'
	INTO import_path;

  EXECUTE 'COPY tz_table FROM ' || quote_literal(import_path) || ' WITH CSV';

UPDATE solar_distributed_polygon_grid_cell_map SET timezone_diff_from_utc = tz FROM tz_table WHERE nrel_gridcode = gridcode;

-- now load the mw_per_km_2 into the temporary table
  SELECT '/Volumes/switch/Models/USA_CAN/Solar/Land_Area/'
	|| technology
	|| '/'
	|| gridcode_text
	|| '.csv'
	INTO import_path;

  EXECUTE 'COPY mw_per_km_2_table (mw_per_km_2) FROM ' || quote_literal(import_path) || ' WITH CSV';

UPDATE mw_per_km_2_table SET nrel_gridcode = gridcode WHERE nrel_gridcode IS NULL;


-- now make a temporary import table and insert into the final solar_hourly_timeseries table
DROP TABLE IF EXISTS solar_hourly_timeseries_import;
CREATE TEMPORARY TABLE solar_hourly_timeseries_import (hour_of_year_sam SERIAL PRIMARY KEY, capacity_factor double precision);

  SELECT '/Volumes/switch/Models/USA_CAN/Solar/Hourly_Outputs/'
	|| technology
	|| '/'
	|| gridcode_text
	|| '_'
	|| year_var
	|| '.csv'
  INTO import_path;

  EXECUTE 'COPY solar_hourly_timeseries_import (capacity_factor) FROM ' || quote_literal(import_path) || ' WITH CSV';

	-- insert into the tmp table
INSERT INTO solar_hourly_timeseries_distributed_tmp (nrel_gridcode, timepoint_id, weighted_capacity_factor)
	SELECT nrel_gridcode, timepoint_id, solar_hourly_timeseries_import.capacity_factor * fraction_of_nrel_gridcode_in_polygon_id
		FROM solar_distributed_polygon_grid_cell_map
		JOIN solar_timepoint_map USING (timezone_diff_from_utc)
		JOIN solar_hourly_timeseries_import USING (hour_of_year_sam)
		WHERE 	nrel_gridcode = gridcode
		AND		polygon_id = current_distributed_site_id
		AND	  year = year_var;

END LOOP;


-- now that we're out of the loop, we have all the information we need to update the mw_per_km_2 field of solar_sites
UPDATE solar_sites
SET mw_per_km_2 = mw_km_2
FROM	(SELECT SUM(mw_per_km_2 * fraction_of_nrel_gridcode_in_polygon_id) as mw_km_2
			FROM mw_per_km_2_table
			JOIN solar_distributed_polygon_grid_cell_map USING (nrel_gridcode)
			WHERE polygon_id = current_distributed_site_id ) as sum_table
WHERE project_id = current_project_id;


-- insert into the FINAL hourly table
-- note - if grid cells cross timezone lines, this might be incomplete for the start and end hour,
-- but insolation should be zero during these times so it's not a big deal for PV... solar thermal with storage is the only possible problem
-- but we excluded timezone lines above for other reasons so we won't handle this complication now... also, solar thermal isn't distributed right now...
INSERT INTO solar_hourly_timeseries (project_id, timepoint_id, capacity_factor)
	SELECT current_project_id, timepoint_id, SUM(weighted_capacity_factor)
		FROM solar_hourly_timeseries_distributed_tmp
		GROUP BY current_project_id, timepoint_id;

-- mark the project we're importing as finished
UPDATE solar_sites SET hourly_timeseries_imported = TRUE WHERE project_id = current_project_id;

END; $$ LANGUAGE 'plpgsql';

-- actually excecute the import function
-- the limit here can do the import in chunks in case it needs interrupting
-- if this needs to be run for more than one year at a time, the function import_solar_timeseries_data could be called using a derived year table
-- for example SELECT generate_series(2004,2006) as year_var...
psql -U jimmy switch_gis -c "SELECT import_solar_distributed_timeseries(project_id, technology, 2006) FROM solar_sites WHERE distributed_site_id IS NOT NULL AND hourly_timeseries_imported IS FALSE LIMIT 1;"

DROP FUNCTION import_solar_distributed_timeseries(int, varchar(64), int);


-- sometimes solar thermal needs a bit of extra juice in an hour to keep it going,
-- so its cap factor can dip to around -0.5 because it's heating up the solar fluid
-- SAM apparently lets it dip even further, presumably in error.
UPDATE solar_hourly_timeseries SET capacity_factor = -0.5 WHERE capacity_factor < -0.5;
-- SAM also lets the turbine of CSP output at very high levels...
-- higher than its rated gross output of 1.1x net output... make the maximum the gross output here
UPDATE solar_hourly_timeseries SET capacity_factor = 1.1 WHERE capacity_factor > 1.1;
-- SAM calculates parasitic loads by PV inverters, but these are tiny... less than 0.1% of capacity in any hour
-- BUT if we include them, the complied linear program has a lot more non-zeros then necessary, so remove here...
UPDATE solar_hourly_timeseries SET capacity_factor = 0 WHERE capacity_factor BETWEEN -0.001 AND 0;

ALTER TABLE solar_hourly_timeseries ADD CONSTRAINT cf_ck CHECK (capacity_factor BETWEEN -0.5 AND 1.1);

-- create indicies and foreign keys at the end to speed up import
CREATE INDEX ON solar_hourly_timeseries (project_id);
CREATE INDEX ON solar_hourly_timeseries (timepoint_id);
ALTER TABLE solar_hourly_timeseries ADD CONSTRAINT site_fk FOREIGN KEY (project_id) REFERENCES solar_sites (project_id);
ALTER TABLE solar_hourly_timeseries ADD CONSTRAINT tp_fk FOREIGN KEY (timepoint_id) REFERENCES weather.timepoints (timepoint_id);

-- add the average capacity factor for each project
UPDATE solar_sites
SET capacity_factor = avg_cap_factor
FROM 	(SELECT project_id, avg(capacity_factor) as avg_cap_factor
			FROM solar_hourly_timeseries
			GROUP BY project_id) as avg_table
WHERE avg_table.project_id = solar_sites.project_id;



































-- APPENDIX:
-- FASTER UNION for rasters
-- from : http://geospatialelucubrations.blogspot.com/2012/07/a-slow-yet-1000x-faster-alternative-to.html


CREATE OR REPLACE FUNCTION ST_FirstRasterValue4ma(pixel FLOAT,
                                                  pos INTEGER[], 
                                                  VARIADIC args TEXT[])
RETURNS FLOAT
AS $$ 
   DECLARE
       pixelgeom text;
       result float4;
       query text;
   BEGIN
       -- Reconstruct the current pixel centroid
       pixelgeom = ST_AsText(
                    ST_Centroid(
                     ST_PixelAsPolygon(
                      ST_MakeEmptyRaster(args[1]::integer,
                                         args[2]::integer, 
                                         args[3]::float,
                                         args[4]::float, 
                                         args[5]::float, 
                                         args[6]::float,
                                         args[7]::float,
                                         args[8]::float, 
                                         args[9]::integer), 
                      pos[1]::integer, 
                      pos[2]::integer)));
        
       -- Intersects it with the raster coverage to find the right value
       query = 'SELECT ST_Value(' || quote_ident(args[12]) || 
               ', ST_GeomFromText(' || quote_literal(pixelgeom) || 
               ', ' || args[9] || 
               ')) FROM ' || quote_ident(args[10]) || 
               '.' || quote_ident(args[11]) || 
               ' WHERE ST_Intersects(ST_GeomFromText(' ||
               quote_literal(pixelgeom) || ', '|| args[9] || '), ' ||
               quote_ident(args[12]) || ') LIMIT 1';
        EXECUTE query INTO result;
        RETURN result;
    END; $$
    LANGUAGE 'plpgsql' IMMUTABLE;


CREATE OR REPLACE FUNCTION ST_FasterUnion(schemaname text, tablename text, rastercolumnname text)
RETURNS raster
AS $$ 
   DECLARE
       query text;
       newrast raster;
   BEGIN
        query = '
SELECT ST_MapAlgebraFct(rast,
                        ''ST_FirstRasterValue4ma(float,
                                                  integer[],
                                                  text[])''::regprocedure, 
                        ST_Width(rast)::text,
                        ST_Height(rast)::text,
                        ST_UpperLeftX(rast)::text,
                        ST_UpperLeftY(rast)::text,
                        ST_ScaleX(rast)::text,
                        ST_ScaleY(rast)::text,
                        ST_SkewX(rast)::text,
                        ST_SkewY(rast)::text,
                        ST_SRID(rast)::text,' || 
                        quote_literal(schemaname) || ', ' ||
                        quote_literal(tablename) || ', ' ||
                        quote_literal(rastercolumnname) || '
                       ) rast
FROM (SELECT ST_AsRaster(ST_Union(rast::geometry), 
                         min(scalex),
                         min(scaley),
                         min(gridx),
                         min(gridy),
                         min(pixeltype),
                         0,
                         min(nodataval)
                        ) rast
      FROM (SELECT ' || quote_ident(rastercolumnname) || 
                   ' rast,
                     ST_ScaleX(' || quote_ident(rastercolumnname) || ') scalex, 
       ST_ScaleY(' || quote_ident(rastercolumnname) || ') scaley, 
       ST_UpperLeftX(' || quote_ident(rastercolumnname) || ') gridx, 
       ST_UpperLeftY(' || quote_ident(rastercolumnname) || ') gridy, 
       ST_BandPixelType(' || quote_ident(rastercolumnname) || ') pixeltype, 
       ST_BandNodataValue(' || quote_ident(rastercolumnname) || ') nodataval
     FROM ' || quote_ident(schemaname) || '.' || quote_ident(tablename) || ' 
     ) foo
      ) foo2';
        EXECUTE query INTO newrast;
        RETURN newrast;
    END; $$
    LANGUAGE 'plpgsql' IMMUTABLE;



CREATE TABLE schema.rastertable_unioned AS
SELECT ST_FasterUnion('schema', 'rastertable', 'rast') rast;


