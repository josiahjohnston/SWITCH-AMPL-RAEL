-- find good canadian wind sites,
-- import hourly canadian wind data
-- and calculate hourly capacity factors for new and existing Canadian wind

-- written in postgresql

-- CHOOSE NEW WIND SITES
-- uploads a 2km canadian wind power capacity factor raster (at 80m hub height)
-- the 2km raster (actually a bunch of point shapefiles) has already been filtered in arcmap
-- for slopes >= 10%, landcover that includes forest, and the wrez exclude/avoid areas
-- it therefore represents the canadian land suitable for wind development

-- first, load up point shapefiles (converted from a 2km raster via ArcGIS) with capacity factor data for all of Canada
-- shp2pgsql -s 4326 /Volumes/switch/Models/GIS/Canada_Wind_AWST/canwindlandpoints.dbf wind_canada_cap_factor_map | psql -h switch-db2.erg.berkeley.edu -U postgres -d switch_gis

alter table wind_canada_cap_factor_map drop column pointid;
alter table wind_canada_cap_factor_map rename column grid_code to cap_factor_80m;
alter table wind_canada_cap_factor_map add column province char(2);
create index can_cap_factor_80m_index on wind_canada_cap_factor_map (cap_factor_80m);
create index can_province_index on wind_canada_cap_factor_map (province);
CREATE INDEX wind_canada_cap_factor_map_index ON wind_canada_cap_factor_map USING gist (the_geom);


-- add the province in which each windpoint resides
update wind_canada_cap_factor_map
set province = abbrev
from ventyx_states_region
where country = 'Canada'
and intersects(wind_canada_cap_factor_map.the_geom, ventyx_states_region.the_geom)
and wind_canada_cap_factor_map.the_geom && ventyx_states_region.the_geom;

-- a few points don't overlap with the ventyx_states_region shapefile...
-- label them with the nearest province as they're likely just offshore
drop table if exists wind_canada_province_distance;
create table wind_canada_province_distance(
	gid int,
	province char(2),
	distance double precision,
	primary key (gid, province)
	);

insert into wind_canada_province_distance (gid, province, distance)
select 	wind_canada_cap_factor_map.gid,
		abbrev as province,
		ST_Distance_Sphere(wind_canada_cap_factor_map.the_geom, ST_ClosestPoint(ventyx_states_region.the_geom, wind_canada_cap_factor_map.the_geom)) as distance
from wind_canada_cap_factor_map, ventyx_states_region
where province is null
and country='Canada';

update wind_canada_cap_factor_map
set province = province_match_table.province
from (select gid, province from 
		(select gid, min(distance) as distance from wind_canada_province_distance group by gid) as min_distance_table
		join wind_canada_province_distance using (gid, distance)
	) as province_match_table
where wind_canada_cap_factor_map.province is null
and wind_canada_cap_factor_map.gid = province_match_table.gid;

drop table if exists wind_canada_province_distance;


-- create a map for easy visualization of quality AB and BC windpoints

drop table if exists wind_canada_cap_factor_map_wecc;
create table wind_canada_cap_factor_map_wecc(
	gid int primary key,
	cap_factor_80m NUMERIC(4,4),
	province char(2),
	is_canidate_windfarm smallint default 0
	);
	
create index wecc__cap_factor_80m_index on wind_canada_cap_factor_map_wecc (cap_factor_80m);
create index wecc__province_index on wind_canada_cap_factor_map_wecc (province);
SELECT AddGeometryColumn ('public','wind_canada_cap_factor_map_wecc','the_geom',4326,'POINT',2);
CREATE INDEX wind__canada_cap_factor_wecc_index ON wind_canada_cap_factor_map_wecc USING gist (the_geom);

-- 
insert into wind_canada_cap_factor_map_wecc (gid, cap_factor_80m, province, the_geom)
	select gid, cap_factor_80m, province, the_geom
	from wind_canada_cap_factor_map
	where province in ('BC', 'AB') and cap_factor_80m > 0.25;

-- manually picked GIDS of BC windfarms:
update wind_canada_cap_factor_map_wecc set is_canidate_windfarm = 1 where gid in (1589158, 1618234, 1624988, 2057953, 2067446, 2037797, 2010303, 1907348, 1765810, 1712055, 1691719, 1675678, 1628399, 1599651, 1559923, 1814208, 1737637, 1765860);
-- manually picked GIDS of AB windfarms:
update wind_canada_cap_factor_map_wecc set is_canidate_windfarm = 1 where gid in (2128264, 2059201, 2188143, 2182121, 2022074, 1768895, 1758519, 1803046, 1637956, 1921947, 1898919, 1932711, 1912836, 1872586, 1928479, 1997377, 2027041, 2054629, 2047507, 2097246, 2133801, 2109964, 2143867, 2174746, 2155624, 2173690, 2184716, 2157651, 2163184);

-- didn't get these in the first round of downloads... try again to get them....
-- 2082789, 2141636... one more in AB also... check later...
 
-- now print out a list of lat/lon for the AWST download website
select ST_X(the_geom) as longitude, ST_Y(the_geom) as latitude from wind_canada_cap_factor_map_wecc where is_canidate_windfarm = 1 order by latitude, longitude;

-- ------------------------------------

-- GET TURBINE POWER CURVES----------
-- upload turbine power curves from NREL's System Advisor Model (SAM) (Release 2012.5.11)

drop table if exists wind_turbine_power_curves;
create table wind_turbine_power_curves(
	turbine_name varchar(64),
	rated_capacity_MW double precision,
	cutout_speed_m_per_s double precision,
	reference_speed_m_per_s double precision,
	reference_power_output_MW double precision,
	slope_to_next_speed_value double precision,
	primary key (turbine_name, reference_speed_m_per_s)
	);

create index turbine_name_idx on wind_turbine_power_curves (turbine_name);
create index reference_speed_m_per_s_idx on wind_turbine_power_curves (reference_speed_m_per_s);
create index reference_power_output_MW_idx on wind_turbine_power_curves (reference_power_output_MW);

drop table if exists wind_turbine_power_curve_import;
create table wind_turbine_power_curve_import (
	row_id serial primary key,
	line_text varchar(1000) );
	
COPY wind_turbine_power_curve_import (line_text)
FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/power_curves/LargeScaleWindTurbine.samlib'
USING DELIMITERS '{';

-- mash up the data to get it into sql form
delete from wind_turbine_power_curve_import where line_text like '!';
delete from wind_turbine_power_curve_import where row_id <=3;
update wind_turbine_power_curve_import set line_text = replace(line_text, 'entry ', '=');
update wind_turbine_power_curve_import set line_text = replace(line_text, '= ', '=');
update wind_turbine_power_curve_import set line_text = substring(line_text from position('=' in line_text) + 1 );

-- pivot the rated capacity and turbine name onto the data lines
-- there are 7 rows per entry, hence modulo 7 ( the % )
update wind_turbine_power_curve_import
set line_text = cap_text || ',' || line_text
from (select row_id as cap_row_id, line_text as cap_text from wind_turbine_power_curve_import where (row_id + 2) % 7 = 0) as name_table
where ( row_id = cap_row_id + 3 or row_id = cap_row_id + 4);

update wind_turbine_power_curve_import
set line_text = name_text || ',' || line_text
from (select row_id as name_row_id, line_text as name_text from wind_turbine_power_curve_import where (row_id + 3) % 7 = 0) as name_table
where ( row_id = name_row_id + 4 or row_id = name_row_id + 5);

-- get rid of all lines that we don't need
delete from wind_turbine_power_curve_import where ( row_id % 7 = 0 or row_id % 7 = 4 or row_id % 7 = 5 or row_id % 7 = 6 ); 


-- PERFORM ADDITION TO TABLE wind_turbine_power_curves 
-- this is a dummy function that will excecute an sql statement inserted into it in the form of text
-- we'll create this text string below by concating parts of an insert statement together
-- with a variable that runs through all of the years we're interested in
CREATE OR REPLACE FUNCTION exec(text) RETURNS text AS $$ BEGIN EXECUTE $1; RETURN $1; END $$ LANGUAGE plpgsql;

-- create the column-looping function
CREATE OR REPLACE FUNCTION pivot_power_curve() RETURNS void AS $$

	declare column_var integer;
	
    BEGIN
	
	-- data starts on the third column
	select 3 into column_var;

	LOOP
		-- we must use PERFORM instead of select here because select will return the text string of the insert statement, which throws an error
		-- and we don't need it printed out (all we need is for the string to be fed through exec() to be executed
		PERFORM exec(
	    		'INSERT INTO wind_turbine_power_curves (turbine_name, rated_capacity_MW, reference_speed_m_per_s, reference_power_output_MW) '
	    		|| 'select turbine_name, rated_capacity_MW, reference_speed_m_per_s, reference_power_output_MW from '
	    		|| '(select row_id, columns[1] as turbine_name, cast(columns[2] as numeric) as rated_capacity_MW, cast(columns['
	  			|| column_var
	  			|| '] as numeric) as reference_speed_m_per_s '
	  			|| 'from (SELECT row_id, string_to_array(line_text, \',\') as columns FROM wind_turbine_power_curve_import where row_id % 7 = 1) as columns_table  ) as speed_table '
	  			|| 'join (select row_id - 1 as row_id, cast(columns['
				|| column_var
				|| '] as numeric) as reference_power_output_MW from '
				|| '(SELECT row_id, string_to_array(line_text, \',\') as columns FROM wind_turbine_power_curve_import) as columns_table where row_id % 7 = 2 ) as power_table '
				|| 'using (row_id) where reference_speed_m_per_s is not null'
		);


		column_var := column_var + 1;

	EXIT WHEN column_var >= 200;
	END LOOP;

    END;
$$ LANGUAGE plpgsql;

-- excute the insert statements
select pivot_power_curve();

-- clean up
drop function pivot_power_curve();

-- data is in kW, but we want MW, so divide by 1000
update wind_turbine_power_curves
set rated_capacity_MW = rated_capacity_MW/1000,
reference_power_output_MW = reference_power_output_MW/1000;

-- also, Idaho National Laboratory put together a file of power curves for older wind turbines
-- data downloaded from http://www.inl.gov/wind/software/ and manually put into the format used here
COPY wind_turbine_power_curves (turbine_name, rated_capacity_MW, reference_speed_m_per_s, reference_power_output_MW)
FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/power_curves/power_curves_INL.csv'
WITH CSV HEADER;


-- fill in the slope_to_next_speed_value
update wind_turbine_power_curves set slope_to_next_speed_value = slope
from
	(select turbine_name,
			speed_step_table.reference_speed_m_per_s,
			(t4.reference_power_output_MW - t3.reference_power_output_MW ) / speed_step as slope
	from 
		(select turbine_name, t1.reference_speed_m_per_s, min(t2.reference_speed_m_per_s - t1.reference_speed_m_per_s) as speed_step
			from wind_turbine_power_curves t1
			join wind_turbine_power_curves t2 using (turbine_name)
			where t2.reference_speed_m_per_s > t1.reference_speed_m_per_s
			group by turbine_name, t1.reference_speed_m_per_s ) as speed_step_table
		join wind_turbine_power_curves t3 using (turbine_name, reference_speed_m_per_s)
		join wind_turbine_power_curves t4 using (turbine_name)
		where t4.reference_speed_m_per_s - speed_step = speed_step_table.reference_speed_m_per_s) as slope_table
	where 	slope_table.turbine_name = wind_turbine_power_curves.turbine_name
	and		slope_table.reference_speed_m_per_s = wind_turbine_power_curves.reference_speed_m_per_s;

-- top of the curve slope_to_next_speed_value is null from above, so make it as zero here
update wind_turbine_power_curves set slope_to_next_speed_value = 0 where slope_to_next_speed_value is null;

-- set cutout_speed_m_per_s
delete from wind_turbine_power_curves
using 	(select turbine_name, min(reference_speed_m_per_s) as speed_at_max_power from
			( select turbine_name, max(reference_power_output_MW) as max_reference_power_output_MW
				from wind_turbine_power_curves group by turbine_name) as max_power_table
				join wind_turbine_power_curves using (turbine_name)
			where reference_power_output_MW = max_reference_power_output_MW
			group by 1
			) as speed_at_max_power_table
where reference_power_output_MW = 0
and	speed_at_max_power_table.turbine_name = wind_turbine_power_curves.turbine_name
and	reference_speed_m_per_s > speed_at_max_power;

update wind_turbine_power_curves set cutout_speed_m_per_s = max_speed
from (select turbine_name, max(reference_speed_m_per_s) as max_speed
		from wind_turbine_power_curves group by turbine_name) as max_speed_table
where max_speed_table.turbine_name = wind_turbine_power_curves.turbine_name;

update wind_turbine_power_curves set slope_to_next_speed_value = 0 where reference_speed_m_per_s = cutout_speed_m_per_s;


-- CREATE IMPORT FUNCTION --------------------
-- after downloading the hourly data from the AWST website and consolidating the hourly csvs into a single folder,
-- this creates info about each wind site and loads the hourly data into postgresql

drop table if exists windfarms_canada_info;
create table windfarms_canada_info (
	id serial primary key,
	elevation_m int,
	roughness_cm numeric,
	latitude numeric,
	longitude numeric,
	capacity_limit_MW float
	);
	
SELECT addgeometrycolumn ('public','windfarms_canada_info','the_geom',4326,'POINT',2);
CREATE INDEX windfarms_canada_info_geom_index ON windfarms_canada_info USING gist (the_geom);
SELECT addgeometrycolumn ('public','windfarms_canada_info','windfarm_geom',4326,'MULTIPOLYGON',2);
CREATE INDEX windfarms_canada_info_windfarm_geom_index ON windfarms_canada_info USING gist (windfarm_geom);

drop table if exists windfarms_canada_hourly_cap_factor;
create table windfarms_canada_hourly_cap_factor (
	id int references windfarms_canada_info,
	timestamp_utc timestamp,
	temperature_degC numeric(5,1),
	pressure_mb numeric(5,1),
	direction_degrees int,
	speed_m_per_s numeric(6,2),
	density_kg_per_m_cubed numeric(5,3),
	cap_factor double precision,
	primary key (id, timestamp_utc)
	);


-- import as raw text first to get information on the first lines of the hourly csv file
-- (these lines have a different number of fields than are in the hourly data)
drop table if exists import_hourly_canada_wind;
create table import_hourly_canada_wind (
	row_id serial primary key,
	line_text varchar(512));

-- create a function that will do all of the importing for a single canadian wind point
-- this function will be called each time a new csv file is imported
CREATE OR REPLACE FUNCTION import_canada_wind_data() RETURNS void AS $$

    BEGIN
		-- delete all spaces from the data because they're pesky
		update import_hourly_canada_wind set line_text = replace( line_text, ' ', '' );
		
		-- add entries in the info table first
		insert into windfarms_canada_info (elevation_m)
			select cast(substring( line_text from position( ',' in line_text ) + 1 ) as numeric)
			from import_hourly_canada_wind where row_id = 2;
		update windfarms_canada_info set roughness_cm = cast( substring( line_text from position( ',' in line_text ) + 1 ) as numeric )
			from import_hourly_canada_wind where roughness_cm is null and row_id = 3;
		update windfarms_canada_info set latitude = cast( substring( line_text from position( ',' in line_text ) + 1 ) as numeric )
			from import_hourly_canada_wind where latitude is null and row_id = 4;
		update windfarms_canada_info set longitude = cast( substring( line_text from position( ',' in line_text ) + 1 ) as numeric )
			from import_hourly_canada_wind where longitude is null and row_id = 5;
		-- make geometries out of lat/lon
		update windfarms_canada_info SET the_geom = SETSRID(MakePoint(longitude, latitude),4326) where the_geom is null;
		
		
		-- now import the hourly data
		insert into windfarms_canada_hourly_cap_factor (id, timestamp_utc, temperature_degC, pressure_mb, direction_degrees, speed_m_per_s, density_kg_per_m_cubed)
		
		SELECT 	id,
				cast(columns[1] || ' ' || overlay(columns[2] placing ':00:00' from 3) as timestamp) as timestamp_utc,
				cast(columns[3] as numeric) as temperature_degC,
				cast(columns[4] as numeric) as pressure_mb,
				cast(columns[5] as numeric) as direction_degrees,
				cast(columns[6] as numeric) as speed_m_per_s,
				cast(columns[7] as numeric) as density_kg_per_m_cubed
		FROM ( 
		  	SELECT string_to_array(line_text, ',') as columns
		    	FROM import_hourly_canada_wind
		    	WHERE row_id > 10
			) as column_array_table,
			windfarms_canada_info
		where 	id = (select max(id) from windfarms_canada_info);
		
		delete from import_hourly_canada_wind;
		ALTER SEQUENCE import_hourly_canada_wind_row_id_seq RESTART WITH 1;

    END;
$$ LANGUAGE plpgsql;


-- delimiter here is something that DOESN'T appear in the file so all lines are imported
-- must be cleared out before the next file is imported otherwise script won't work
-- then excute the insert statements and calculate the power output

-- NOTE: vmm_44806 and vmm_44807 are for the same point, so vmm_44807 isn't included here because it's redundant
-- also vmm_45010 is in a redundant place, so it isn't included either
COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_44800.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_44801.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_44802.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_44803.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_44804.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_44805.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_44806.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_44808.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_44809.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45011.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45012.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45013.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45014.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45015.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45016.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45017.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45019.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45020.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45021.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45022.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45023.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45024.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45025.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45026.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45027.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45028.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45029.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45030.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45031.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45032.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45033.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45034.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45035.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45036.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45037.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45038.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45039.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45040.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45041.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45042.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45043.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45044.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45045.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45046.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45047.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45048.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45049.csv' USING DELIMITERS '{';
select import_canada_wind_data();

COPY import_hourly_canada_wind (line_text) FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/hourly_data/vmm_45050.csv' USING DELIMITERS '{';
select import_canada_wind_data();


-- clean up
drop function import_canada_wind_data();

-- for now, delete all hourly values that we're not going to use in SWITCH (SWITCH uses only 2004-2006 data)
delete from windfarms_canada_hourly_cap_factor where timestamp_utc::date < cast('2003-12-31' as date);
delete from windfarms_canada_hourly_cap_factor where timestamp_utc::date > cast('2007-01-01' as date);

-- CALCULATE CAP FACTORS FOR NEW CANADIAN WIND
-- run the windspeed values through a Vestas V90 turbine curve
-- correcting for air density

-- how to correct for air density
-- from http://www.windsim.com/ws_docs/ModuleDescriptions/Energy2.html
-- (also here http://www.awstruepower.com/wp-content/media/2011/04/OpenWindTheoryAndValidation.pdf)

-- Specification of the air density at the Turbine positions. A power curve is given for a specific air density.
-- If the air densities given in the power curves differ from the air density given herein, a correction will be applied to the power curves.
-- Two different correction methods can be applied depending on the power control system of the WECS (EN 61400-12).
-- If a power curve is defined without any corresponding density, the correction of the power curve will not be applied. The default value is 1 (kg/m3).

-- Method for density correction
-- Pitch-regulated WECS
-- In the case of pitch-regulated wind turbines the power output of the WECS is calculated by entering in the original power curve with a corrected wind speed.
-- The corrected wind speed is obtained by the wind speed times the fraction (air density AEP)/(air density power curve) at the power 1/3.
-- Stall-regulated WECS
-- In the case of stall-regulated wind turbines the fraction (air density AEP)/(air density power curve) is used in the AEP calculations as a multiplication factor of the reference power curves.

-- Vestas V90 turbines are pitch regulated, so we'll use that correction
-- also, the turbine power curve is assumed to have the standard reference air density of 1.225kg/m^3, so a denominator of 1.225 is in the above correction
-- the density-normalized wind speed here is speed_m_per_s * POWER(density_kg_per_m_cubed/1.225, 0.333333333333333)

-- first, the cap_factor for any windspeeds above the turbine cutout_speed_m_per_s are zeroed out here
update 	windfarms_canada_hourly_cap_factor
set 	cap_factor = 0
from 	wind_turbine_power_curves
where 	turbine_name = 'V90-3.0'
and 	speed_m_per_s >= cutout_speed_m_per_s;

-- next, fill out all other cap factors
update 	windfarms_canada_hourly_cap_factor
set 	cap_factor = ( reference_power_output_MW + slope_to_next_speed_value * MOD(speed_m_per_s * POWER(density_kg_per_m_cubed/1.225, 0.333333333333333), 0.25) ) / rated_capacity_MW
from 	wind_turbine_power_curves
where 	turbine_name = 'V90-3.0'
and 	reference_speed_m_per_s = 0.25 * FLOOR(speed_m_per_s * POWER(density_kg_per_m_cubed/1.225, 0.333333333333333) * 4)
and		cap_factor is null;

-- MAKE WIND FARM GEOM-------------
-- The Western Wind and Solar Integration study uses Vestas v90 turbines as above.
-- they calculate that you can put 10 turbines at 3 MW per turbine on a 2x2km piece of land
-- here we calculate the area of a windfarm in km^2 and then use this ratio to convert the area to MW
-- also, only wind projects that are both within a small distance and a small cap factor difference from the windpoint
-- that was downloaded from AWS truepower are included here.

-- the join using intersects(expand( takes care of small geom mismatches between wind_canada_cap_factor_map_wecc and windfarms_canada_info
update windfarms_canada_info
set capacity_limit_MW = windfarm_geom_cap_table.capacity_limit_MW,
windfarm_geom = windfarm_geom_cap_table.windfarm_geom
from
		(select	w1.gid,
				w1.the_geom,
				sum( ( 30.0 / 4.0 ) * area(transform(expand(w2.the_geom, 0.0091), 2163)) / 1000000.0 ) as capacity_limit_MW,
				multi(ST_union( expand(w2.the_geom, 0.0091) ) ) as windfarm_geom
		from 	wind_canada_cap_factor_map_wecc w1,
				wind_canada_cap_factor_map_wecc w2,
				(select min(st_distance_sphere(w1.the_geom, w2.the_geom) / 2.0) / 1000.0 as min_distance_km
					from 	wind_canada_cap_factor_map_wecc w1,
							wind_canada_cap_factor_map_wecc w2
					where 	w1.gid <> w2.gid
					and 	w1.is_canidate_windfarm = 1
					and		w2.is_canidate_windfarm = 1
				) as min_distance_km_table
		where 	w1.is_canidate_windfarm = 1
		and 	abs(w1.cap_factor_80m - w2.cap_factor_80m) < 0.03
		and		(st_distance_sphere(w1.the_geom, w2.the_geom) / 2.0) / 1000.0 <= min_distance_km
		group by w1.gid, w1.the_geom ) as windfarm_geom_cap_table
where 	intersects(expand(windfarms_canada_info.the_geom, 0.001), windfarm_geom_cap_table.the_geom)
and		expand(windfarms_canada_info.the_geom, 0.001) && windfarm_geom_cap_table.the_geom;

-- export to mysql
COPY 
(select id,
		timestamp_utc,
		cap_factor
from windfarms_canada_hourly_cap_factor
order by id, timestamp_utc)
TO '/Volumes/switch/Models/GIS/Canada_Wind_AWST/windfarms_canada_hourly_cap_factor.csv'
WITH CSV HEADER;

-- -------------------------------------------
-- EXISTING CANADIAN WIND
-- draws on or parallels /Volumes/switch/Models/GIS/Windfarms\ Existing/windfarms\ existing\ import\ north\ america.sql

-- data from http://www.canwea.ca/farms/wind-farms_e.php
-- copied down the info by hand for each windfarm
-- you can get the lat/lon of each windfarm from google maps by 'View Source' in Safari (down near the bottom)
-- a few wind farm lat/lon were approximated by their nearest town
drop table if exists windfarms_canada_existing_info;
create table windfarms_canada_existing_info(
	windfarm_existing_id serial primary key,
	windfarm_name character varying(100),
	latitude double precision,
	longitude double precision,
	total_capacity_mw double precision,
	turbine_capacity_mw double precision,
	number_of_turbines int,
	turbine_manufacturer character varying(50),
	company character varying(50),
	year_online int,
	province char(2),
	landcover_id int,
	windspeed_ratio_to_80m double precision,
	nearest_windpoint_id int,
	hub_height double precision,
	power_curve_turbine_name varchar(64) 
	);

SELECT AddGeometryColumn ('public','windfarms_canada_existing_info','the_geom',4326,'POINT',2);
alter table windfarms_canada_existing_info add constraint unique_name_year_canada UNIQUE (windfarm_name, year_online);
create index power_curve_turbine_name_idx on windfarms_canada_existing_info (power_curve_turbine_name);
create index power_curve_turbine_name_id_idx on windfarms_canada_existing_info (power_curve_turbine_name, windfarm_existing_id);

COPY windfarms_canada_existing_info (windfarm_name, latitude, longitude, total_capacity_mw, turbine_capacity_mw, number_of_turbines,
										turbine_manufacturer, company, year_online, province)
FROM '/Volumes/switch/Models/GIS/Canada_Wind_AWST/AWST_Canada_CapacityFactor_Maps/canada_existing_windfarms.csv'
WITH CSV HEADER;

UPDATE windfarms_canada_existing_info SET the_geom = SETSRID(MakePoint(longitude, latitude),4326);

-- ADD TURBINE HUB HEIGHT
-- this part presumes that turbine info has already been loaded by the script /Volumes/switch/Models/GIS/Windfarms\ Existing/windfarms\ existing\ import\ north\ america.sql

-- even the turbine manufacturer names aren't quite the same so we create a table to match as many as possible here
drop table if exists turbine_manufacturer_matches;
create temporary table turbine_manufacturer_matches as
	select 	distinct windfarms_canada_existing_info.turbine_manufacturer as farm_manufacturer,
			wind_turbine_info.manufacturer as info_manufacturer
	from 	windfarms_canada_existing_info
	join 	wind_turbine_info on (turbine_manufacturer = manufacturer);

insert into turbine_manufacturer_matches values
	('GE', 'GE Energy'),
	('NEG-Micon','Neg Micon'),
	('Lagerway','Lagerwey')
;

-- match turbine manufactures and rated_power_kw to get hub height
-- the rounding is so that if the turbine_capacity_mw value is slightly off, then it still matches
-- because turbines @ or above 300kW only go in steps of minimum 50 kW
-- and ones below (large enough that we care) go in steps of minimum 5kW
-- this can be seen by "select distinct rated_power_kw from wind_turbine_info"
update 	windfarms_canada_existing_info
set 	hub_height = wind_turbine_info.average_hub_height
from 	wind_turbine_info
join 	turbine_manufacturer_matches on (manufacturer = info_manufacturer)
where 	windfarms_canada_existing_info.turbine_manufacturer = turbine_manufacturer_matches.farm_manufacturer
and ( 
		( 50 * round( 20 * windfarms_canada_existing_info.turbine_capacity_mw ) = wind_turbine_info.rated_power_kw and turbine_capacity_mw >= 0.3 )
	OR
		( 5 * round( 200 * windfarms_canada_existing_info.turbine_capacity_mw ) = wind_turbine_info.rated_power_kw and turbine_capacity_mw < 0.3 ) 
	);


-- the above of course didn't match everything
-- but also some turbine models don't have hub height values
-- so we'll have to fill the data in with averages here.
-- the two updates below find the closest value of rated power for which a hub height is listed
-- and then adds that (averaged) value to the table when hub height is null

update 	windfarms_canada_existing_info
set 	hub_height = round(avg_hub_height)
from
	(select turbine_capacity_mw,
			avg_hub_height
	from
		(select turbine_capacity_mw,
				min( abs( turbine_capacity_mw * 1000  - rated_power_kw ) ) as min_kw_diff
		from	windfarms_canada_existing_info,
				(select distinct rated_power_kw as rated_power_kw
				from 	wind_turbine_info
				where 	average_hub_height is not null) as distinct_rated_power_kw_table
		group by turbine_capacity_mw) as  min_kw_diff_table,
		(select rated_power_kw,
				avg(average_hub_height) as avg_hub_height
		from 	wind_turbine_info
		where 	average_hub_height is not null
		group by rated_power_kw) as avg_hub_height_table
	where	min_kw_diff = abs( turbine_capacity_mw * 1000  - rated_power_kw )) as mw_turbine_hub_table
where 	windfarms_canada_existing_info.turbine_capacity_mw = mw_turbine_hub_table.turbine_capacity_mw
and		hub_height is null;

-- MAP TO POWER CURVE
-- above, ~90 turbine power curves were uploaded into the table wind_turbine_power_curves
-- here we match each turbine to one of these power curves (they don't all match exactally, so some will be approximations)
-- there aren't many wind farms, so this was done manually using the sql statements below
-- select distinct turbine_manufacturer, turbine_capacity_mw from windfarms_canada_existing_info order by 1,2;
-- select distinct turbine_name, rated_capacity_mw from wind_turbine_power_curves order by 1

drop table if exists info_power_curve_map;
create temporary table info_power_curve_map (
	info_turbine_manufacturer varchar(50),
	info_turbine_capacity_mw double precision,
	curve_turbine_name varchar(64) );

-- NOTE: some of these turbines don't quite match on rated power
-- we use the rated_capacity_MW values in wind_turbine_power_curves to calculate a capacity factor
-- this capacity factor will be multiplied by the plant size in MW, there by scaling up or down power production
-- in correct porportion if the to rated capacites in this map don't exactally match
insert into info_power_curve_map values
	('Bonus',0.15,'Bonus 300kW Mk II 33m rotor'),
	('Enercon',0.6,'Enercon E48'),
	('Enercon',2.2,'Enercon E70'),
	('Enercon',3,'Enercon E82'),
	('GE',1.5,'GE 1.5s'),
	('GE',1.6,'GE 1.5s'),
	('Kenetech',0.375,'Zond Z-40'),
	('Lagerway',0.75,'Lagerwey LW58 58m rotor'),
	('Leitwind',1.5,'S82 1.5'),
	('NEG-Micon',0.9,'NM 52 900'),
	('Nordex',1.3,'Nordex N60-1300'),
	('Vestas',0.6,'V44-600'),
	('Vestas',0.66,'V47 660'),
	('Vestas',1.8,'V90-1.8'),
	('Vestas',3,'V90-3.0');
	
update windfarms_canada_existing_info
set power_curve_turbine_name = curve_turbine_name
from info_power_curve_map
where info_turbine_manufacturer = turbine_manufacturer
and info_turbine_capacity_mw = turbine_capacity_mw;

-- FIND NEAREST NEIGHBOR

-- we'll find the nearest Canadian windpoint that we've downloaded from AWS truewind.. none of them are too far away from existing sites
update windfarms_canada_existing_info
set nearest_windpoint_id = windpoint_id
	from ( select windfarm_existing_id, id as windpoint_id
			from	windfarms_canada_info,
			(select windfarm_existing_id,
					min( st_distance_sphere(windfarms_canada_info.the_geom, windfarms_canada_existing_info.the_geom) ) as distance_m
				from windfarms_canada_info, windfarms_canada_existing_info
				group by windfarm_existing_id
			) as distance_table			
			join windfarms_canada_existing_info using (windfarm_existing_id)
			where distance_m = st_distance_sphere(windfarms_canada_info.the_geom, windfarms_canada_existing_info.the_geom)
			) as find_nearest_windpoint
	where find_nearest_windpoint.windfarm_existing_id = windfarms_canada_existing_info.windfarm_existing_id;

-- update the land cover type
update windfarms_canada_existing_info
set landcover_id = gridcode
from land_cover_north_america_1km
	where 	intersects(land_cover_north_america_1km.the_geom, windfarms_canada_existing_info.the_geom)
	and		land_cover_north_america_1km.the_geom && windfarms_canada_existing_info.the_geom;

-- make a table of surface roughness vs. land cover type
-- from /Volumes/switch/Models/GIS/Land_Cover/aersurface_userguide.pdf
-- year-averaged because the seasonal variation is minimial for the land cover types we care about for wind
drop table if exists land_cover_to_surface_roughness;
create table land_cover_to_surface_roughness (
	landcover_id int primary key,
	surface_roughness_m double precision );
	
insert into land_cover_to_surface_roughness values
	(0, 0.001),
	(1, 1.3),
	(2, 1.3),
	(3, 0.94),
	(4, 0.94),
	(5, 1.12),
	(6, 0.64),
	(7, 0.18),
	(8, 0.3),
	(9, 0.15),
	(10, 0.053),
	(11, 0.092),
	(12, 0.05),
	(13, 0.08);
	
-- update the ratio between wind speed at 80m and the hub height of the existing wind farm
-- see Masters, "Renewable and Efficient Electric Power Systems" p.319.. gives equation of 
-- (speed_80m / speed_at_hub_height_in_question) = ln(80m / surface_roughness_m) / ln(hub_height_in_question / surface_roughness_m)
update windfarms_canada_existing_info
set windspeed_ratio_to_80m = ln(hub_height / surface_roughness_m) / ln(80 / surface_roughness_m)
from land_cover_to_surface_roughness
where land_cover_to_surface_roughness.landcover_id = windfarms_canada_existing_info.landcover_id;


-----------------------------
-- EXISTING WIND CAP FACTOR
-- some of the columns in this table will be dropped by the end to give a simple cap_factor table
drop table if exists windfarms_canada_existing_cap_factor;
create table windfarms_canada_existing_cap_factor(
	windfarm_existing_id int references windfarms_canada_existing_info (windfarm_existing_id),
	timestamp_utc timestamp,
	speed_m_per_s float,
	cap_factor float,
	PRIMARY KEY (windfarm_existing_id, timestamp_utc) );

create index windfarm_existing_id_idx on windfarms_canada_existing_cap_factor (windfarm_existing_id);
create index timestamp_utc_idx on windfarms_canada_existing_cap_factor (timestamp_utc);
create index speed_m_per_s_idx on windfarms_canada_existing_cap_factor (speed_m_per_s);

-- windspeeds are at 80m, so scale them up or down to hub height here
-- includes all timestamp_utc in the original windfarms_canada_hourly_cap_factor table
-- NOTE: the speed_m_per_s here is density-scaled, whereas it is not in the original table windfarms_canada_hourly_cap_factor
insert into windfarms_canada_existing_cap_factor
    select  windfarms_canada_existing_info.windfarm_existing_id,
            timestamp_utc,
            speed_m_per_s * windspeed_ratio_to_80m * POWER(density_kg_per_m_cubed/1.225, 0.333333333333333) as speed_m_per_s
    from    windfarms_canada_existing_info
    join    windfarms_canada_hourly_cap_factor on (nearest_windpoint_id = id);

-- the cap_factor for any windspeeds above the turbine cutout_speed_m_per_s are zeroed out here
update 	windfarms_canada_existing_cap_factor
set 	cap_factor = 0
from 	wind_turbine_power_curves,
		windfarms_canada_existing_info
where 	turbine_name = power_curve_turbine_name
and 	windfarms_canada_existing_info.windfarm_existing_id = windfarms_canada_existing_cap_factor.windfarm_existing_id
and 	speed_m_per_s >= cutout_speed_m_per_s;
 
-- calculate cap factors
update windfarms_canada_existing_cap_factor
set cap_factor = ( t.reference_power_output_MW + t.slope_to_next_speed_value * (speed_diff) ) / t.rated_capacity_MW
from
	(select windfarm_existing_id,
			timestamp_utc,
			min(speed_m_per_s - wind_turbine_power_curves.reference_speed_m_per_s) as speed_diff
		from 	windfarms_canada_existing_cap_factor
		join	windfarms_canada_existing_info using (windfarm_existing_id)
		join	wind_turbine_power_curves on (turbine_name = power_curve_turbine_name)
		where 	speed_m_per_s - wind_turbine_power_curves.reference_speed_m_per_s > 0
		and 	cap_factor is null
		group by windfarm_existing_id, timestamp_utc ) as speed_diff_table
	join 	windfarms_canada_existing_info using (windfarm_existing_id)
	join 	wind_turbine_power_curves t on (turbine_name = power_curve_turbine_name)
	where	speed_m_per_s - t.reference_speed_m_per_s = speed_diff
	and		speed_diff_table.windfarm_existing_id = windfarms_canada_existing_cap_factor.windfarm_existing_id
	and 	speed_diff_table.timestamp_utc = windfarms_canada_existing_cap_factor.timestamp_utc
	and 	cap_factor is null;


-- export to mysql in the correct format
COPY (	select 	'Wind_EP' as technology,
				CASE WHEN province = 'BC' THEN 'CAN_BC' WHEN province = 'AB' THEN 'CAN_ALB' END as load_area,
				'Wind_EP_Can_' || windfarm_existing_id as plant_name,
				0 as eia_id,
				year_online as start_year,
				'WND' as primemover,
				0 as cogen,
				'Wind' as fuel,
				total_capacity_mw as capacity_MW,
				0 as heat_rate,
				0 as cogen_thermal_demand_mmbtus_per_mwh
		from 	windfarms_canada_existing_info
		order by windfarm_existing_id)
TO '/Volumes/switch/Models/GIS/Canada_Wind_AWST/windfarms_canada_existing_info.csv'
WITH CSV HEADER;

COPY (	select	windfarm_existing_id,
				timestamp_utc as datetime_utc,
				cap_factor
		from	windfarms_canada_existing_cap_factor
		order by windfarm_existing_id, timestamp_utc )
TO '/Volumes/switch/Models/GIS/Canada_Wind_AWST/windfarms_canada_existing_cap_factor.csv'
WITH CSV HEADER;



