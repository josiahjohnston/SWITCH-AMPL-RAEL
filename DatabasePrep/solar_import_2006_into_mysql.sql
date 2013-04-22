use switch_inputs_wecc_v2_2;

-- ---------------------------------------------------------------------
-- PROPOSED PROJECTS--------------
-- imported from postgresql, this table has all pv and csp sites
-- ---------------------------------------------------------------------

drop table if exists _proposed_projects_v3;
CREATE TABLE _proposed_projects_v3 (
  project_id int unsigned default NULL,
  gen_info_project_id mediumint unsigned PRIMARY KEY AUTO_INCREMENT,
  technology_id tinyint unsigned NOT NULL,
  area_id smallint unsigned NOT NULL,
  location_id INT DEFAULT NULL,
  ep_project_replacement_id INT DEFAULT NULL,
  technology varchar(64),
  original_dataset_id INT DEFAULT NULL,
  capacity_limit float DEFAULT NULL,
  capacity_limit_conversion float DEFAULT NULL,
  connect_cost_per_mw float,
  heat_rate float default 0,
  cogen_thermal_demand float default 0,
  avg_cap_factor_intermittent float default NULL,
  avg_cap_factor_percentile_by_intermittent_tech float default NULL,
  cumulative_avg_MW_tech_load_area float default NULL,
  rank_by_tech_in_load_area int default NULL,
  INDEX project_id (project_id),
  INDEX area_id (area_id),
  INDEX technology_and_location (technology, location_id),
  INDEX technology_id (technology_id),
  INDEX location_id (location_id),
  INDEX original_dataset_id (original_dataset_id),
  INDEX original_dataset_id_tech_id (original_dataset_id, technology_id),
  INDEX avg_cap_factor_percentile_by_intermittent_tech_idx (avg_cap_factor_percentile_by_intermittent_tech),
  INDEX rank_by_tech_in_load_area_idx (rank_by_tech_in_load_area),
  UNIQUE (technology_id, original_dataset_id, area_id),
  UNIQUE (technology_id, location_id, ep_project_replacement_id, area_id)
) ROW_FORMAT=FIXED;

DROP VIEW IF EXISTS proposed_projects_v3;
CREATE VIEW proposed_projects_v3 as
  SELECT 	project_id, 
            gen_info_project_id,
            technology_id, 
            technology, 
            area_id, 
            load_area,
            location_id,
            ep_project_replacement_id,
            original_dataset_id, 
            capacity_limit, 
            capacity_limit_conversion, 
            connect_cost_per_mw,
            heat_rate,
            cogen_thermal_demand,
            avg_cap_factor_intermittent,
            avg_cap_factor_percentile_by_intermittent_tech,
            cumulative_avg_MW_tech_load_area,
            rank_by_tech_in_load_area
    FROM _proposed_projects_v3
    join load_area_info using (area_id);
    

-- everything in proposed projects stays the same except for solar, so insert everything else from _proposed_projects_v2 first!
INSERT INTO _proposed_projects_v3
	SELECT * FROM _proposed_projects_v2
	WHERE technology_id NOT IN (select distinct technology_id from generator_info_v2 where fuel = 'Solar')






---------------------------------------------------------------------
-- CAP FACTOR-----------------
-- assembles the hourly power output for wind and solar technologies
-- indicies and primary key will be added later to speed up import
drop table if exists _cap_factor_intermittent_sites_v2;
create table _cap_factor_intermittent_sites_v2(
	project_id int unsigned,
	hour smallint unsigned,
	cap_factor float
);


DROP VIEW IF EXISTS cap_factor_intermittent_sites;
CREATE VIEW cap_factor_intermittent_sites as
  SELECT 	cp.project_id,
  			technology,
  			load_area_info.area_id,
  			load_area,
  			location_id,
  			original_dataset_id,
  			hour,
  			cap_factor
    FROM _cap_factor_intermittent_sites_v2 cp
    join proposed_projects_v3 using (project_id)
    join load_area_info using (load_area);

-- doing this insert to _cap_factor_intermittent_sites_v2 BEFORE adding solar projects to _proposed_projects_v3
-- makes it such that we DON't insert solar cap factors from the old table (this is what we want)
INSERT INTO _cap_factor_intermittent_sites_v2
	SELECT project_id,hour,cap_factor   FROM _cap_factor_intermittent_sites
	JOIN _proposed_projects_v3 USING (project_id); 

 -- add solar cap factors that have been prepared in postgresql
load data local infile
	'/Volumes/switch/Models/USA_CAN/Solar/Mysql/solar_hourly_timeseries.csv'
	into table _cap_factor_intermittent_sites_v2
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;	


CREATE INDEX project_id ON _cap_factor_intermittent_sites_v2 (project_id);
CREATE INDEX hour ON _cap_factor_intermittent_sites_v2 (hour);
ALTER TABLE _cap_factor_intermittent_sites_v2 ADD PRIMARY KEY (project_id, hour);


-- SOLAR!
drop table if exists proposed_projects_solar_import;
create table proposed_projects_solar_import(
	project_id bigint PRIMARY KEY,
	technology varchar(30),
	original_dataset_id integer NOT NULL,
	load_area varchar(11),
	capacity_limit float,
 	capacity_limit_conversion float,
	connect_cost_per_mw double,
	location_id INT,
	avg_capacity_factor double,
	INDEX project_id (project_id),
	INDEX load_area (load_area),
	UNIQUE (technology, location_id, load_area)
);
	
load data local infile
	'/Volumes/switch/Models/USA_CAN/Solar/Mysql/proposed_projects_solar_update.csv'
	into table proposed_projects_solar_import
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;	

-- the capacity limit is either in MW if the capacity_limit_conversion is 1, or in other units if the capacity_limit_conversion is nonzero
-- so for CSP and central PV the limit is expressed in land area, not MW
insert into _proposed_projects_v3
	(project_id, gen_info_project_id, technology_id, technology, area_id, location_id, original_dataset_id,
	capacity_limit, capacity_limit_conversion, connect_cost_per_mw, avg_cap_factor_intermittent )
	select  project_id as project_id,
	        project_id as gen_info_project_id,
	        technology_id,
	        technology,
			area_id,
			location_id,
			original_dataset_id,
			capacity_limit,
			capacity_limit_conversion,
			(connect_cost_per_mw + connect_cost_per_mw_generic) * economic_multiplier  as connect_cost_per_mw,
    		avg_capacity_factor			
	from proposed_projects_solar_import
	join (SELECT distinct technology, technology_id, connect_cost_per_mw_generic from generator_info_v2 where fuel = 'Solar') tech_map using (technology)
	join load_area_info using (load_area)
	order by 2;

-- --------------------
select 'Calculating Intermittent Resource Quality Ranks' as progress;
DROP PROCEDURE IF EXISTS determine_intermittent_cap_factor_rank;
delimiter $$
CREATE PROCEDURE determine_intermittent_cap_factor_rank()
BEGIN

declare current_ordering_id int;
declare rank_total float;

-- RANK BY TECH--------------------------
-- add the avg_cap_factor_percentile_by_intermittent_tech values
-- which will be used to subsample the larger range of intermittent tech hourly values
drop table if exists rank_table;
create table rank_table (
	ordering_id int unsigned PRIMARY KEY AUTO_INCREMENT,
	project_id int unsigned NOT NULL,
	technology_id tinyint unsigned NOT NULL,
	avg_MW double,
	INDEX ord_tech (ordering_id, technology_id),
	INDEX tech (technology_id),
	INDEX ord_proj (ordering_id, project_id)
	);

insert into rank_table (project_id, technology_id, avg_MW)
	select project_id, technology_id, capacity_limit * IF(capacity_limit_conversion is null, 1, capacity_limit_conversion) * avg_cap_factor_intermittent as avg_MW from _proposed_projects_v3
	where avg_cap_factor_intermittent is not null
	order by technology_id, avg_cap_factor_intermittent;

set current_ordering_id = (select min(ordering_id) from rank_table);

rank_loop_total: LOOP

	-- find the rank by technology class such that all resources above a certain class can be included
	set rank_total = 
		(select 	sum(avg_MW)/total_tech_avg_mw
			from 	rank_table,
					(select sum(avg_MW) as total_tech_avg_mw
						from rank_table
						where technology_id = (select technology_id from rank_table where ordering_id = current_ordering_id)
					) as total_tech_capacity_table
			where ordering_id <= current_ordering_id
			and technology_id = (select technology_id from rank_table where ordering_id = current_ordering_id)
		);
			
	update _proposed_projects_v3, rank_table
	set avg_cap_factor_percentile_by_intermittent_tech = rank_total
	where rank_table.project_id = _proposed_projects_v3.project_id
	and rank_table.ordering_id = current_ordering_id;
	
	set current_ordering_id = current_ordering_id + 1;        
	
IF current_ordering_id > (select max(ordering_id) from rank_table)
	THEN LEAVE rank_loop_total;
    	END IF;
END LOOP rank_loop_total;

drop table rank_table;

END;
$$
delimiter ;

CALL determine_intermittent_cap_factor_rank;
DROP PROCEDURE IF EXISTS determine_intermittent_cap_factor_rank;


-- CUMULATIVE AVERAGE MW AND RANK IN EACH LOAD AREA BY TECH-------------------------
-- find the amount of average MW of each technology in each load area at or above the level of each project
-- also get the rank in each load area for each tech 
DROP PROCEDURE IF EXISTS cumulative_intermittent_cap_factor_rank;
delimiter $$
CREATE PROCEDURE cumulative_intermittent_cap_factor_rank()
BEGIN

declare current_ordering_id int;
declare cumulative_avg_MW float;
declare rank_load_area float;

drop table if exists cumulative_gen_load_area_table_v3;
create table cumulative_gen_load_area_table_v3 (
	ordering_id int unsigned PRIMARY KEY AUTO_INCREMENT,
	project_id int unsigned NOT NULL,
	technology_id tinyint unsigned NOT NULL,
	area_id smallint unsigned NOT NULL,
  	avg_MW double,
	INDEX ord_tech (ordering_id, technology_id),
	INDEX tech (technology_id),
	INDEX ord_proj (ordering_id, project_id),
	INDEX area_id (area_id),
	INDEX ord_tech_area (ordering_id, technology_id, area_id),
	INDEX ord_proj_area (ordering_id, project_id, area_id)
	);

insert into cumulative_gen_load_area_table_v3 (project_id, technology_id, area_id, avg_MW)
	select 	project_id, technology_id, area_id,
			capacity_limit * IF(capacity_limit_conversion is null, 1, capacity_limit_conversion) * avg_cap_factor_intermittent as avg_MW
		from _proposed_projects_v3
		where avg_cap_factor_intermittent is not null
		order by technology_id, area_id, avg_cap_factor_intermittent;


set current_ordering_id = (select min(ordering_id) from cumulative_gen_load_area_table_v3);

cumulative_capacity_loop: LOOP

	set cumulative_avg_MW = 
		(select 	sum(avg_MW) 
			from 	cumulative_gen_load_area_table_v3
			where ordering_id >= current_ordering_id
			and technology_id = (select technology_id from cumulative_gen_load_area_table_v3 where ordering_id = current_ordering_id)
			and area_id = (select area_id from cumulative_gen_load_area_table_v3 where ordering_id = current_ordering_id)
		);

	set rank_load_area = 
		(select 	count(*) 
			from 	cumulative_gen_load_area_table_v3
			where ordering_id >= current_ordering_id
			and technology_id = (select technology_id from cumulative_gen_load_area_table_v3 where ordering_id = current_ordering_id)
			and area_id = (select area_id from cumulative_gen_load_area_table_v3 where ordering_id = current_ordering_id)
		);
			
	update _proposed_projects_v3, cumulative_gen_load_area_table_v3
	set cumulative_avg_MW_tech_load_area = cumulative_avg_MW,
		rank_by_tech_in_load_area = rank_load_area
	where cumulative_gen_load_area_table_v3.project_id = _proposed_projects_v3.project_id
	and cumulative_gen_load_area_table_v3.ordering_id = current_ordering_id;
	
	
	set current_ordering_id = current_ordering_id + 1;        
	
IF current_ordering_id > (select max(ordering_id) from cumulative_gen_load_area_table_v3)
	THEN LEAVE cumulative_capacity_loop;
		END IF;
END LOOP cumulative_capacity_loop;

drop table cumulative_gen_load_area_table_v3;

END;
$$
delimiter ;

CALL cumulative_intermittent_cap_factor_rank;
DROP PROCEDURE IF EXISTS cumulative_intermittent_cap_factor_rank;

