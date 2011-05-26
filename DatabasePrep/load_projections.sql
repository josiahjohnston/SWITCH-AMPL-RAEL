USE switch_inputs_wecc_v2_2;

-- This table enumerates the hourly timepoints from 2010 to 2060.
CREATE TABLE study_timepoints (
  timepoint_id INT UNSIGNED PRIMARY KEY,
  datetime_utc DATETIME NOT NULL,
  index (datetime_utc)
);

-- Make a table with integers 0 to 999,999
drop table if exists integers ;
CREATE TABLE integers (num INT UNSIGNED PRIMARY KEY);
INSERT INTO integers VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9);
INSERT IGNORE INTO integers 
  select @row := @row + 1 FROM 
  (SELECT @row:=0) AS a, integers i1, integers i2, integers i3, integers i4, integers i5, integers i6;

set @start_date := '2010-01-01 00:00:00';
set @end_date := '2060-12-31 23:59:59';
INSERT INTO study_timepoints
  select num as timepoint_id, DATE_ADD( @start_date, INTERVAL num HOUR) as datetime_utc 
  FROM integers HAVING datetime_utc <= @end_date;
drop table integers ;


-- This table will keep track of our load growth scenarios. 
CREATE TABLE load_scenarios (
  load_scenario_id  TINYINT UNSIGNED PRIMARY KEY,
  notes             TEXT
);
-- The default Business-As-Usual scenario
INSERT INTO load_scenarios (load_scenario_id, notes)
  VALUES (1, '1% per year load growth scaling factor - the amount projected for all of WECC from 2010 to 2018 by the EIA AEO 2008. Even years are scaled from historic data from 2004. Odd years are scaled from 2005. Leap days are scaled from the leap day in 2004.');

set @BAU_load_scenario_id := 1;
set @num_historic_years := (select count(distinct year(datetime_utc)) from hours);


-- This table stores load projections. The accompanying view provides labels for timepoints and load areas instead of ids. 
CREATE TABLE _load_projections (
  load_scenario_id  TINYINT UNSIGNED NOT NULL,
  area_id           SMALLINT UNSIGNED NOT NULL,
  timepoint_id      INT UNSIGNED NOT NULL,
  future_year       YEAR,
  historic_hour     SMALLINT UNSIGNED NOT NULL, 
  power             DECIMAL(6,0) NOT NULL,
  PRIMARY KEY (load_scenario_id, area_id, timepoint_id),
  INDEX (future_year),
  index historic_datum (load_scenario_id, area_id, historic_hour),
  index future_time (load_scenario_id, timepoint_id),
  CONSTRAINT load_scenario_id FOREIGN KEY load_scenario_id (load_scenario_id)
    REFERENCES load_scenarios (load_scenario_id)
);
CREATE OR REPLACE VIEW load_projections AS
  SELECT 
    load_scenario_id,
    load_area,
    timepoint_id,
    datetime_utc,
    historic_hour,
    power
  from _load_projections join study_timepoints using(timepoint_id) join load_area_info using(area_id)
;

CREATE TABLE load_scenario_historic_timepoints (
	load_scenario_id  TINYINT UNSIGNED NOT NULL,
  timepoint_id      INT UNSIGNED NOT NULL,
  historic_hour     SMALLINT UNSIGNED NOT NULL,
  PRIMARY KEY(load_scenario_id, timepoint_id),
  index (timepoint_id),
  index (historic_hour, load_scenario_id),
  CONSTRAINT load_scenario_id FOREIGN KEY load_scenario_id (load_scenario_id)
    REFERENCES load_scenarios (load_scenario_id),
  CONSTRAINT timepoint_id FOREIGN KEY timepoint_id (timepoint_id)
    REFERENCES study_timepoints (timepoint_id),
  CONSTRAINT historic_hour FOREIGN KEY historic_hour (historic_hour)
    REFERENCES hours (hournum)
);

INSERT INTO load_scenario_historic_timepoints (load_scenario_id, timepoint_id, historic_hour)
	SELECT @BAU_load_scenario_id, timepoint_id, hournum
		FROM study_timepoints s JOIN hours h
		WHERE MONTH(s.datetime_utc) = MONTH(h.datetime_utc)
			AND HOUR(s.datetime_utc) = HOUR(h.datetime_utc)
			AND DAY(s.datetime_utc) = DAY(h.datetime_utc)
			AND YEAR(s.datetime_utc) MOD @num_historic_years = YEAR(h.datetime_utc) MOD @num_historic_years;

-- System load is missing hours 1-23 and 8769-8791 (Jan 1, 2004 and 2004/12/31 9AM - 2005/01/01 7AM). It has a total of 17497 hours, ending with 2005-12-31 23:00:00

INSERT INTO _load_projections (load_scenario_id, area_id, timepoint_id, future_year, historic_hour, power)
  SELECT @BAU_load_scenario_id, area_id, timepoint_id, YEAR(study_timepoints.datetime_utc),
    hours.hournum as historic_hour,
    CAST( power(1.01, YEAR(study_timepoints.datetime_utc) - YEAR(hours.datetime_utc))*power AS DECIMAL(6,0)) as system_load
    FROM study_timepoints join load_scenario_historic_timepoints using(timepoint_id) join _system_load on (historic_hour=hour) join hours on (hour=hournum)
    WHERE load_scenario_id=@BAU_load_scenario_id
    ;

-- Daily summaries of load projections will simplify some other steps. 
CREATE TABLE IF NOT EXISTS _load_projection_daily_summaries (
  load_scenario_id TINYINT UNSIGNED NOT NULL,
  date_utc DATE, 
  num_data_points SMALLINT UNSIGNED,
  total_load DECIMAL(8,0),
  average_load DECIMAL(6,0),
  peak_load DECIMAL(6,0),
  peak_hour_id INT UNSIGNED NOT NULL,
  peak_hour_historic_id SMALLINT UNSIGNED NOT NULL, 
  PRIMARY KEY (load_scenario_id, date_utc), 
  INDEX (load_scenario_id, date_utc, peak_hour_historic_id), 
  CONSTRAINT load_scenario_id FOREIGN KEY load_scenario_id (load_scenario_id)
    REFERENCES load_scenarios (load_scenario_id),
  CONSTRAINT peak_hour_fk FOREIGN KEY peak_hour_id (peak_hour_id)
    REFERENCES study_timepoints (timepoint_id)
);

CREATE TEMPORARY TABLE _hourly_summaries 
	SELECT load_scenario_id, timepoint_id, historic_hour,
		DATE(datetime_utc) AS date_utc, 
		CAST(SUM(power) AS DECIMAL(6,0)) AS system_load, 
		COUNT(power) AS n
	FROM _load_projections JOIN study_timepoints USING(timepoint_id) 
	GROUP BY 1,2,3;
ALTER TABLE _hourly_summaries ADD INDEX (load_scenario_id), ADD INDEX (date_utc);

INSERT INTO _load_projection_daily_summaries (load_scenario_id, date_utc, num_data_points, total_load, average_load, peak_load)
  SELECT load_scenario_id, date_utc, sum(n), 
  	CAST(sum(system_load) AS DECIMAL(8,0)), 
  	CAST(sum(system_load)/24 AS DECIMAL(6,0)),
  	CAST(max(system_load) AS DECIMAL(6,0))
    FROM _hourly_summaries
    GROUP BY 1, 2; 
    
UPDATE _load_projection_daily_summaries, _hourly_summaries 
	SET peak_hour_id = timepoint_id, peak_hour_historic_id = historic_hour
	WHERE _hourly_summaries.date_utc = _load_projection_daily_summaries.date_utc
		AND _hourly_summaries.system_load = _load_projection_daily_summaries.peak_load;

DROP TABLE _hourly_summaries;

