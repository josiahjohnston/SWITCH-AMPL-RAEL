create database if not exists switch_inputs_wecc_v2_2;
use switch_inputs_wecc_v2_2;

-- add entries to the insert into training_sets statement to add training sets to the model
-- also, to make good subsampling scenarios, add lines to DefineScenarios.SQL
	
	
	
CREATE TABLE IF NOT EXISTS training_sets (
  training_set_id INT NOT NULL,
  base_year YEAR NOT NULL,
  years_per_period INT NOT NULL,
  number_of_periods INT NOT NULL,
  selection_method VARCHAR(64) NOT NULL COMMENT 'This field describes the method of selection of timepoints. The two main methods - MEDIAN and RAND - differ in their selection of representative timepoints. MEDIAN selects days with near-median loads. RAND selects representative days at random.',
  notes TEXT COMMENT 'This field describes the selection method in full sentences. ',
  PRIMARY KEY (training_set_id)
)
COMMENT = 'This stores descriptions of a set of timepoints that the SWITCH model optimizes cost over. i.e. Training sets ';


insert ignore into training_sets ( training_set_id, base_year, years_per_period, number_of_periods, selection_method, notes ) VALUES
	( 1, 2014, 4, 4, 'MEDIAN', 'Starting in 2014, with 4 years per period, For each month, the day with peak load and a representative day with near-median load were selected. The peak day was selected by average hourly consumption (system-wide), while the median was based on total consumption during the day.' ),
	( 2, 2015, 10, 4, 'MEDIAN', 'Starting in 2015, with 10 years per period, For each month, the day with peak load and a representative day with near-median load were selected. The peak day was selected by average hourly consumption (system-wide), while the median was based on total consumption during the day.' )
	;


-- Study Hours----------------------
-- Randomly select study dates and hours for the SWITCH model. 
-- Sub-sampling of specific months and hours are the responsibility of the shell script that exports data from the DB

-- Make a table of study hours
CREATE TABLE IF NOT EXISTS study_hours_all (
  training_set_id INT NOT NULL,
  period year,
  study_date INT,
  study_hour INT,
  date_utc DATE, 
  month_of_year INT,
  hours_in_sample DOUBLE,
  hour_of_day INT,
  hournum INT,
  datetime_utc DATETIME, 
  INDEX training_set_id(training_set_id),
  INDEX date_utc(date_utc),
  INDEX datetime_utc(datetime_utc),
  INDEX hour(hournum),
  INDEX period(period),
  INDEX date_subselect(period, training_set_id),
  INDEX hour_subselect(period, training_set_id, hours_in_sample),
  PRIMARY KEY id_hour (training_set_id, study_hour),
  CONSTRAINT training_set_id FOREIGN KEY training_set_id (training_set_id)
    REFERENCES training_sets (training_set_id),
  CONSTRAINT hournum FOREIGN KEY hournum (hournum)
    REFERENCES hours (hournum)
);


-- makes a table of study dates
CREATE TABLE IF NOT EXISTS study_dates_all (
  training_set_id INT NOT NULL,
  period year,
  study_date INT,
  date_utc DATE, 
  month_of_year INT,
  hours_in_sample DOUBLE,
  INDEX training_set_id(training_set_id),
  INDEX date_utc(date_utc),
  INDEX period(period),
  INDEX date_subselect(period, training_set_id),
  INDEX hour_subselect(period, training_set_id, hours_in_sample),
  PRIMARY KEY (training_set_id, study_date), 
  CONSTRAINT training_set_id FOREIGN KEY training_set_id (training_set_id)
    REFERENCES training_sets (training_set_id)
);





DROP PROCEDURE IF EXISTS define_all_training_sets;
DELIMITER $$
CREATE PROCEDURE define_all_training_sets()
BEGIN

-- create a tmp table off of which to go through the training sets loop
drop table if exists training_sets_tmp;
create table training_sets_tmp as select * from training_sets;

-- start the loop to define training sets
    define_all_training_sets_loop: LOOP

-- find what scenario parameters we're going to be using
select 
	@training_set_id := training_set_id,
    @base_year := base_year,
    @years_per_period := years_per_period,
    @number_of_periods := number_of_periods,
    @selection_method := selection_method
from (select * from training_sets_tmp limit 1) as training_sets_tmp_top_row;

	
	-- This select sets @training_set_id to the next valid id
	-- old code, but helpful to have around
	-- set @training_set_id := (select if(max(training_set_id) is null, 1, max(training_set_id)+1) from training_sets);
	-- INSERT INTO training_sets VALUES ( @training_set_id, @base_year, @years_per_period, @number_of_periods, @training_set_method, @training_set_notes );
	
	
	-- make a list of all the possible periods
	drop table if exists tperiods;
	create table if not exists tperiods (periodnum int PRIMARY KEY);
	insert IGNORE into tperiods (periodnum) values (0), (1), (2), (3), (4), (5), (6), (7), (8), (9), (10);
	delete from tperiods where periodnum > ( @number_of_periods - 1 );

	
	-- make a list of all the possible months
	-- also report the number of days in each month, for sample-weighting later
	create table if not exists tmonths (month_of_year tinyint PRIMARY KEY, days_in_month double);
	insert IGNORE into tmonths values 
	  (1, 31), (2, 29.25), (3, 31), (4, 30), (5, 31), (6, 30),
	  (7, 31), (8, 31), (9, 30), (10, 31), (11, 30), (12, 31);
	
	
	-- Create a list of all the dates for which we have 24 hours of data.
	-- The load data is the least scrubbed hourly data, so it will be used here to excluded days - the solar and wind data has proven robust to datetime problems
	-- This will exclude the Fall daylight savings times days because they are missing an hour,
	-- The first day of 2004 is already excluded because of the difference between datetime_utc and datetime_local (the load data starts on the 2nd of January utc)
	-- note that the load areas here are wecc_v1 load areas (should be changed over at some time, but the load data originates from here)
	-- drop temporary table if exists tdates;
	create table if not exists tdates (
		date_utc date primary key,
		month_of_year int,
		date_order double,
		max_load int,
		rank int,
		INDEX (date_utc),
		index mr (month_of_year, rank)
	);
	
	set @num_load_areas := (select count(distinct(area_id)) as num_load_areas from _system_load);

	insert ignore into tdates
	select 
		date(hours.datetime_utc) as date_utc,
		month(hours.datetime_utc) as month_of_year,
		rand() as date_order,
		NULL as max_load,
		NULL as rank
		from hours,
			(select hour from
				(select hour,
						count(*) as number_of_loads_in_hournum
					from _system_load
					group by 1
					) as number_of_loads_in_hournum_table
			where number_of_loads_in_hournum = @num_load_areas
			) as complete_load_hours
		where hours.hournum = complete_load_hours.hour;
	
	
	-- Add the peak system load for every day considered
	-- drop temporary table if exists thourtotal;
	create table if not exists thourtotal 
		(hour int PRIMARY KEY, system_load int, date_utc date, INDEX (date_utc));
	insert ignore into thourtotal
		select hour, sum(system_load.power) as system_load, date(datetime_utc) from system_load join hours on(hournum=hour) group by 1;
	update tdates set tdates.max_load = (
	  select max( thourtotal.system_load ) 
	    from thourtotal
	    where thourtotal.date_utc = tdates.date_utc
	) where max_load is NULL;
	
	-- Create a list of days with peak load by month
	-- drop temporary table if exists tmaxday_in_month;
	create table if not exists tmaxday_in_month (
	  month_of_year int PRIMARY KEY,
	  max_load int,
	  max_load_date datetime
	);
	insert ignore into tmaxday_in_month (month_of_year, max_load)
	  select month(tdates.date_utc) as month_of_year, max( max_load ) as max_load
	    from tdates group by 1;
	update tmaxday_in_month, thourtotal, hours set 
	  tmaxday_in_month.max_load_date = hours.datetime_utc 
	  where thourtotal.hour = hours.hournum and thourtotal.system_load = tmaxday_in_month.max_load;
	
	-- Mark the peak days of each month by setting their date_order column to a 2. This will ensure they have the top rank, since the rest of the historic dates have date_order values between 0 & 1.
	update tdates, tmaxday_in_month set tdates.date_order = 2
	  where tdates.date_utc = date( tmaxday_in_month.max_load_date );
	
	-- randomly order the dates that fall within each month of the year
	-- they will be selected for study (without replacement) based on this ordering.
	-- another option would be a stratified approach, e.g. just to take the 15th of the month, 
	-- and alternate between using data from the first or second year of measurements
	set @lastrank = 0, @lastmonth = 0;
	-- to switch from random ordering to choosing days with median loads, change 'date_order' in the order by clause to 'max_load'
	-- to switch from choosing days with median loads to random ordering, change 'max_load' in the order by clause to 'date_order'
	update tdates set rank = (@lastrank := if(@lastmonth=(@lastmonth:=month_of_year), @lastrank+1, 1)) order by month_of_year, max_load desc;
	

	-- Make a table listing the individual dates that we are sampling
	-- Choose the individual dates from the datelist, based on their ordering
	-- The first study period uses one of the dates in the middle of the list, second uses the one after, etc.
	-- This strategy allows us to easily switch between selecting random dates and dates with near-median loads.
	-- We also report how many hours are represented by each sample, for weighting in the optimization
	-- The formula for the number of hours represented by each sample is based on one less than the days in 
	-- the month, to avoid overlapping with the days of peak load.
	INSERT IGNORE INTO study_dates_all ( training_set_id, period, study_date, date_utc, month_of_year, hours_in_sample )
	  select @training_set_id, periodnum * @years_per_period + @base_year as period, 
	    -- create unique ids for each date of the simulation
	    -- NOTE: the following code assumes that no historical date is used more than once in the same investment period
	    -- it also assumes that study periods and historical years are uniquely identified by their last two digits
	    (periodnum * @years_per_period + @base_year mod 100) * 1000000 + mod(year(date_utc), 100) * 10000 + month(date_utc)*100 + day(date_utc) as study_date, 
	    date_utc, d.month_of_year, 
	    (days_in_month-1)*@years_per_period as hours_in_sample
	    from tperiods p join tmonths m 
	      join tdates d 
	        on (d.month_of_year=m.month_of_year and
	      	    d.rank = floor( m.days_in_month / 2 - @number_of_periods/2 + p.periodnum ) 
	      	)
	      order by period, month_of_year, date_utc;
	
	-- Add the dates with peak loads. The peak load have a rank of 1.
	INSERT IGNORE INTO study_dates_all ( training_set_id, period, study_date, date_utc, month_of_year, hours_in_sample )
	  select @training_set_id, periodnum * @years_per_period + @base_year as period, 
	    -- create unique ids for each date of the simulation
	    -- NOTE: the following code assumes that no historical date is used more than once in the same investment period
	    -- it also assumes that study periods and historical years are uniquely identified by their last two digits
	    (periodnum * @years_per_period + @base_year mod 100) * 1000000 + mod(year(date_utc), 100) * 10000 + month(date_utc)*100 + day(date_utc) as study_date, 
	    date_utc, d.month_of_year, 
	    @years_per_period as hours_in_sample
	    from tperiods p join tdates d 
	    where rank = periodnum+1 
	      order by period, month_of_year, date_utc;
	
	-- create the final list of study hours
	INSERT IGNORE INTO study_hours_all ( training_set_id, period, study_date, study_hour, date_utc, month_of_year, hours_in_sample, hour_of_day, hournum, datetime_utc )
	  select @training_set_id, period, study_date, 
	    -- create unique ids for each hour of the simulation
	    ((period mod 100) * 10000 + month_of_year * 100 + hour(datetime_utc)) * 1000 + (year(date_utc) mod 10) * 100 + day(date_utc)  as study_hour,
	    date_utc, month_of_year, hours_in_sample,
	    hour(datetime_utc) as hour_of_day, hournum, datetime_utc
	    from study_dates_all d join hours h on d.date_utc = date(h.datetime_utc)
	      where training_set_id = @training_set_id
	      order by period, month_of_year, datetime_utc;
	


-- now we're done with that training set
delete from training_sets_tmp where training_set_id = @training_set_id;
    
IF ( (select count(*) from training_sets_tmp) = 0 )
    THEN LEAVE define_all_training_sets_loop;
        END IF;
END LOOP define_all_training_sets_loop;

END;
$$
delimiter ;

-- excute the procedure
CALL define_all_training_sets();
DROP PROCEDURE define_all_training_sets;





CREATE TABLE IF NOT EXISTS scenarios (
  scenario_id INT NOT NULL AUTO_INCREMENT,
  scenario_name VARCHAR(128),
  training_set_id INT NOT NULL,
  exclude_peaks BOOLEAN NOT NULL default 0, 
  exclude_periods VARCHAR(256) NOT NULL default '' COMMENT 'If you want to exclude the periods starting at 2010 and 2018, you would set this to "2010,2018".',
  period_reduced_by float NOT NULL DEFAULT 1 COMMENT 'If you exclude 2 of four periods, set this value to 4/2=2. If you do not exclude any periods, this will default to 1. The "hours_in_sample" are multiplied by this factor to scale them appropriately.',
  regional_cost_multiplier_scenario_id INT NOT NULL DEFAULT 1, 
  regional_fuel_cost_scenario_id INT NOT NULL DEFAULT 1, 
  regional_gen_price_scenario_id INT NOT NULL DEFAULT 1, 
  months_between_samples INT NOT NULL DEFAULT 6, 
  start_month INT NOT NULL DEFAULT 3 COMMENT 'The value of START_MONTH should be between 0 and one less than the value of NUM_HOURS_BETWEEN_SAMPLES. 0 means sampling starts in Jan, 1 means Feb, 2 -> March, 3 -> April', 
  hours_between_samples INT NOT NULL DEFAULT 24, 
  start_hour INT NOT NULL DEFAULT 11 COMMENT 'The value of START_HOUR should be between 0 and one less than the value of NUM_HOURS_BETWEEN_SAMPLES. 0 means sampling starts at 12am, 1 means 1am, ... 15 means 3pm, etc', 
  enable_rps BOOLEAN NOT NULL DEFAULT 0 COMMENT 'This controls whether Renewable Portfolio Standards are considered in the optimization.', 
  enable_carbon_cap BOOLEAN NOT NULL DEFAULT 0 COMMENT 'This controls whether a carbon cap is considered in the optimization.',
  notes TEXT,
  num_timepoints INT, 
  _datesample TEXT,
  _timesample TEXT,
  _hours_in_sample TEXT,
  PRIMARY KEY (scenario_id), 
  UNIQUE INDEX unique_params(training_set_id, exclude_peaks, exclude_periods, period_reduced_by, regional_cost_multiplier_scenario_id, regional_fuel_cost_scenario_id, regional_gen_price_scenario_id, months_between_samples, start_month, hours_between_samples, start_hour, enable_rps, enable_carbon_cap), 
  CONSTRAINT training_set_id FOREIGN KEY training_set_id (training_set_id)
    REFERENCES training_sets (training_set_id), 
  CONSTRAINT regional_cost_multiplier_scenario_id FOREIGN KEY regional_cost_multiplier_scenario_id (regional_cost_multiplier_scenario_id)
    REFERENCES regional_economic_multiplier (scenario_id), 
  CONSTRAINT regional_fuel_cost_scenario_id FOREIGN KEY regional_fuel_cost_scenario_id (regional_fuel_cost_scenario_id)
    REFERENCES regional_fuel_prices (scenario_id), 
  CONSTRAINT regional_gen_price_scenario_id FOREIGN KEY regional_gen_price_scenario_id (regional_gen_price_scenario_id)
    REFERENCES regional_generator_costs (scenario_id)
)
COMMENT = 'Each record in this table is a specification of how to compile a set of inputs for a specific run. Several fields specify how to subselect timepoints from a given training_set. Other fields indicate which set of regional price data to use.';


DELIMITER $$

DROP FUNCTION IF EXISTS set_scenarios_sql_columns$$
CREATE FUNCTION set_scenarios_sql_columns (target_scenario_id int) RETURNS INT 
BEGIN
  DECLARE done INT DEFAULT 0;
  DECLARE current_scenario_id INT;
  DECLARE cur_id_list CURSOR FOR SELECT scenario_id FROM switch_inputs_wecc_v2_2.scenarios WHERE switch_inputs_wecc_v2_2.scenarios.scenario_id >= target_scenario_id;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;
  
  DROP TEMPORARY TABLE IF EXISTS switch_inputs_wecc_v2_2.__set_scenarios_sql_columns;
  CREATE TEMPORARY TABLE switch_inputs_wecc_v2_2.__set_scenarios_sql_columns
    SELECT * FROM switch_inputs_wecc_v2_2.scenarios WHERE switch_inputs_wecc_v2_2.scenarios.scenario_id >= target_scenario_id;

  OPEN cur_id_list;
  
  REPEAT
    FETCH cur_id_list INTO current_scenario_id;
  
    UPDATE switch_inputs_wecc_v2_2.scenarios
      SET 
        _datesample = concat(
            concat( 'FIND_IN_SET( period, "', exclude_periods, '")=0 and '), 
            'MOD(month_of_year, ', months_between_samples, ') = ', start_month, ' and ',
            'training_set_id = ', training_set_id, 
            if( exclude_peaks, ' and hours_in_sample > 100', '')
        )
      WHERE switch_inputs_wecc_v2_2.scenarios.scenario_id = current_scenario_id;
    UPDATE switch_inputs_wecc_v2_2.scenarios
      SET 
        _timesample = concat(
            _datesample, ' and ', 
            'MOD(hour_of_day, ', hours_between_samples, ') = ', start_hour
        ),
        _hours_in_sample = if( period_reduced_by * months_between_samples * hours_between_samples != 1,
           concat( 'hours_in_sample', '*', period_reduced_by, '*', months_between_samples, '*', hours_between_samples ), 
           'hours_in_sample'
        )
      WHERE switch_inputs_wecc_v2_2.scenarios.scenario_id = current_scenario_id;
    UPDATE switch_inputs_wecc_v2_2.scenarios
      SET 
        switch_inputs_wecc_v2_2.scenarios.num_timepoints = 
        (select count(switch_inputs_wecc_v2_2.study_hours_all.hournum) 
          from switch_inputs_wecc_v2_2.study_hours_all, switch_inputs_wecc_v2_2.__set_scenarios_sql_columns params
          where
            params.scenario_id = current_scenario_id and
            switch_inputs_wecc_v2_2.study_hours_all.training_set_id = params.training_set_id and
            FIND_IN_SET( switch_inputs_wecc_v2_2.study_hours_all.period, params.exclude_periods ) = 0 and 
            MOD(switch_inputs_wecc_v2_2.study_hours_all.month_of_year, params.months_between_samples ) = params.start_month and
            switch_inputs_wecc_v2_2.study_hours_all.hours_in_sample > 100*params.exclude_peaks and
            MOD(switch_inputs_wecc_v2_2.study_hours_all.hour_of_day, params.hours_between_samples) = params.start_hour
        )
      WHERE switch_inputs_wecc_v2_2.scenarios.scenario_id = current_scenario_id
    ;
    UPDATE switch_inputs_wecc_v2_2.scenarios
      SET 
        scenario_name = concat(
           't', target_scenario_id, '_', 
           if(exclude_peaks, 'np_', 'p_'),
           if(length(exclude_periods) > 0, 
             concat( 'xp_', replace(exclude_periods,',','_' ) ),
             ''
           ), 
           'regids', regional_cost_multiplier_scenario_id, '_', regional_fuel_cost_scenario_id, '_', regional_gen_price_scenario_id, '_', 
           'm', months_between_samples, '_', start_month, '_',
           'h', hours_between_samples, '_', start_hour
        )
      WHERE switch_inputs_wecc_v2_2.scenarios.scenario_id = current_scenario_id and (scenario_name is NULL or length(scenario_name) = 0)
      ;
  UNTIL done END REPEAT;
  CLOSE cur_id_list;
  
  DROP TEMPORARY TABLE switch_inputs_wecc_v2_2.__set_scenarios_sql_columns;
  RETURN (SELECT count(*) FROM switch_inputs_wecc_v2_2.scenarios WHERE scenario_id >= target_scenario_id);
END$$

DELIMITER ;

INSERT IGNORE INTO scenarios (scenario_name, training_set_id) 
  VALUES ( 'default scenario', @training_set_id );
select max(scenario_id) into @scenario_id from scenarios;
SELECT set_scenarios_sql_columns( @scenario_id );


-- Drop the tables that are supposed to be temporary if the script finished successfully.
drop table if exists tperiods;
drop table if exists tmonths;
drop table if exists tdates;
drop table if exists thourtotal;
drop table if exists tmaxday_in_month;
