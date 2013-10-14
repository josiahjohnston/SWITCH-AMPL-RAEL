-- WITH PRESENT DAY DISPATCH NEW TABLE!!!
-- FUTURE: Put the scenario_id, training_set_id and present_year instead of a number!!

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
WHERE demand_scenario_id = 1 -- Put variable instead of number
AND training_set_id = 1 -- Put variable instead of number
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




