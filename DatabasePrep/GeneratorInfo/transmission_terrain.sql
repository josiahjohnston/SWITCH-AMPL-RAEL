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

-- SLOPE ----------------------
-- the slope category represents the different types of slope cited in "CAPITAL COSTS FOR TRANSMISSION AND SUBSTATIONS:
-- Recommendations for WECC Transmission Expansion Planning" from Black and Veatch, 2012
-- the slope_category bins are 0-2%, 2-8% and >8%
DROP TABLE IF EXISTS transmission_slope_cateogories;
CREATE TABLE transmission_slope_cateogories (
	rid int,
	state varchar(3),
	slope_category varchar(3),
	PRIMARY KEY (rid, state, slope_category) );

SELECT addgeometrycolumn ('usa_can','transmission_slope_cateogories','the_geom',4326,'MULTIPOLYGON',2);
CREATE INDEX ON transmission_slope_cateogories USING gist (the_geom);
CREATE INDEX ON transmission_slope_cateogories (rid);
CREATE INDEX ON transmission_slope_cateogories (state);
CREATE INDEX ON transmission_slope_cateogories (slope_category);

-- the ST_Buffer(, 0.000001) fixes a floating point precision problem that spits out polygons
-- that should have identical vertices but instead are seperated by a *really* small margin
-- Takes a few hours to run for all of North America!
INSERT INTO transmission_slope_cateogories (rid, state, slope_category, the_geom)
	SELECT 	rid,
			state,
			CASE WHEN percent_slope < 2 THEN '0-2'
				WHEN percent_slope BETWEEN 2 AND 8 THEN '2-8'
				ELSE '8-' END
				AS slope_category,
			ST_Multi(ST_Union(the_geom)) as the_geom
	FROM	(	SELECT 	l.rid,
						state,
						(ST_DumpAsPolygons(rast)).val as percent_slope,
						ST_Intersection(ST_Buffer((ST_DumpAsPolygons(rast)).geom, 0.000001), the_geom) as the_geom
				FROM	usa_can.slope_usa_can,
						land_cover_rid_to_states_map l
				WHERE	ST_Intersects(rast, the_geom)
			) as pixel_to_polygon_table
	WHERE 	ST_Dimension(the_geom) = 2
	GROUP BY rid, state, slope_category;
	
	
	
	
-- LAND COVER -----------------------	
-- from the same Black and Veatch document above, the land cover can infulence the cost of building transmission
-- B&V identifies 7 different non-slope categories:  Desert, Scrub-Flat, Farmland, Forested, Wetland, Suburban, Urban
-- our land cover data doesn't do very well at differentiating Desert from Scrub-Flat, and these have a tiny difference in the B&V cost estimates
-- (1.05 vs 1) so we combine Desert and Scrub-Flat into 'Desert-Scrub'
-- also, the differentiation between urban and suburban is difficult from our land cover data,
-- so we'll make a conservative assumption and assume all "22:Urban and Built-up" is urban, thereby discarding the suburban class

-- first, insert land cover from raster tiles that don't cross state borders
-- this means that we don't have to do an intersection with the state geom for these tiles,
-- thereby saving a lot of computation time

-- create a table of acceptable land cover, broken up by raster tile for easier manipulation
DROP TABLE IF EXISTS transmission_land_category;
CREATE TABLE transmission_land_category (
	rid int,
	state varchar(3),
	land_category varchar(15),
	PRIMARY KEY (rid, state, land_category) );
	
SELECT addgeometrycolumn ('usa_can','transmission_land_category','the_geom',4326,'MULTIPOLYGON',2);
CREATE INDEX ON transmission_land_category USING gist (the_geom);
CREATE INDEX ON transmission_land_category (rid);
CREATE INDEX ON transmission_land_category (state);
CREATE INDEX ON transmission_land_category (land_category);


INSERT INTO transmission_land_category (rid, state, land_category, the_geom)
SELECT rid,
			state,
			CASE WHEN classification_type IN ( 9, 10, 11, 12, 13, 14, 15, 16, 17, 21, 23, 25, 26 ) THEN 'Desert-Scrub'
				WHEN classification_type IN ( 18, 19 ) THEN 'Farmland'
				WHEN classification_type IN ( 1, 2, 3, 4, 5, 6, 7, 8, 20, 29 ) THEN 'Forested'
				WHEN classification_type IN ( 27, 28 ) THEN 'Wetland'
				WHEN classification_type IN ( 22 ) THEN 'Urban'
				WHEN classification_type IN ( 0, 24 ) THEN 'Water'
				END as land_category,
			ST_Multi(ST_Union(the_geom)) as the_geom
	FROM	(	SELECT 	rid,
						state,
						(ST_DumpAsPolygons(rast)).val as classification_type,
						(ST_DumpAsPolygons(rast)).geom as the_geom
				FROM	land_cover_north_america_1km
				JOIN	land_cover_rid_to_states_map USING (rid)
				WHERE	NOT rid_is_across_state_borders
			) as pixel_to_polygon_table
	GROUP BY rid, state, land_category;



-- the above query hasn't cut land area around the coasts correctly
-- do an update here to cut off pixels that go into the sea
-- the ST_CollectionExtract..., 3 returns multipolygons out of the intersection - we don't want point or line intersections
UPDATE 	transmission_land_category l
SET 	the_geom = ST_CollectionExtract(ST_Multi(ST_Intersection(l.the_geom, s.the_geom)),3)
FROM 	ventyx_may_2012.states_region s 
WHERE	s.abbrev = l.state;


-- now do the intersection with state polygons for tiles that cross state borders
INSERT INTO transmission_land_category (rid, state, land_category, the_geom)
SELECT rid,
			state,
			CASE WHEN classification_type IN ( 9, 10, 11, 12, 13, 14, 15, 16, 17, 21, 23, 25, 26 ) THEN 'Desert-Scrub'
				WHEN classification_type IN ( 18, 19 ) THEN 'Farmland'
				WHEN classification_type IN ( 1, 2, 3, 4, 5, 6, 7, 8, 20, 29 ) THEN 'Forested'
				WHEN classification_type IN ( 27, 28 ) THEN 'Wetland'
				WHEN classification_type IN ( 22 ) THEN 'Urban'
				WHEN classification_type IN ( 0, 24 ) THEN 'Water'
				END as land_category,
			ST_Multi(ST_Union(the_geom)) as the_geom
	FROM	(	SELECT 	rid,
						state,
						(ST_Intersection(rast, the_geom)).val as classification_type,
						(ST_Intersection(rast, the_geom)).geom as the_geom
				FROM	land_cover_north_america_1km
				JOIN	land_cover_rid_to_states_map USING (rid)
				WHERE	rid_is_across_state_borders
			) as pixel_to_polygon_table
	WHERE 	ST_Dimension(the_geom) = 2
	GROUP BY rid, state, land_category;
	
	
-- Make transmission_terrain_multiplier table
-- Black and Veatch has different transmission cost multipliers for slope and terrain type,
-- which are combined here into one cost surface that can be intersected with transmission line routes
-- to determine the final terrain cost for a given route
-- We'll use B&V's WECC value from Table 2-5 'Terrain Cost Multipliers'

-- the value of slope and terrain multiplier will be applied to a base transmission cost INDEPENDENTLY
-- as shown in examples in the PG&E and SCE links in the B&V document
-- the multipliers are therefore summed to get the total multiplier

DROP TABLE IF EXISTS transmission_terrain_multiplier;
CREATE TABLE transmission_terrain_multiplier (
	rid int,
	state varchar(3),
	slope_category varchar(3) CHECK (slope_category IN ('0-2', '2-8', '8-')),
	land_category varchar(15) CHECK (land_category IN ('Desert-Scrub', 'Farmland', 'Forested', 'Wetland', 'Urban', 'Water')),
	terrain_multiplier NUMERIC(3,2) CHECK (terrain_multiplier BETWEEN 1 AND 4),
	PRIMARY KEY (rid, state, slope_category, land_category) );
	
SELECT addgeometrycolumn ('usa_can','transmission_terrain_multiplier','the_geom',4326,'MULTIPOLYGON',2);
CREATE INDEX ON transmission_terrain_multiplier USING gist (the_geom);
CREATE INDEX ON transmission_terrain_multiplier (rid);
CREATE INDEX ON transmission_terrain_multiplier (state);
CREATE INDEX ON transmission_terrain_multiplier (slope_category);
CREATE INDEX ON transmission_terrain_multiplier (land_category);


INSERT INTO transmission_terrain_multiplier (rid, state, slope_category, land_category, the_geom)
	SELECT 	rid,
			state,
			slope_category,
			land_category,
			ST_CollectionExtract(ST_Multi(ST_Union(ST_Intersection(l.the_geom, s.the_geom))),3) as the_geom
	FROM transmission_land_category l
	JOIN transmission_slope_cateogories s USING (rid, state)
	GROUP BY rid, state, slope_category, land_category;


-- actually calculate the terrain_multiplier value
-- which is 1 (the base cost) + adders for slope and land
-- note that Black and Veatch didn't have values for water,
-- but hopefully any transmission lines that we're building won't go over much water at all
-- so I put a high but not limiting value of 1 + 1 = 2 on water, which is meant to be roughly correct for short spans
UPDATE 	transmission_terrain_multiplier
SET 	terrain_multiplier =
	1 + 
		CASE 	WHEN slope_category = '0-2' THEN 0
				WHEN slope_category = '2-8' THEN 0.4
				WHEN slope_category = '8-' 	THEN 0.75
		END
	+
		CASE 	WHEN land_category = 'Desert-Scrub' THEN 0
				WHEN land_category = 'Farmland' THEN 0
				WHEN land_category = 'Forested'  THEN 1.25
				WHEN land_category = 'Wetland' THEN 0.2
				WHEN land_category = 'Urban'  THEN 0.59
				WHEN land_category = 'Water'  THEN 1
		END;
		

	
	
SELECT 	load_area_start,
		load_area_end,
		transmission_line_id,
		sum(	terrain_multiplier
				* ST_Length(ST_Intersection(m.the_geom, route_geom)::geography, false)
				/ ST_Length(route_geom::geography, false)
			)
FROM wecc_trans_lines,
	 transmission_terrain_multiplier m
where 	ST_Intersects(m.the_geom, route_geom)
-- AND		load_area_start like 'CA_%' AND load_area_end like 'CA_%'
GROUP BY load_area_start, load_area_end, transmission_line_id;




















