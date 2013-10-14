-- WITH PRESENT DAY DISPATCH NEW TABLE!!!
-- FUTURE: Put the scenario_id, training_set_id and present_year instead of a number!!

-- -----------------------------------------------------------------------------------------
-- SWITCH Chile
-- June 12th, 2013
-- Patricia Hidalgo-Gonzalez, patricia.hidalgo.g@berkeley.edu

-- This script builds the tables that need to be added to the databse in order to be able to -- run the script get_switch_input_tables.sh for SWITCH CHILE
-- -----------------------------------------------------------------------------------------
-- 1st successful run: 4pm 6/17/2013

set search_path to chile;

-- -----------------------------------------------------------------------------------------
-- Code taken from /Volumes/switch/Users/pehidalg/Switch_Chile/JP/compile_switch_chinav1.sql
-- -----------------------------------------------------------------------------------------
-- DEMAND SUMMARIES
-- add daily summary of demand projections to simplify following steps 
drop table if exists demand_projection_daily_summaries;
CREATE TABLE demand_projection_daily_summaries (
  demand_scenario_id smallint,
  date_cst date, 
  num_data_points smallint,
  total_demand numeric(10,0),
  average_demand numeric(8,0),
  peak_demand numeric(8,0),
  peak_hour_number int,
  PRIMARY KEY (demand_scenario_id, date_cst), 
  FOREIGN KEY (demand_scenario_id) REFERENCES chile.demand_scenarios (demand_scenario_id),
  FOREIGN KEY (peak_hour_number) REFERENCES chile.hours (hour_number)
);

create index daily_summary_idx on demand_projection_daily_summaries (demand_scenario_id, date_cst);

drop table if exists hourly_demand_summaries;
CREATE TABLE hourly_demand_summaries as
	SELECT 	demand_scenario_id,
			hour_number,
			date_cst, 
			cast(sum(la_demand_mwh) as numeric (8,0)) AS total_chile_demand_in_hour_number, 
			count(la_demand_mwh) AS num_data_points
	FROM chile.la_hourly_demand JOIN chile.hours USING(hour_number) 
	GROUP BY demand_scenario_id, hour_number, date_cst;
create index demand_scenario_id_idx on hourly_demand_summaries (demand_scenario_id);
create index date_cst_idx on hourly_demand_summaries (date_cst);


INSERT INTO demand_projection_daily_summaries (demand_scenario_id, date_cst, num_data_points, total_demand, average_demand, peak_demand)
  SELECT 	demand_scenario_id,
  			date_cst,
  			sum(num_data_points) as num_data_points, 
			cast(sum(total_chile_demand_in_hour_number) AS numeric(10,0)) as total_demand, 
			cast(sum(total_chile_demand_in_hour_number)/24 AS numeric(8,0)) as average_demand,
 		 	cast(max(total_chile_demand_in_hour_number) AS numeric(8,0)) as peak_demand
    FROM hourly_demand_summaries
    GROUP BY demand_scenario_id, date_cst
    order by demand_scenario_id, date_cst; 
    
UPDATE demand_projection_daily_summaries
	set peak_hour_number = hour_number
	from hourly_demand_summaries
	WHERE hourly_demand_summaries.date_cst = demand_projection_daily_summaries.date_cst
		AND hourly_demand_summaries.total_chile_demand_in_hour_number = demand_projection_daily_summaries.peak_demand;

DROP TABLE hourly_demand_summaries;

-- ---------------------------------------------------------------------
--        TRAINING SETS
-- ---------------------------------------------------------------------
-- training sets are a subset of hours on which SWITCH does its optimization.
-- these sets are different sets of study hours

-- see the scripts Setup_Study_Hours.sql and DefineScenarios.sql for more information
select define_new_training_sets();

-- ---------------------------------------------------------------------
--        SCENARIOS
-- ---------------------------------------------------------------------

drop table if exists scenarios_switch_chile;
CREATE TABLE scenarios_switch_chile (
  scenario_id serial primary key,
  scenario_name character varying(128),
  training_set_id int not null,
  notes TEXT,
  UNIQUE (training_set_id), 
  FOREIGN KEY (training_set_id) REFERENCES training_sets
);


CREATE OR REPLACE RULE "insert_ignore_scenarios_switch_chile" AS ON INSERT TO "scenarios_switch_chile"
WHERE EXISTS (SELECT 1 FROM "scenarios_switch_chile" WHERE training_set_id = NEW.training_set_id) DO INSTEAD NOTHING;


CREATE OR REPLACE FUNCTION clone_scenario_chile (name character varying(128), source_scenario_id int ) RETURNS int AS $$

	DECLARE new_id INT DEFAULT 0;

BEGIN

INSERT INTO scenarios_switch_chile (scenario_name, training_set_id, notes)
  SELECT name, training_set_id, notes
		FROM scenarios_switch_chile where scenario_id = source_scenario_id;

  SELECT CURRVAL(pg_get_serial_sequence('scenarios_switch_chile','scenario_id'));

  RETURN (new_id);
END;
$$ LANGUAGE plpgsql;



-- SWITCH Chile code
insert into scenarios_switch_chile (training_set_id)
	SELECT 
		training_set_id
	FROM training_sets
	where training_set_id not in (select distinct training_set_id from scenarios_switch_chile)
;

-- This needs the training sets table, so I'll continue editing that script!

-- -----------------------------------------------------------------------------------------
-- End of the extact
-- -----------------------------------------------------------------------------------------

-- New table for la_hourly_demand.tab

set search_path to chile;

DROP TABLE IF EXISTS la_hourly_demand_mwh_tab;

CREATE TABLE la_hourly_demand_mwh_tab (
la_id VARCHAR,
hour TEXT,
year SMALLINT,
month SMALLINT,
day SMALLINT,
hour_int SMALLINT,
la_demand_mwh DOUBLE PRECISION)
;

INSERT INTO la_hourly_demand_mwh_tab
SELECT la_id, 
to_char(chile.training_set_timepoints.timestamp_cst, 'YYYYMMDDHH24') AS hour, 
extract (year from chile.training_set_timepoints.timestamp_cst) AS year,
extract (month from chile.training_set_timepoints.timestamp_cst) AS month,
extract (day from chile.training_set_timepoints.timestamp_cst) AS day,
extract (hour from chile.training_set_timepoints.timestamp_cst) AS hour_int,
la_demand_mwh  
	FROM chile.la_hourly_demand 
	JOIN chile.training_sets USING (demand_scenario_id) 
	JOIN chile.training_set_timepoints USING (training_set_id, hour_number) 
	JOIN chile.load_area USING (la_id) 
WHERE demand_scenario_id = 1 -- Put the variable instead of a number!!
AND training_set_id = 1 -- Put the variable instead of a number!!
ORDER BY la_id, hour;


DROP TABLE IF EXISTS present_year_demand_mwh;

CREATE TABLE present_year_demand_mwh (
la_id VARCHAR,
hour TEXT,
year SMALLINT,
month SMALLINT,
day SMALLINT,
hour_int SMALLINT,
present_day_system_load DOUBLE PRECISION)
;

INSERT INTO present_year_demand_mwh
SELECT la_id, 
to_char(chile.hours.timestamp_cst, 'YYYYMMDDHH24') AS hour, 
extract (year from chile.hours.timestamp_cst) AS year,
extract (month from chile.hours.timestamp_cst) AS month,
extract (day from chile.hours.timestamp_cst) AS day,
extract (hour from chile.hours.timestamp_cst) AS hour_int,
la_demand_mwh AS present_day_system_load
	FROM chile.la_hourly_demand 
	JOIN chile.training_sets USING (demand_scenario_id) 
	JOIN chile.hours USING (hour_number) 
	JOIN chile.load_area USING (la_id) 
WHERE demand_scenario_id = 1 -- Put the variable instead of a number!!
AND training_set_id = 1 -- Put the variable instead of a number!!
AND extract (year from chile.hours.timestamp_cst) = 2011 -- SHOULD BE present_year
ORDER BY la_id, hour;


DROP TABLE IF EXISTS la_hourly_demand_mwh_new;

CREATE TABLE la_hourly_demand_mwh_new (
la_id VARCHAR,
hour TEXT,
year SMALLINT,
month SMALLINT,
day SMALLINT,
hour_int SMALLINT,
la_demand_mwh DOUBLE PRECISION,
present_day_system_load DOUBLE PRECISION)
;

INSERT INTO la_hourly_demand_mwh_new
SELECT t1.la_id, t1.hour, t1.year, t1.month, t1.day, t1.hour_int, t1.la_demand_mwh, t2.present_day_system_load
FROM la_hourly_demand_mwh_tab AS t1
JOIN present_year_demand_mwh AS t2 USING(la_id, month, day, hour_int)
WHERE t1.la_id = t2.la_id
AND t1.month = t2.month
AND t1.day = t2.day
AND t1.hour_int = t2.hour_int
ORDER BY la_id, hour;



SELECT * FROM la_hourly_demand_mwh_new;