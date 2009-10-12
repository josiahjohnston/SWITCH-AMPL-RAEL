-- GENERATOR COSTS---------------


create database if not exists switch_inputs_wecc_v2;
use switch_inputs_wecc_v2;


-- HOURS-------------------------
-- creates hours table from the CSP data because 3tier knows how to deal correctly in UTC, right now only for 2004-2005
-- omits the last day because we're using UTC and so records for the first day (Jan 1 2004) won't be complete.
drop table if exists hours;
create table hours 
	select distinct(datetime_utc)
		FROM 3tier.csp_power_output
		where datetime_utc between "2004-01-02 00:00" and "2005-12-31 23:59"
	order by datetime_utc;
alter table hours add column hournum int;
set @curhour = 0;
update hours set hournum = (@curhour := @curhour+1);
alter table hours add index (datetime_utc);

-- SYSTEM LOAD
-- patched together from the old wecc loads... should be improved in the future
drop table if exists system_load;
create table system_load as
select 	v2_load_area as load_area, 
		hour,
		sum( power * population_fraction) as power
from 	loads_wecc.v1_wecc_load_areas_to_v2_wecc_load_areas,
		wecc.system_load
where	v1_load_area = wecc.system_load.load_area
group by v2_load_area, hour;
alter table system_load add index hour(hour);
alter table system_load add index load_area(load_area);

insert into system_load
select  ( CASE load_area
          WHEN 'BCTC' THEN 'CAN_BC'
          WHEN 'AESO' THEN 'CAN_ALB'
          WHEN 'CFE'  THEN 'MEX_BAJA'
          END
        ),
		hour,
		power
from 	wecc.system_load
where	load_area IN ( 'BCTC', 'AESO', 'CFE' );

-- Study Hours----------------------
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
-- to switch from random ordering to choosing days with median loads, change 'ord' in the order by clause to 'max_load'
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
INSERT INTO study_dates_all ( training_set_id, period, study_date, date_utc, month_of_year, hours_in_sample )
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
      	    d.rank = floor( m.days_in_month / 2 - @num_periods/2 + p.periodnum ) 
      	)
      order by period, month_of_year, date_utc;

-- Add the dates with peak loads. The peak load have a rank of 1.
INSERT INTO study_dates_all ( training_set_id, period, study_date, date_utc, month_of_year, hours_in_sample )
  select @training_set_id, periodnum * @years_per_period + @base_year as period, 
    -- create unique ids for each date of the simulation
    -- NOTE: the following code assumes that no historical date is used more than once in the same investment period
    -- it also assumes that study periods and historical years are uniquely identified by their last two digits
    (periodnum * @years_per_period + @base_year mod 100) * 1000000 + mod(year(date_utc), 100) * 10000 + month(date_utc)*100 + day(date_utc) as study_date, 
    date_utc, d.month_of_year, 
    @years_per_period as hours_in_sample
    from tperiods p join tdates d 
    where rank = 1 
      order by period, month_of_year, date_utc;

-- create the final list of study hours
INSERT INTO study_hours_all ( training_set_id, period, study_date, study_hour, date_utc, month_of_year, hours_in_sample, hour_of_day, hournum, datetime_utc )
  select @training_set_id, period, study_date, 
    -- create unique ids for each hour of the simulation
    ((period mod 100) * 10000 + month_of_year * 100 + hour(datetime_utc)) * 1000 + (year(date_utc) mod 10) * 100 + day(date_utc)  as study_hour,
    date_utc, month_of_year, hours_in_sample,
    hour(datetime_utc) as hour_of_day, hournum, datetime_utc
    from study_dates_all d join hours h on d.date_utc = date(h.datetime_utc)
      where training_set_id = @training_set_id
      order by period, month_of_year, datetime_utc;


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

DROP FUNCTION IF EXISTS `switch_inputs_wecc_v2`.`set_scenarios_sql_columns`$$
CREATE FUNCTION `switch_inputs_wecc_v2`.`set_scenarios_sql_columns` (target_scenario_id int) RETURNS INT 
BEGIN
  DECLARE done INT DEFAULT 0;
  DECLARE current_scenario_id INT;
  DECLARE cur_id_list CURSOR FOR SELECT scenario_id FROM switch_inputs_wecc_v2.scenarios WHERE switch_inputs_wecc_v2.scenarios.scenario_id >= target_scenario_id;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;
  
  DROP TEMPORARY TABLE IF EXISTS switch_inputs_wecc_v2.__set_scenarios_sql_columns;
  CREATE TEMPORARY TABLE switch_inputs_wecc_v2.__set_scenarios_sql_columns
    SELECT * FROM switch_inputs_wecc_v2.scenarios WHERE switch_inputs_wecc_v2.scenarios.scenario_id >= target_scenario_id;

  OPEN cur_id_list;
  
  REPEAT
    FETCH cur_id_list INTO current_scenario_id;
  
    UPDATE switch_inputs_wecc_v2.scenarios
      SET 
        _datesample = concat(
            concat( 'FIND_IN_SET( period, "', exclude_periods, '")=0 and '), 
            'MOD(month_of_year, ', months_between_samples, ') = ', start_month, ' and ',
            'training_set_id = ', training_set_id, 
            if( exclude_peaks, ' and hours_in_sample > 100', '')
        )
      WHERE switch_inputs_wecc_v2.scenarios.scenario_id = current_scenario_id;
    UPDATE switch_inputs_wecc_v2.scenarios
      SET 
        _timesample = concat(
            _datesample, ' and ', 
            'MOD(hour_of_day, ', hours_between_samples, ') = ', start_hour
        ),
        _hours_in_sample = if( period_reduced_by * months_between_samples * hours_between_samples != 1,
           concat( 'hours_in_sample', '*', period_reduced_by, '*', months_between_samples, '*', hours_between_samples ), 
           'hours_in_sample'
        )
      WHERE switch_inputs_wecc_v2.scenarios.scenario_id = current_scenario_id;
    UPDATE switch_inputs_wecc_v2.scenarios
      SET 
        switch_inputs_wecc_v2.scenarios.num_timepoints = 
        (select count(switch_inputs_wecc_v2.study_hours_all.hournum) 
          from switch_inputs_wecc_v2.study_hours_all, switch_inputs_wecc_v2.__set_scenarios_sql_columns params
          where
            params.scenario_id = current_scenario_id and
            switch_inputs_wecc_v2.study_hours_all.training_set_id = params.training_set_id and
            FIND_IN_SET( switch_inputs_wecc_v2.study_hours_all.period, params.exclude_periods ) = 0 and 
            MOD(switch_inputs_wecc_v2.study_hours_all.month_of_year, params.months_between_samples ) = params.start_month and
            switch_inputs_wecc_v2.study_hours_all.hours_in_sample > 100*params.exclude_peaks and
            MOD(switch_inputs_wecc_v2.study_hours_all.hour_of_day, params.hours_between_samples) = params.start_hour
        )
      WHERE switch_inputs_wecc_v2.scenarios.scenario_id = current_scenario_id
    ;
    UPDATE switch_inputs_wecc_v2.scenarios
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
      WHERE switch_inputs_wecc_v2.scenarios.scenario_id = current_scenario_id and (scenario_name is NULL or length(scenario_name) = 0)
      ;
  UNTIL done END REPEAT;
  CLOSE cur_id_list;
  
  DROP TEMPORARY TABLE switch_inputs_wecc_v2.__set_scenarios_sql_columns;
  RETURN (SELECT count(*) FROM switch_inputs_wecc_v2.scenarios WHERE scenario_id >= target_scenario_id);
END$$

DELIMITER ;

INSERT INTO scenarios (scenario_name, training_set_id) 
  VALUES ( 'default scenario', @training_set_id );
select max(scenario_id) into @scenario_id from scenarios;
SELECT set_scenarios_sql_columns( @scenario_id );









-- RENEWABLE SITES--------------
-- imported from postgresql, this table has all distributed pv, trough, wind, geothermal and biomass sites
drop table if exists proposed_renewable_sites;
create table proposed_renewable_sites
select 	generator_type,
		load_area,
		site_id,
		renewable_id,
		capacity_mw,
		connect_cost_per_mw
from generator_info.proposed_renewable_sites
order by 1,2,3;

CREATE INDEX site_id ON proposed_renewable_sites (site_id);
CREATE INDEX generator_type_renewable_id ON proposed_renewable_sites (generator_type, renewable_id);



-- CAP FACTOR-----------------
drop table if exists cap_factor_proposed_renewable_sites;
create table cap_factor_proposed_renewable_sites
SELECT      generator_type,
            generator_info.proposed_renewable_sites.load_area,
            generator_info.proposed_renewable_sites.site_id as site,
			cast(orientation as char(2)) as configuration,
            hournum as hour,
            cap_factor
    from    generator_info.proposed_renewable_sites, 
            suny.grid_hourlies,
            hours
    where   generator_type = 'Distributed_PV'
	and		generator_info.proposed_renewable_sites.renewable_id = suny.grid_hourlies.grid_id
    and     hours.datetime_utc = suny.grid_hourlies.datetime_utc;
 
insert into cap_factor_proposed_renewable_sites
SELECT      generator_type,
            load_area,
            generator_info.proposed_renewable_sites.site_id as site,
            'na' as configuration,
            hournum as hour,
            e_net_mw/100 as cap_factor
    from    generator_info.proposed_renewable_sites, 
            3tier.csp_power_output,
            hours
    where   generator_type in ('CSP_Trough')
    and     generator_info.proposed_renewable_sites.renewable_id = 3tier.csp_power_output.siteid
    and     hours.datetime_utc = 3tier.csp_power_output.datetime_utc;

insert into cap_factor_proposed_renewable_sites
SELECT      generator_type,
            load_area,
            generator_info.proposed_renewable_sites.site_id as site,
            'na' as configuration,           
            hournum as hour,
            cap_factor
    from    generator_info.proposed_renewable_sites, 
            3tier.wind_farm_power_output,
            hours
    where   generator_type in ('Wind', 'Offshore Wind')
    and     generator_info.proposed_renewable_sites.renewable_id = 3tier.wind_farm_power_output.wind_farm_id
    and     hours.datetime_utc = 3tier.wind_farm_power_output.datetime_utc;
    
alter table cap_factor_proposed_renewable_sites add index hour (hour);


-- EXISTING PLANTS---------
-- made in 'build proposed plants table.sql'
drop table if exists existing_plants;
create table existing_plants
select * from generator_info.existing_plants_agg;


-- HYDRO-------------------
-- made in 'build proposed plants table.sql'
drop table if exists hydro_monthly_limits;
create table hydro_monthly_limits
select * from generator_info.hydro_monthly_limits;

alter table hydro_monthly_limits add index (year,month);


-- TRANS LINES----------
-- made in postgresql
drop table if exists transmission_lines;
create table transmission_lines(
	transmission_line_id int,
	load_area_start varchar(11),
	load_area_end varchar(11),
	existing_transfer_capacity_mw double,
	transmission_length_km double,
	load_areas_border_each_other char(1)
);

load data local infile
	'/Volumes/1TB_RAID-2/Models/Switch\ Input\ Data/Transmission/wecc_trans_lines.csv'
	into table transmission_lines
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;
	
-- LOAD AREA INFO	
-- made in postgresql
drop table if exists load_area_info;
create table load_area_info(
  load_area varchar(11),
  primary_nerc_subregion varchar(20),
  primary_state varchar(20),
  economic_multiplier double,
  rps_compliance_year integer,
  rps_compliance_percentage double,
  INDEX load_area (load_area)
);

load data local infile
	'/Volumes/1TB_RAID-2/Models/GIS/wecc_load_area_info.csv'
	into table load_area_info
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;

alter table load_area_info add column scenario_id INT NOT NULL first;
alter table load_area_info add index scenario_id (scenario_id);
alter table load_area_info add column area_id int NOT NULL AUTO_INCREMENT primary key first;

select if( max(scenario_id) + 1 is null, 1, max(scenario_id) + 1 ) into @this_scenario_id
    from load_area_info;

update load_area_info set scenario_id = @this_scenario_id;



-----------------------------------------------------------------------
--        REGION-SPECIFIC GENERATOR COSTS & AVAILIBILITY
-----------------------------------------------------------------------

DROP TABLE if exists regional_generator_costs;
CREATE TABLE regional_generator_costs(
  scenario_id INT NOT NULL,
  area_id INT NOT NULL,
  technology varchar(30),
  price_year year(4),
  overnight_cost double,
  connect_cost_per_MW_generic double,
  fixed_o_m double,
  variable_o_m double,
  overnight_cost_change double,
  fixed_o_m_change double,
  variable_o_m_change double
);

set @cost_mult_scenario_id = 1;

-- Find the next scenario id. 
select if( max(scenario_id) + 1 is null, 1, max(scenario_id) + 1 ) into @reg_generator_scenario_id
    from regional_generator_costs;

-- The middle four lines in the select statment are prices that are affected by regional price differences
-- The rest of these variables aren't affected by region, but they're brought along here to make it easier in AMPL
-- technologies that Switch can't build yet but might in the future are eliminated in the last line
insert into regional_generator_costs
    (scenario_id, area_id, technology, price_year, overnight_cost, connect_cost_per_MW_generic, 
     fixed_o_m, variable_o_m, overnight_cost_change, fixed_o_m_change, variable_o_m_change)

    select 	@reg_generator_scenario_id as scenario_id, 
    		area_id,
    		technology,
    		price_year,  
   			overnight_cost * economic_multiplier as overnight_cost,
    		connect_cost_per_MW_generic * economic_multiplier as connect_cost_per_MW_generic,
    		fixed_o_m * economic_multiplier as fixed_o_m,
    		variable_o_m * economic_multiplier as variable_o_m,
   			overnight_cost_change,
   			fixed_o_m_change,
   			variable_o_m_change
    from 	generator_info.generator_costs,
			load_area_info
	where 	load_area_info.scenario_id  = @cost_mult_scenario_id
	and		technology not in ('Central_Station_PV', 'CSP_Trough_No_Storage', 'Coal_IGCC', 'Coal_IGCC_With_CSS')
;


-- regional generator restrictions
-- currently, the only restrictions are that Coal_ST and Nuclear can't be built in CA
delete from regional_generator_costs
 	where 	(technology in ('Nuclear', 'Coal_ST') and
			area_id in (select area_id from load_area_info where primary_nerc_subregion like 'CA'));


-- Make a view that is more user-friendly
drop view if exists regional_generator_costs_view;
CREATE VIEW regional_generator_costs_view as
  SELECT load_area, regional_generator_costs.* 
    FROM regional_generator_costs, load_area_info
    WHERE	load_area_info.area_id = regional_generator_costs.area_id;
    
-----------------------------------------------------------------------
--        NON-REGIONAL GENERATOR INFO
-----------------------------------------------------------------------


DROP TABLE IF EXISTS generator_info;
CREATE TABLE generator_info (
  select technology, min_build_year, fuel, heat_rate, construction_time_years,
  		max_age_years, forced_outage_rate, scheduled_outage_rate, intermittent,
  		resource_limited, baseload, min_build_capacity
  from generator_info.generator_costs );



-- FUEL PRICES-------------
-- run 'v2 wecc fuel price import no elasticity.sql' first

drop table if exists regional_fuel_prices;
CREATE TABLE regional_fuel_prices (
  scenario_id INT NOT NULL,
  area_id INT NOT NULL,
  fuel VARCHAR(30),
  year year,
  fuel_price FLOAT NOT NULL COMMENT 'Regional fuel prices for various types of fuel in $2007 per MMBtu',
  INDEX scenario_id(scenario_id),
  INDEX area_id(area_id),
  CONSTRAINT area_id FOREIGN KEY area_id (area_id)
    REFERENCES load_area_info (area_id)
);

select if( max(scenario_id) + 1 is null, 1, max(scenario_id) + 1 ) into @this_scenario_id
    from regional_fuel_prices;
  
insert into regional_fuel_prices
	select
		@this_scenario_id as scenario_id,
        area_id,
        if(fuel like 'NaturalGas', 'Gas', fuel),
        year,
        fuel_price
    from fuel_prices.regional_fuel_prices, load_area_info
    where load_area_info.load_area = fuel_prices.regional_fuel_prices.load_area
    and fuel not like 'DistillateFuelOil'
    and fuel not like 'ResidualFuelOil';

  
drop view if exists regional_fuel_prices_view;
CREATE VIEW regional_fuel_prices_view as
SELECT regional_fuel_prices.scenario_id, load_area_info.area_id, load_area, fuel, year, fuel_price 
    FROM regional_fuel_prices, load_area_info
    WHERE regional_fuel_prices.area_id = load_area_info.area_id;

-- RPS----------------------
drop table if exists fuel_info;
create table fuel_info(
	fuel varchar(30),
	rps_fuel_category varchar(10), 
	carbon_content float COMMENT 'carbon content (tonnes CO2 per million Btu)'
);

-- gas converted from http://www.eia.doe.gov/oiaf/1605/coefficients.html
-- this page says nevada and arizona coal are around 205-208 pounds per million Btu: http://www.eia.doe.gov/cneaf/coal/quarterly/co2_article/co2.html
-- Nuclear, Geothermal, Biomass, Water, Wind and Solar have non-zero LCA emissions. To model those emissions, we'd need to divide carbon content into capital, fixed, 
--   and variable emissions. Currently, this only lists variable emissions. 
insert into fuel_info (fuel, rps_fuel_category, carbon_content) values
	('Gas', 'fossilish', 0.0531),
	('Wind', 'renewable', 0.0939),
	('Solar', 'renewable', 0),
	('Biomass', 'renewable', 0),
	('Coal', 'fossilish', 0),
	('Uranium', 'fossilish', 0),
	('Geothermal', 'renewable', 0),
	('Water', 'fossilish', 0);


drop table if exists fuel_qualifies_for_rps;
create table fuel_qualifies_for_rps(
	area_id INT NOT NULL,
	load_area varchar(11),
	rps_fuel_category varchar(10),
	qualifies boolean,
	INDEX area_id (area_id),
  	CONSTRAINT area_id FOREIGN KEY area_id (area_id)
   		REFERENCES load_area_info (area_id)
);

insert into fuel_qualifies_for_rps
	select distinct 
	        area_id,
			load_area,
			rps_fuel_category,
			if(rps_fuel_category like 'renewable', 1, 0)
		from fuel_info, load_area_info;

