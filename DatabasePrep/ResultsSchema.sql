CREATE DATABASE IF NOT EXISTS switch_results_wecc_v2_1;
USE switch_results_wecc_v2_1;

CREATE TABLE IF NOT EXISTS technologies (
  technology_id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  technology varchar(30),
  UNIQUE technology (technology)
) ROW_FORMAT=FIXED;
INSERT IGNORE INTO technologies (technology_id, technology)
  SELECT technology_id, technology from switch_inputs_wecc_v2_1.generator_info gen_info;


CREATE TABLE IF NOT EXISTS load_areas (
  area_id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  load_area varchar(20),
  UNIQUE load_area (load_area)
) ROW_FORMAT=FIXED;
INSERT IGNORE INTO load_areas (area_id, load_area)
  SELECT area_id, load_area from switch_inputs_wecc_v2_1.load_area_info src;

CREATE TABLE IF NOT EXISTS sites (
  project_id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  site varchar(50),
  UNIQUE site (site)
) ROW_FORMAT=FIXED;
INSERT IGNORE INTO sites (project_id, site)
  SELECT project_id, site from switch_inputs_wecc_v2_1.proposed_renewable_sites src;
INSERT IGNORE INTO sites (project_id, site)
  SELECT project_id, plant_code from switch_inputs_wecc_v2_1.existing_plants;
INSERT IGNORE INTO sites (project_id, site)
  SELECT distinct project_id, site from switch_inputs_wecc_v2_1.hydro_monthly_limits;
INSERT IGNORE INTO sites (project_id, site)
  SELECT project_id, concat(load_area,'-',technology) from switch_inputs_wecc_v2_1.generator_costs_regional;


CREATE TABLE IF NOT EXISTS months (
  month_id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  month_name varchar(50),
  UNIQUE month_name (month_name)
) ROW_FORMAT=FIXED;
INSERT IGNORE INTO months (month_name) 
  VALUES ("Jan"), ("Feb"), ("Mar"), ("Apr"), ("May"), ("Jun"), ("Jul"), ("Aug"), ("Sept"), ("Oct"), ("Nov"), ("Dec");


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

CREATE TABLE IF NOT EXISTS _dispatch (
  scenario_id int,
  carbon_cost double,
  period year,
  area_id int NOT NULL, 
  study_date int,
  study_hour int,
  technology_id int NOT NULL, 
  project_id int NOT NULL,
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
  INDEX period (period),
  INDEX carbon_cost (carbon_cost),
  INDEX study_hour (study_hour),
  PRIMARY KEY (scenario_id, carbon_cost, area_id, study_hour, project_id, orientation), 
  INDEX technology_id (technology_id),
  FOREIGN KEY (technology_id) REFERENCES technologies(technology_id), 
  INDEX area_id (area_id),
  FOREIGN KEY (area_id) REFERENCES load_areas(area_id), 
  INDEX site (project_id),
  FOREIGN KEY (project_id) REFERENCES sites(project_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW dispatch as
  SELECT scenario_id, carbon_cost, period, load_area, study_date, study_hour, technology, site, orientation, new, baseload, cogen, fuel, power, co2_tons, hours_in_sample, heat_rate, fuel_cost_tot, carbon_cost_tot, variable_o_m_tot
    FROM _dispatch join load_areas using(area_id) join technologies using(technology_id) join sites using (project_id);

CREATE TABLE IF NOT EXISTS _gen_cap (
  scenario_id int,
  carbon_cost DOUBLE,
  period YEAR,
  area_id int NOT NULL, 
  technology_id int NOT NULL, 
  project_id int NOT NULL,
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
  INDEX area_id (area_id),
  FOREIGN KEY (area_id) REFERENCES load_areas(area_id), 
  INDEX technology_id (technology_id),
  FOREIGN KEY (technology_id) REFERENCES technologies(technology_id), 
  INDEX site (project_id),
  FOREIGN KEY (project_id) REFERENCES sites(project_id), 
  PRIMARY KEY (scenario_id, carbon_cost, period, area_id, technology_id, project_id, orientation)
)  ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_cap as
  SELECT scenario_id, carbon_cost, period, load_area, area_id, technology, technology_id, site, project_id, orientation, new, baseload, cogen, fuel, capacity, fixed_cost
    FROM _gen_cap join load_areas using(area_id) join technologies using(technology_id) join sites using (project_id);


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
) ROW_FORMAT=FIXED;

CREATE TABLE IF NOT EXISTS _gen_cap_summary_la (
  scenario_id int,
  carbon_cost double,
  period year,
  area_id int NOT NULL, 
  source varchar(35),
  capacity double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX area_id (area_id),
  FOREIGN KEY (area_id) REFERENCES load_areas(area_id), 
  INDEX `source` (`source`),
  PRIMARY KEY (scenario_id, carbon_cost, period, area_id, `source`)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_cap_summary_la as
  SELECT scenario_id, carbon_cost, period, load_area, source, capacity
    FROM _gen_cap_summary_la join load_areas using(area_id);

CREATE TABLE IF NOT EXISTS _gen_hourly_summary (
  scenario_id int,
  carbon_cost double,
  period year,
  study_date int,
  study_hour int,
  hours_in_sample int,
  month int,
  quarter_of_day bigint,
  hour_of_day bigint,
  source varchar(35),
  power double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX `source` (`source`),
  PRIMARY KEY (scenario_id, carbon_cost, study_hour, `source`)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_hourly_summary as
  SELECT scenario_id, carbon_cost, period, study_date, study_hour, hours_in_sample, month, month_name, quarter_of_day, hour_of_day, source, power
    FROM _gen_hourly_summary join months on(month=month_id);


CREATE TABLE IF NOT EXISTS _gen_hourly_summary_la (
  scenario_id int,
  carbon_cost double,
  period year,
  area_id int NOT NULL, 
  study_date int,
  study_hour int,
  hours_in_sample int,
  month int,
  quarter_of_day bigint,
  hour_of_day bigint,
  source varchar(35),
  power double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX `source` (`source`),
  INDEX area_id (area_id),
  FOREIGN KEY (area_id) REFERENCES load_areas(area_id), 
  PRIMARY KEY (scenario_id, carbon_cost, study_hour, area_id, `source`)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_hourly_summary_la as
  SELECT scenario_id, carbon_cost, period, load_area, study_date, study_hour, hours_in_sample, month, month_name, quarter_of_day, hour_of_day, source, power
    FROM _gen_hourly_summary_la join load_areas using(area_id) join months on(month=month_id);


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
) ROW_FORMAT=FIXED;

CREATE TABLE IF NOT EXISTS _gen_summary_la (
  scenario_id int,
  carbon_cost double,
  period year,
  area_id int NOT NULL, 
  source varchar(35),
  avg_power double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX area_id (area_id),
  FOREIGN KEY (area_id) REFERENCES load_areas(area_id), 
  INDEX `source` (`source`),
  PRIMARY KEY (scenario_id, carbon_cost, period, area_id, `source`)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_summary_la as
  SELECT scenario_id, carbon_cost, period, load_area, source, avg_power
    FROM _gen_summary_la join load_areas using(area_id);


CREATE TABLE IF NOT EXISTS _local_td_cap (
  scenario_id int,
  carbon_cost double,
  period year,
  area_id int NOT NULL, 
  local_td_mw double,
  fixed_cost double, 
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX area_id (area_id),
  FOREIGN KEY (area_id) REFERENCES load_areas(area_id), 
  PRIMARY KEY (scenario_id, carbon_cost, period, area_id)
);
CREATE OR REPLACE VIEW local_td_cap as
  SELECT scenario_id, carbon_cost, period, load_area, local_td_mw, fixed_cost
    FROM _local_td_cap join load_areas using(area_id);


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

CREATE TABLE IF NOT EXISTS _trans_cap (
  scenario_id int,
  carbon_cost double,
  period year,
  start_id int,
  end_id int,
  tid int,
  new boolean,
  trans_mw double,
  fixed_cost double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  PRIMARY KEY (scenario_id, carbon_cost, period, start_id, end_id, new)
);
CREATE OR REPLACE VIEW trans_cap as
  SELECT scenario_id, carbon_cost, period, start.load_area as start, end.load_area as end, tid, new, trans_mw, fixed_cost 
    FROM _trans_cap join load_areas start on(start_id=start.area_id) join load_areas end on(end_id=end.area_id) ;

CREATE TABLE IF NOT EXISTS _transmission (
  scenario_id int,
  carbon_cost double,
  period int,
  receive_id int,
  send_id int,
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
  INDEX receive_id (receive_id),
  INDEX send_id (send_id),
  INDEX rps_fuel_category (rps_fuel_category),
  PRIMARY KEY (scenario_id, carbon_cost, period, study_hour, receive_id, send_id, rps_fuel_category)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW transmission as
  SELECT scenario_id, carbon_cost, period, start.load_area as load_area_receive, end.load_area as load_area_from, study_date, study_hour, rps_fuel_category, power_sent, power_received, hours_in_sample 
    FROM _transmission join load_areas start on(receive_id=start.area_id) join load_areas end on(send_id=end.area_id);

CREATE TABLE IF NOT EXISTS _trans_summary (
  scenario_id int,
  carbon_cost double,
  period int,
  area_id int,
  study_date int,
  study_hour int,
  net_power double,
  hours_in_sample int,
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX area_id (area_id),
  PRIMARY KEY (scenario_id, carbon_cost, period, study_hour, area_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW trans_summary as
  SELECT scenario_id, carbon_cost, period, load_area, study_date, study_hour, net_power, hours_in_sample 
    FROM _trans_summary join load_areas using(area_id);

CREATE TABLE IF NOT EXISTS _trans_loss (
  scenario_id int,
  carbon_cost double,
  period int,
  area_id int comment "Losses are assigned to areas that transmit power, rather than areas that receive.",
  study_date int,
  study_hour int,
  power double,
  hours_in_sample int,
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX area_id (area_id),
  PRIMARY KEY (scenario_id, carbon_cost, period, study_hour, area_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW trans_loss as
  SELECT scenario_id, carbon_cost, period, load_area, study_date, study_hour, net_power, hours_in_sample 
    FROM _trans_summary join load_areas using(area_id);

CREATE TABLE IF NOT EXISTS _system_load (
  scenario_id int,
  carbon_cost double,
  period int,
  area_id int,
  study_date int,
  study_hour int,
  power double,
  hours_in_sample int,
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX area_id (area_id),
  PRIMARY KEY (scenario_id, carbon_cost, period, study_hour, area_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW system_load as
  SELECT scenario_id, carbon_cost, period, load_area, study_date, study_hour, power, hours_in_sample 
    FROM _system_load join load_areas using(area_id);



CREATE TABLE IF NOT EXISTS run_times (
  scenario_id int,
  carbon_cost double,
  cost_optimization_run_time float COMMENT 'Time to optimize for cost (in seconds).',
  trans_optimization_run_time float COMMENT 'Time to optimize for transmission (in seconds).',
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  PRIMARY KEY (scenario_id, carbon_cost)
);


DELIMITER $$

DROP FUNCTION IF EXISTS `clear_scenario_results`$$
CREATE FUNCTION `clear_scenario_results` (target_scenario_id int) RETURNS INT 
BEGIN
  
  
  DELETE FROM co2_cc WHERE scenario_id = target_scenario_id;
  DELETE FROM _dispatch WHERE scenario_id = target_scenario_id;
  DELETE FROM _gen_cap WHERE scenario_id = target_scenario_id;
  DELETE FROM gen_cap_summary WHERE scenario_id = target_scenario_id;
  DELETE FROM _gen_cap_summary_la WHERE scenario_id = target_scenario_id;
  DELETE FROM _gen_hourly_summary WHERE scenario_id = target_scenario_id;
  DELETE FROM _gen_hourly_summary_la WHERE scenario_id = target_scenario_id;
  DELETE FROM gen_summary WHERE scenario_id = target_scenario_id;
  DELETE FROM _gen_summary_la WHERE scenario_id = target_scenario_id;
  DELETE FROM _local_td_cap WHERE scenario_id = target_scenario_id;
  DELETE FROM power_cost WHERE scenario_id = target_scenario_id;
  DELETE FROM _trans_cap WHERE scenario_id = target_scenario_id;
  DELETE FROM _transmission WHERE scenario_id = target_scenario_id;
  DELETE FROM _trans_summary WHERE scenario_id = target_scenario_id;
  DELETE FROM _trans_loss WHERE scenario_id = target_scenario_id;
  DELETE FROM _system_load WHERE scenario_id = target_scenario_id;
  DELETE FROM run_times WHERE scenario_id = target_scenario_id;
  
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