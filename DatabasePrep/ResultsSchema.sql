CREATE DATABASE IF NOT EXISTS switch_results_wecc_v2_2;
USE switch_results_wecc_v2_2;

CREATE OR REPLACE VIEW technologies as 
	select technology_id, technology, fuel, can_build_new from switch_inputs_wecc_v2_2.generator_info;
CREATE OR REPLACE VIEW load_areas as 
	select area_id, load_area from switch_inputs_wecc_v2_2.load_area_info;
CREATE OR REPLACE VIEW load_areas as 
	select area_id, load_area from switch_inputs_wecc_v2_2.load_area_info;
CREATE OR REPLACE VIEW sites as 
  SELECT project_id, location_id as site from switch_inputs_wecc_v2_2.proposed_projects UNION
  SELECT project_id, plant_code as site from switch_inputs_wecc_v2_2.existing_plants UNION 
  SELECT distinct project_id, site from switch_inputs_wecc_v2_2.hydro_monthly_limits;


CREATE TABLE IF NOT EXISTS months (
  month_id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  month_name varchar(50),
  UNIQUE month_name (month_name)
) ROW_FORMAT=FIXED;
INSERT IGNORE INTO months (month_name) 
  VALUES ("Jan"), ("Feb"), ("Mar"), ("Apr"), ("May"), ("Jun"), ("Jul"), ("Aug"), ("Sept"), ("Oct"), ("Nov"), ("Dec");


CREATE TABLE IF NOT EXISTS co2_cc (
  scenario_id int,
  carbon_cost smallint,
  period year,
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
  carbon_cost smallint,
  period year,
  project_id mediumint NOT NULL,
  area_id smallint NOT NULL, 
  study_date int,
  study_hour int,
  technology_id tinyint unsigned NOT NULL, 
  new boolean,
  baseload boolean,
  cogen boolean,
  fuel varchar(64),
  power double,
  co2_tons double,
  hours_in_sample int,
  heat_rate double, 
  fuel_cost double,
  carbon_cost_incurred double,
  variable_o_m_cost double,
  INDEX scenario_id (scenario_id),
  INDEX period (period),
  INDEX carbon_cost (carbon_cost),
  INDEX study_hour (study_hour),
  PRIMARY KEY (scenario_id, carbon_cost, area_id, study_hour, project_id), 
  INDEX technology_id (technology_id),
  FOREIGN KEY (technology_id) REFERENCES technologies(technology_id), 
  INDEX area_id (area_id),
  FOREIGN KEY (area_id) REFERENCES load_areas(area_id), 
  INDEX proj (project_id),
  FOREIGN KEY (project_id) REFERENCES sites(project_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW dispatch as
  SELECT scenario_id, carbon_cost, period, load_area, study_date, study_hour, technology, site, new, baseload, cogen, fuel, power, co2_tons, hours_in_sample, heat_rate, fuel_cost, carbon_cost_incurred, variable_o_m_cost
    FROM _dispatch join load_areas using(area_id) join technologies using(technology_id) join sites using (project_id);

CREATE TABLE IF NOT EXISTS _gen_cap (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint NOT NULL, 
  technology_id tinyint unsigned NOT NULL, 
  project_id mediumint NOT NULL,
  new BOOLEAN,
  baseload BOOLEAN,
  cogen BOOLEAN,
  fuel VARCHAR(64),
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
  PRIMARY KEY (scenario_id, carbon_cost, period, area_id, technology_id, project_id)
)  ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_cap as
  SELECT scenario_id, carbon_cost, period, load_area, area_id, technology, technology_id, site, project_id, new, baseload, cogen, fuel, capacity, fixed_cost
    FROM _gen_cap join load_areas using(area_id) join technologies using(technology_id) join sites using (project_id);


CREATE TABLE IF NOT EXISTS _gen_cap_summary (
  scenario_id int,
  carbon_cost smallint,
  period year,
  technology_id tinyint unsigned NOT NULL,
  capacity double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX technology_id (technology_id),
  PRIMARY KEY (scenario_id, carbon_cost, period, technology_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_cap_summary as
  SELECT scenario_id, carbon_cost, period, technology, capacity
    FROM _gen_cap_summary technologies using(technology_id);

CREATE TABLE IF NOT EXISTS _gen_cap_summary_la (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint NOT NULL, 
  technology_id tinyint unsigned NOT NULL,
  capacity double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX area_id (area_id),
  FOREIGN KEY (area_id) REFERENCES load_areas(area_id), 
  FOREIGN KEY (technology_id) REFERENCES technologies(technology_id),
  INDEX technology_id (technology_id),
  PRIMARY KEY (scenario_id, carbon_cost, period, area_id, technology_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_cap_summary_la as
  SELECT scenario_id, carbon_cost, period, load_area, technology, capacity
    FROM _gen_cap_summary_la join load_areas using(area_id) join technologies using (technology_id);

CREATE TABLE IF NOT EXISTS _gen_hourly_summary (
  scenario_id int,
  carbon_cost smallint,
  period year,
  study_date int,
  study_hour int,
  hours_in_sample int,
  month int,
  hour_of_day bigint,
  technology_id tinyint unsigned NOT NULL,
  power double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX technology_id (technology_id),
  FOREIGN KEY (technology_id) REFERENCES technologies(technology_id),
  PRIMARY KEY (scenario_id, carbon_cost, study_hour, technology_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_hourly_summary as
  SELECT scenario_id, carbon_cost, period, study_date, study_hour, hours_in_sample, month, month_name, hour_of_day, technology, power
    FROM _gen_hourly_summary join months on(month = month_id) join technologies using (technology_id);


CREATE TABLE IF NOT EXISTS _gen_hourly_summary_la (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint NOT NULL, 
  study_date int,
  study_hour int,
  hours_in_sample int,
  month int,
  hour_of_day int,
  technology_id tinyint unsigned NOT NULL,
  variable_o_m_cost double,
  fuel_cost double,
  carbon_cost_incurred double,
  co2_tons double,
  power double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX technology_id (technology_id),
  INDEX area_id (area_id),
  FOREIGN KEY (area_id) REFERENCES load_areas(area_id), 
  FOREIGN KEY (technology_id) REFERENCES technologies(technology_id),
  PRIMARY KEY (scenario_id, carbon_cost, study_hour, area_id, technology_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_hourly_summary_la as
  SELECT scenario_id, carbon_cost, period, load_area, study_date, study_hour, hours_in_sample, month, month_name, hour_of_day, technology, variable_o_m_cost, fuel_cost, carbon_cost_incurred, co2_tons, power
    FROM _gen_hourly_summary_la join load_areas using(area_id) join months on(month=month_id) join technologies using (technology_id);


CREATE TABLE IF NOT EXISTS _gen_summary (
  scenario_id int,
  carbon_cost smallint,
  period year,
  technology_id tinyint unsigned NOT NULL,
  avg_power double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX technology_id (technology_id),
  PRIMARY KEY (scenario_id, carbon_cost, period, technology_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_summary as
  SELECT scenario_id, carbon_cost, period, technology, avg_power
    FROM _gen_summary join technologies using (technology_id);

CREATE TABLE IF NOT EXISTS _gen_summary_la (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint NOT NULL, 
  technology_id tinyint unsigned NOT NULL,
  avg_power double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX area_id (area_id),
  FOREIGN KEY (area_id) REFERENCES load_areas(area_id), 
  FOREIGN KEY (technology_id) REFERENCES technologies(technology_id),
  INDEX technology_id (technology_id),
  PRIMARY KEY (scenario_id, carbon_cost, period, area_id, technology_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_summary_la as
  SELECT scenario_id, carbon_cost, period, load_area, technology, avg_power
    FROM _gen_summary_la join load_areas using(area_id) join technologies using (technology_id);


CREATE TABLE IF NOT EXISTS _local_td_cap (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint NOT NULL, 
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
  carbon_cost smallint,
  period year,
  load_in_period_mwh double,
  local_td_cost double,
  transmission_cost double,
  generator_capital_and_fixed_cost double,
  generator_variable_o_m_cost double,
  fuel_cost double,
  carbon_cost_total double,
  total_cost double,
  cost_per_mwh double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  PRIMARY KEY (scenario_id, carbon_cost, period)
);

CREATE TABLE IF NOT EXISTS _trans_cap (
  scenario_id int,
  carbon_cost smallint,
  period year,
  start_id smallint,
  end_id smallint,
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

CREATE TABLE IF NOT EXISTS _transmission_dispatch (
  scenario_id int,
  carbon_cost smallint,
  period year,
  receive_id smallint,
  send_id smallint,
  study_date int,
  study_hour int,
  month int,
  hour_of_day int,
  hours_in_sample int,
  rps_fuel_category varchar(20),
  power_sent double,
  power_received double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX receive_id (receive_id),
  INDEX send_id (send_id),
  INDEX rps_fuel_category (rps_fuel_category),
  PRIMARY KEY (scenario_id, carbon_cost, period, study_hour, receive_id, send_id, rps_fuel_category)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW transmission_dispatch as
  SELECT scenario_id, carbon_cost, period, start.load_area as load_area_receive, end.load_area as load_area_from, study_date, study_hour, month, hour_of_day, hours_in_sample, rps_fuel_category, power_sent, power_received  
    FROM _transmission_dispatch join load_areas start on(receive_id=start.area_id) join load_areas end on(send_id=end.area_id);

CREATE TABLE IF NOT EXISTS _trans_summary (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint,
  study_date int,
  study_hour int,
  month int,
  hour_of_day int,
  hours_in_sample int,
  net_power double,
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX area_id (area_id),
  PRIMARY KEY (scenario_id, carbon_cost, period, study_hour, area_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW trans_summary as
  SELECT scenario_id, carbon_cost, period, load_area, study_date, study_hour, month, hour_of_day, hours_in_sample, net_power 
    FROM _trans_summary join load_areas using(area_id);

CREATE TABLE IF NOT EXISTS _trans_loss (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint comment "Losses are assigned to areas that transmit power, rather than areas that receive.",
  study_date int,
  study_hour int,
  month int,
  hour_of_day int,
  hours_in_sample int,
  power double,
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX area_id (area_id),
  PRIMARY KEY (scenario_id, carbon_cost, period, study_hour, area_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW trans_loss as
  SELECT scenario_id, carbon_cost, period, load_area, study_date, study_hour, month, hour_of_day, hours_in_sample, power
    FROM _trans_loss join load_areas using(area_id);

CREATE TABLE IF NOT EXISTS _system_load (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint,
  study_date int,
  study_hour int,
  month int,
  hour_of_day int,
  hours_in_sample int,
  power double,
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX area_id (area_id),
  PRIMARY KEY (scenario_id, carbon_cost, period, study_hour, area_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW system_load as
  SELECT scenario_id, carbon_cost, period, load_area, study_date, study_hour, month, hour_of_day, hours_in_sample, power 
    FROM _system_load join load_areas using(area_id);

CREATE TABLE IF NOT EXISTS system_load_summary (
  scenario_id int,
  carbon_cost smallint,
  period year,
  system_load double,
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  PRIMARY KEY (scenario_id, carbon_cost, period)
) ROW_FORMAT=FIXED;


CREATE TABLE IF NOT EXISTS run_times (
  scenario_id int,
  carbon_cost year,
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
  DELETE FROM _gen_cap_summary WHERE scenario_id = target_scenario_id;
  DELETE FROM _gen_cap_summary_la WHERE scenario_id = target_scenario_id;
  DELETE FROM _gen_hourly_summary WHERE scenario_id = target_scenario_id;
  DELETE FROM _gen_hourly_summary_la WHERE scenario_id = target_scenario_id;
  DELETE FROM gen_summary WHERE scenario_id = target_scenario_id;
  DELETE FROM _gen_summary_la WHERE scenario_id = target_scenario_id;
  DELETE FROM _local_td_cap WHERE scenario_id = target_scenario_id;
  DELETE FROM power_cost WHERE scenario_id = target_scenario_id;
  DELETE FROM _trans_cap WHERE scenario_id = target_scenario_id;
  DELETE FROM _transmission_dispatch WHERE scenario_id = target_scenario_id;
  DELETE FROM _trans_summary WHERE scenario_id = target_scenario_id;
  DELETE FROM _trans_loss WHERE scenario_id = target_scenario_id;
  DELETE FROM _system_load WHERE scenario_id = target_scenario_id;
  DELETE FROM system_load_summary WHERE scenario_id = target_scenario_id;
  DELETE FROM run_times WHERE scenario_id = target_scenario_id;
  
  RETURN 1;
END
$$
