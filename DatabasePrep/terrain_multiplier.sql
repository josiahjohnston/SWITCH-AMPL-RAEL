-- #######################################
-- 6 Connection cost correction for remote projects
-- #######################################
-- This script determines the altitude difference between projects and their closest >66 kV substation (assumed connection point)
-- under the assumption that higher altitude differences imply costlier transmission lines. It also implements a land cover premimum, assuming
-- that building in forests is more expensive than in desert.
-- Multipliers were taken from the Black and Veatch report referenced by Jimmy in the WECC version of this same algorithm.
-- Roughly, what this script does is build a project list from all three proposed project tables, spatially assign them a connection substation above 66 kV,
-- calculating the straight line and determining the intersections with altitude iso-curves. From there, slopes are determined and land cover ids assigned
-- to each point (start, end, and intersections). Multipliers are applied for each slope and land cover type and weighted-averaged to assign to a specific
-- project.

-- First, create a table with all proposed project ids and their coordinates.
-- For nuclear and storage, we are picking them to be located in the same spot as the main substation for their load area as indicated in load_area
drop table if exists new_projects_location;
create table new_projects_location(
	project_id int,
	technology_id int,
	la_id varchar,
	PRIMARY KEY (project_id, technology_id)
);

SELECT addgeometrycolumn ('chile','new_projects_location','geom',4326,'POINT',2);

insert into new_projects_location
select project_id, technology_id, n.la_id, geom
from new_projects_alternative_1 n
join new_projects_conventional_import on location_id = unit
union
select project_id, technology_id, n.la_id, geom
from new_projects_alternative_1 n
join wind_and_solar_sites on location_id = sitecode
union
select project_id, technology_id, n.la_id, geom
from new_projects_alternative_1 n
join geothermalsites on location_id = gid::varchar 
union
select project_id, technology_id, n.la_id, geom
from new_projects_alternative_2 n
join (select la_id, geom from load_area join geo_substations on main_substation_for_load_area = id) t using (la_id)
where technology like 'Nucl%'
union
select project_id, technology_id, n.la_id, geom
from new_projects_alternative_3 n
join (select la_id, geom from load_area join geo_substations on main_substation_for_load_area = id) t using (la_id)
where location_id like 'Stor%';


-- Second, create straight lines between these and their closest above 66 kV substation using closest neighbor algorithm
alter table new_projects_location add column substation_code varchar;
alter table new_projects_location add column substation_name varchar;
alter table new_projects_location add column distance_to_closest_ss double precision;

SELECT addgeometrycolumn ('chile','new_projects_location','line_geom',4326,'LINESTRING',2);
SELECT addgeometrycolumn ('chile','new_projects_location','ssee_geom',4326,'POINT',2);

UPDATE new_projects_location
set 	substation_code = sseecod,
	substation_name = busname,
	distance_to_closest_ss = dist_ssee_project,
	ssee_geom = that_geom,
	line_geom = this_geom
FROM (
SELECT DISTINCT ON(r1.project_id, r1.technology_id) r1.project_id, r1.technology_id, r2.sseecod, r2.busname, 
	ST_Distance(r1.geom,r2.geom) * 100 as dist_ssee_project,
	r2.geom as that_geom,
	ST_Makeline(r1.geom,r2.geom) as this_geom
FROM new_projects_location r1, 
(select sseecod, busname, geom from geo_substations join bus_la_assignment on busname = bus_cmg where bus_voltage >= 66) r2
WHERE ST_DWithin(r1.geom, r2.geom,100000)
ORDER BY r1.project_id, r1.technology_id, ST_Distance(r1.geom,r2.geom)) t
where new_projects_location.project_id = t.project_id and new_projects_location.technology_id = t.technology_id;

-- Below, old code for altitude difference calculation, now superseeded
/*SELECT DISTINCT ON(r1.project_id, r1.technology_id) r1.project_id, r1.technology_id, r1.alt_project, r2.sseecod, r2.busname, r2.alt_ssee, abs(r1.alt_project - r2.alt_ssee) as alt_diff, 
	ST_Distance(r1.geom,r2.geom) * 100 as dist_ssee_project
    FROM (SELECT DISTINCT ON(g1.project_id, g1.technology_id) g1.project_id, g1.technology_id, g2.gid As gnn_gid, 
        g2.altura As alt_project, g1.geom, ST_Distance(g1.geom,g2.geom) as dist
	FROM new_projects_location As g1, geo_level_curves As g2   
	WHERE ST_DWithin(g1.geom, g2.geom,100000)   
	ORDER BY g1.project_id, g1.technology_id, ST_Distance(g1.geom,g2.geom)) As r1, 
	(select DISTINCT ON(g1.sseecod) sseecod, busname, g1.geom, g1.gid, g2.altura as alt_ssee 
	from geo_level_curves g2, geo_substations g1 join bus_la_assignment on busname = bus_cmg 
	where bus_voltage >= 66 
	ORDER BY g1.sseecod, ST_Distance(g1.geom,g2.geom)) As r2   
    WHERE ST_DWithin(r1.geom, r2.geom,100000)   
    ORDER BY r1.project_id, r1.technology_id, ST_Distance(r1.geom,r2.geom)*/

-- Third, we intersect these line geometries with the level curves to determine the points where slope changes
-- Adjust SRID for iso-curves
Select UpdateGeometrySRID('geo_level_curves', 'geom', 4326);

-- Create new table with the intersection results
-- This table lacks the start and end points, which are added later
drop table if exists new_projects_level_curve_intersection;
select 	project_id, technology_id, g.altura as altura, 
	(ST_Dump(ST_Intersection(g.geom, n.line_geom))).geom as geom
into new_projects_level_curve_intersection
from new_projects_location n, geo_level_curves g
where GeometryType(ST_Intersection(g.geom, n.line_geom)) = 'POINT' or GeometryType(ST_Intersection(g.geom, n.line_geom)) = 'MULTIPOINT';

-- Adding project location points: start
insert into new_projects_level_curve_intersection (project_id, technology_id, altura, geom)
SELECT DISTINCT ON(g1.project_id, g1.technology_id) g1.project_id, g1.technology_id, 
        g2.altura As alt_project, g1.geom
FROM new_projects_location As g1, geo_level_curves As g2   
WHERE ST_DWithin(g1.geom, g2.geom,100000)   
ORDER BY g1.project_id, g1.technology_id, ST_Distance(g1.geom,g2.geom);

-- Adding connecting SSEE points: end
insert into new_projects_level_curve_intersection (project_id, technology_id, altura, geom)
SELECT DISTINCT ON(g1.project_id, g1.technology_id) g1.project_id, g1.technology_id, 
        g2.altura As alt_project, g1.ssee_geom
FROM new_projects_location As g1, geo_level_curves As g2   
WHERE ST_DWithin(g1.ssee_geom, g2.geom,100000)   
ORDER BY g1.project_id, g1.technology_id, ST_Distance(g1.ssee_geom,g2.geom);

-- And add distances from new project location to this new table
-- Attempted random() for the distance, didn't result
alter table new_projects_level_curve_intersection add column distance double precision;
update new_projects_level_curve_intersection
set distance = d
from (	select project_id, technology_id, t.geom, ST_Distance(t.geom,n.geom) * 100 as d 
	from new_projects_level_curve_intersection t join new_projects_location n using (project_id, technology_id)
	order by 1,2,4 asc ) t
where	t.project_id = new_projects_level_curve_intersection.project_id 
and 	t.technology_id = new_projects_level_curve_intersection.technology_id 
and		t.geom = new_projects_level_curve_intersection.geom

-- Finally, we rank those points and find the slope between them
-- Add a column to hold the rank
alter table new_projects_level_curve_intersection add column rank bigint;

update 	new_projects_level_curve_intersection
set 	rank = t.rank
from	(SELECT project_id, technology_id, altura, distance, row_number() OVER (PARTITION BY project_id, technology_id order by distance asc) as rank
	FROM new_projects_level_curve_intersection ) t
where	t.project_id = new_projects_level_curve_intersection.project_id 
and 	t.technology_id = new_projects_level_curve_intersection.technology_id 
and		t.distance = new_projects_level_curve_intersection.distance;

-- Calculate slope and add it to the table.
alter table new_projects_level_curve_intersection add column slope double precision;

update 	new_projects_level_curve_intersection
set	slope = s.slope
from ( 	
select n.project_id, n.technology_id, n.rank, abs(t.altura - n.altura)/(abs(t.distance - n.distance) * 1000) * 100 as slope
from 	new_projects_level_curve_intersection n,
	(select project_id, technology_id, altura, distance, rank from new_projects_level_curve_intersection) t
where 	n.project_id = t.project_id
and	n.technology_id = t.technology_id
and	n.rank + 1 = t.rank ) s
where 	s.project_id = new_projects_level_curve_intersection.project_id
and	s.technology_id = new_projects_level_curve_intersection.technology_id
and	s.rank = new_projects_level_curve_intersection.rank

-- Now determine the land use for the intersection points, start and end points.
alter table new_projects_level_curve_intersection add column cover_id int;
alter table new_projects_level_curve_intersection add column cover_name character varying (25);

update new_projects_level_curve_intersection
set 	cover_id = t.cover_id,
		cover_name = t.cover_name
from (
select project_id, technology_id, distance, rank, slope, left(nombre,1)::int as cover_id, nombre as cover_name 
from new_projects_level_curve_intersection n, geo_land_cover g
where ST_Intersects(g.geom, n.geom)
order by project_id, technology_id, rank ) t
where	new_projects_level_curve_intersection.project_id = t.project_id
and		new_projects_level_curve_intersection.technology_id = t.technology_id
and		new_projects_level_curve_intersection.rank = t.rank

-- Land cover ids from the Chilean shapefile and its mapping into the 2012 Black and Veatch one
-- Improvising for 7 and 9, though they shouldn't show up in our cases
-- "1.- URBANAS E INDUSTRIAL" --> 'Urban'
-- "2.- TERRENOS AGRICOLAS" --> 'Farmland'
-- "3.- PRADERAS MATORRALES" --> 'Scrub'
-- "4.- BOSQUES" --> 'Forested'
-- "5.- HUMEDALES" --> 'Wetland'
-- "6.- AREAS SIN VEGETACION" --> 'Desert'
-- "7.- NIEVES Y GLACIARES" --> 'Water'
-- "8.- CUERPOS DE AGUA" --> 'Water'
-- "9.- AREAS NO RECONOCIDAS" --> 'Water'

-- Calculate the multiplier for each point, adding a new column
alter table new_projects_level_curve_intersection add column terrain_multiplier double precision;

update new_projects_level_curve_intersection
set terrain_multiplier = tm
from (
select project_id, technology_id, rank,
(CASE 	WHEN coalesce(slope,0) <= 2 then 0
	WHEN coalesce(slope,0) BETWEEN 2 AND 8 then 0.4
	WHEN coalesce(slope,0) >= 8 THEN 0.75
END
+
CASE 	WHEN cover_id = 6 THEN 0.05 --'Desert'
	WHEN cover_id = 3 THEN 0 --'Scrub'  
	WHEN cover_id = 2 THEN 0 --'Farmland' 
	WHEN cover_id = 4 THEN 1.25 --'Forested'
	WHEN cover_id = 5 THEN 0.2 --'Wetland' 
	WHEN cover_id = 1 THEN 0.59  --'Urban'  
	WHEN cover_id IN (7, 8, 9) THEN 1 -- 'Water'
END) as tm
from new_projects_level_curve_intersection
--where project_id = 268
order by 1,2,3 ) p
where 	new_projects_level_curve_intersection.project_id = p.project_id
and	new_projects_level_curve_intersection.technology_id = p.technology_id
and	new_projects_level_curve_intersection.rank = p.rank

-- Finally, calculate a terrain multiplier for each project's connection line in the new_projects_location table
alter table new_projects_location add column avg_terrain_multiplier double precision default 1;

update new_projects_location
set avg_terrain_multiplier = avg_terr_mult
from (
select 	n.project_id, n.technology_id,
		1 + sum((coalesce(t.distance,0) - coalesce(n.distance,0)) * (coalesce(t.terrain_multiplier,0) + coalesce(n.terrain_multiplier,0)) / 2 ) / coalesce(max(t.distance),0) as avg_terr_mult
from 	new_projects_level_curve_intersection n,
		(select project_id, technology_id, distance, rank, terrain_multiplier from new_projects_level_curve_intersection) t
where 	n.project_id = t.project_id
and		n.technology_id = t.technology_id
and		n.rank + 1 = t.rank
group by 1,2) m
where new_projects_location.project_id = m.project_id
and new_projects_location.technology_id = m.technology_id

-- Now, this has to be imported to AMPL and/or incorporated to the connection cost calculation per project
-- We will change the connection costs in the new_projects' tables
-- I now realize that we should migrate to a unified proposed projects list with a scheme to select project sets as scenarios
update 	new_projects_alternative_1
set 	connect_cost_per_mw = transmission_new_annual_payment_per_mw_km/0.106 * distance_to_closest_ss * avg_terrain_multiplier
from	new_projects_location n join load_area using (la_id)
where	n.project_id = new_projects_alternative_1.project_id
and		n.technology_id = new_projects_alternative_1.technology_id;

update 	new_projects_alternative_2
set 	connect_cost_per_mw = transmission_new_annual_payment_per_mw_km/0.106 * distance_to_closest_ss * avg_terrain_multiplier
from	new_projects_location n join load_area using (la_id)
where	n.project_id = new_projects_alternative_2.project_id
and		n.technology_id = new_projects_alternative_2.technology_id;

update 	new_projects_alternative_2
set 	connect_cost_per_mw = transmission_new_annual_payment_per_mw_km/0.106 * distance_to_closest_ss * avg_terrain_multiplier
from	new_projects_location n join load_area using (la_id)
where	n.project_id = new_projects_alternative_2.project_id
and		n.technology_id = new_projects_alternative_2.technology_id;