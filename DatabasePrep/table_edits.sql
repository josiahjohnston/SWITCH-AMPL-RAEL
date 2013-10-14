-- -----------------------------------------------------------------------------------------
-- SWITCH Chile
-- June 17th, 2013
-- Patricia Hidalgo-Gonzalez, patricia.hidalgo.g@berkeley.edu

-- This script edits the tables in order to be able to 
-- run the script get_switch_input_tables.sh for SWITCH CHILE
-- -----------------------------------------------------------------------------------------

set search_path to chile;


-- make col demand_scenario_id in table demand_secenarios a primary key
alter table chile.demand_scenarios add primary key (demand_scenario_id);







--ALTER TABLE chile.existing_plants ADD COLUMN project_id_int SERIAL;


---------------------------------------------------------------------------------------
-- table to add a project_id SERIAL col (with index as well)
--DROP TABLE IF EXISTS count;

--CREATE TABLE count (project_id varchar, id serial);

--ALTER SEQUENCE count_id_seq RESTART WITH 1000;


--INSERT INTO count
--	 (project_id)  select existing_plants.project_id
--	FROM existing_plants;

	
--select * from count;

---------------------------------------------------------------------------------------

--UPDATE existing_plants
--	SET project_id_int = count.id
--	FROM count
--	WHERE existing_plants.project_id = count.project_id;
---------------------------------------------------------------------------------------

CREATE UNIQUE INDEX project_id_int_idx ON existing_plants (project_id_int);

SELECT * FROM existing_plants order by project_id_int;