use switch_inputs_wecc_v2_2;

-- Residential and Commercial DR scenarios table
-- Each dr_scenario_id will be linked to the load_scenario_id as it is calculated from a particular demand profile
-- Since we want null values in dr_scenario_id, we include that in a unique key rather than a primary key (the latter does not allow null values)
-- However, there's a bug in MySQL that gives an error upon 'select * from' when there's no primary key defined and there are null values in a primary key (see http://bugs.mysql.com/bug.php?id=63867); to get around this issues, there's a fake primary key in this table (dummy_column)
drop table if exists demand_response_scenarios;
create table demand_response_scenarios (
	load_scenario_id tinyint(4),
	dr_scenario_id tinyint(4),
	dr_scenario_name varchar(50),
	notes text,
	dummy_column int auto_increment,
	UNIQUE KEY (load_scenario_id, dr_scenario_id),
	PRIMARY KEY (dummy_column)
	);

-- add No DR scenarios
DROP PROCEDURE IF EXISTS add_pre_dr_scenarios;
DELIMITER $$
CREATE PROCEDURE add_pre_dr_scenarios()
BEGIN

drop table if exists all_load_scenario_ids;
create table all_load_scenario_ids (
	load_scenario_id tinyint(4)
	);
insert into all_load_scenario_ids (load_scenario_id)
	select distinct(load_scenario_id) from training_sets where load_scenario_id is not null;

        add_load_scenario_ids: LOOP
	
		SET @current_load_scenario_id = (select load_scenario_id from all_load_scenario_ids LIMIT 1);
        
        INSERT into demand_response_scenarios (load_scenario_id)
		VALUES (@current_load_scenario_id);
	
		DELETE FROM all_load_scenario_ids where load_scenario_id = @current_load_scenario_id;
	
		IF (select count(*) from all_load_scenario_ids) = 0 THEN LEAVE add_load_scenario_ids;
		END IF;
	END LOOP add_load_scenario_ids;
END;
$$
DELIMITER ;

CALL add_pre_dr_scenarios();
DROP PROCEDURE add_pre_dr_scenarios;

-- manually add residential and commercial full technical potential scenario for 
insert into demand_response_scenarios (load_scenario_id, dr_scenario_id, dr_scenario_name, notes)
	VALUES (21, 1, 'TP DR', 'Technical potential DR from commercial and residential heating');
	

-- actually create the shiftable residential and commercial load table in the Switch WECC inputs database
drop table if exists shiftable_res_comm_load;
create table shiftable_res_comm_load (
	load_scenario_id tinyint(4),
	dr_scenario_id tinyint(4) default 0,
	area_id smallint(5),
	timepoint_id int(10),
	shiftable_res_comm_load double default 0,
	shifted_res_comm_load_hourly_max double default 0,
	PRIMARY KEY (load_scenario_id, dr_scenario_id, area_id, timepoint_id),
	FOREIGN KEY load_dr_combination (load_scenario_id, dr_scenario_id) REFERENCES demand_response_scenarios (load_scenario_id, dr_scenario_id)
	);


----------------------------------------------------------
--EV DR scenarios table
-- Each dr_scenario_id will be linked to the load_scenario_id as it is calculated from a particular demand profile
-- Since we want null values in dr_scenario_id, we include that in a unique key rather than a primary key (the latter does not allow null values)
-- However, there's a bug in MySQL that gives an error upon 'select * from' when there's no primary key defined and there are null values in a primary key (see http://bugs.mysql.com/bug.php?id=63867); to get around this issues, there's a fake primary key in this table (dummy_column)
drop table if exists ev_scenarios;
create table ev_scenarios (
	load_scenario_id tinyint(4),
	ev_scenario_id tinyint(4),
	ev_scenario_name varchar(50),
	notes text,
	dummy_column int auto_increment,
	UNIQUE KEY (load_scenario_id, ev_scenario_id),
	PRIMARY KEY (dummy_column)
	);

-- add No EV Load Shifting scenarios
DROP PROCEDURE IF EXISTS add_pre_ev_load_shifting_scenarios;
DELIMITER $$
CREATE PROCEDURE add_pre_ev_load_shifting_scenarios()
BEGIN

drop table if exists all_load_scenario_ids;
create table all_load_scenario_ids (
	load_scenario_id tinyint(4)
	);
insert into all_load_scenario_ids (load_scenario_id)
	select distinct(load_scenario_id) from training_sets where load_scenario_id is not null;

        add_load_scenario_ids: LOOP
	
		SET @current_load_scenario_id = (select load_scenario_id from all_load_scenario_ids LIMIT 1);
        
        INSERT into ev_scenarios (load_scenario_id)
		VALUES (@current_load_scenario_id);
	
		DELETE FROM all_load_scenario_ids where load_scenario_id = @current_load_scenario_id;
	
		IF (select count(*) from all_load_scenario_ids) = 0 THEN LEAVE add_load_scenario_ids;
		END IF;
	END LOOP add_load_scenario_ids;
END;
$$
DELIMITER ;

CALL add_pre_ev_load_shifting_scenarios();
DROP PROCEDURE add_pre_ev_load_shifting_scenarios;

-- manually add full technical potential scenario for 
insert into ev_scenarios (load_scenario_id, ev_scenario_id, ev_scenario_name, notes)
	VALUES (21, 1, 'TP EV', 'Technical potential EV load shifting');
insert into ev_scenarios (load_scenario_id, ev_scenario_id, ev_scenario_name, notes)
	VALUES (21, 2, 'Aggressive realistic EV', '"Aggressive realistic" EV load shifting');


-- actually create the shiftable residential and commercial load table in the Switch WECC inputs database
drop table if exists shiftable_ev_load;
create table shiftable_ev_load (
	load_scenario_id tinyint(4),
	ev_scenario_id tinyint(4) default 0,
	area_id smallint(5),
	timepoint_id int(10),
	shiftable_ev_load double default 0,
	shifted_ev_load_hourly_max double default 0,
	PRIMARY KEY load_ev_area_timepoint (load_scenario_id, ev_scenario_id, area_id, timepoint_id),
	FOREIGN KEY load_ev_combination (load_scenario_id, ev_scenario_id) REFERENCES ev_scenarios (load_scenario_id, ev_scenario_id)
	);