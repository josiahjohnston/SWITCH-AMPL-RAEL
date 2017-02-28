-- This file defines database schema and methods for subsampling timepoints.

create database if not exists switch_inputs_wecc_v2_2;
use switch_inputs_wecc_v2_2;
	
CREATE TABLE IF NOT EXISTS training_sets (
  training_set_id INT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT,
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
  training_set_id INT UNSIGNED NOT NULL,
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
  training_set_id INT UNSIGNED NOT NULL,
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
  hours_in_sample  decimal(10,4),
  UNIQUE (training_set_id, test_set_id, timepoint_id),
  INDEX (training_set_id, test_set_id, timepoint_id, historic_hour),
  INDEX (training_set_id, periodnum),
  CONSTRAINT training_set_id_fk FOREIGN KEY training_set_id_fk (training_set_id)
    REFERENCES training_sets (training_set_id)
);

CREATE TABLE _dispatch_load_summary (
  training_set_id int unsigned NOT NULL,
  period year NOT NULL,
  load_in_period_mwh decimal(20,0),
  PRIMARY KEY (training_set_id, period)
);

CREATE TABLE IF NOT EXISTS scenarios_v3 (
  scenario_id INT NOT NULL AUTO_INCREMENT,
  scenario_name VARCHAR(128),
  training_set_id INT NOT NULL,
  base_year INT COMMENT 'I think this would be better off in a new version of training_sets, but that would be less backwards compatible with archived scenarios that used the same training sets over multiple years and consequently used multiple base_years for a single training_set when base_year was set to now() during execution rather than being explicitly defined.',
  regional_cost_multiplier_scenario_id INT NOT NULL DEFAULT 1, 
  regional_fuel_cost_scenario_id INT NOT NULL DEFAULT 1, 
  gen_costs_scenario_id MEDIUMINT NOT NULL DEFAULT 2 COMMENT 'The default scenario is 2 and has the baseline cost assumptions.', 
  gen_info_scenario_id MEDIUMINT NOT NULL DEFAULT 2 COMMENT 'The default scenario is 2 and has the baseline generator assumptions.',
  enable_rps BOOLEAN NOT NULL DEFAULT 0 COMMENT 'This controls whether Renewable Portfolio Standards are considered in the optimization.', 
  carbon_cap_scenario_id int unsigned DEFAULT 0 COMMENT 'The default scenario is no cap. Browse existing scenarios or define new ones in the table carbon_cap_scenarios.',
  nems_fuel_scenario_id int unsigned DEFAULT 1 COMMENT 'The default scenario is the reference case. Check out the nems_fuel_scenarios table for other scenarios.',
  dr_scenario_id int unsigned default NULL COMMENT 'The default scenario is NULL: no demand response scenario specified. The DR scenario is linked to the load_scenario_id. Browse existing DR scenarios or define new ones in the demand_response_scenarios table.',
  ev_scenario_id int unsigned default NULL COMMENT 'The default scenario is NULL: no ev demand response scenario specified. The EV scenario is linked to the load_scenario_id. Browse existing EV scenarios or define new ones in the ev_scenarios table.',
  enforce_ca_dg_mandate BOOLEAN NOT NULL DEFAULT 0,
  linearize_optimization BOOLEAN NOT NULL DEFAULT 0,
  transmission_capital_cost_per_mw_km INT NOT NULL DEFAULT 1000,
  notes TEXT,
  model_version varchar(16) NOT NULL,
  inputs_adjusted varchar(16) NOT NULL DEFAULT 'no',
  PRIMARY KEY (scenario_id), 
  UNIQUE KEY unique_params (scenario_name, training_set_id, base_year, regional_cost_multiplier_scenario_id, regional_fuel_cost_scenario_id, gen_costs_scenario_id, gen_info_scenario_id, enable_rps, carbon_cap_scenario_id, nems_fuel_scenario_id, dr_scenario_id, ev_scenario_id, enforce_ca_dg_mandate, linearize_optimization, model_version, inputs_adjusted, transmission_capital_cost_per_mw_km), 
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


drop PROCEDURE if exists `prepare_load_exports2`;
DELIMITER $$
CREATE PROCEDURE `prepare_load_exports2`(IN target_scenario_id INT)
BEGIN
    -- This version takes a scenario id instead of a training set id, and will
    -- retrieve the base year of the scenario from the scenario table instead
    -- of getting it from the execution time via now().
    SET @training_set_id := (select training_set_id FROM scenarios_v3 WHERE scenario_id=target_scenario_id);
	SET @load_scenario_id := (select load_scenario_id FROM training_sets WHERE training_set_id=@training_set_id);
	set @base_year := (SELECT base_year FROM scenarios_v3 WHERE scenario_id=target_scenario_id);
	set @num_historic_years := (select count(distinct year(datetime_utc)) from hours JOIN load_scenario_historic_timepoints ON(historic_hour=hournum) WHERE load_scenario_id=@load_scenario_id);
	DROP TABLE IF EXISTS present_day_timepoint_map;
	CREATE TEMPORARY TABLE present_day_timepoint_map 
		SELECT timepoint_id as future_timepoint_id, DATE_SUB(s.datetime_utc, INTERVAL period-@base_year + FLOOR((years_per_period-@num_historic_years)/2) YEAR) as present_day_timepoint
			FROM _training_set_timepoints t
				JOIN training_sets USING(training_set_id)
				JOIN study_timepoints  s USING (timepoint_id)
			WHERE training_set_id=@training_set_id 
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
		WHERE training_set_id=@training_set_id AND load_scenario_id=@load_scenario_id;
	UPDATE scenario_loads_export, present_day_timepoint_map, _load_projections
		SET present_day_system_load = _load_projections.power
		WHERE scenario_loads_export.timepoint_id    = future_timepoint_id
			AND scenario_loads_export.area_id         = _load_projections.area_id
			AND scenario_loads_export.training_set_id = @training_set_id
			AND _load_projections.timepoint_id        = present_day_timepoint_id 
			AND _load_projections.load_scenario_id    = @load_scenario_id;
	UPDATE scenario_loads_export e, load_area_info, study_timepoints
		SET e.load_area = load_area_info.load_area,
				e.datetime_utc = study_timepoints.datetime_utc
		WHERE e.area_id = load_area_info.area_id AND e.timepoint_id = study_timepoints.timepoint_id;
END$$
DELIMITER ;


DROP PROCEDURE IF EXISTS clean_load_exports$$
CREATE PROCEDURE clean_load_exports( IN target_training_set_id INT UNSIGNED)
BEGIN
	DELETE FROM scenario_loads_export WHERE training_set_id = target_training_set_id;
	IF( (SELECT COUNT(*) FROM scenario_loads_export) = 0 ) THEN
		DROP TABLE scenario_loads_export;
	END IF;
END$$

DELIMITER ;

-- Res/comm and EV demand response
DROP PROCEDURE IF EXISTS prepare_res_comm_shiftable_load_exports;

DELIMITER $$

CREATE PROCEDURE prepare_res_comm_shiftable_load_exports( IN target_training_set_id INT UNSIGNED, IN target_scenario_id INT UNSIGNED)
BEGIN
	SET @load_scenario_id := (select load_scenario_id FROM training_sets WHERE training_set_id=target_training_set_id);
	SET @dr_scenario_id := (select dr_scenario_id FROM scenarios_v3 WHERE scenario_id = target_scenario_id );
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
	CREATE TABLE IF NOT EXISTS scenario_res_comm_shiftable_loads_export (
		training_set_id INT UNSIGNED,
		scenario_id int unsigned,
		area_id SMALLINT UNSIGNED,
		load_area varchar(20),
		timepoint_id INT UNSIGNED,
		datetime_utc datetime,
		shiftable_res_comm_load double,
		shifted_res_comm_load_hourly_max double,
		PRIMARY KEY(training_set_id, scenario_id, area_id, timepoint_id), 
		INDEX(timepoint_id,area_id)
	);
	REPLACE INTO scenario_res_comm_shiftable_loads_export ( training_set_id, scenario_id, area_id, timepoint_id, shiftable_res_comm_load, shifted_res_comm_load_hourly_max )
		SELECT training_set_id, target_scenario_id as scenario_id, f.area_id, f.timepoint_id, f.shiftable_res_comm_load, f.shifted_res_comm_load_hourly_max
		FROM _training_set_timepoints
			JOIN shiftable_res_comm_load f USING (timepoint_id)
		WHERE training_set_id=target_training_set_id AND load_scenario_id=@load_scenario_id AND dr_scenario_id=@dr_scenario_id;
	
	UPDATE scenario_res_comm_shiftable_loads_export e, load_area_info, study_timepoints
		SET e.load_area = load_area_info.load_area,
				e.datetime_utc = study_timepoints.datetime_utc
		WHERE e.area_id = load_area_info.area_id AND e.timepoint_id = study_timepoints.timepoint_id;
END$$

DROP PROCEDURE IF EXISTS clean_res_comm_shiftable_load_exports$$
CREATE PROCEDURE clean_res_comm_shiftable_load_exports( IN target_training_set_id INT UNSIGNED, IN target_scenario_id int unsigned)
BEGIN
	DELETE FROM scenario_res_comm_shiftable_loads_export WHERE training_set_id = target_training_set_id and scenario_id = target_scenario_id;
	IF( (SELECT COUNT(*) FROM scenario_res_comm_shiftable_loads_export) = 0 ) THEN
		DROP TABLE scenario_res_comm_shiftable_loads_export;
	END IF;
END$$

DELIMITER ;

DROP PROCEDURE IF EXISTS prepare_ev_shiftable_load_exports;

DELIMITER $$

CREATE PROCEDURE prepare_ev_shiftable_load_exports( IN target_training_set_id INT UNSIGNED, IN target_scenario_id INT UNSIGNED)
BEGIN
	SET @load_scenario_id := (select load_scenario_id FROM training_sets WHERE training_set_id=target_training_set_id);
	SET @ev_scenario_id := (select ev_scenario_id FROM scenarios_v3 WHERE scenario_id = target_scenario_id );
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
	CREATE TABLE IF NOT EXISTS scenario_ev_shiftable_loads_export (
		training_set_id INT UNSIGNED,
		scenario_id int unsigned,
		area_id SMALLINT UNSIGNED,
		load_area varchar(20),
		timepoint_id INT UNSIGNED,
		datetime_utc datetime,
		shiftable_ev_load double,
		shifted_ev_load_hourly_max double,
		PRIMARY KEY(training_set_id, scenario_id, area_id, timepoint_id), 
		INDEX(timepoint_id,area_id)
	);
	REPLACE INTO scenario_ev_shiftable_loads_export ( training_set_id, scenario_id, area_id, timepoint_id, shiftable_ev_load, shifted_ev_load_hourly_max )
		SELECT training_set_id, target_scenario_id as scenario_id, f.area_id, f.timepoint_id, f.shiftable_ev_load, f.shifted_ev_load_hourly_max
		FROM _training_set_timepoints
			JOIN shiftable_ev_load f USING (timepoint_id)
		WHERE training_set_id=target_training_set_id AND load_scenario_id=@load_scenario_id AND ev_scenario_id=@ev_scenario_id;
	
	UPDATE scenario_ev_shiftable_loads_export e, load_area_info, study_timepoints
		SET e.load_area = load_area_info.load_area,
				e.datetime_utc = study_timepoints.datetime_utc
		WHERE e.area_id = load_area_info.area_id AND e.timepoint_id = study_timepoints.timepoint_id;
END$$

DROP PROCEDURE IF EXISTS clean_ev_shiftable_load_exports$$
CREATE PROCEDURE clean_ev_shiftable_load_exports( IN target_training_set_id INT UNSIGNED, IN target_scenario_id int unsigned)
BEGIN
	DELETE FROM scenario_ev_shiftable_loads_export WHERE training_set_id = target_training_set_id and scenario_id = target_scenario_id;
	IF( (SELECT COUNT(*) FROM scenario_ev_shiftable_loads_export) = 0 ) THEN
		DROP TABLE scenario_ev_shiftable_loads_export;
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
DROP TABLE IF EXISTS historic_dates_used;
DROP TABLE IF EXISTS month_cursor;
DROP TABLE IF EXISTS t_period_years;

-- create a tmp table off of which to go through the training sets loop
create table training_sets_tmp as 
	select * from training_sets 
		where load_scenario_id IS NOT NULL AND
			training_set_id NOT IN (select distinct training_set_id from _training_set_timepoints);

-- make a list of all the possible months
-- also report the number of days in each month, for sample-weighting later
create table if not exists tmonths (month_of_year tinyint PRIMARY KEY, days_in_month double);
insert IGNORE into tmonths values 
	(1, 31), (2, 28.25), (3, 31), (4, 30), (5, 31), (6, 30),
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
  CREATE TEMPORARY TABLE t_period_years
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
	CREATE TABLE historic_dates_used (date_utc date PRIMARY KEY);
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
						AND historic_date_utc NOT IN (SELECT * FROM historic_dates_used)
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
				INSERT INTO historic_dates_used 
					SELECT historic_date_utc FROM _load_projection_daily_summaries WHERE load_scenario_id=@load_scenario_id AND date_utc=@peak_day;
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
							WHERE periodnum = @periodnum AND MONTH(date_utc) = @month AND load_scenario_id=@load_scenario_id AND historic_date_utc NOT IN (SELECT * FROM historic_dates_used)
					);
					SET @date_utc := 0;
					SET @date_sql_select := CONCAT(
						'SELECT date_utc INTO @date_utc',
						'	FROM _load_projection_daily_summaries JOIN t_period_populations USING (date_utc) ',
						'	WHERE periodnum = @periodnum AND MONTH(date_utc) = @month AND load_scenario_id=@load_scenario_id AND historic_date_utc NOT IN (SELECT * FROM historic_dates_used) ',
						'	ORDER BY total_load ',
						'	LIMIT 1 ',
						'	OFFSET ',(select FLOOR(@n_dates/2)));
					PREPARE date_selection_stmt FROM @date_sql_select;
					EXECUTE date_selection_stmt;
					INSERT INTO _training_set_timepoints (training_set_id, period, timepoint_id, hours_in_sample)
						SELECT @training_set_id, @period, timepoint_id, @hours_in_sample
							FROM study_timepoints
							WHERE DATE(datetime_utc) = @date_utc AND (HOUR(datetime_utc) MOD @hours_between_samples) = (@start_hour MOD @hours_between_samples);
				WHEN 'MEAN' THEN
				  set @monthly_avg := (
				    SELECT avg(total_load)
				    FROM _load_projection_daily_summaries
				      JOIN t_period_populations USING(date_utc)
            WHERE MONTH(date_utc) = @month 
              AND periodnum        = @periodnum
              AND load_scenario_id = @load_scenario_id
          );
          IF(@exclude_peaks = 0) THEN
            SET @days_in_month := (SELECT days_in_month FROM tmonths WHERE month_of_year = @month);
            set @daily_target := (
              SELECT ( @monthly_avg * @days_in_month - total_load) / (@days_in_month - 1)
              FROM _load_projection_daily_summaries
              WHERE date_utc = @peak_day
                AND load_scenario_id=@load_scenario_id 
            );
          ELSE
            SET @daily_target := @monthly_avg;
          END IF;
					SET @date_utc := (
  					SELECT date_utc
              FROM _load_projection_daily_summaries JOIN t_period_populations USING (date_utc) 
              WHERE periodnum = @periodnum AND MONTH(date_utc) = @month AND load_scenario_id=@load_scenario_id AND historic_date_utc NOT IN (SELECT * FROM historic_dates_used) 
              ORDER BY abs(total_load - @daily_target)
              LIMIT 1
          );
					INSERT INTO _training_set_timepoints (training_set_id, period, timepoint_id, hours_in_sample)
						SELECT @training_set_id, @period, timepoint_id, @hours_in_sample
							FROM study_timepoints
							WHERE DATE(datetime_utc) = @date_utc AND (HOUR(datetime_utc) MOD @hours_between_samples) = (@start_hour MOD @hours_between_samples);
				WHEN 'RAND'   THEN
					SET @date_utc := (
						SELECT date_utc 
						FROM _load_projection_daily_summaries JOIN t_period_populations USING (date_utc) 
						WHERE periodnum = @periodnum 
							AND MONTH(date_utc) = @month 
							AND load_scenario_id=@load_scenario_id 
							AND historic_date_utc NOT IN (SELECT * FROM historic_dates_used)
						ORDER BY rand()
						LIMIT 1
					);
					INSERT INTO _training_set_timepoints (training_set_id, period, timepoint_id, hours_in_sample)
						SELECT @training_set_id, @period, timepoint_id, @hours_in_sample
							FROM study_timepoints
							WHERE DATE(datetime_utc) = @date_utc AND (HOUR(datetime_utc) MOD @hours_between_samples) = (@start_hour MOD @hours_between_samples);					
			END CASE;
			INSERT INTO historic_dates_used 
				SELECT historic_date_utc FROM _load_projection_daily_summaries WHERE load_scenario_id=@load_scenario_id AND date_utc=@date_utc;

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
 	DROP TABLE historic_dates_used;

	CALL define_test_set(@training_set_id);

	-- We're finished processing this training set, so delete it from the work list.
	delete from training_sets_tmp where training_set_id = @training_set_id;
			
	-- Drop the tables that are supposed to be temporary
 	DROP TABLE IF EXISTS t_period_populations;
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

DROP PROCEDURE IF EXISTS define_test_set;
DELIMITER $$
CREATE PROCEDURE define_test_set(this_training_set_id int)
BEGIN
  set @hours_per_test_set := 1*24;

  set @load_scenario_id=0, @study_start_year=0, @years_per_period=0, @number_of_periods=0;
  select load_scenario_id, study_start_year, years_per_period, number_of_periods
    INTO @load_scenario_id, @study_start_year, @years_per_period, @number_of_periods
  from training_sets WHERE training_set_id=this_training_set_id;

  set @first_historic_hour := (select min(historic_hour) from load_scenario_historic_timepoints where load_scenario_id=@load_scenario_id);
  set @num_load_areas := (select count(distinct(area_id)) as num_load_areas from load_area_info);

  set @min_historical_year := (select min(year(datetime_utc)) from hours JOIN load_scenario_historic_timepoints ON(historic_hour=hournum) WHERE load_scenario_id=@load_scenario_id);
  set @num_historical_years := (select count(distinct year(datetime_utc)) from hours JOIN load_scenario_historic_timepoints ON(historic_hour=hournum) WHERE load_scenario_id=@load_scenario_id);


 	DROP TABLE IF EXISTS incomplete_test_sets;
 	DROP TABLE IF EXISTS test_timepoints_per_period_month;
	DROP TABLE IF EXISTS years_to_sample_from;

	-- Make a list of years for each period that we will draw samples from.
	-- This picks years that are in the middle of the period. The number of years picked is equal to the number of historic years data was drawn from.
	set @period_offset    := (select FLOOR((@years_per_period - @num_historical_years) / 2));
	CREATE TABLE years_to_sample_from
		SELECT periodnum, period_start + @period_offset + historic_year_factor as sampled_year
			FROM training_set_periods, (SELECT DISTINCT year(datetime_utc)-@min_historical_year as historic_year_factor from hours JOIN load_scenario_historic_timepoints ON(historic_hour=hournum) WHERE load_scenario_id=@load_scenario_id) as foo
			WHERE training_set_id = this_training_set_id;
	ALTER TABLE years_to_sample_from ADD INDEX (periodnum), ADD INDEX (sampled_year), CHANGE COLUMN periodnum periodnum TINYINT(3) UNSIGNED NULL DEFAULT NULL;
	
  -- Skip entries for the present year for now.
--  INSERT INTO years_to_sample_from
--    SELECT NULL, year(now()) + historic_year_factor as sampled_year
--      FROM (SELECT DISTINCT year(datetime_utc)-@min_historical_year as historic_year_factor from hours JOIN load_scenario_historic_timepoints ON(historic_hour=hournum) WHERE load_scenario_id=@load_scenario_id) as foo;
  -- Add hourly entries for each distinct historical hour crossed with future periods (and the present)
  INSERT INTO dispatch_test_sets (training_set_id, test_set_id, periodnum, historic_hour, timepoint_id)
    SELECT this_training_set_id, floor((historic_hour - @first_historic_hour)/@hours_per_test_set), periodnum, historic_hour, timepoint_id
    FROM load_scenario_historic_timepoints 
      JOIN study_timepoints USING(timepoint_id) 
      JOIN years_to_sample_from ON(timepoint_year=sampled_year)
      JOIN _load_projection_daily_summaries ON(DATE(datetime_utc)=date_utc)
    WHERE num_data_points = @num_load_areas * 24 AND
      _load_projection_daily_summaries.load_scenario_id = @load_scenario_id AND
      load_scenario_historic_timepoints.load_scenario_id = @load_scenario_id;
  -- Make a list of test sets with incomplete data
 	DROP TABLE IF EXISTS incomplete_test_sets;
  CREATE TEMPORARY TABLE incomplete_test_sets
    SELECT test_set_id, COUNT(*) as cnt FROM dispatch_test_sets WHERE training_set_id=this_training_set_id GROUP BY 1 HAVING cnt != @hours_per_test_set * @number_of_periods;
  ALTER TABLE incomplete_test_sets ADD UNIQUE (test_set_id);
  -- Delete test sets that have incomplete data. 
  DELETE dispatch_test_sets FROM dispatch_test_sets, incomplete_test_sets 
    WHERE dispatch_test_sets.training_set_id = this_training_set_id AND
      dispatch_test_sets.test_set_id = incomplete_test_sets.test_set_id;
  -- make a list of the length of every month
  create TEMPORARY table if not exists tmonths (month_of_year tinyint PRIMARY KEY, days_in_month double);
  insert IGNORE into tmonths values 
    (1, 31), (2, 28.25), (3, 31), (4, 30), (5, 31), (6, 30),
    (7, 31), (8, 31), (9, 30), (10, 31), (11, 30), (12, 31);
  -- Determine how much to weight each test timepoint. 
  CREATE TEMPORARY TABLE test_timepoints_per_period_month -- Counts how many test timepoints are in each period
    SELECT periodnum, month_of_year, COUNT(*) as cnt 
    FROM dispatch_test_sets 
      JOIN study_timepoints USING (timepoint_id)
    WHERE training_set_id=this_training_set_id 
    GROUP BY 1,2;
  UPDATE dispatch_test_sets, test_timepoints_per_period_month, tmonths, study_timepoints
    SET hours_in_sample = (@years_per_period * days_in_month * 24)/cnt
    WHERE dispatch_test_sets.training_set_id = this_training_set_id AND
      dispatch_test_sets.timepoint_id = study_timepoints.timepoint_id AND
      study_timepoints.month_of_year = tmonths.month_of_year AND
      study_timepoints.month_of_year = test_timepoints_per_period_month.month_of_year AND
      dispatch_test_sets.periodnum = test_timepoints_per_period_month.periodnum
      ;
  set @present_day_period_length := (select @study_start_year - YEAR(NOW()));
  UPDATE dispatch_test_sets, test_timepoints_per_period_month, tmonths, study_timepoints
    SET hours_in_sample = (@present_day_period_length * days_in_month * 24)/cnt
    WHERE dispatch_test_sets.training_set_id = this_training_set_id AND
      dispatch_test_sets.timepoint_id = study_timepoints.timepoint_id AND
      study_timepoints.month_of_year = tmonths.month_of_year AND
      study_timepoints.month_of_year = test_timepoints_per_period_month.month_of_year AND
      dispatch_test_sets.periodnum IS NULL AND 
      test_timepoints_per_period_month.periodnum IS NULL;

  -- Calculate the total load served in each period by these test sets
  INSERT INTO _dispatch_load_summary (training_set_id, period, load_in_period_mwh)
    SELECT training_set_id, period_start as period, sum(power*hours_in_sample) as load_in_period_mwh
    FROM dispatch_test_sets 
      JOIN training_sets USING (training_set_id)
      JOIN _load_projections USING(timepoint_id,load_scenario_id)
      JOIN training_set_periods USING(periodnum,training_set_id)
    WHERE training_set_id = @training_set_id
    GROUP BY 1,2;

 	DROP TABLE IF EXISTS incomplete_test_sets;
 	DROP TABLE IF EXISTS test_timepoints_per_period_month;
	DROP TABLE IF EXISTS years_to_sample_from;
	DROP TABLE IF EXISTS tmonths;

END;
$$
delimiter ;


DELIMITER $$
DROP FUNCTION IF EXISTS clone_scenario_v3$$
CREATE FUNCTION clone_scenario_v3 (_base_year INT, _scenario_name varchar(128), _model_version varchar(16), _inputs_adjusted varchar(16), source_scenario_id int ) RETURNS int DETERMINISTIC
BEGIN

	DECLARE new_id INT DEFAULT 0;
	INSERT INTO scenarios_v3 (scenario_name, training_set_id, base_year, regional_cost_multiplier_scenario_id,
        regional_fuel_cost_scenario_id, gen_costs_scenario_id, gen_info_scenario_id, enable_rps,
        nems_fuel_scenario_id, dr_scenario_id, ev_scenario_id, enforce_ca_dg_mandate, linearize_optimization,
        carbon_cap_scenario_id, notes, model_version, inputs_adjusted, transmission_capital_cost_per_mw_km)
    SELECT _scenario_name, training_set_id, _base_year, regional_cost_multiplier_scenario_id,
  	    regional_fuel_cost_scenario_id, gen_costs_scenario_id, gen_info_scenario_id, enable_rps,
      	nems_fuel_scenario_id, dr_scenario_id, ev_scenario_id, enforce_ca_dg_mandate, linearize_optimization,
      	carbon_cap_scenario_id, CONCAT("Based on scenario ", source_scenario_id), _model_version,
      	_inputs_adjusted, transmission_capital_cost_per_mw_km
    FROM scenarios_v3 where scenario_id=source_scenario_id;

  SELECT LAST_INSERT_ID() into new_id;

  RETURN (new_id);
END$$

DELIMITER ;
