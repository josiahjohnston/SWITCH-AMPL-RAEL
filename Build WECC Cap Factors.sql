-- This compiles input data for the SWITCH model from various databases, creating tables in the WECC database such that are easy to export. 
-- builds off of old code by Mathias, Josiah and Ian, but compliled in final form by Jimmy

-- Edit data in the other databases first, and then let this script get them in the form we want.

-- This script is intended to be used in conjunction with 'get WECC cap factors.sh' maybe?

-- run at terminal by pasting: mysql -h xserve-rael.erg.berkeley.edu -u jimmy -p < /Volumes/1TB_RAID/Models/Switch/ampl/Dual_WECC/Build\ WECC\ Cap\ Factors.sql
-- and entering the password (or changing the username and entering your password)

-- takes a long time (~2h), so run sparingly or get a coffee or something.

-- note: some load areas used to have spaces (i.e. UT S), which ampl apparently detests
-- the spaces were replaced by underscores in all tables I could find, but I could have missed something.
-- Make sure that if you import any table into mysql that it has the correct load area (with underscores, not spaces).
-- If you need to change them, this command does it nicely:
-- update tbl_name set load_area = replace(load_area, ' ', '_');


CREATE DATABASE IF NOT EXISTS WECC;
use WECC;

-- Reference Tables-----------------------------------------
-- gets important site tables from other databases... update the tables in the other database rather than in WECC
-- then use this script to make all the right tables for ampl
drop table if exists csp_sites_3tier_wecc;
CREATE TABLE csp_sites_3tier_wecc
SELECT * FROM 3tier.csp_sites_3tier_wecc;

drop table if exists wind_farms_wecc;
CREATE TABLE wind_farms_wecc
SELECT * FROM 3tier.wind_farms_wecc;

-- pv import script was run only for points that have a population of >= 10000
drop table if exists pv_grid_points_wecc;
CREATE TABLE pv_grid_points_wecc
SELECT * FROM suny.pv_grid_points
WHERE load_area is not null
AND population >=10000;

-- Hours-------------------------------------------------
-- creates hours table from the CSP data because 3tier knows how to deal correctly in UTC, right now only for 2004-2005
-- omits the last day because we're using UTC and so records for the first day (Jan 1 2004) won't be complete.
drop table if exists hours;
create table hours 
  SELECT * from 
		(select distinct(addtime(3tier.csp_power_output.datetime_local, TIME(concat(-csp_sites_3tier_wecc.timezone_difference_from_gmt, ":", '00', ":", '00')))) as datetime_utc
		FROM 3tier.csp_power_output, csp_sites_3tier_wecc
		WHERE 3tier.csp_power_output.siteid = csp_sites_3tier_wecc.id) as foo
		where datetime_utc between "2004-01-02 00:00" and "2005-12-31 23:59"
	order by datetime_utc;
alter table hours add column hournum int;
set @curhour = 0;
update hours set hournum = (@curhour := @curhour+1);
alter table hours add index (datetime_utc);


-- System Loads--------------------------------------
-- takes the ferc 714 filings and apportions to them to load areas in the proper timezones, then references them back to utc, then hours.
-- when dealing with reported loads, always make sure that daylight savings time has been dealt with correctly.
drop table if exists system_load;
create table system_load
select moo.load_area, hournum as hour, moo.power as power
from hours,
	(select baz.load_area, baz.datetime_utc, sum(baz.power) as power
		from(
			select lse, bar.load_area, bar.datetime_utc, power*load_allocations_wecc.share_load_area as power
			from loads_wecc.load_allocations_wecc,
				(select lse, load_area, timestampadd(hour, tz_law - tz_flw, datetime_utc) as datetime_utc, power from loads_wecc.ferc_714_loads_WECC,
				(SELECT load_allocations_wecc.abbreviation as abbrev_law, load_allocations_wecc.load_area, load_allocations_wecc.timezone as tz_law, ferc_lse_wecc.abbreviation as abbrev_flw, ferc_lse_wecc.timezone as tz_flw
				FROM loads_wecc.load_allocations_wecc, loads_wecc.ferc_lse_wecc
				WHERE load_allocations_wecc.abbreviation = ferc_lse_wecc.abbreviation) as foo
			where abbrev_law = ferc_714_loads_WECC.lse) as bar
		where load_allocations_wecc.load_area = bar.load_area
		and load_allocations_wecc.abbreviation = bar.lse
		and wecc_geo_extent = 1) as baz
	group by baz.load_area, baz.datetime_utc) as moo
where moo.datetime_utc = hours.datetime_utc;
alter table system_load add index hour(hour);



-- Study Hours------------------------------------------
-- Randomly select study dates and hours for the SWITCH model. 
-- Sub-sampling of specific months and hours are the responsibility of the shell script that exports data from the DB
-- Add rows to the tperiods table (defined in the middle of the section) if you want more than 4 investment periods

set @base_year        := 2010;
set @years_per_period := 4;
set @max_timepoints_per_day = 24;

-- correct? Check!
set @training_set_method := 'MEDIAN';
set @training_set_notes := 'For each month, the day with peak load and a representative day with near-median load were selected. The peak day was selected by average hourly consumption (system-wide), while the median was based on total consumption during the day.';


-- make lists of all the possible periods and months
-- also report the number of days in each month, for sample-weighting later
drop temporary table if exists tperiods;
create temporary table tperiods (periodnum int);
insert into tperiods (periodnum) values (0), (1), (2), (3);
select count( periodnum ) into @num_periods from tperiods;
drop temporary table if exists tmonths;
create temporary table tmonths (month_of_year tinyint, days_in_month double);
insert into tmonths values 
  (1, 31), (2, 29.25), (3, 31), (4, 30), (5, 31), (6, 30),
  (7, 31), (8, 31), (9, 30), (10, 31), (11, 30), (12, 31);


-- Make a table of study hours
CREATE TABLE IF NOT EXISTS study_hours_all (
  training_set_id INT NOT NULL,
  period BIGINT,
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
CREATE TABLE IF NOT EXISTS study_dates_all(
  training_set_id INT NOT NULL,
  period BIGINT,
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

CREATE TABLE IF NOT EXISTS training_sets (
  training_set_id INT NOT NULL AUTO_INCREMENT,
  selection_method VARCHAR(64) NOT NULL COMMENT 'This field describes the method of selection of timepoints. The two main methods - MEDIAN and RAND - differ in their selection of representative timepoints. MEDIAN selects days with near-median loads. RAND selects representative days at random.',
  notes TEXT COMMENT 'This field describes the selection method in full sentences. ',
  PRIMARY KEY (training_set_id)
)
COMMENT = 'This stores descriptions of a set of timepoints that the SWITCH model optimizes cost over. i.e. Training sets ';

-- This select sets @training_set_id to the next valid id
select if(max(training_set_id) is null, 1, max(training_set_id)+1) into @training_set_id from training_sets;

INSERT INTO training_sets VALUES ( @training_set_id, @training_set_method, @training_set_notes );

-- Create a list of all the dates for which we have 24 hours of data. This will exclude the Fall daylight savings times days because they are missing an hour.
drop temporary table if exists tdates;
create temporary table tdates
  select date(hours.datetime_utc) as date_utc, month(hours.datetime_utc) as month_of_year, rand() as ord
    from hours
    group by 1
    having count(*) = @max_timepoints_per_day;
alter table tdates add index( date_utc );

-- Add the peak system load for every day considered
drop temporary table if exists thourtotal;
create temporary table thourtotal select hour, sum(system_load.power) as system_load from system_load group by 1;
alter table tdates add column max_load int;
update tdates set tdates.max_load = (
  select max( round( thourtotal.system_load ) ) 
    from thourtotal, hours
    where hours.hournum = thourtotal.hour
    and date(hours.datetime_utc) = tdates.date_utc
);

-- Create a list of days with peak load by month
drop temporary table if exists tmaxday_in_month;
create temporary table tmaxday_in_month
  select month(tdates.date_utc) as month_of_year, max( max_load ) as max_load
    from tdates group by 1;
alter table tmaxday_in_month add column max_load_date datetime;
update tmaxday_in_month, thourtotal, hours set tmaxday_in_month.max_load_date = hours.datetime_utc 
  where thourtotal.hour = hours.hournum and round(thourtotal.system_load) = tmaxday_in_month.max_load;

-- Mark the peak days of each month by setting their ord column to a 2. This will ensure they have the top rank, since the rest of the historic dates have ord values between 0 & 1.
update tdates, tmaxday_in_month set tdates.ord = 2
  where tdates.date_utc = date( tmaxday_in_month.max_load_date );

-- randomly order the dates that fall within each month of the year
-- they will be selected for study (without replacement) based on this ordering.
-- another option would be a stratified approach, e.g. just to take the 15th of the month, 
-- and alternate between using data from the first or second year of measurements
alter table tdates add column rank int;
set @lastrank = 0, @lastmonth = 0;
-- to switch from random ordering to choosing days with median loads, change 'ord'      in the order by clause to 'max_load'
-- to switch from choosing days with median loads to random ordering, change 'max_load' in the order by clause to 'ord'
update tdates set rank = (@lastrank := if(@lastmonth=(@lastmonth:=month_of_year), @lastrank+1, 1)) order by month_of_year, max_load desc;
alter table tdates add index mr (month_of_year, rank), add index (date_utc);


-- Make a table listing the individual dates that we are sampling
-- Choose the individual dates from the datelist, based on their ordering
-- The first study period uses one of the dates in the middle of the list, second uses the one after, etc.
-- This strategy allows us to easily switch between selecting random dates and dates with near-median loads.
-- We also report how many hours are represented by each sample, for weighting in the optimization
-- The formula for the number of hours represented by each sample is based on one less than the days in 
-- the month, to avoid overlapping with the days of peak load.
INSERT INTO study_dates_all ( training_set_id, period, date_utc, month_of_year, hours_in_sample )
  select @training_set_id, periodnum * @years_per_period + @base_year as period, date_utc, d.month_of_year, 
    (days_in_month-1)*@years_per_period as hours_in_sample
    from tperiods p join tmonths m 
      join tdates d 
        on (d.month_of_year=m.month_of_year and
      	    d.rank = floor( m.days_in_month / 2 - @num_periods/2 + p.periodnum ) 
      	)
      order by period, month_of_year, date_utc;

-- Add the dates with peak loads. The peak load have a rank of 1.
INSERT INTO study_dates_all ( training_set_id, period, date_utc, month_of_year, hours_in_sample )
  select @training_set_id, periodnum * @years_per_period + @base_year as period, date_utc, d.month_of_year, 
    @years_per_period as hours_in_sample
    from tperiods p join tdates d 
    where rank = 1 
      order by period, month_of_year, date_utc;

-- create unique ids for each date of the simulation
-- NOTE: the following code assumes that no historical date is used more than once in the same investment period
-- it also assumes that study periods and historical years are uniquely identified by their last two digits
update study_dates_all set 
  study_date = (period mod 100) * 1000000 + mod(year(date_utc), 100) * 10000 + month(date_utc)*100 + day(date_utc)
  where training_set_id = @training_set_id;

-- create the final list of study hours
INSERT INTO study_hours_all ( training_set_id, period, study_date, date_utc, month_of_year, hours_in_sample, hour_of_day, hournum, datetime_utc )
  select @training_set_id, period, study_date, 
    date_utc, month_of_year, hours_in_sample,
    hour(datetime_utc) as hour_of_day, hournum, datetime_utc
    from study_dates_all d join hours h on d.date_utc = date(h.datetime_utc)
      where training_set_id = @training_set_id
      order by period, month_of_year, datetime_utc;

-- create unique ids for each hour of the simulation
update study_hours_all set 
  study_hour = ((period mod 100) * 10000 + month_of_year * 100 + hour_of_day) * 1000 + (year(date_utc) mod 10) * 100 + day(date_utc) 
  where training_set_id = @training_set_id;


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
  notes TEXT,
  num_timepoints INT, 
  _datesample TEXT,
  _timesample TEXT,
  _hours_in_sample TEXT,
  PRIMARY KEY (scenario_id), 
  UNIQUE INDEX unique_params(`training_set_id`, `exclude_peaks`, `exclude_periods`, `period_reduced_by`, `regional_cost_multiplier_scenario_id`, `regional_fuel_cost_scenario_id`, `regional_gen_price_scenario_id`, `months_between_samples`, `start_month`, `hours_between_samples`, `start_hour`, `enable_rps`), 
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

DROP FUNCTION IF EXISTS `wecc`.`set_scenarios_sql_columns`$$
CREATE FUNCTION `wecc`.`set_scenarios_sql_columns` (target_scenario_id int) RETURNS INT 
BEGIN
  DECLARE done INT DEFAULT 0;
  DECLARE current_scenario_id INT;
  DECLARE cur_id_list CURSOR FOR SELECT scenario_id FROM wecc.scenarios WHERE wecc.scenarios.scenario_id >= target_scenario_id;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;
  
  DROP TEMPORARY TABLE IF EXISTS wecc.__set_scenarios_sql_columns;
  CREATE TEMPORARY TABLE wecc.__set_scenarios_sql_columns
    SELECT * FROM wecc.scenarios WHERE wecc.scenarios.scenario_id >= target_scenario_id;

  OPEN cur_id_list;
  
  REPEAT
    FETCH cur_id_list INTO current_scenario_id;
  
    UPDATE wecc.scenarios
      SET 
        _datesample = concat(
            concat( 'FIND_IN_SET( period, "', exclude_periods, '")=0 and '), 
            'MOD(month_of_year, ', months_between_samples, ') = ', start_month, ' and ',
            'training_set_id = ', training_set_id, 
            if( exclude_peaks, ' and hours_in_sample > 100', '')
        )
      WHERE wecc.scenarios.scenario_id = current_scenario_id;
    UPDATE wecc.scenarios
      SET 
        _timesample = concat(
            _datesample, ' and ', 
            'MOD(hour_of_day, ', hours_between_samples, ') = ', start_hour
        ),
        _hours_in_sample = if( period_reduced_by * months_between_samples * hours_between_samples != 1,
           concat( 'hours_in_sample', '*', period_reduced_by, '*', months_between_samples, '*', hours_between_samples ), 
           'hours_in_sample'
        )
      WHERE wecc.scenarios.scenario_id = current_scenario_id;
    UPDATE wecc.scenarios
      SET 
        wecc.scenarios.num_timepoints = 
        (select count(wecc.study_hours_all.hournum) 
          from wecc.study_hours_all, wecc.__set_scenarios_sql_columns params
          where
            params.scenario_id = current_scenario_id and
            wecc.study_hours_all.training_set_id = params.training_set_id and
            FIND_IN_SET( wecc.study_hours_all.period, params.exclude_periods ) = 0 and 
            MOD(wecc.study_hours_all.month_of_year, params.months_between_samples ) = params.start_month and
            wecc.study_hours_all.hours_in_sample > 100*params.exclude_peaks and
            MOD(wecc.study_hours_all.hour_of_day, params.hours_between_samples) = params.start_hour
        )
      WHERE wecc.scenarios.scenario_id = current_scenario_id
    ;
    UPDATE wecc.scenarios
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
      WHERE wecc.scenarios.scenario_id = current_scenario_id and (scenario_name is NULL or length(scenario_name) = 0)
      ;
  UNTIL done END REPEAT;
  CLOSE cur_id_list;
  
  DROP TEMPORARY TABLE wecc.__set_scenarios_sql_columns;
  RETURN (SELECT count(*) FROM wecc.scenarios WHERE scenario_id >= target_scenario_id);
END$$

DELIMITER ;

INSERT INTO scenarios (scenario_name, training_set_id) 
  VALUES ( 'default scenario', @training_set_id );
select max(scenario_id) into @scenario_id from scenarios;
SELECT set_scenarios_sql_columns( @scenario_id );


-- Load Areas---------------------------------------------
-- Copy the relevant load areas into this database. It's not strictly necessary, and it's a little bad form, but the old build cap factors had it.
-- doesn't get the x_utm and y_utm columns of the old table... make sure these aren't needed anywhere (shouldn't be)... puts in dummy values... hopefully we can just delete these.
drop table if exists load_area;
CREATE TABLE load_area
SELECT distinct(load_area) FROM wecc.system_load order by load_area;
ALTER TABLE load_area add column area_id int not null primary key auto_increment first;
ALTER TABLE load_area add column x_utm double;
ALTER TABLE load_area add column y_utm double;
UPDATE load_area set x_utm = 10000*area_id, y_utm = 20000*area_id;


-- Existing and New Plants----------------------------------------
-- aggregated in 'build existing plants table for WECC.sql'

drop table if exists existing_plants_agg;
create table existing_plants_agg
	select * from grid.existing_plants_agg
	where load_area not like ''
	and load_area is not null
	order by load_area;

-- Generator Costs
-- update the generator_costs table in grid if you want to change these values.
-- change the clause below if you want to include or not include various technologies
-- CCGTs can burn gas or oil
drop table if exists generator_costs;
create table generator_costs
	select * from grid.generator_costs
	where technology in ('CTA', 'Wind', 'DistPV', 'CentPV', 'Trough', 'Coal_ST', 'Nuclear', 'Biomass_ST', 'Geothermal')
			or technology like 'CCGT' and fuel like 'Gas';
			
-- run regionalize.sql... should be put here eventually			
	
-- Hydro----------------------------------------------
-- Set the hydro monthly limits by table

-- don't know quite what to do with the year here.. we only have 2007 but Matthias seemed to have three years.
-- do we need to get each year's max, min and avg flow, i.e. do we need to import 2004-2006 EIA data?
-- also need Canadian Plant Data

drop table if exists plantcap;
create table plantcap
  select g.plntcode, g.plntname, g.load_area,
    sum(summcap) as summcap, sum(wintcap) as wintcap,
    sum(if(primemover="PS", summcap, 0)) as summcap_ps, 
    sum(if(primemover="PS", wintcap, 0)) as wintcap_ps, 
    count(*) as numgen 
  from grid.eia860gen07_US g join grid.eia860plant07_US p using (plntcode)
  where primemover in ("HY", "PS")
  and p.load_area not like ''
  and g.load_area not like ''
  group by 1, 2, 3;
  
-- for now, we assume:
-- maximum flow is equal to the plant capacity (summer or winter, ignoring discrepancy from nameplate)
-- minimum flow is negative of the pumped storage capacity, if applicable, or 0.1 * average flow for simple hydro
-- TODO: find better estimates of minimum flow, e.g., by looking through remarks in the USGS datasheets, or looking
--   at the lowest daily average flow in each month.
-- daily average is equal to net historical production of power
-- note: the fancy date math below just figures out how many days there are in each month
-- TODO: find a better estimate of pumping capacity, rather than just the negative of the PS generating capacity
-- TODO: estimate net daily energy balance in the reservoir, not via netgen. i.e., avg_flow should be based on the
--   total flow of water (and its potential energy), not the net power generation, which includes losses from 
--   inefficiency on both the generation and storage sides 
--   (we ignore this for now, which is OK if net flow and net gen are both much closer to zero than max flow)
--   This can be done by fitting a linear model of water flow and efficiency to the eia energy consumption and net_gen
--   data and the USGS monthly water flow data, for pumped storage facilities. This model may be improved by looking up
--   the head height for each dam, to link water flows directly to power.

drop table if exists hydro_gen;
create table hydro_gen(
  plntcode int,
  primemover char(2),
  year year,
  month tinyint,
  netgen double);

insert into hydro_gen select plntcode, primemover, year, 1, netgen_jan from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year < 2007;
insert into hydro_gen select plntcode, primemover, year, 2, netgen_feb from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year < 2007;
insert into hydro_gen select plntcode, primemover, year, 3, netgen_mar from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year < 2007;
insert into hydro_gen select plntcode, primemover, year, 4, netgen_apr from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year < 2007;
insert into hydro_gen select plntcode, primemover, year, 5, netgen_may from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year < 2007;
insert into hydro_gen select plntcode, primemover, year, 6, netgen_jun from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year < 2007;
insert into hydro_gen select plntcode, primemover, year, 7, netgen_jul from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year < 2007;
insert into hydro_gen select plntcode, primemover, year, 8, netgen_aug from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year < 2007;
insert into hydro_gen select plntcode, primemover, year, 9, netgen_sep from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year < 2007;
insert into hydro_gen select plntcode, primemover, year, 10, netgen_oct from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year < 2007;
insert into hydro_gen select plntcode, primemover, year, 11, netgen_nov from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year < 2007;
insert into hydro_gen select plntcode, primemover, year, 12, netgen_dec from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year < 2007;

alter table hydro_gen add index pm (plntcode, primemover), add index ym (year, month);


drop table if exists hydro_monthly_limits;
create table hydro_monthly_limits
  select load_area,
    concat(replace(left(p.plntname, 6), " ", "_"), "_", p.plntcode) as site,
    year, month,
    sum(if(g.month between 4 and 9, -p.summcap_ps, -p.wintcap_ps)) as min_flow,
    sum(if(g.month between 4 and 9, p.summcap, p.wintcap)) as max_flow,
    sum(netgen / 
      (24 * datediff(
        date_add(concat(year, "-", month, "-01"), interval 1 month), concat(year, "-", month, "-01")
      ))) as avg_flow
    from hydro_gen g join plantcap p using (plntcode)
    where g.primemover in ("HY", "PS")
    group by 1, 2, 3, 4;
-- you can add this to the where clause
-- and p.summcap >= 50 and p.wintcap >= 50
update hydro_monthly_limits set min_flow = 0 where min_flow = -0;
alter table hydro_monthly_limits add index ym (year, month);

-- some of the plants come in with average production or pumping 
-- that is beyond their rated capacities; we just scale these back.
update hydro_monthly_limits set avg_flow=max_flow where avg_flow > max_flow;
update hydro_monthly_limits set avg_flow=min_flow where avg_flow < min_flow;

-- calculate the minimum flow for simple hydro plants.
-- we assume that they must release at least 10% of the monthly average flow 
-- in every hour, to maintain instream flows below the dam.
-- TODO: find a better estimate of minimum allowed flow
update hydro_monthly_limits set min_flow = 0.1 * avg_flow where min_flow <= 0.1 * avg_flow;

-- force small plants to run in baseload mode
-- (in theory, this could make some plants run as baseload in summer and dispatchable
-- in the winter, but that doesn't actually happen)
-- TODO: revise the plant size cutoff to match the California RPS distinction between large and small hydro?
update hydro_monthly_limits set max_flow=avg_flow, min_flow=avg_flow where max_flow < 50;


-- drop the sites that have too few months of data (i.e., started running after 2004)
-- should check how many plants this is
drop temporary table if exists toofew;
create temporary table toofew
select site, count(*) as n from hydro_monthly_limits group by 1 having n < 36;
alter table toofew add index (site);
delete l.* from hydro_monthly_limits l join toofew f using (site);

-- a few sites come out with max_flow less than or equal to zero and ampl doesn't like this, so we set max_flow to a really small number here.
update hydro_monthly_limits
set max_flow = 0.001
where max_flow <=0;

-- Canadian Hydro
-- import filtered and edited hydro data for Alberta and BC Hydro from TEPPC
insert into hydro_monthly_limits
select load_area, site, 2004, month, min_flow, max_flow, avg_flow from grid.hydro_monthly_limits_can;
insert into hydro_monthly_limits
select load_area, site, 2005, month, min_flow, max_flow, avg_flow from grid.hydro_monthly_limits_can;
insert into hydro_monthly_limits
select load_area, site, 2006, month, min_flow, max_flow, avg_flow from grid.hydro_monthly_limits_can;

-- some names from the Canadian data come out with spaces, so we remove them with this command
update hydro_monthly_limits set site = replace(site, ' ', '_');

Update hydro_monthly_limits 
set min_flow = max_flow
where min_flow>max_flow;

-- and replace original max values if desired
-- should be changed - too manual for this stage of the code

Update grid.hydro_monthly_limits
set max_flow = 31.05
where site like 'Oldma_100010'; 

Update grid.hydro_monthly_limits 
set max_flow = 31.05
where site like 'Oldma_100012'; 

Update grid.hydro_monthly_limits
set max_flow = 23.8
where site like 'Taylo_100019' ;

Update grid.hydro_monthly_limits
set max_flow = 100
where site like 'GMS U_100026' ;

Update grid.hydro_monthly_limits
set max_flow = 30
where site like 'Soo R_100094' ;


Update wecc.hydro_monthly_limits 
set site = 'S_Slo1_100096'
where site like 'S_Slo_100096' and max_flow = 15.7;

Update wecc.hydro_monthly_limits 
set site = 'S_Slo2_100096'
where site like 'S_Slo_100096' and max_flow = 21.6;



-- TransLines---------------------------------------------

-- mostly compiled in previous scripts that make wecc_trans_lines from windsun.wecc_link_info.  This data is a few years old, so this could be updated.

-- the rest of the links should be checked to make sure nothing important is missing.
-- creates trans_lines table to export to ampl
-- this one lets the model build any lines it feels like between any areas.
-- Could easily be restricted to only adjacent load areas if it messes up in ampl.
drop table if exists trans_line;
create table trans_line
SELECT load_area_start, load_area_end, tid, distkm as length_km, geoms_intersect as geoms_intersect, efficiency as transmission_efficiency, existing_mw_from as existing_transmission_from, existing_mw_to as existing_transmission_to
FROM grid.wecc_trans_lines
order by load_area_start, load_area_end;
  

-- Connect Cost ----------------------------------------
-- should be done better - ideally there would be a connect cost for each site, especially offshore wind, but right now it's all the same :-(
-- fix later - geothermal comes in with a connection cost per MW, but this is just the length*233301, so here I (Jimmy) just make it look like the others by dividing by that factor again
-- should just input the total connect cost, which includes the length
drop table if exists connect_cost_all;
create table connect_cost_all
  select 'Trough' as technology, load_area, concat(csp_sites_3tier_wecc.load_area, '_', csp_sites_3tier_wecc.siteid, '_tr') as site, 'na' as orientation, connect_dist_km as connect_length_km, 233301 as connect_cost_per_MW 
  	from csp_sites_3tier_wecc
  union all 
  select 'Wind' as technology, load_area, concat(wind_farms_wecc.load_area, '_', wind_farms_wecc.wind_farm_id) as site, 'na' as orientation, connect_dist_km as connect_length_km, 233301 as connect_cost_per_MW 
  	from wind_farms_wecc
  union all
  select 'Geothermal' as technology, load_area, geosite as site, 'na' as orientation, connect_cost_per_MW/233301 as connect_dist_km, 233301 as connect_cost_per_MW
  	from grid.geothermal_sites;





-- Max Capacity----------------------------------------
-- Creates the max_capacity_all table for intermittent resources.

-- The csp site max capacity should be updated at some point with the correct data
-- (we don't have this in hand right now) 

-- for DistPV, we assume the maximum in all orientations is 0.0015 MWp/person
-- (based on the arbitrary assumption of 2000 square foot house per 4 people,
-- with 2 stories, so 1000 square feet total, or 10 square meters per person.
-- then, assume commercial space doubles this, but shading cuts it back in half
-- so we have for a 15% efficient cell, 10 m2/person * 150 Wp/m2 = 1500 Wp/person)
-- then, this gets apportioned between 12 compass points, so 1500 Wp/person * 1/12 = 125Wp/person = 0.000125MW/person.
-- should do this by finding the average roof area per person in the US.
-- LA might have an unreasonably large population at 18million without some suburbs... maybe we should do something about that.

drop table if exists max_capacity_all;
create table max_capacity_all
  select 'Trough' as technology, load_area, concat(csp_sites_3tier_wecc.load_area, '_', csp_sites_3tier_wecc.siteid, '_tr') as site, 'na' as orientation, max_capacity 
    from csp_sites_3tier_wecc
  union all 
  select 'Wind' as technology, load_area, concat(wind_farms_wecc.load_area, '_', wind_farms_wecc.wind_farm_id) as site, 'na' as orientation, max_mw as max_capacity
    from wind_farms_wecc
  union all 
  select 'DistPV' as technology, load_area, concat(pv_grid_points_wecc.load_area, '_', pv_grid_points_wecc.grid_id) as site, suny.surface_azimuth_angle.angle as orientation, 0.000125*population as max_capacity
    from pv_grid_points_wecc,
		suny.surface_azimuth_angle
  union all
  select 'Biomass_ST' as technology, load_area, concat(load_area, '_', 'Bio') as site, 'na' as orientation, bio as max_capacity
  	from biomass.biomass_potential
  		where bio > 10
  union all
  select 'Geothermal' as technology, load_area, geosite as site, 'na' as orientation, capacity_mw as max_capacity
  	from grid.geothermal_sites;
  		


-- Cap Factor Tables------------------------------------------------

-- CSP
-- sets the cap_factor to 1 when the e_net_mw gets larger than 100MW (the max value is 103MW)
-- because the assumed max_capacity is 100MW for this table, though the csp_sites_3tier_wecc table scales some of these up
-- could relieve constraint in ampl code to allow for cap factors greater than 1 or less than zero (it's unclear whether the trough technology is parasitic on the grid when it isn't producing power)
drop table if exists cap_factor_csp;
create table cap_factor_csp
select 		csp_sites_3tier_wecc.load_area,		
			hours.hournum as hour,
  			concat(csp_sites_3tier_wecc.load_area, '_', csp_sites_3tier_wecc.siteid, '_tr') as site,
  			if(if(3tier.csp_power_output.e_net_mw > 100, 1, 3tier.csp_power_output.e_net_mw/100) < 0, 0, if(3tier.csp_power_output.e_net_mw > 100, 1, 3tier.csp_power_output.e_net_mw/100)) as cap_factor,
  			3tier.csp_power_output.siteid as siteid
  	from 	hours,
  			3tier.csp_power_output,
			csp_sites_3tier_wecc
  	where hours.datetime_utc = timestampadd(hour, -csp_sites_3tier_wecc.timezone_difference_from_gmt, 3tier.csp_power_output.datetime_local)
	and csp_sites_3tier_wecc.id = 3tier.csp_power_output.siteid;
alter table cap_factor_csp add index siteid (siteid), add index hour (hour), add index load_area (load_area);

-- Wind
drop table if exists cap_factor_wind;
create table cap_factor_wind
select 		wind_farms_wecc.load_area,
  			concat(wind_farms_wecc.load_area, '_', wind_farms_wecc.wind_farm_id) as site, 
  			hours.hournum as hour, 
    		if(if(3tier.wind_farm_power_output.corrected_score_lite_power_output_mw/wind_farms_wecc.max_mw > 1, 1, 3tier.wind_farm_power_output.corrected_score_lite_power_output_mw/wind_farms_wecc.max_mw) < 0, 0, if(3tier.wind_farm_power_output.corrected_score_lite_power_output_mw/wind_farms_wecc.max_mw > 1, 1, 3tier.wind_farm_power_output.corrected_score_lite_power_output_mw/wind_farms_wecc.max_mw)) as cap_factor,
    		wind_farms_wecc.wind_farm_id as siteid
   from 	3tier.wind_farm_power_output,
   			wind_farms_wecc,
   			hours
   where 	wind_farms_wecc.wind_farm_id = 3tier.wind_farm_power_output.siteid
   and		hours.datetime_utc = TIMESTAMPADD(HOUR, -wind_farms_wecc.timezone_diff_from_gmt, 3tier.wind_farm_power_output.datetime_local)
   order by wind_farms_wecc.load_area, 
   			wind_farms_wecc.wind_farm_id;
alter table cap_factor_wind add index siteid (siteid), add index hour (hour), add index load_area (load_area);

-- PV
-- right now limits the cap_factor arbitrarily to 1 to make ampl happy,
-- but this should be changed in the future as a solar panel can make more power than its rated output on a good day.
drop table if exists cap_factor_pv;
create table cap_factor_pv
select 	pv_grid_points_wecc.load_area,
		concat(pv_grid_points_wecc.load_area, '_', pv_grid_points_wecc.grid_id) as site,
		suny.grid_hourlies.orientation as orientation,
		hours.hournum as hour,
		if(suny.grid_hourlies.cap_factor > 1, 1, if(suny.grid_hourlies.cap_factor < 0, 0, suny.grid_hourlies.cap_factor)) as cap_factor,
		pv_grid_points_wecc.grid_id as siteid
from	hours,
		pv_grid_points_wecc,
		suny.grid_hourlies
where	pv_grid_points_wecc.grid_id = suny.grid_hourlies.grid_id
and		hours.datetime_utc = suny.grid_hourlies.datetime_utc
order by pv_grid_points_wecc.load_area,
		pv_grid_points_wecc.grid_id;
alter table cap_factor_pv add index siteid (siteid), add index hour (hour), add index load_area (load_area);

-- creating a cap_factor_all table for this many sites takes a really long time (~0.5-1h), a lot of disk space, and is somewhat unnecessary... could make it in the ampl tab.
-- combine all intermittent renewable technologies into one big table, for easier handling
drop table if exists cap_factor_all;
create table cap_factor_all
  select 'Trough' as technology, load_area, site, "na" as orientation, hour, cap_factor from cap_factor_csp
  union all 
  select 'Wind' as technology, load_area, site, "na" as orientation, hour, cap_factor from cap_factor_wind
  union all
  select 'DistPV' as technology, load_area, site, orientation, hour, cap_factor from cap_factor_pv;
alter table cap_factor_all add index hour (hour);

