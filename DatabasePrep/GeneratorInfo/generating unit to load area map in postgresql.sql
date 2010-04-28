-- Run this in PostgreSQL

-- creates a map of generators to load areas by ventyx units and plants that will be imported into mysql

-- for an unknown reason,5 (significant) plants got left off the e_plants_point shapefile
-- that are present in the e_units_point shapefile
-- I went to the velocity suite online and copied these plants... I insert them here into the ventyx_e_plants_point before preceding
-- there isn't the plantoperid, but we don't use this anyway

-- insert into ventyx_e_plants_point
-- (plant_name,plant_oper,op_cap_mw,pln_cap_mw,ret_cap_mw,can_cap_mw,mth_cap_mw,descriptio,city,state,county,zip_code,proposed,loc_code,source,eia_id,layer_id,rec_id)
-- VALUES
-- ('Desert Sky Wind Project','General Electric Wind Energy',160.5,0,0,0,0,'2 OP WND WT(s)','Iraan','TX','Pecos',79744,'F',1,'Aerial Imagery',55992,69,7131),
-- ('Fairmont','Fairmont Public Utilities Commission',35.7,0,5,0,0,'4 OP WND WT(s),3 OP NG ST(s),2 OP NG IC(s),2 RE COL ST(s)','Fairmont','MN','Martin',56031,'F',1,'Aerial Imagery',1973,69,5245),
-- ('Geysers','Geysers Power Co LLC',710,80,137,0,60,'12 OP GEO GE(s),2 SC GEO GE(s),1 PL GEO GE(s),5 RE GEO GE(s)','Middletown','CA','Sonoma',95461,'F',1,'Aerial Imagery',286,69,7732),
-- ('King Mountain Wind Ranch 1','FPL Energy Upton Wind LP',278.2,0,0,0,0,'4 OP WND WT(s)','Mccamey','TX','Upton',79752,'F',1,'Aerial Imagery',55581,69,7087)
-- ;
-- update ventyx_e_plants_point
-- set 	plant_id = ventyx_e_units_point.plant_id,
-- 		the_geom = ventyx_e_units_point.the_geom
-- from ventyx_e_units_point
-- where ventyx_e_plants_point.plant_id is null
-- and ventyx_e_plants_point.plant_name = ventyx_e_units_point.plant_name;


-- real code now...
drop table if exists generating_plant_to_load_area_map;
create table generating_plant_to_load_area_map as
select plant_id,load_area
from ventyx_e_plants_point,wecc_load_area_polygons
where intersects(ventyx_e_plants_point.the_geom,wecc_load_area_polygons.the_geom)
and ventyx_e_plants_point.plant_id <> -99;

create index plant_id on generating_plant_to_load_area_map (plant_id);

-- exports existing plants with an operating capacity greater than 0 MW
COPY 
	(select load_area,plant_name,plant_oper,op_cap_mw,pln_cap_mw,ret_cap_mw,
			can_cap_mw,mth_cap_mw,descriptio,city,state,county,zip_code,
			proposed,loc_code,source,ventyx_e_plants_point.plant_id,
			plntoperid,eia_id,rec_id
	from 	ventyx_e_plants_point,generating_plant_to_load_area_map
	where	ventyx_e_plants_point.plant_id = generating_plant_to_load_area_map.plant_id
	and		ventyx_e_plants_point.plant_id <> -99
	and 	ventyx_e_plants_point.op_cap_mw > 0)
TO '/Volumes/1TB_RAID/Models/Switch\ Input\ Data/Generators/ventyx_e_plants_with_load_areas.csv'
WITH CSV HEADER;

-- exports existing units that are currently operational
COPY
	(SELECT load_area,unit,plant_name,pm_group,statustype,cap_mw,
			fuel_type,loc_code,source,unit_id,
			ventyx_e_units_point.plant_id
	FROM 	ventyx_e_units_point,generating_plant_to_load_area_map
	where	ventyx_e_units_point.plant_id = generating_plant_to_load_area_map.plant_id
	and		ventyx_e_units_point.statustype like 'Operating')
TO '/Volumes/1TB_RAID/Models/Switch\ Input\ Data/Generators/ventyx_e_units_with_load_areas.csv'
WITH CSV HEADER;