-- This file defines database schema and methods for subsampling timepoints.

create database if not exists switch_inputs_wecc_v2_2;
use switch_inputs_wecc_v2_2;
	
CREATE TABLE IF NOT EXISTS training_sets (
  training_set_id INT NOT NULL PRIMARY KEY AUTO_INCREMENT,
  load_scenario_id  TINYINT UNSIGNED,
  num_timepoints INT NOT NULL,
  study_start_year YEAR NOT NULL,
  years_per_period INT NOT NULL,
  number_of_periods INT NOT NULL,
  exclude_peaks BOOLEAN NOT NULL default 0, 
  months_between_samples INT NOT NULL DEFAULT 6, 
  start_month INT NOT NULL DEFAULT 3 COMMENT 'The value of START_MONTH should be between 0 and one less than the value of NUM_HOURS_BETWEEN_SAMPLES. 0 means sampling starts in Jan, 1 means Feb, 2 -> March, 3 -> April', 
  hours_between_samples INT NOT NULL DEFAULT 24, 
  start_hour INT NOT NULL DEFAULT 11 COMMENT 'The value of START_HOUR should be between 0 and one less than the value of NUM_HOURS_BETWEEN_SAMPLES. 0 means sampling starts at 12am, 1 means 1am, ... 15 means 3pm, etc', 
  selection_method VARCHAR(64) NOT NULL COMMENT 'This field describes the method of selection of timepoints. The two main methods - MEDIAN and RAND - differ in their selection of representative timepoints. MEDIAN selects days with near-median loads. RAND selects representative days at random.',
  notes TEXT COMMENT 'This field describes the selection method in full sentences. ',
  INDEX (load_scenario_id),
  INDEX (num_timepoints),
  UNIQUE (load_scenario_id, study_start_year, years_per_period, number_of_periods, exclude_peaks, months_between_samples, start_month, hours_between_samples, start_hour, selection_method)
)
COMMENT = 'This stores descriptions of a set of timepoints that the SWITCH model optimizes cost over. i.e. Training sets ';


CREATE TABLE IF NOT EXISTS training_set_periods (
  training_set_id INT NOT NULL,
  periodnum TINYINT UNSIGNED,
  period_start year,
  period_end year,
  INDEX (training_set_id, period_start),
  PRIMARY KEY id_periodnum (training_set_id, periodnum),
  CONSTRAINT training_set_id FOREIGN KEY training_set_id (training_set_id)
    REFERENCES training_sets (training_set_id)
);


-- Make a table of study hours
CREATE TABLE IF NOT EXISTS _training_set_timepoints (
  training_set_id INT NOT NULL,
  period year,
  timepoint_id INT UNSIGNED,
  hours_in_sample DECIMAL (6,1),
  INDEX (training_set_id, period, timepoint_id),
  PRIMARY KEY id_hour (training_set_id, timepoint_id),
  CONSTRAINT training_set_id FOREIGN KEY training_set_id (training_set_id)
    REFERENCES training_sets (training_set_id),
  CONSTRAINT timepoint_id FOREIGN KEY timepoint_id (timepoint_id)
    REFERENCES study_timepoints (timepoint_id)
);
CREATE OR REPLACE VIEW training_set_timepoints AS
  SELECT training_set_id, period, timepoint_id, datetime_utc, historic_hour as historic_hour_id, hours_in_sample
  FROM _training_set_timepoints 
  	JOIN training_sets     USING(training_set_id)
  	JOIN _load_projections USING(timepoint_id,load_scenario_id)
  	JOIN study_timepoints  USING(timepoint_id)
  WHERE area_id = (SELECT MIN(area_id) FROM load_area_info)
;

CREATE TABLE IF NOT EXISTS dispatch_test_sets (
  training_set_id  INT UNSIGNED,
  test_set_id      INT UNSIGNED,
  periodnum        TINYINT UNSIGNED,
  historic_hour    SMALLINT UNSIGNED,
  timepoint_id     INT UNSIGNED,
  hours_in_sample  decimal(6,1),
  UNIQUE (training_set_id, test_set_id, timepoint_id),
  INDEX (training_set_id, test_set_id, timepoint_id, historic_hour),
  INDEX (training_set_id, periodnum),
  CONSTRAINT training_set_id_fk FOREIGN KEY training_set_id_fk (training_set_id)
    REFERENCES training_sets (training_set_id)
);

CREATE TABLE IF NOT EXISTS scenarios_v3 (
  scenario_id INT NOT NULL AUTO_INCREMENT,
  scenario_name VARCHAR(128),
  training_set_id INT NOT NULL,
  regional_cost_multiplier_scenario_id INT NOT NULL DEFAULT 1, 
  regional_fuel_cost_scenario_id INT NOT NULL DEFAULT 1, 
  gen_costs_scenario_id MEDIUMINT NOT NULL DEFAULT 2 COMMENT 'The default scenario is 2 and has the baseline cost assumptions.', 
  gen_info_scenario_id MEDIUMINT NOT NULL DEFAULT 2 COMMENT 'The default scenario is 2 and has the baseline generator assumptions.',
  enable_rps BOOLEAN NOT NULL DEFAULT 0 COMMENT 'This controls whether Renewable Portfolio Standards are considered in the optimization.', 
  carbon_cap_scenario_id int unsigned DEFAULT 0 COMMENT 'The default scenario is no cap. Browse existing scenarios or define new ones in the table carbon_cap_scenarios.',
  nems_fuel_scenario_id int unsigned DEFAULT 1 COMMENT 'The default scenario is the reference case. Check out the nems_fuel_scenarios table for other scenarios.',
  notes TEXT,
  model_version varchar(16) NOT NULL,
  inputs_adjusted varchar(16) NOT NULL DEFAULT 'no',
  PRIMARY KEY (scenario_id), 
  UNIQUE KEY unique_params (training_set_id, regional_cost_multiplier_scenario_id, regional_fuel_cost_scenario_id, gen_costs_scenario_id, gen_info_scenario_id, enable_rps, carbon_cap_scenario_id, model_version, inputs_adjusted), 
  CONSTRAINT training_set_id FOREIGN KEY training_set_id (training_set_id)
    REFERENCES training_sets (training_set_id), 
  CONSTRAINT regional_cost_multiplier_scenario_id FOREIGN KEY regional_cost_multiplier_scenario_id (regional_cost_multiplier_scenario_id)
    REFERENCES regional_economic_multiplier (scenario_id), 
  CONSTRAINT regional_fuel_cost_scenario_id FOREIGN KEY regional_fuel_cost_scenario_id (regional_fuel_cost_scenario_id)
    REFERENCES regional_fuel_prices (scenario_id),  
  CONSTRAINT gen_costs_scenario_id FOREIGN KEY gen_costs_scenario_id (gen_costs_scenario_id)
    REFERENCES generator_costs_scenarios (gen_costs_scenario_id),
  CONSTRAINT gen_info_scenario_id FOREIGN KEY gen_info_scenario_id (gen_info_scenario_id)
    REFERENCES generator_info_scenarios (gen_info_scenario_id),
	CONSTRAINT carbon_cap_scenario_id FOREIGN KEY carbon_cap_scenario_id (carbon_cap_scenario_id) 
	  REFERENCES carbon_cap_scenarios (carbon_cap_scenario_id),
	CONSTRAINT nems_fuel_scenario_id FOREIGN KEY nems_fuel_scenario_id (nems_fuel_scenario_id) 
	  REFERENCES nems_fuel_scenarios (nems_fuel_scenario_id)
)
COMMENT = 'Each record in this table is a specification of how to compile a set of inputs for a specific run. Several fields specify how to subselect timepoints from a given training_set. Other fields indicate which set of regional price data to use.';


DROP PROCEDURE IF EXISTS prepare_load_exports;
DELIMITER $$
CREATE PROCEDURE prepare_load_exports( IN target_training_set_id INT UNSIGNED)
BEGIN
	SET @load_scenario_id := (select load_scenario_id FROM training_sets WHERE training_set_id=target_training_set_id);
	set @num_historic_years := (select count(distinct year(datetime_utc)) from hours JOIN load_scenario_historic_timepoints ON(historic_hour=hournum) WHERE load_scenario_id=@load_scenario_id);
	DROP TABLE IF EXISTS present_day_timepoint_map;
	CREATE TEMPORARY TABLE present_day_timepoint_map 
		SELECT timepoint_id as future_timepoint_id, DATE_SUB(s.datetime_utc, INTERVAL period-YEAR(NOW()) + FLOOR((years_per_period-@num_historic_years)/2) YEAR) as present_day_timepoint
			FROM _training_set_timepoints t
				JOIN training_sets USING(training_set_id)
				JOIN study_timepoints  s USING (timepoint_id)
			WHERE training_set_id=target_training_set_id 
			ORDER BY 1;
	ALTER TABLE present_day_timepoint_map ADD INDEX (future_timepoint_id), ADD INDEX (present_day_timepoint), ADD COLUMN present_day_timepoint_id INT UNSIGNED, ADD INDEX (present_day_timepoint_id);
	UPDATE present_day_timepoint_map, study_timepoints
		SET present_day_timepoint_id=timepoint_id
		WHERE present_day_timepoint=datetime_utc;
	CREATE TABLE IF NOT EXISTS scenario_loads_export (
		training_set_id INT UNSIGNED,
		area_id SMALLINT UNSIGNED,
		load_area varchar(20),
		timepoint_id INT UNSIGNED,
		datetime_utc datetime,
		system_load DECIMAL(6,0),
		present_day_system_load DECIMAL(6,0),
		PRIMARY KEY(training_set_id,area_id,timepoint_id), 
		INDEX(timepoint_id,area_id)
	);
	REPLACE INTO scenario_loads_export ( training_set_id, area_id, timepoint_id, system_load )
		SELECT training_set_id, f.area_id, f.timepoint_id, f.power as system_load
		FROM _training_set_timepoints
			JOIN _load_projections f USING (timepoint_id)
		WHERE training_set_id=target_training_set_id AND load_scenario_id=@load_scenario_id;
	UPDATE scenario_loads_export, present_day_timepoint_map, _load_projections
		SET present_day_system_load = _load_projections.power
		WHERE scenario_loads_export.timepoint_id    = future_timepoint_id
			AND scenario_loads_export.area_id         = _load_projections.area_id
			AND scenario_loads_export.training_set_id = target_training_set_id
			AND _load_projections.timepoint_id        = present_day_timepoint_id 
			AND _load_projections.load_scenario_id    = @load_scenario_id;
	UPDATE scenario_loads_export e, load_area_info, study_timepoints
		SET e.load_area = load_area_info.load_area,
				e.datetime_utc = study_timepoints.datetime_utc
		WHERE e.area_id = load_area_info.area_id AND e.timepoint_id = study_timepoints.timepoint_id;
END$$

DROP PROCEDURE IF EXISTS clean_load_exports$$
CREATE PROCEDURE clean_load_exports( IN target_training_set_id INT UNSIGNED)
BEGIN
	DELETE FROM scenario_loads_export WHERE training_set_id = target_training_set_id;
	IF( (SELECT COUNT(*) FROM scenario_loads_export) = 0 ) THEN
		DROP TABLE scenario_loads_export;
	END IF;
END$$

DELIMITER ;


DROP PROCEDURE IF EXISTS define_new_training_sets;
DELIMITER $$
CREATE PROCEDURE define_new_training_sets()
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

-- create a tmp table off of which to go through the training sets loop
create table training_sets_tmp as 
	select * from training_sets 
		where load_scenario_id IS NOT NULL AND
			training_set_id NOT IN (select distinct training_set_id from _training_set_timepoints);

-- make a list of all the possible months
-- also report the number of days in each month, for sample-weighting later
create table if not exists tmonths (month_of_year tinyint PRIMARY KEY, days_in_month double);
insert IGNORE into tmonths values 
	(1, 31), (2, 29.25), (3, 31), (4, 30), (5, 31), (6, 30),
	(7, 31), (8, 31), (9, 30), (10, 31), (11, 30), (12, 31);

set @num_load_areas := (select count(distinct(area_id)) as num_load_areas from load_area_info);

-- start the loop to define training sets
define_new_training_sets_loop: LOOP


	-- find what scenario parameters we're going to be using
	set @training_set_id=0, @load_scenario_id=0, @study_start_year=0, @years_per_period=0, @number_of_periods=0, @selection_method=0, @exclude_peaks=0, @months_between_samples=0, @start_month=0, @hours_between_samples=0, @start_hour=0;
	select training_set_id, load_scenario_id, study_start_year, years_per_period, number_of_periods, selection_method, exclude_peaks, months_between_samples, start_month, hours_between_samples, start_hour
		INTO @training_set_id, @load_scenario_id, @study_start_year, @years_per_period, @number_of_periods, @selection_method, @exclude_peaks, @months_between_samples, @start_month, @hours_between_samples, @start_hour
	from training_sets_tmp ORDER BY training_set_id LIMIT 1;

	-- Set the number of timepoints .. It's a derived column, so maybe we'll migrate it to a view later.
	UPDATE training_sets
		SET num_timepoints = number_of_periods * (2- exclude_peaks) * 
			FLOOR(12/months_between_samples) * FLOOR(24/hours_between_samples)
		WHERE training_set_id=@training_set_id;

	set @min_historic_year := (select min(year(datetime_utc)) from hours JOIN load_scenario_historic_timepoints ON(historic_hour=hournum) WHERE load_scenario_id=@load_scenario_id);
	set @num_historic_years := (select count(distinct year(datetime_utc)) from hours JOIN load_scenario_historic_timepoints ON(historic_hour=hournum) WHERE load_scenario_id=@load_scenario_id);


	-- Make a list of periods
	SET @periodnum := 0;
	WHILE @periodnum < @number_of_periods DO
		INSERT IGNORE INTO training_set_periods (training_set_id, periodnum, period_start, period_end)
			VALUES (@training_set_id, @periodnum, periodnum*@years_per_period + @study_start_year, periodnum*@years_per_period + @study_start_year + (@years_per_period-1));
		SET @periodnum := @periodnum + 1;
	END WHILE;

	-- Make a list of years for each period that we will draw samples from.
	-- This picks years that are in the middle of the period. The number of years picked is equal to the number of historic years data was drawn from.
	set @period_offset    := (select FLOOR((@years_per_period - @num_historic_years) / 2));
	CREATE TABLE t_period_years
		SELECT periodnum, period_start + @period_offset + historic_year_factor as sampled_year
			FROM training_set_periods, (SELECT DISTINCT year(datetime_utc)-@min_historic_year as historic_year_factor from hours JOIN load_scenario_historic_timepoints ON(historic_hour=hournum) WHERE load_scenario_id=@load_scenario_id) as foo
			WHERE training_set_id = @training_set_id;
	ALTER TABLE t_period_years ADD INDEX (periodnum), ADD INDEX (sampled_year), CHANGE COLUMN periodnum periodnum TINYINT(3) UNSIGNED NULL DEFAULT NULL;
	
	-- make a list of dates for each period that we will select from
	CREATE TABLE t_period_populations (
		periodnum int,
		date_utc date primary key,
		INDEX (periodnum),
		INDEX (date_utc)
	);
	INSERT INTO t_period_populations (periodnum, date_utc)
		SELECT periodnum, date_utc 
			FROM _load_projection_daily_summaries JOIN t_period_years ON(YEAR(date_utc) = sampled_year)
			WHERE num_data_points = @num_load_areas * 24 -- Exclude dates that have incomplete data.
				AND load_scenario_id=@load_scenario_id ; 


	-- Pick samples for each period. Loop through periods sequentially to avoid picking more than one sample based on the same historic date.
	CREATE TABLE period_cursor
		SELECT periodnum, period_start as period from training_set_periods WHERE training_set_id=@training_set_id order by 1;
	CREATE TABLE historic_timepoints_used (historic_hour INT UNSIGNED PRIMARY KEY);
	iterate_through_periods: LOOP
		SET @periodnum = 0, @period = 0;
		SELECT MIN(periodnum), MIN(period) INTO @periodnum, @period FROM period_cursor;

		CREATE TABLE month_cursor
			SELECT month_of_year from tmonths WHERE (month_of_year-1) mod @months_between_samples = @start_month - 1 ; -- The two instances of "- 1" converts 1-12 to 0-11 for modulo arithmetic.
		iterate_through_months: LOOP
			SET @month := (SELECT MIN(month_of_year) FROM month_cursor);
			-- PEAK days
			IF ( @exclude_peaks = 0 ) THEN
				SET @peak_day := (
					SELECT date_utc 
					FROM _load_projection_daily_summaries JOIN t_period_populations USING (date_utc) 
					WHERE periodnum = @periodnum 
						AND MONTH(date_utc) = @month 
						AND load_scenario_id=@load_scenario_id 
						AND peak_hour_historic_id NOT IN (SELECT * FROM historic_timepoints_used)
					ORDER BY peak_load DESC
					LIMIT 1
				);
				SET @peak_start_hour := (SELECT HOUR(datetime_utc) MOD @hours_between_samples 
					FROM study_timepoints JOIN _load_projection_daily_summaries ON(timepoint_id=peak_hour_id) 
					WHERE date_utc = @peak_day AND load_scenario_id=@load_scenario_id 
				);
				INSERT INTO _training_set_timepoints (training_set_id, period, timepoint_id, hours_in_sample)
					SELECT @training_set_id, @period, timepoint_id, 
						@years_per_period * @hours_between_samples * @months_between_samples AS hours_in_sample
						FROM study_timepoints 
						WHERE DATE(datetime_utc) = @peak_day AND (HOUR(datetime_utc) MOD @hours_between_samples) = @peak_start_hour;
				INSERT INTO historic_timepoints_used 
					SELECT peak_hour_historic_id FROM _load_projection_daily_summaries WHERE load_scenario_id=@load_scenario_id AND date_utc=@peak_day;
			END IF;

			-- REPRESENTATIVE days
			SET @hours_in_sample := (SELECT 
				IF(@exclude_peaks=1, days_in_month, days_in_month-1) * @years_per_period * @hours_between_samples * @months_between_samples FROM tmonths WHERE month_of_year = @month);
			CASE @selection_method
				WHEN 'MEDIAN' THEN
					-- Pick a day with median total system load. First count the number of possible dates, then select a date from the middle of a list of potential dates that is ordered by system load. 
					SET @n_dates := (
						SELECT COUNT(*) 
							FROM _load_projection_daily_summaries JOIN t_period_populations USING (date_utc) 
							WHERE periodnum = @periodnum AND MONTH(date_utc) = @month AND load_scenario_id=@load_scenario_id AND peak_hour_historic_id NOT IN (SELECT * FROM historic_timepoints_used)
					);
					SET @date_utc := 0;
					SET @date_sql_select := CONCAT(
						'SELECT date_utc INTO @date_utc',
						'	FROM _load_projection_daily_summaries JOIN t_period_populations USING (date_utc) ',
						'	WHERE periodnum = @periodnum AND MONTH(date_utc) = @month AND load_scenario_id=@load_scenario_id AND peak_hour_historic_id NOT IN (SELECT * FROM historic_timepoints_used) ',
						'	ORDER BY total_load ',
						'	LIMIT 1 ',
						'	OFFSET ',(select FLOOR(@n_dates/2)));
					PREPARE date_selection_stmt FROM @date_sql_select;
					EXECUTE date_selection_stmt;
					INSERT INTO _training_set_timepoints (training_set_id, period, timepoint_id, hours_in_sample)
						SELECT @training_set_id, @period, timepoint_id, @hours_in_sample
							FROM study_timepoints
							WHERE DATE(datetime_utc) = @date_utc AND (HOUR(datetime_utc) MOD @hours_between_samples) = @start_hour;
				WHEN 'RAND'   THEN
					SET @date_utc := (
						SELECT date_utc 
						FROM _load_projection_daily_summaries JOIN t_period_populations USING (date_utc) 
						WHERE periodnum = @periodnum 
							AND MONTH(date_utc) = @month 
							AND load_scenario_id=@load_scenario_id 
							AND peak_hour_historic_id NOT IN (SELECT * FROM historic_timepoints_used)
						ORDER BY rand()
						LIMIT 1
					);
					INSERT INTO _training_set_timepoints (training_set_id, period, timepoint_id, hours_in_sample)
						SELECT @training_set_id, @period, timepoint_id, @hours_in_sample
							FROM study_timepoints
							WHERE DATE(datetime_utc) = @date_utc AND (HOUR(datetime_utc) MOD @hours_between_samples) = @start_hour;					
			END CASE;
			INSERT INTO historic_timepoints_used 
				SELECT peak_hour_historic_id FROM _load_projection_daily_summaries WHERE load_scenario_id=@load_scenario_id AND date_utc=@date_utc;

			DELETE FROM month_cursor WHERE month_of_year = @month;
			IF ( (select count(*) from month_cursor) = 0 )
					THEN LEAVE iterate_through_months;
			END IF;
		END LOOP iterate_through_months;
		DROP TABLE month_cursor;
		
		DELETE FROM period_cursor WHERE periodnum = @periodnum;
		IF ( (select count(*) from period_cursor) = 0 )
				THEN LEAVE iterate_through_periods;
		END IF;
	END LOOP iterate_through_periods;

 	DROP TABLE period_cursor;
 	DROP TABLE historic_timepoints_used;

  -- Make test sets to go along with this training set.
  set @hours_per_test_set := 7*24;
  set @first_historic_hour := (select min(historic_hour) from load_scenario_historic_timepoints where load_scenario_id=@load_scenario_id);

  -- Skip entries for the present year for now.
--  INSERT INTO t_period_years
--    SELECT NULL, year(now()) + historic_year_factor as sampled_year
--      FROM (SELECT DISTINCT year(datetime_utc)-@min_historic_year as historic_year_factor from hours JOIN load_scenario_historic_timepoints ON(historic_hour=hournum) WHERE load_scenario_id=@load_scenario_id) as foo;
  -- Add hourly entries for each distinct historical hour crossed with future periods (and the present)
  INSERT INTO dispatch_test_sets (training_set_id, test_set_id, periodnum, historic_hour, timepoint_id)
    SELECT @training_set_id, floor((historic_hour - @first_historic_hour)/@hours_per_test_set), periodnum, historic_hour, timepoint_id
    FROM load_scenario_historic_timepoints 
      JOIN study_timepoints USING(timepoint_id) 
      JOIN t_period_years ON(timepoint_year=sampled_year)
      JOIN _load_projection_daily_summaries ON(DATE(datetime_utc)=date_utc)
    WHERE num_data_points = @num_load_areas * 24 AND
      _load_projection_daily_summaries.load_scenario_id = @load_scenario_id AND
      load_scenario_historic_timepoints.load_scenario_id = @load_scenario_id;
  -- Make a list of test sets with incomplete data
  CREATE TABLE incomplete_test_sets
    SELECT test_set_id, COUNT(*) as cnt FROM dispatch_test_sets WHERE training_set_id=@training_set_id GROUP BY 1 HAVING cnt != @hours_per_test_set * @number_of_periods;
  ALTER TABLE incomplete_test_sets ADD UNIQUE (test_set_id);
  -- Delete test sets that have incomplete data. 
  DELETE dispatch_test_sets FROM dispatch_test_sets, incomplete_test_sets 
    WHERE dispatch_test_sets.training_set_id = @training_set_id AND
      dispatch_test_sets.test_set_id = incomplete_test_sets.test_set_id;
  -- Determine how much to weight each test timepoint. 
  CREATE TABLE test_timepoints_per_period -- Counts how many test timepoints are in each period
    SELECT periodnum, COUNT(*) as cnt FROM dispatch_test_sets WHERE training_set_id=@training_set_id GROUP BY 1;
  UPDATE dispatch_test_sets, test_timepoints_per_period
    SET hours_in_sample = @years_per_period*8764/cnt
    WHERE dispatch_test_sets.training_set_id = @training_set_id AND
      dispatch_test_sets.periodnum = test_timepoints_per_period.periodnum;
  set @present_day_period_length := (select @study_start_year - YEAR(NOW()));
  UPDATE dispatch_test_sets, test_timepoints_per_period
    SET hours_in_sample = @present_day_period_length*8764/cnt
    WHERE dispatch_test_sets.training_set_id = @training_set_id AND
      dispatch_test_sets.periodnum IS NULL AND 
      test_timepoints_per_period.periodnum IS NULL;

	-- We're finished processing this training set, so delete it from the work list.
	delete from training_sets_tmp where training_set_id = @training_set_id;
			
	-- Drop the tables that are supposed to be temporary
 	DROP TABLE IF EXISTS t_period_populations;
 	DROP TABLE IF EXISTS incomplete_test_sets;
 	DROP TABLE IF EXISTS test_timepoints_per_period;
	DROP TABLE IF EXISTS t_period_years;

	IF ( (select count(*) from training_sets_tmp) = 0 )
			THEN LEAVE define_new_training_sets_loop;
					END IF;
END LOOP define_new_training_sets_loop;
drop table if exists training_sets_tmp;
drop table if exists tmonths;

END;
$$
delimiter ;


DELIMITER $$
DROP FUNCTION IF EXISTS clone_scenario_v3$$
CREATE FUNCTION clone_scenario_v3 (name varchar(128), model_v varchar(16), inputs_diff varchar(16), source_scenario_id int ) RETURNS int
BEGIN

	DECLARE new_id INT DEFAULT 0;
	INSERT INTO scenarios_v3 (scenario_name, training_set_id, regional_cost_multiplier_scenario_id, regional_fuel_cost_scenario_id, gen_costs_scenario_id, gen_info_scenario_id, enable_rps, carbon_cap_scenario_id, notes, model_version, inputs_adjusted)

  SELECT name, training_set_id, regional_cost_multiplier_scenario_id, regional_fuel_cost_scenario_id, gen_costs_scenario_id, gen_info_scenario_id, enable_rps, carbon_cap_scenario_id, notes, model_v, inputs_diff
		FROM scenarios_v3 where scenario_id=source_scenario_id;

  SELECT LAST_INSERT_ID() into new_id;

  RETURN (new_id);
END$$

DELIMITER ;
