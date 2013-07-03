drop table if exists transmission_switch_wecc_bus_map;
create table transmission_switch_wecc_bus_map
	( 	bus_name varchar(30),
		bus_id int,
		load_area varchar(30) REFERENCES wecc_load_areas (load_area) ON UPDATE CASCADE,
		voltage int,
		primary key (bus_id) );
SELECT addgeometrycolumn ('usa_can','transmission_switch_wecc_bus_map','the_geom',4326,'POINT',2);
CREATE INDEX ON transmission_switch_wecc_bus_map USING gist (the_geom);


-- these buses match on bus_id, name, area, and voltage... we know where they are!
-- buses in the e_buses_wecc_2011_point table don't have geometries that are also in the e_substn_point table
-- are quite suspect... I've found a bunch of them to be wrong.  So eliminate them by forcing
-- all e_buses_wecc_2011_point the_geom to existing in e_substn_point... the cast(the_geom) as text speeds the query up
insert into transmission_switch_wecc_bus_map (bus_name, bus_id, load_area, voltage, the_geom)
	select bus_name, bus_id, load_area, voltage, p.the_geom
		from ventyx_may_2012.e_buses_wecc_2011_point p
		join ferc_form_715.area a on (area = area_name)
		join ferc_form_715.bus b using (case_name, bus_name, area_id),
			 wecc_load_areas l
		where st_intersects(p.the_geom, l.polygon_geom)
		and p.the_geom && l.polygon_geom
		and a.case_name = 'WECC_12hs3sap'
		and source != 'Ventyx Research'
		and round(base_voltage) = round(voltage)
		and bus_number = bus_id;


-- don't forget plants off the coast that don't quite intersect with the wecc_load_areas shapefile!
-- give them to the geographically nearest load area
insert into transmission_switch_wecc_bus_map (bus_name, bus_id, load_area, voltage, the_geom)
	select bus_name, bus_id, load_area, voltage, p.the_geom
		from ventyx_may_2012.e_buses_wecc_2011_point p
		join (select bus_number,
					 min(st_distance_spheroid(the_geom, polygon_geom, 'SPHEROID["WGS 84",6378137,298.257223563]')) as min_distance
				from 	ventyx_may_2012.e_buses_wecc_2011_point,
						wecc_load_areas
				where bus_number not in
				(select bus_number
					from ventyx_may_2012.e_buses_wecc_2011_point, wecc_load_areas
					where st_intersects(the_geom, polygon_geom)
					and the_geom && polygon_geom)
					group by bus_number) as min_distance_table
			using (bus_number)
		join ferc_form_715.area a on (area = area_name)
		join ferc_form_715.bus b using (case_name, bus_name, area_id),
			 wecc_load_areas l
	where 	min_distance = st_distance_spheroid(p.the_geom, polygon_geom, 'SPHEROID["WGS 84",6378137,298.257223563]')
	and		a.case_name = 'WECC_12hs3sap'
	and 	source != 'Ventyx Research'
	and 	round(base_voltage) = round(voltage)
	and 	bus_number = bus_id;


-- now get buses that match on bus_id, area, and voltage, but don't completly match on name
-- we only label the load_area of a bus_id if all buses of a certain name type (of left(bus_name))
-- are within the same load_area (the large subselect left(p.bus_name,current_length))
-- and that the name type matches between ventyx and ferc

-- 1
CREATE OR REPLACE FUNCTION length_loop1() RETURNS VOID AS $$

DECLARE current_length int;
BEGIN
select 8 into current_length;

WHILE ( ( select current_length ) >= 1 ) LOOP

-- we get the best matches first by starting at length=8 (the longest full name length is 8)
-- and then go down from there to get other matches
insert into transmission_switch_wecc_bus_map (bus_name, bus_id, load_area, voltage, the_geom)
	select b.bus_name, bus_id, load_area, base_voltage, p.the_geom
			from ventyx_may_2012.e_buses_wecc_2011_point p
			join ferc_form_715.area a on (area = area_name)
			join ferc_form_715.bus b using (case_name, area_id),
				 wecc_load_areas l,
			 	 ( select distinct the_geom from ventyx_may_2012.e_substn_point) s
			where st_intersects(p.the_geom, l.polygon_geom)
			and p.the_geom && l.polygon_geom
			and cast(p.the_geom as text) = cast(s.the_geom as text)
			and a.case_name = 'WECC_12hs3sap'
			and source != 'Ventyx Research'
			and round(base_voltage) = round(voltage)
			and bus_number = bus_id
			and bus_id not in (select bus_id from transmission_switch_wecc_bus_map)
			and left(p.bus_name,current_length) = left(b.bus_name,current_length)
			and left(p.bus_name,current_length) in 
				(select left_bus_name from
					(select left_bus_name, count(*) as cnt from
						(select distinct left(p.bus_name,current_length) as left_bus_name, area_id
							from ventyx_may_2012.e_buses_wecc_2011_point p, wecc_load_areas l
							where st_intersects(p.the_geom, l.polygon_geom)
							and p.the_geom && l.polygon_geom
							group by left_bus_name, area_id) as distinct_name_la_table
					group by left_bus_name
					) as count_table
				where cnt = 1);

select current_length - 1 into current_length;
END LOOP;

END; $$ LANGUAGE 'plpgsql';

-- Actually call the function
SELECT length_loop1();
drop function length_loop1();


-- create table of unmatched ferc buses to help matches from here on
drop table if exists unmatched_wecc_buses;
create table unmatched_wecc_buses as 
	select bus_id, bus_name, area_name, zone_name, base_voltage, area_id, zone_id
	from ferc_form_715.bus join ferc_form_715.area using (case_name, area_id) join ferc_form_715.zone using (case_name, zone_id)
	where case_name = 'WECC_12hs3sap'
	and bus_id not in (select distinct bus_id from transmission_switch_wecc_bus_map)
	order by base_voltage, area_id desc;



-- transformer and transmission line matches loop!
CREATE OR REPLACE FUNCTION transformtransmit_loop_wecc() RETURNS VOID AS $$

DECLARE num_unmatched_buses_current_iteration int;
DECLARE num_unmatched_buses_previous_iteration int;
BEGIN
-- the zero here is a dummy value so it doesn't exit the loop before it starts
select 0 into num_unmatched_buses_current_iteration;
select count(*) from unmatched_wecc_buses into num_unmatched_buses_previous_iteration;

-- exit the loop once we're not finding any more matches
WHILE ( ( select num_unmatched_buses_current_iteration != num_unmatched_buses_previous_iteration) ) LOOP

		select count(*) from unmatched_wecc_buses into num_unmatched_buses_previous_iteration;
		
		-- TRANSFORMER MATCHES
		-- tap the transformer table to tell us where a lot of as of yet unlocated buses are
		-- if a bus is connected via transformer to another bus, both buses will have the same load_area
		
		-- ventyx has given a few buses that are at the same substation incorrect and different geoms
		-- not really a big deal - they seem to be somewhat close, but it makes it so we have to add max() to everything
		-- as to not hit to pkey on the transmission_switch_wecc_bus_map table
		insert into transmission_switch_wecc_bus_map (bus_name, bus_id, load_area, voltage, the_geom)
			select max(u.bus_name), u.bus_id, load_area, max(u.base_voltage), max(the_geom)
			from ferc_form_715.transformer
			join transmission_switch_wecc_bus_map p on (bus_id_1 = p.bus_id)
			join unmatched_wecc_buses u on (bus_id_2 = u.bus_id)
			and case_name = 'WECC_12hs3sap'
			group by u.bus_id, load_area;
		
		delete from unmatched_wecc_buses where bus_id in (select bus_id from transmission_switch_wecc_bus_map);
		
		insert into transmission_switch_wecc_bus_map (bus_name, bus_id, load_area, voltage, the_geom)
			select max(u.bus_name), u.bus_id, load_area, max(u.base_voltage), max(the_geom)
			from ferc_form_715.transformer
			join transmission_switch_wecc_bus_map p on (bus_id_1 = p.bus_id)
			join unmatched_wecc_buses u on (bus_id_3 = u.bus_id)
			and case_name = 'WECC_12hs3sap'
			group by u.bus_id, load_area;
		
		delete from unmatched_wecc_buses where bus_id in (select bus_id from transmission_switch_wecc_bus_map);
		
		insert into transmission_switch_wecc_bus_map (bus_name, bus_id, load_area, voltage, the_geom)
			select max(u.bus_name), u.bus_id, load_area, max(u.base_voltage), max(the_geom)
			from ferc_form_715.transformer
			join transmission_switch_wecc_bus_map p on (bus_id_2 = p.bus_id)
			join unmatched_wecc_buses u on (bus_id_1 = u.bus_id)
			and case_name = 'WECC_12hs3sap'
			group by u.bus_id, load_area;
		
		delete from unmatched_wecc_buses where bus_id in (select bus_id from transmission_switch_wecc_bus_map);
		
		insert into transmission_switch_wecc_bus_map (bus_name, bus_id, load_area, voltage, the_geom)
			select max(u.bus_name), u.bus_id, load_area, max(u.base_voltage), max(the_geom)
			from ferc_form_715.transformer
			join transmission_switch_wecc_bus_map p on (bus_id_2 = p.bus_id)
			join unmatched_wecc_buses u on (bus_id_3 = u.bus_id)
			and case_name = 'WECC_12hs3sap'
			group by u.bus_id, load_area;
		
		delete from unmatched_wecc_buses where bus_id in (select bus_id from transmission_switch_wecc_bus_map);
		
		insert into transmission_switch_wecc_bus_map (bus_name, bus_id, load_area, voltage, the_geom)
			select max(u.bus_name), u.bus_id, load_area, max(u.base_voltage), max(the_geom)
			from ferc_form_715.transformer
			join transmission_switch_wecc_bus_map p on (bus_id_3 = p.bus_id)
			join unmatched_wecc_buses u on (bus_id_1 = u.bus_id)
			and case_name = 'WECC_12hs3sap'
			group by u.bus_id, load_area;
		
		delete from unmatched_wecc_buses where bus_id in (select bus_id from transmission_switch_wecc_bus_map);
		
		insert into transmission_switch_wecc_bus_map (bus_name, bus_id, load_area, voltage, the_geom)
			select max(u.bus_name), u.bus_id, load_area, max(u.base_voltage), max(the_geom)
			from ferc_form_715.transformer
			join transmission_switch_wecc_bus_map p on (bus_id_3 = p.bus_id)
			join unmatched_wecc_buses u on (bus_id_2 = u.bus_id)
			and case_name = 'WECC_12hs3sap'
			group by u.bus_id, load_area;
		
		delete from unmatched_wecc_buses where bus_id in (select bus_id from transmission_switch_wecc_bus_map);
		
		-- TRANSMISSION LINE MATCHES
		-- now use transmission lines to locate buses in load areas.
		-- if an unmatched bus is connected to lines that are all in the same load area,
		-- then label the unmatched bus that load area
		-- this should work well because load areas are designed to not have radial or spur lines across borders
		-- we don't get a geom out of this because we don't know the site of the bus anymore :-(
		
		-- note that here UNION actually functions as 'select distinct' as it eliminates duplicates
		insert into transmission_switch_wecc_bus_map (bus_name, bus_id, load_area, voltage, the_geom)
			select bus_name, bus_id, load_area, base_voltage, null
		 		from unmatched_wecc_buses
		 	join (
					select u.bus_id, load_area
						from ferc_form_715.branch
						join unmatched_wecc_buses u on (to_bus_id = u.bus_id)
						join transmission_switch_wecc_bus_map p on (from_bus_id = p.bus_id)
						where case_name = 'WECC_12hs3sap'
					UNION 
					select u.bus_id, load_area
						from ferc_form_715.branch
						join unmatched_wecc_buses u on (from_bus_id = u.bus_id)
						join transmission_switch_wecc_bus_map p on (to_bus_id = p.bus_id)
						where case_name = 'WECC_12hs3sap'
				) as bus_area_table
		 using (bus_id)
		where bus_id in (
				select bus_id from (
					select bus_id, count(*) as cnt
						from (
							select u.bus_id, load_area
								from ferc_form_715.branch
								join unmatched_wecc_buses u on (to_bus_id = u.bus_id)
								join transmission_switch_wecc_bus_map p on (from_bus_id = p.bus_id)
								where case_name = 'WECC_12hs3sap'
							UNION 
							select u.bus_id, load_area
								from ferc_form_715.branch
								join unmatched_wecc_buses u on (from_bus_id = u.bus_id)
								join transmission_switch_wecc_bus_map p on (to_bus_id = p.bus_id)
								where case_name = 'WECC_12hs3sap'
						) as bus_area_table
					group by bus_id
					) as count_table
				where cnt = 1
		);
		
		delete from unmatched_wecc_buses where bus_id in (select bus_id from transmission_switch_wecc_bus_map);
		
		select count(*) from unmatched_wecc_buses into num_unmatched_buses_current_iteration;
		
END LOOP;

END; $$ LANGUAGE 'plpgsql';

-- Actually call the function
SELECT transformtransmit_loop_wecc();


-- now that we've done pretty much everything we can to locate buses,
-- we go back and dig into buses that have been geolocated by the dubious 'Ventyx Research' category
insert into transmission_switch_wecc_bus_map (bus_name, bus_id, load_area, voltage, the_geom)
	select bus_name, bus_id, load_area, voltage, p.the_geom
		from ventyx_may_2012.e_buses_wecc_2011_point p
		join ferc_form_715.area a on (area = area_name)
		join ferc_form_715.bus b using (case_name, bus_name, area_id),
			 wecc_load_areas l
		where st_intersects(p.the_geom, l.polygon_geom)
		and p.the_geom && l.polygon_geom
		and a.case_name = 'WECC_12hs3sap'
		and round(base_voltage) = round(voltage)
		and bus_number = bus_id
		and bus_id in (select bus_id from unmatched_wecc_buses);

delete from unmatched_wecc_buses where bus_id in (select bus_id from transmission_switch_wecc_bus_map);

-- go after the_geom of buses that haven't yet had one assigned
-- we're not going to get them all because ventyx hasn't mapped them all, but we can get most here
update transmission_switch_wecc_bus_map w
set the_geom = l.the_geom from 
	(select bus_name, bus_number as bus_id, load_area, round(voltage) as voltage, the_geom
		from ventyx_may_2012.e_buses_wecc_2011_point p,
			 wecc_load_areas l
		where st_intersects(p.the_geom, l.polygon_geom)
		and p.the_geom && l.polygon_geom
		and source = 'Ventyx Research') l
where w.bus_name = l.bus_name
and w.bus_id = l.bus_id
and w.load_area = l.load_area
and w.voltage = l.voltage
and w.the_geom is null;

update transmission_switch_wecc_bus_map w
set the_geom = t.the_geom
from	(select p1.bus_id, p2.the_geom
			from ferc_form_715.transformer
			join transmission_switch_wecc_bus_map p1 on (bus_id_1 = p1.bus_id)
			join transmission_switch_wecc_bus_map p2 on (bus_id_2 = p2.bus_id)
			where case_name = 'WECC_12hs3sap'
			and p1.the_geom is null
			and p2.the_geom is not null) t
where t.bus_id = w.bus_id;

update transmission_switch_wecc_bus_map w
set the_geom = t.the_geom
from	(select p1.bus_id, p2.the_geom
			from ferc_form_715.transformer
			join transmission_switch_wecc_bus_map p1 on (bus_id_1 = p1.bus_id)
			join transmission_switch_wecc_bus_map p2 on (bus_id_3 = p2.bus_id)
			where case_name = 'WECC_12hs3sap'
			and p1.the_geom is null
			and p2.the_geom is not null) t
where t.bus_id = w.bus_id;

update transmission_switch_wecc_bus_map w
set the_geom = t.the_geom
from	(select p1.bus_id, p2.the_geom
			from ferc_form_715.transformer
			join transmission_switch_wecc_bus_map p1 on (bus_id_2 = p1.bus_id)
			join transmission_switch_wecc_bus_map p2 on (bus_id_1 = p2.bus_id)
			where case_name = 'WECC_12hs3sap'
			and p1.the_geom is null
			and p2.the_geom is not null) t
where t.bus_id = w.bus_id;

update transmission_switch_wecc_bus_map w
set the_geom = t.the_geom
from	(select p1.bus_id, p2.the_geom
			from ferc_form_715.transformer
			join transmission_switch_wecc_bus_map p1 on (bus_id_2 = p1.bus_id)
			join transmission_switch_wecc_bus_map p2 on (bus_id_3 = p2.bus_id)
			where case_name = 'WECC_12hs3sap'
			and p1.the_geom is null
			and p2.the_geom is not null) t
where t.bus_id = w.bus_id;

update transmission_switch_wecc_bus_map w
set the_geom = t.the_geom
from	(select p1.bus_id, p2.the_geom
			from ferc_form_715.transformer
			join transmission_switch_wecc_bus_map p1 on (bus_id_3 = p1.bus_id)
			join transmission_switch_wecc_bus_map p2 on (bus_id_1 = p2.bus_id)
			where case_name = 'WECC_12hs3sap'
			and p1.the_geom is null
			and p2.the_geom is not null) t
where t.bus_id = w.bus_id;

update transmission_switch_wecc_bus_map w
set the_geom = t.the_geom
from	(select p1.bus_id, p2.the_geom
			from ferc_form_715.transformer
			join transmission_switch_wecc_bus_map p1 on (bus_id_3 = p1.bus_id)
			join transmission_switch_wecc_bus_map p2 on (bus_id_2 = p2.bus_id)
			where case_name = 'WECC_12hs3sap'
			and p1.the_geom is null
			and p2.the_geom is not null) t
where t.bus_id = w.bus_id;



-- get geometries by matching names in the same load area... these will almost always be the same substation
CREATE OR REPLACE FUNCTION length_loop2() RETURNS VOID AS $$

DECLARE current_length int;
BEGIN
select 8 into current_length;

WHILE ( ( select current_length ) >= 5 ) LOOP

-- we get the best matches first by starting at length=8 (the longest full name length is 8)
-- and then go down from there to get other matches
update transmission_switch_wecc_bus_map p1
	set the_geom = p2.the_geom
	from transmission_switch_wecc_bus_map p2
	where p1.load_area = p2.load_area
	and p1.the_geom is null
	and p2.the_geom is not null
	and left(p1.bus_name, current_length) = left(p2.bus_name, current_length);


select current_length - 1 into current_length;
END LOOP;

END; $$ LANGUAGE 'plpgsql';

-- Actually call the function
SELECT length_loop2();
drop function length_loop2();

-- don't add the load_area... will be added at the end for all rouge bus matches for simplicity
insert into transmission_switch_wecc_bus_map (bus_name, bus_id, voltage, the_geom)
	select bus_name, bus_id, base_voltage, the_geom
		from (select the_geom from transmission_switch_wecc_bus_map where bus_name = 'NAVAJO' and voltage = 500) t,
		unmatched_wecc_buses where bus_name like 'NAVAJO%'
	UNION
	select bus_name, bus_id, base_voltage, the_geom
		from (select the_geom from transmission_switch_wecc_bus_map where bus_name = 'SAN_JUAN' and voltage = 345) t, 
		unmatched_wecc_buses where bus_name like 'SAN_JU%'
	UNION
	select bus_name, bus_id, base_voltage, the_geom
		from (select the_geom from transmission_switch_wecc_bus_map where bus_name = 'FOURCORN' and voltage = 500) t, 
		unmatched_wecc_buses where bus_name like 'FOURCO%'
	UNION
	select bus_name, bus_id, base_voltage, the_geom
		from (select the_geom from transmission_switch_wecc_bus_map where bus_name = 'YAVAPAI' and voltage = 500) t,
		unmatched_wecc_buses where bus_name like 'YAVAP%'
	UNION
	select bus_name, bus_id, base_voltage, the_geom
		from (select the_geom from transmission_switch_wecc_bus_map where bus_name = 'FLAGSTAF' and voltage = 345) t,
		unmatched_wecc_buses where bus_name like 'FLAGST%'
	UNION
	select bus_name, bus_id, base_voltage, the_geom
		from (select the_geom from transmission_switch_wecc_bus_map where bus_name = 'MAPLE VL' and voltage = 500) t,
		unmatched_wecc_buses where bus_name = 'MAPLE &1'
	UNION
	select bus_name, bus_id, base_voltage, the_geom
		from (select the_geom from transmission_switch_wecc_bus_map where bus_name = 'RIDDLE' and bus_id = 44992) t,
		unmatched_wecc_buses where bus_name = 'RIDDLE'
	UNION
	select bus_name, bus_id, base_voltage, the_geom
		from (select the_geom from transmission_switch_wecc_bus_map where bus_name = 'ABEL') t,
		unmatched_wecc_buses where bus_name = 'ABEL'
	UNION
	select bus_name, bus_id, base_voltage, the_geom
		from (select the_geom from transmission_switch_wecc_bus_map where bus_name = 'GRAMERCY') t,
		unmatched_wecc_buses where bus_name like 'GRAMER%'
	UNION
	select bus_name, bus_id, base_voltage, the_geom
		from (select the_geom from transmission_switch_wecc_bus_map where bus_name = 'RINALDI' AND voltage = 500) t,
		unmatched_wecc_buses where bus_name like 'RINALD%'
	UNION
	select bus_name, bus_id, base_voltage, the_geom
		from (select the_geom from transmission_switch_wecc_bus_map where bus_name = 'LODHLM') t,
		unmatched_wecc_buses where bus_name like 'LODHLM%'
	UNION
	select bus_name, bus_id, base_voltage, the_geom
		from (select the_geom from transmission_switch_wecc_bus_map where bus_name = 'COLRPLJE' and voltage = 161) t,
		unmatched_wecc_buses where bus_name = 'CHAFINCK'
	;

insert into transmission_switch_wecc_bus_map (bus_name, bus_id, load_area, voltage)
	select bus_name, bus_id, 'CA_SCE_S' as load_area, base_voltage
		from unmatched_wecc_buses where ( bus_name like 'TAP%' or bus_name = 'MENTONE')
	;


delete from unmatched_wecc_buses where bus_id in (select bus_id from transmission_switch_wecc_bus_map);



-- ventyx appears to have labeled a few buses in the same substation wrong
-- ... give them all the same geom here using the primary bus for each substation
-- give important substations geometries so we can visualize important lines
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from transmission_switch_wecc_bus_map where bus_name = 'MALIN' and voltage = 500) t
	where bus_name like 'MALIN%' ;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from transmission_switch_wecc_bus_map where bus_name = 'GRIZZLY' and voltage = 500) t
	where bus_name like 'GRIZZL&%' ;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from transmission_switch_wecc_bus_map where bus_name = 'LUGO' and voltage = 500) t
	where bus_name like 'LUGO%' ;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from transmission_switch_wecc_bus_map where bus_name = 'NAVAJO' and voltage = 500) t
	where bus_name like 'NAVAJO&%' ;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'DUGAS' and voltage = 500) t
	where bus_name like 'DUGAS%' ;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from transmission_switch_wecc_bus_map where bus_name = 'MOENKOPI' and voltage = 500) t
	where bus_name like 'MOENKO&%' ;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from transmission_switch_wecc_bus_map where bus_name = 'FLAGSTAF' and voltage = 345) t
	where bus_name like 'FLAGST&%' ;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'RANDOLPH' and voltage = 230) t
	where bus_name = 'RANDOLPH' and voltage = 230 ;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'SAN_JUAN' and voltage = 230) t
	where bus_name like 'SAN_JU%' ;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'PINALWES') t
	where bus_name = 'PINALW&1' ;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'GRAMERCY') t
	where bus_name like 'GRAMER%' ;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'ELDORDO' and voltage = 500) t
	where bus_name like 'ELDORD%' ;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from transmission_switch_wecc_bus_map where bus_name = 'HARBOR' and voltage = 230) t
	where bus_name = 'HARBOR&1' and voltage = 138;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from transmission_switch_wecc_bus_map where bus_name = 'RINALDI' and voltage = 230) t
	where bus_name like 'RINALD%' ;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from transmission_switch_wecc_bus_map where bus_name = 'MCCULLGH' and voltage = 500) t
	where bus_name like 'MCCULL%' and voltage >= 230;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from transmission_switch_wecc_bus_map where bus_name = 'CAMANCHE' and voltage = 115) t
	where bus_name like 'CAMANC%';
update transmission_switch_wecc_bus_map
	set the_geom = null
	where bus_name = 'DIXON LD';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from transmission_switch_wecc_bus_map where bus_name = 'BRKR SLG') t
	where bus_name like 'BRKR%';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from transmission_switch_wecc_bus_map where bus_name = 'BERNARDO' and voltage = 115) t
	where bus_name like 'BERNAR%' and voltage = 115;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'N.GUNNSN') t
	where bus_name = 'N.GUNNSN';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'BASALT' and voltage = 230) t
	where bus_name = 'BASLTDST';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'BLENDE') t
	where bus_name = 'BLENDE';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_substn_point where name = 'Populus') t
	where bus_name like 'POPULU%';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'CLIN WT') t
	where bus_name = 'CLINTONU';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'WASHAKIE' and voltage = 138) t
	where bus_name like 'WASHAK%';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'PAN JCT') t
	where bus_name = 'PAN JCT';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'PANATP') t
	where bus_name = 'PANATP';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'PANORAMA' and voltage = 69) t
	where bus_name = 'PANORAMA' and voltage = 69;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'RCLF-WSH') t
	where bus_name = 'RCLF-WSH';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'AMOCO') t
	where bus_name in ('AMOCO', 'AMOCOTP');
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'LATHAM' and voltage = 230) t
	where bus_id in (67499, 67574);
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'BGTMBERA') t
	where bus_name = 'CHAFINCK';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'ADEL') t
	where bus_name = 'ADEL-SIE';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'RATTLE S' and voltage = 161) t
	where bus_name = 'BONNERMT';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from transmission_switch_wecc_bus_map where bus_name = 'MIDPOINT' and voltage = 500) t
	where bus_name = 'MIDPOI&1';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_substn_point where name = 'Hemingway' and mx_volt_kv = 500) t
	where bus_name = 'HEMINWAY';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'MT HOME' and voltage = 138) t
	where bus_name like 'MT HOM%';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'L MALAD' and voltage = 138) t
	where bus_name like 'L MALA%';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'BERNE') t
	where bus_name = 'BERNE';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'COLESCRN') t
	where bus_name = 'COLESCRN';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'ROZA M') t
	where bus_name like 'ROZA%';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_substn_point where name = 'Buckley' and mx_volt_kv = 55) t
	where bus_name = 'BUCKLEY' and voltage < 100;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_substn_point where name = 'Wilkeson' and mx_volt_kv = 55) t
	where bus_name = 'WILKNSON' and voltage < 100;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'OSTRNDER') t
	where bus_name like 'OSTRND%';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'HAUSER' and voltage = 115) t
	where bus_name = 'HAUSER' and voltage = 115;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'N BONNVL') t
	where bus_name = 'NBONVL E';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'CAPTJACK') t
	where bus_name like 'CAPTJA%';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'ASHE' and voltage = 500) t
	where bus_name like 'ASHE R%' and voltage = 500;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'HIDEDCT1') t
	where bus_name = 'HIDESERT' and voltage = 230;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'N.ST_SW') t
	where bus_name = 'NEWARKS';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_substn_point where name = 'Dixon Landing') t
	where bus_name = 'DIXON LD';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'SANRAMON' and voltage = 230) t
	where bus_name = 'SRRC JCT';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_substn_point where name = 'San Ramon Research Center') t
	where bus_name = 'RESEARCH' and voltage = 230;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'SFWY_TP1') t
	where bus_name = 'SFWY_TP1';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'PALMVLY' and voltage = 230) t
	where bus_name = 'PALMVLY' and voltage = 230;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'BRUSHTAP') t
	where bus_name IN ('B.CK TRI', 'B.CRK_PS', 'BEAVERCK');
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'WALA AVA') t
	where bus_name = 'TALBOT' ANd voltage = 230;	
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_substn_point where name = 'Swift Tap (Woodland Tap)') t
	where bus_name = 'WOODLAND' and voltage = 230;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'LONGVIEW' and voltage = 230) t
	where bus_name like 'LONGVAN%';
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'RAVER' and voltage = 500) t
	where bus_name like 'RAVER%' AND voltage = 500;
update transmission_switch_wecc_bus_map
	set the_geom = t.the_geom
 	from 	(select the_geom from ventyx_may_2012.e_buses_wecc_2011_point where bus_name = 'NORTHMTN' and voltage = 230) t
	where bus_name like 'NORTHM&%' AND voltage = 230;



	
update transmission_switch_wecc_bus_map
	set load_area = 'CA_SCE_CEN'
	where bus_name in ('HLTAP &1', 'HLTAP', 'HLAKE');
update transmission_switch_wecc_bus_map
	set the_geom = null, load_area = 'NV_N'
	where bus_name in ('BRDRTWN', 'BRDRTNPS');
update transmission_switch_wecc_bus_map
	set the_geom = null, load_area = 'CO_NW'
	where bus_name = 'NORTH PA';
update transmission_switch_wecc_bus_map
	set the_geom = null, load_area = 'CO_E'
	where bus_name = 'READER';
update transmission_switch_wecc_bus_map
	set the_geom = null, load_area = 'CO_DEN'
	where bus_name in ('LOSTCKTP', 'LOST CK');	
update transmission_switch_wecc_bus_map
	set the_geom = null, load_area = 'MT_SW'
	where bus_name in ('BUT CONC', 'BUTECORA', 'BTMINDPK', 'RAMSAYPM', 'MONT ST', 'MONST TP', 'BUTECRSH');
update transmission_switch_wecc_bus_map
	set the_geom = null, load_area = 'OR_W'
	where bus_name like 'ELMA%' and voltage < 100;
update transmission_switch_wecc_bus_map
	set the_geom = null, load_area = 'OR_PDX'
	where bus_name in ('ALDRWOOD', 'KLNGSWTH') and voltage = 69;

update transmission_switch_wecc_bus_map
	set the_geom = null, load_area = 'WA_SEATAC'
	where bus_name in ('CRESCNT1', 'CRESENT', 'FREDRICK', 'FREDERC2', 'FREDERC1', 'FRDRKSN2', 'FRED TAP', 'FRDRKSN1', 'FRDRKSNT', 'FRDRKSN', 'BOE_PUY', 'SW28TIE', 'SPANAWAY', 'KNOBLE', 'KNOBLEP')
	AND voltage = 115 or voltage = round(13.8);
update transmission_switch_wecc_bus_map
	set the_geom = null, load_area = 'WA_W'
	where bus_name in ('GIGHBR-1', 'GIGHBR-2', 'GIGHBR', 'ARTNDL-1', 'ARTNDL-2', 'NARROWS1', 'NARROWS2', 'NARROWST')
	AND voltage = 115;	

-- ventyx data is especially bad for oregon 115kv lines
-- any buses that aren't matched by now aren't reliable at all and will be excluded
delete from transmission_switch_wecc_bus_map
	where voltage = 115 and load_area in ('OR_W', 'OR_PDX')
	and bus_name in ('JASPER', 'MT VERN', 'OLYMPC S', 'GATEWAYS', 'GATEWY T', 'SPRING B', 'TENTH ST', 'ALVEY', 'LAURA', 'MT VER T', 'MCKENZEW', 'KNAPPA', 'FERN HIL', 'RIDDLE')
;



-- we updated a bunch of the_geom above but didn't get the load area.... do an intersection to get the load area
UPDATE transmission_switch_wecc_bus_map t
SET load_area = CASE WHEN the_geom IS NULL THEN t.load_area ELSE w.load_area END
FROM wecc_load_areas w
WHERE ST_Intersects(polygon_geom, the_geom);



	
-- check table:
-- makes straightline geomtries of the FERC lines that we're modeling using ventyx substation data
-- can't pull the full transmission line geometry easily as the network connectivity of ventyx data is subpar vs ferc
drop table if exists trans_wecc_ferc_ventyx;
create table trans_wecc_ferc_ventyx (
	load_area_start varchar(30) REFERENCES wecc_load_areas (load_area) ON UPDATE CASCADE,
	load_area_end varchar(30) REFERENCES wecc_load_areas (load_area) ON UPDATE CASCADE,
	voltage int,
	rating_mva int,
	from_bus_id int,
	to_bus_id int,
	from_bus_name varchar(12),
	to_bus_name varchar(12),
	circuit varchar(2),
	interconnect varchar(12),
	straightline_length_km int,
	primary key (from_bus_id, to_bus_id, circuit, interconnect)
	);

SELECT addgeometrycolumn ('usa_can','trans_wecc_ferc_ventyx','straightline_geom',4326,'LINESTRING',2);

insert into trans_wecc_ferc_ventyx ( load_area_start, load_area_end, voltage, rating_mva,
											from_bus_id, to_bus_id, from_bus_name, to_bus_name,
											circuit, interconnect, straightline_length_km, straightline_geom)
select 	m1.load_area as load_area_start,
		m2.load_area as load_area_end,
		m1.voltage,
		round(rating_one_mva) as rating_mva,
		from_bus_id,
		to_bus_id,
		m1.bus_name as from_bus_name,
		m2.bus_name as to_bus_name,	
		circuit,
		'WECC' as interconnect,
		st_distance_spheroid(m1.the_geom, m2.the_geom, 'SPHEROID["WGS 84",6378137,298.257223563]')/1000 as straightline_length_km,
		st_makeline(m1.the_geom, m2.the_geom) as straightline_geom
	from 	ferc_form_715.branch
	join	transmission_switch_wecc_bus_map m1 on (from_bus_id = m1.bus_id)
	join	transmission_switch_wecc_bus_map m2 on (to_bus_id = m2.bus_id)
	where	m1.load_area <> m2.load_area
	and 	case_name = 'WECC_12hs3sap'
	and 	status = 1
	and 	m1.voltage > 10;