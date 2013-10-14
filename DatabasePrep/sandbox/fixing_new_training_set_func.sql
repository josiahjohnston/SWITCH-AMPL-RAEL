set search_path to chile;

CREATE OR REPLACE FUNCTION exec(text) RETURNS text AS $$ BEGIN EXECUTE $1; 
RETURN $1; 
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION func1() RETURNS void AS $$

declare num_la int default 0;
declare current_training_set_id int default 0;
declare current_demand_scenario_id smallint default 0;
declare current_study_start_year smallint default 0;
declare current_years_per_period smallint default 0;
declare current_number_of_periods smallint default 0;
declare current_selection_method character varying(64) default 0;
declare current_exclude_peaks boolean default false;
declare current_months_between_samples smallint default 0;
declare current_start_month smallint default 0;
declare current_hours_between_samples smallint default 0;
declare current_start_hour smallint default 0;
declare current_peak_start_hour smallint default 0;
declare current_peak_day date;
declare current_period smallint default 0;
declare current_period_number smallint default 0;
declare current_month smallint default 0;
declare current_date_cst date;
declare current_n_dates smallint default 0;
declare current_hours_in_sample smallint default 0;

BEGIN
-- Clean up this function's "temporary" tables in case it was called earlier and crashed before cleaning up.
DROP TABLE IF EXISTS training_sets_tmp;
DROP TABLE IF EXISTS tmonths;
DROP TABLE IF EXISTS t_period_populations;
DROP TABLE IF EXISTS period_cursor;
DROP TABLE IF EXISTS historic_timepoints_used;
DROP TABLE IF EXISTS month_cursor;
DROP TABLE IF EXISTS t_period_years;
DROP TABLE IF EXISTS incomplete_test_sets;
DROP TABLE IF EXISTS test_timepoints_per_period;
DROP TABLE IF EXISTS date_tmp;

-- create a tmp table off of which to go through the training sets loop
create table training_sets_tmp as 
	select * from training_sets 
		where demand_scenario_id IS NOT NULL AND
			training_set_id NOT IN (select distinct training_set_id from training_set_timepoints);

-- make a list of all the possible months
-- also report the number of days in each month, for sample-weighting later
create table tmonths (month_of_year smallint PRIMARY KEY, days_in_month double precision);
insert into tmonths values 
	(1, 31), (2, 29.25), (3, 31), (4, 30), (5, 31), (6, 30),
	(7, 31), (8, 31), (9, 30), (10, 31), (11, 30), (12, 31);


select count(distinct(la_id)) from load_area into num_la;






END;

 $$ LANGUAGE plpgsql;

SELECT func1();

--SELECT * FROM tmonths;
--select * from training_set_timepoints;