CREATE DATABASE IF NOT EXISTS switch_results_wecc_v2;
USE switch_results_wecc_v2;

CREATE TABLE IF NOT EXISTS co2_cc (
  scenario_id int,
  carbon_cost double,
  co2_tons double,
  co2_tons_reduced double,
  co2_share_reduced double,
  co2_tons_reduced_1990 double,
  co2_share_reduced_1990 double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  PRIMARY KEY (scenario_id, carbon_cost)
);

CREATE TABLE IF NOT EXISTS dispatch (
  scenario_id int,
  carbon_cost double,
  period year,
  load_area varchar(20),
  study_date int,
  study_hour int,
  technology varchar(10),
  site varchar(30),
  orientation char(3),
  new boolean,
  baseload boolean,
  cogen boolean,
  fuel varchar(20),
  power double,
  co2_tons double,
  hours_in_sample int,
  heat_rate double, 
  fuel_cost_tot double,
  carbon_cost_tot double,
  variable_o_m_tot double,
  INDEX scenario_id (scenario_id),
  INDEX load_area (load_area),
  INDEX period (period),
  INDEX carbon_cost (carbon_cost),
  INDEX study_hour (study_hour),
  INDEX study_date (study_date),
  INDEX technology (technology),
  INDEX site (site),
  PRIMARY KEY (scenario_id, carbon_cost, load_area, study_hour, technology, site, orientation, fuel)
);

CREATE TABLE IF NOT EXISTS gen_by_load_area (
  scenario_id int,
  row longblob,
  INDEX scenario_id (scenario_id)
);

CREATE TABLE IF NOT EXISTS gen_cap (
  scenario_id int,
  carbon_cost DOUBLE,
  period YEAR,
  load_area VARCHAR(20),
  technology VARCHAR(10),
  site VARCHAR(30),
  orientation CHAR(3),
  new BOOLEAN,
  baseload BOOLEAN,
  cogen BOOLEAN,
  fuel VARCHAR(20),
  capacity DOUBLE,
  fixed_cost DOUBLE,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX load_area (load_area),
  INDEX technology (technology),
  INDEX site (site),
  PRIMARY KEY (scenario_id, carbon_cost, period, load_area, technology, site, orientation)
);

CREATE TABLE IF NOT EXISTS gen_cap_summary (
  scenario_id int,
  carbon_cost double,
  period year,
  source varchar(35),
  capacity double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX `source` (`source`),
  PRIMARY KEY (scenario_id, carbon_cost, period, `source`)
);

CREATE TABLE IF NOT EXISTS gen_cap_summary_la (
  scenario_id int,
  carbon_cost double,
  period year,
  load_area varchar(20),
  source varchar(35),
  capacity double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX load_area (load_area),
  INDEX `source` (`source`),
  PRIMARY KEY (scenario_id, carbon_cost, period, load_area, `source`)
);

CREATE TABLE IF NOT EXISTS gen_hourly_summary (
  scenario_id int,
  carbon_cost double,
  period year,
  study_date int(11),
  study_hour int(11),
  hours_in_sample int(11),
  month bigint(13),
  month_name varchar(4),
  quarter_of_day bigint(14),
  hour_of_day bigint(13),
  source varchar(35),
  power double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX `source` (`source`),
  PRIMARY KEY (scenario_id, carbon_cost, study_hour, `source`)
);

CREATE TABLE IF NOT EXISTS gen_hourly_summary_la (
  scenario_id int,
  carbon_cost double,
  period year,
  load_area varchar(20),
  study_date int(11),
  study_hour int(11),
  hours_in_sample int(11),
  month bigint(13),
  month_name varchar(4),
  quarter_of_day bigint(14),
  hour_of_day bigint(13),
  source varchar(35),
  power double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX load_area (load_area),
  INDEX `source` (`source`),
  PRIMARY KEY (scenario_id, carbon_cost, study_hour, load_area, `source`)
);

CREATE TABLE IF NOT EXISTS gen_summary (
  scenario_id int,
  carbon_cost double,
  period year,
  source varchar(35),
  avg_power double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX `source` (`source`),
  PRIMARY KEY (scenario_id, carbon_cost, period, `source`)
);

CREATE TABLE IF NOT EXISTS gen_summary_la (
  scenario_id int,
  carbon_cost double,
  period year,
  load_area varchar(20),
  source varchar(35),
  avg_power double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX load_area (load_area),
  INDEX `source` (`source`),
  PRIMARY KEY (scenario_id, carbon_cost, period, load_area, `source`)
);

CREATE TABLE IF NOT EXISTS local_td_cap (
  scenario_id int,
  carbon_cost double,
  period year,
  load_area varchar(20),
  local_td_mw double,
  fixed_cost double, 
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX load_area (load_area),
  PRIMARY KEY (scenario_id, carbon_cost, period, load_area)
);

CREATE TABLE IF NOT EXISTS power_cost (
  scenario_id int,
  carbon_cost double,
  period year,
  load_mwh double,
  fixed_cost_gen double,
  fixed_cost_trans double,
  fixed_cost_local_td double,
  fuel_cost double,
  carbon_cost_tot double,
  variable_o_m double,
  total_cost double,
  cost_per_mwh double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  PRIMARY KEY (scenario_id, carbon_cost, period)
);

CREATE TABLE IF NOT EXISTS trans_cap (
  scenario_id int,
  carbon_cost double,
  period year,
  start varchar(20),
  end varchar(20),
  tid int,
  new boolean,
  trans_mw double,
  fixed_cost double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  PRIMARY KEY (scenario_id, carbon_cost, period, start, end, new)
);

CREATE TABLE IF NOT EXISTS transmission (
  scenario_id int,
  carbon_cost double,
  period int,
  load_area_receive varchar(20),
  load_area_from varchar(20),
  study_date int,
  study_hour int,
  rps_fuel_category varchar(20),
  power_sent double,
  power_received double,
  hours_in_sample int,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX load_area_receive (load_area_receive),
  INDEX load_area_from (load_area_from),
  INDEX rps_fuel_category (rps_fuel_category),
  PRIMARY KEY (scenario_id, carbon_cost, period, study_hour, load_area_receive, load_area_from, rps_fuel_category)
);


DELIMITER $$

DROP FUNCTION IF EXISTS `clear_scenario_results`$$
CREATE FUNCTION `clear_scenario_results` (target_scenario_id int) RETURNS INT 
BEGIN
  
  
  DELETE FROM co2_cc WHERE scenario_id = target_scenario_id;
  DELETE FROM dispatch WHERE scenario_id = target_scenario_id;
  DELETE FROM gen_by_load_area WHERE scenario_id = target_scenario_id;
  DELETE FROM gen_cap WHERE scenario_id = target_scenario_id;
  DELETE FROM gen_cap_summary WHERE scenario_id = target_scenario_id;
  DELETE FROM gen_cap_summary_la WHERE scenario_id = target_scenario_id;
  DELETE FROM gen_hourly_summary WHERE scenario_id = target_scenario_id;
  DELETE FROM gen_hourly_summary_la WHERE scenario_id = target_scenario_id;
  DELETE FROM gen_source_capacity_by_carbon_cost WHERE scenario_id = target_scenario_id;
  DELETE FROM gen_source_share_by_carbon_cost WHERE scenario_id = target_scenario_id;
  DELETE FROM gen_summary WHERE scenario_id = target_scenario_id;
  DELETE FROM gen_summary_la WHERE scenario_id = target_scenario_id;
  DELETE FROM local_td_cap WHERE scenario_id = target_scenario_id;
  DELETE FROM power_cost WHERE scenario_id = target_scenario_id;
  DELETE FROM trans_cap WHERE scenario_id = target_scenario_id;
  DELETE FROM transmission WHERE scenario_id = target_scenario_id;
  
  RETURN 1;
END
$$

DELIMITER ;

DROP FUNCTION IF EXISTS `get_gen_cap_query_source_as_col`;
DELIMITER $$
CREATE DEFINER=`siah`@`localhost` FUNCTION `get_gen_cap_query_source_as_col`(target_scenario_id int) RETURNS varchar(16384)
BEGIN
  
  return( select concat( 
  "select * from (SELECT distinct scenario_id,carbon_cost, period, study_date,study_hour,hours_in_sample,month,month_name,quarter_of_day,hour_of_day FROM gen_hourly_summary WHERE scenario_id = ",target_scenario_id,") t ", 
  group_concat(
    concat(
      "join (select carbon_cost, study_hour, power as `",source,"` FROM gen_hourly_summary where source='",source,"' and scenario_id = ",target_scenario_id,") as `",source,"` using (carbon_cost, study_hour)"
      )
    SEPARATOR ' '
  ),
  " order by carbon_cost, period, month, hour_of_day;") as column_oriented_query 
from (select distinct source from gen_hourly_summary where target_scenario_id = target_scenario_id ) as a );

END
$$