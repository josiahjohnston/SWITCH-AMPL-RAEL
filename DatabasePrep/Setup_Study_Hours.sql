set search_path to chile;

-- add entries to the insert into training_sets statement to add training sets to the model
-- also, to make good subsampling scenarios, add lines to DefineScenarios.SQL

-- change later to the postgresql equivalent of 'CREATE TABLE IF NOT EXISTS'

-- 'This table stores descriptions of a set of timepoints that the SWITCH model optimizes cost over. i.e. Training sets '
-- 'The value of START_MONTH should be between 0 and one less than the value of NUM_HOURS_BETWEEN_SAMPLES. 0 means sampling starts in Jan, 1 means Feb, 2 -> March, 3 -> April'
-- 'The value of START_HOUR should be between 0 and one less than the value of NUM_HOURS_BETWEEN_SAMPLES. 0 means sampling starts at 12am, 1 means 1am, ... 15 means 3pm, etc'
-- 'selection_method describes the method of selection of timepoints. The two main methods - MEDIAN and RAND - differ in their selection of representative timepoints. MEDIAN selects days with near-median demands. RAND selects representative days at random.'
-- 

drop table if exists training_sets;
CREATE TABLE training_sets (
  training_set_id serial primary key,
  demand_scenario_id smallint not null,
  number_of_timepoints int,
  study_start_year smallint not null,
  years_per_period smallint not null,
  number_of_periods smallint not null,
  exclude_peaks boolean default false not null,
  months_between_samples smallint not null,
  start_month smallint not null,
  hours_between_samples smallint not null,
  start_hour smallint not null,
  selection_method character varying(64) not null,
  notes TEXT,
  UNIQUE (demand_scenario_id, study_start_year, years_per_period, number_of_periods, exclude_peaks, months_between_samples, start_month, hours_between_samples, start_hour, selection_method)
);

create index demand_scenario_id_training_set_idx on training_sets (demand_scenario_id);
create index number_of_timepoints_training_set_idx on training_sets (number_of_timepoints);

-- add insert ignore to the training_sets table
CREATE OR REPLACE RULE "insert_ignore_training_sets" AS ON INSERT TO "training_sets"
WHERE EXISTS (SELECT 1 FROM "training_sets"
	WHERE demand_scenario_id = 		NEW.demand_scenario_id
	AND study_start_year = 			NEW.study_start_year
	AND years_per_period = 			NEW.years_per_period
	AND number_of_periods = 		NEW.number_of_periods
	AND exclude_peaks = 			NEW.exclude_peaks
	AND months_between_samples = 	NEW.months_between_samples
	AND start_month = 				NEW.start_month
	AND hours_between_samples = 	NEW.hours_between_samples
	AND start_hour = 				NEW.start_hour
	AND selection_method = 			NEW.selection_method
	) DO INSTEAD NOTHING;


drop table if exists training_set_periods;
CREATE TABLE training_set_periods (
  training_set_id INT NOT NULL REFERENCES training_sets ON DELETE CASCADE,
  period_number smallint not null,
  period_start smallint not null,
  period_end smallint not null,
  PRIMARY KEY (training_set_id, period_number)
);

create index id_start_idx on training_set_periods (training_set_id, period_start);

CREATE OR REPLACE RULE "insert_ignore_training_set_periods" AS ON INSERT TO "training_set_periods"
WHERE EXISTS (SELECT 1 FROM "training_set_periods" WHERE training_set_id = NEW.training_set_id and period_number = NEW.period_number) DO INSTEAD NOTHING;


-- Make a table of study hours
drop table if exists training_set_timepoints;
CREATE TABLE training_set_timepoints (
  training_set_id INT NOT NULL REFERENCES training_sets ON DELETE CASCADE,
  period smallint not null,
  hour_number INT not null,
  timestamp_cst timestamp not null,
  hours_in_sample numeric(6,1) not null,
  PRIMARY KEY (training_set_id, hour_number),
  FOREIGN KEY (hour_number) REFERENCES hours (hour_number)
);

create index id_period_hour_idx on training_set_timepoints (training_set_id, period, hour_number);
create index timestamp_idx on training_set_timepoints (training_set_id, timestamp_cst);






CREATE OR REPLACE FUNCTION exec(text) RETURNS text AS $$ BEGIN EXECUTE $1; RETURN $1; END $$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION define_new_training_sets() RETURNS void AS $$

-- edit: num_la used to be num_provinces

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

-- start the loop to define training sets
WHILE ( (select count(*) from training_sets_tmp) > 0 ) LOOP -- define_training_sets_loop


	-- find what scenario parameters we're going to be using
	select training_set_id 			from training_sets_tmp ORDER BY training_set_id LIMIT 1 INTO current_training_set_id;
	select demand_scenario_id 		from training_sets_tmp where training_set_id = current_training_set_id INTO current_demand_scenario_id;
	select study_start_year 		from training_sets_tmp where training_set_id = current_training_set_id INTO current_study_start_year;
	select years_per_period 		from training_sets_tmp where training_set_id = current_training_set_id INTO current_years_per_period;
	select number_of_periods		from training_sets_tmp where training_set_id = current_training_set_id INTO current_number_of_periods;
	select selection_method 		from training_sets_tmp where training_set_id = current_training_set_id INTO current_selection_method;
	select exclude_peaks 			from training_sets_tmp where training_set_id = current_training_set_id INTO current_exclude_peaks;
	select months_between_samples 	from training_sets_tmp where training_set_id = current_training_set_id INTO current_months_between_samples;
	select start_month 				from training_sets_tmp where training_set_id = current_training_set_id INTO current_start_month;
	select hours_between_samples 	from training_sets_tmp where training_set_id = current_training_set_id INTO current_hours_between_samples;
	select start_hour 				from training_sets_tmp where training_set_id = current_training_set_id INTO current_start_hour;

	RAISE NOTICE 'current_training_set_id is at %',current_training_set_id;

	-- a temporary table to hold dates
	create table date_tmp (date_cst date);

	-- Make a list of periods
	select 0 into current_period_number;
	WHILE (current_period_number < current_number_of_periods) LOOP
		INSERT INTO training_set_periods (training_set_id, period_number, period_start, period_end)
			SELECT 	current_training_set_id,
				current_period_number,
				current_period_number * current_years_per_period + current_study_start_year,
				current_period_number * current_years_per_period + current_study_start_year + (current_years_per_period-1);
		select current_period_number + 1 into current_period_number;
	END LOOP;

	-- Make a list of years for each period that we will draw samples from.
	-- This picks years that are in the middle of the period. 
	CREATE TABLE t_period_years AS 
		SELECT period_number, period_start + FLOOR(current_years_per_period / 2) as sampled_year
			FROM training_set_periods
			WHERE training_set_id = current_training_set_id;
	create index period_number on t_period_years (period_number);
	create index sampled_year on t_period_years (sampled_year);
	
	-- make a list of dates for each period that we will select from
	CREATE TABLE t_period_populations (
		date_cst date primary key,
		period_number smallint);
	create index period_number_pop on t_period_populations (period_number);

	INSERT INTO t_period_populations (date_cst, period_number)
		SELECT date_cst, period_number  
			FROM demand_projection_daily_summaries, t_period_years
			WHERE num_data_points = num_la * 24  -- Exclude dates that have incomplete data. -- 
			AND demand_scenario_id = current_demand_scenario_id
				and extract(year from date_cst) = sampled_year; 


	-- Pick samples for each period. Loop through periods sequentially to avoid picking more than one sample based on the same historic date.
	CREATE TABLE period_cursor AS
		SELECT period_number, period_start as period from training_set_periods WHERE training_set_id = current_training_set_id order by 1;

	WHILE ( (select count(*) from period_cursor) > 0 ) LOOP -- iterate_through_periods 
		SELECT min(period_number) FROM period_cursor INTO current_period_number;
		RAISE NOTICE 'current_period_number is at %',current_period_number;
		SELECT min(period) FROM period_cursor INTO current_period;

		CREATE TABLE month_cursor AS
			SELECT month_of_year from tmonths WHERE mod(month_of_year - 1, current_months_between_samples) = current_start_month - 1 ; -- The two instances of "- 1" converts 1-12 to 0-11 for modulo arithmetic.
		WHILE ( (select count(*) from month_cursor) > 0 ) LOOP -- iterate_through_months 
			select MIN(month_of_year) FROM month_cursor into current_month;
			RAISE NOTICE 'current_month is at %',current_month;

			-- PEAK days
			IF (current_exclude_peaks is false) THEN
				SELECT date_cst
					FROM demand_projection_daily_summaries JOIN t_period_populations USING (date_cst) 
					WHERE period_number = current_period_number 
						AND extract(month from date_cst) = current_month 
						AND demand_scenario_id = current_demand_scenario_id 
					ORDER BY peak_demand DESC
					LIMIT 1
				INTO current_peak_day;
				SELECT mod(hour_of_day, current_hours_between_samples) 
					FROM hours JOIN demand_projection_daily_summaries ON (hour_number = peak_hour_number) 
					WHERE demand_projection_daily_summaries.date_cst = current_peak_day
					AND demand_scenario_id = current_demand_scenario_id 
				INTO current_peak_start_hour;
				INSERT INTO training_set_timepoints (training_set_id, period, hour_number, timestamp_cst, hours_in_sample)
					SELECT current_training_set_id, current_period, hour_number, timestamp_cst,
						current_years_per_period * current_hours_between_samples * current_months_between_samples AS hours_in_sample
						FROM hours 
						WHERE date_cst = current_peak_day
						AND mod(hour_of_day, current_hours_between_samples) = current_peak_start_hour;
			END IF;







			-- REPRESENTATIVE days
			select  CASE WHEN current_exclude_peaks is true THEN days_in_month ELSE days_in_month - 1 END * current_years_per_period * current_hours_between_samples * current_months_between_samples
					FROM tmonths WHERE month_of_year = current_month
				into current_hours_in_sample;
			IF (current_selection_method = 'MEDIAN') THEN
					-- Pick a day with median total system demand. First count the number of possible dates, then select a date from the middle of a list of potential dates that is ordered by system demand. 
					SELECT COUNT(*) 
							FROM demand_projection_daily_summaries JOIN t_period_populations USING (date_cst) 
							WHERE period_number = current_period_number
							AND extract(month from date_cst) = current_month
							AND demand_scenario_id = current_demand_scenario_id
					into current_n_dates;

				delete from date_tmp;
				PERFORM exec(
						   ' INSERT INTO date_tmp (date_cst)'
						|| ' SELECT date_cst FROM demand_projection_daily_summaries JOIN t_period_populations USING (date_cst) WHERE period_number = '
						|| current_period_number
						|| ' AND extract(month from date_cst) = '
						|| current_month
						|| ' AND demand_scenario_id = '
						|| current_demand_scenario_id
						|| ' ORDER BY total_demand LIMIT 1 OFFSET (select FLOOR('
						|| current_n_dates
						|| '/2))');
				select date_cst from date_tmp into current_date_cst;	
				
					INSERT INTO training_set_timepoints (training_set_id, period, hour_number, timestamp_cst, hours_in_sample)
						SELECT current_training_set_id, current_period, hour_number, timestamp_cst, current_hours_in_sample
							FROM hours
							WHERE date_cst = current_date_cst
							AND mod(hour_of_day, current_hours_between_samples) = current_start_hour;
			END IF;
			IF (current_selection_method = 'RANDOM') THEN
					SELECT date_cst   
						FROM demand_projection_daily_summaries JOIN t_period_populations USING (date_cst) 
						WHERE period_number = current_period_number 
						AND extract(month from date_cst) = current_month 
						AND demand_scenario_id = current_demand_scenario_id
						AND date_cst not in (select cast(timestamp_cst as date) from training_set_timepoints where training_set_id = current_training_set_id)
						ORDER BY random()
						LIMIT 1
						INTO current_date_cst;
					INSERT INTO training_set_timepoints (training_set_id, period, hour_number, timestamp_cst, hours_in_sample)
						SELECT current_training_set_id, current_period, hour_number, timestamp_cst, current_hours_in_sample
							FROM hours
							WHERE date_cst = current_date_cst
							AND mod(hour_of_day, current_hours_between_samples) = current_start_hour;					
			END IF;












			DELETE FROM month_cursor WHERE month_of_year = current_month;
	
		END LOOP; -- iterate_through_months
		DROP TABLE month_cursor;
		
		DELETE FROM period_cursor WHERE period_number = current_period_number;

	END LOOP; -- iterate_through_periods

	-- We're finished processing this training set, so delete it from the work list.
	delete from training_sets_tmp where training_set_id = current_training_set_id;
			
	-- Drop the tables that are supposed to be temporary

DROP TABLE IF EXISTS t_period_populations;
DROP TABLE IF EXISTS period_cursor;
DROP TABLE IF EXISTS month_cursor;
DROP TABLE IF EXISTS t_period_years;
DROP TABLE IF EXISTS date_tmp;

-- DROP TABLE IF EXISTS incomplete_test_sets;
-- DROP TABLE IF EXISTS test_timepoints_per_period;

					
END LOOP; -- define_training_sets_loop
drop table if exists training_sets_tmp;
drop table if exists tmonths;

END;
$$ LANGUAGE plpgsql;



