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
  SELECT distinct project_id, hydro_id from switch_inputs_wecc_v2_2.hydro_monthly_limits;
CREATE OR REPLACE VIEW transmission_lines as 
	select 	transmission_line_id, load_area_start, load_area_end,
			la1.area_id as start_id, la2.area_id as end_id
		from switch_inputs_wecc_v2_2.transmission_lines tl, load_areas la1, load_areas la2
		where	tl.load_area_start = la1.load_area
		and		tl.load_area_end = la2.load_area;



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
  INDEX period (period),
  PRIMARY KEY (scenario_id, carbon_cost, period)
);


CREATE TABLE IF NOT EXISTS _dispatch (
  scenario_id int,
  carbon_cost smallint,
  period year,
  project_id int NOT NULL,
  area_id smallint NOT NULL, 
  study_date int,
  study_hour int,
  technology_id tinyint unsigned NOT NULL, 
  new boolean,
  baseload boolean,
  cogen boolean,
  fuel VARCHAR(64) NOT NULL,
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
  SELECT scenario_id, carbon_cost, period, load_area, study_date, study_hour, technology, site, new, baseload, cogen, _dispatch.fuel, power, co2_tons, hours_in_sample, heat_rate, fuel_cost, carbon_cost_incurred, variable_o_m_cost
    FROM _dispatch join load_areas using(area_id) join technologies using(technology_id) join sites using (project_id);

-- gen cap summaries by TECH-----
CREATE TABLE IF NOT EXISTS _gen_cap (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint NOT NULL, 
  technology_id tinyint unsigned NOT NULL, 
  project_id int NOT NULL,
  new BOOLEAN,
  baseload BOOLEAN,
  cogen BOOLEAN,
  fuel VARCHAR(64) NOT NULL,
  capacity DOUBLE,
  capital_cost DOUBLE,
  fixed_o_m_cost DOUBLE,
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
  SELECT scenario_id, carbon_cost, period, load_area, area_id, technology, technology_id, site, project_id, new, baseload, cogen, _gen_cap.fuel, capacity, capital_cost, fixed_o_m_cost
    FROM _gen_cap join load_areas using(area_id) join technologies using(technology_id) join sites using (project_id);


CREATE TABLE IF NOT EXISTS _gen_cap_summary_tech (
  scenario_id int,
  carbon_cost smallint,
  period year,
  technology_id tinyint unsigned NOT NULL,
  capacity double NOT NULL default 0,
  capital_cost double NOT NULL default 0,
  o_m_cost_total double NOT NULL default 0,
  fuel_cost double NOT NULL default 0,
  carbon_cost_total double NOT NULL default 0,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX technology_id (technology_id),
  PRIMARY KEY (scenario_id, carbon_cost, period, technology_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_cap_summary as
  SELECT scenario_id, carbon_cost, period, technology, capacity, capital_cost, o_m_cost_total, fuel_cost, carbon_cost_total
    FROM _gen_cap_summary_tech join technologies using(technology_id);

CREATE TABLE IF NOT EXISTS _gen_cap_summary_tech_la (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint NOT NULL, 
  technology_id tinyint unsigned NOT NULL,
  capacity double NOT NULL default 0,
  capital_cost double NOT NULL default 0,
  fixed_o_m_cost double NOT NULL default 0,
  variable_o_m_cost double NOT NULL default 0,
  fuel_cost double NOT NULL default 0,
  carbon_cost_total double NOT NULL default 0,
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
  SELECT scenario_id, carbon_cost, period, load_area, technology, capacity, capital_cost, fixed_o_m_cost, variable_o_m_cost, fuel_cost, carbon_cost_total
    FROM _gen_cap_summary_tech_la join load_areas using(area_id) join technologies using (technology_id);

-- gen cap summaries by FUEL-----

CREATE TABLE IF NOT EXISTS gen_cap_summary_fuel (
  scenario_id int,
  carbon_cost smallint,
  period year,
  fuel VARCHAR(64) NOT NULL,
  capacity double NOT NULL default 0,
  capital_cost double NOT NULL default 0,
  o_m_cost_total double NOT NULL default 0,
  fuel_cost double NOT NULL default 0,
  carbon_cost_total double NOT NULL default 0,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX fuel (fuel),
  PRIMARY KEY (scenario_id, carbon_cost, period, fuel)
) ROW_FORMAT=FIXED;

CREATE TABLE IF NOT EXISTS _gen_cap_summary_fuel_la (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint NOT NULL, 
  fuel VARCHAR(64) NOT NULL,
  capacity double NOT NULL default 0,
  capital_cost double NOT NULL default 0,
  fixed_o_m_cost double NOT NULL default 0,
  variable_o_m_cost double NOT NULL default 0,
  fuel_cost double NOT NULL default 0,
  carbon_cost_total double NOT NULL default 0,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX area_id (area_id),
  FOREIGN KEY (area_id) REFERENCES load_areas(area_id), 
  FOREIGN KEY (fuel) REFERENCES technologies(fuel),
  INDEX fuel (fuel),
  PRIMARY KEY (scenario_id, carbon_cost, period, area_id, fuel)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_cap_summary_fuel_la as
  SELECT scenario_id, carbon_cost, period, load_area, fuel, capacity, capital_cost, fixed_o_m_cost, variable_o_m_cost, fuel_cost, carbon_cost_total
    FROM _gen_cap_summary_fuel_la join load_areas using(area_id);


-- generation summaries by TECHNOLOGY -------------------
CREATE TABLE IF NOT EXISTS _gen_hourly_summary_tech_la (
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
  variable_o_m_cost double NOT NULL default 0,
  fuel_cost double NOT NULL default 0,
  carbon_cost_incurred double NOT NULL default 0,
  co2_tons double NOT NULL default 0,
  power double NOT NULL default 0,
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
CREATE OR REPLACE VIEW gen_hourly_summary_la_tech as
  SELECT scenario_id, carbon_cost, period, load_area, study_date, study_hour, hours_in_sample, month, month_name, hour_of_day, technology, variable_o_m_cost, fuel_cost, carbon_cost_incurred, co2_tons, power
    FROM _gen_hourly_summary_tech_la join load_areas using(area_id) join months on(month=month_id) join technologies using (technology_id);

CREATE TABLE IF NOT EXISTS _gen_hourly_summary_tech (
  scenario_id int,
  carbon_cost smallint,
  period year,
  study_date int,
  study_hour int,
  hours_in_sample int,
  month int,
  hour_of_day int,
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
CREATE OR REPLACE VIEW gen_hourly_summary_tech as
  SELECT scenario_id, carbon_cost, period, study_date, study_hour, hours_in_sample, month, month_name, hour_of_day, technology, power
    FROM _gen_hourly_summary_tech join months on(month = month_id) join technologies using (technology_id);

CREATE TABLE IF NOT EXISTS _gen_summary_tech_la (
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
CREATE OR REPLACE VIEW gen_summary_tech_la as
  SELECT scenario_id, carbon_cost, period, load_area, technology, avg_power
    FROM _gen_summary_tech_la join load_areas using(area_id) join technologies using (technology_id);

CREATE TABLE IF NOT EXISTS _gen_summary_tech (
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
CREATE OR REPLACE VIEW gen_summary_tech as
  SELECT scenario_id, carbon_cost, period, technology, avg_power
    FROM _gen_summary_tech join technologies using (technology_id);


-- generation summaries by FUEL -------------------
CREATE TABLE IF NOT EXISTS _gen_hourly_summary_fuel_la (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint NOT NULL, 
  study_date int,
  study_hour int,
  hours_in_sample int,
  month int,
  hour_of_day int,
  fuel VARCHAR(64) NOT NULL,
  power double NOT NULL default 0,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX fuel (fuel),
  INDEX area_id (area_id),
  FOREIGN KEY (area_id) REFERENCES load_areas(area_id), 
  FOREIGN KEY (fuel) REFERENCES technologies(fuel),
  PRIMARY KEY (scenario_id, carbon_cost, study_hour, area_id, fuel)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_hourly_summary_fuel_la as
  SELECT scenario_id, carbon_cost, period, load_area, study_date, study_hour, hours_in_sample, month, month_name, hour_of_day, fuel, power
    FROM _gen_hourly_summary_fuel_la join load_areas using(area_id) join months on(month=month_id);

CREATE TABLE IF NOT EXISTS _gen_hourly_summary_fuel (
  scenario_id int,
  carbon_cost smallint,
  period year,
  study_date int,
  study_hour int,
  hours_in_sample int,
  month int,
  hour_of_day int,
  fuel VARCHAR(64) NOT NULL,
  power double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX technology_id (fuel),
  FOREIGN KEY (fuel) REFERENCES technologies(fuel),
  PRIMARY KEY (scenario_id, carbon_cost, study_hour, fuel)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_hourly_summary_fuel as
  SELECT scenario_id, carbon_cost, period, study_date, study_hour, hours_in_sample, month, month_name, hour_of_day, fuel, power
    FROM _gen_hourly_summary_fuel join months on(month = month_id);

CREATE TABLE IF NOT EXISTS _gen_summary_fuel_la (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint NOT NULL, 
  fuel VARCHAR(64) NOT NULL,
  avg_power double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX area_id (area_id),
  FOREIGN KEY (area_id) REFERENCES load_areas(area_id), 
  FOREIGN KEY (fuel) REFERENCES technologies(fuel),
  INDEX fuel (fuel),
  PRIMARY KEY (scenario_id, carbon_cost, period, area_id, fuel)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_summary_fuel_la as
  SELECT scenario_id, carbon_cost, period, load_area, fuel, avg_power
    FROM _gen_summary_fuel_la join load_areas using(area_id);

CREATE TABLE IF NOT EXISTS gen_summary_fuel (
  scenario_id int,
  carbon_cost smallint,
  period year,
  fuel VARCHAR(64) NOT NULL,
  avg_power double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX fuel (fuel),
  PRIMARY KEY (scenario_id, carbon_cost, period, fuel)
) ROW_FORMAT=FIXED;

-- ----------------
CREATE TABLE IF NOT EXISTS _local_td_cap (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint NOT NULL,
  new boolean,
  local_td_mw double,
  fixed_cost double, 
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX area_id (area_id),
  FOREIGN KEY (area_id) REFERENCES load_areas(area_id), 
  PRIMARY KEY (scenario_id, carbon_cost, period, area_id, new)
);
CREATE OR REPLACE VIEW local_td_cap as
  SELECT scenario_id, carbon_cost, period, load_area, new, local_td_mw, fixed_cost
    FROM _local_td_cap join load_areas using(area_id);


CREATE TABLE IF NOT EXISTS power_cost (
  scenario_id int NOT NULL,
  carbon_cost smallint NOT NULL,
  period year NOT NULL,
  load_in_period_mwh double NOT NULL,
  existing_local_td_cost double default 0 NOT NULL,
  new_local_td_cost double default 0 NOT NULL,
  existing_transmission_cost double default 0 NOT NULL,
  new_transmission_cost double default 0 NOT NULL,
  existing_plant_sunk_cost double default 0 NOT NULL, 
  existing_plant_operational_cost double default 0 NOT NULL,
  new_coal_nonfuel_cost double default 0 NOT NULL,
  coal_fuel_cost double default 0 NOT NULL, 
  new_gas_nonfuel_cost double default 0 NOT NULL, 
  gas_fuel_cost double default 0 NOT NULL,
  new_nuclear_nonfuel_cost double default 0 NOT NULL, 
  nuclear_fuel_cost double default 0 NOT NULL,
  new_renewable_cost double default 0 NOT NULL, 
  carbon_cost_total double default 0 NOT NULL, 
  total_cost double default 0 NOT NULL,
  cost_per_mwh double default 0 NOT NULL,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  PRIMARY KEY (scenario_id, carbon_cost, period)
);


CREATE TABLE IF NOT EXISTS _storage_dispatch (
  scenario_id int,
  carbon_cost smallint,
  period year,
  project_id int,
  area_id smallint,
  study_date int,
  study_hour int,
  technology_id tinyint unsigned NOT NULL,
  storage_efficiency double,
  new boolean,
  rps_fuel_category varchar(20),
  hours_in_sample int,
  power double,
  variable_o_m_cost double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX project_id (project_id),
  INDEX technology_id (technology_id),
  INDEX new (new),
  INDEX area_id (area_id),
  INDEX study_date (study_date),
  INDEX study_hour (study_hour),
  INDEX rps_fuel_category (rps_fuel_category), 
  PRIMARY KEY (scenario_id, carbon_cost, period, project_id, study_hour, rps_fuel_category)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW storage_dispatch as
  SELECT scenario_id, carbon_cost, period, project_id, area_id, load_area, study_date, study_hour, 
  		technology_id, technology, storage_efficiency, new, hours_in_sample, power, variable_o_m_cost
    FROM _storage_dispatch join load_areas using (area_id) join technologies using (technology_id);


CREATE TABLE IF NOT EXISTS _trans_cap (
  scenario_id int,
  carbon_cost smallint,
  period year,
  transmission_line_id int,
  start_id smallint,
  end_id smallint,
  new boolean,
  trans_mw double,
  fixed_cost double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX transmission_line_id (transmission_line_id),
  INDEX start_id (start_id),
  INDEX end_id (end_id),  
  INDEX new (new),  
  PRIMARY KEY (scenario_id, carbon_cost, period, transmission_line_id, new)
);
CREATE OR REPLACE VIEW trans_cap as
  SELECT scenario_id, carbon_cost, period, transmission_line_id, start.load_area as start, end.load_area as end, new, trans_mw, fixed_cost 
    FROM _trans_cap join load_areas start on(start_id=start.area_id) join load_areas end on(end_id=end.area_id) ;


CREATE VIEW trans_cap_summary AS
select
e.scenario_id, e.carbon_cost, e.period, e.transmission_line_id,
load_area_start, load_area_end,
e.trans_mw as existing_trans_mw, n.trans_mw as new_trans_mw, e.trans_mw + n.trans_mw as total_trans_mw
from _trans_cap e, _trans_cap n join transmission_lines using (transmission_line_id)
where e.scenario_id = n.scenario_id
and e.carbon_cost = n.carbon_cost
and e.period = n.period
and e.transmission_line_id = n.transmission_line_id
and e.start_id = n.start_id
and e.end_id = n.end_id
and e.new = 0
and n.new = 1
order by 1,2,3,5,6;


CREATE TABLE IF NOT EXISTS _existing_trans_cost (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint NOT NULL,
  fixed_cost double, 
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX area_id (area_id),
  FOREIGN KEY (area_id) REFERENCES load_areas(area_id), 
  PRIMARY KEY (scenario_id, carbon_cost, period, area_id)
);

CREATE TABLE IF NOT EXISTS _transmission_dispatch (
  scenario_id int,
  carbon_cost smallint,
  period year,
  transmission_line_id int,
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
  INDEX transmission_line_id (transmission_line_id),
  INDEX study_hour (study_hour),
  INDEX receive_id (receive_id),
  INDEX send_id (send_id),
  INDEX rps_fuel_category (rps_fuel_category),
  PRIMARY KEY (scenario_id, carbon_cost, period, transmission_line_id, study_hour, rps_fuel_category)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW transmission_dispatch as
  SELECT scenario_id, carbon_cost, period, transmission_line_id, start.load_area as load_area_receive, end.load_area as load_area_from, study_date, study_hour, month, hour_of_day, hours_in_sample, rps_fuel_category, power_sent, power_received  
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
  INDEX scenario_id (scenario_id),
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
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX area_id (area_id),
  PRIMARY KEY (scenario_id, carbon_cost, period, study_hour, area_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW trans_loss as
  SELECT scenario_id, carbon_cost, period, load_area, study_date, study_hour, month, hour_of_day, hours_in_sample, power
    FROM _trans_loss join load_areas using(area_id);


CREATE TABLE IF NOT EXISTS _transmission_directed_hourly (
  scenario_id int,
  carbon_cost smallint,
  period year,
  study_hour int,
  transmission_line_id int,
  send_id smallint,
  receive_id smallint,
  directed_trans_avg int,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX transmission_line_id (transmission_line_id),
  INDEX send_id (send_id),
  INDEX receive_id (receive_id),
  PRIMARY KEY (scenario_id, carbon_cost, period, study_hour, transmission_line_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW transmission_directed_hourly as
  SELECT scenario_id, carbon_cost, period, study_hour, transmission_line_id, load_area_start as load_area_from, load_area_end as load_area_receive, start_id as send_id, end_id as receive_id, directed_trans_avg
    FROM _transmission_directed_hourly join transmission_lines using(transmission_line_id);


CREATE TABLE IF NOT EXISTS _transmission_avg_directed (
  scenario_id int,
  carbon_cost smallint,
  period year,
  transmission_line_id int,
  send_id smallint,
  receive_id smallint,
  directed_trans_avg int,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX transmission_line_id (transmission_line_id),
  INDEX send_id (send_id),
  INDEX receive_id (receive_id),
  PRIMARY KEY (scenario_id, carbon_cost, period, transmission_line_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW transmission_avg_directed as
  SELECT scenario_id, carbon_cost, period, transmission_line_id, load_area_start as load_area_from, load_area_end as load_area_receive, start_id as send_id, end_id as receive_id, directed_trans_avg
    FROM _transmission_avg_directed join transmission_lines using(transmission_line_id);
		

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
  carbon_cost smallint,
  process_type varchar(64),
  time_seconds float,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX process_type (process_type),
  PRIMARY KEY (scenario_id, carbon_cost, process_type)
);


DELIMITER $$

DROP FUNCTION IF EXISTS `clear_scenario_results`$$
CREATE FUNCTION `clear_scenario_results` (target_scenario_id int) RETURNS INT 
BEGIN
  
  DELETE FROM _dispatch WHERE scenario_id = target_scenario_id;
  DELETE FROM _existing_trans_cost WHERE scenario_id = target_scenario_id;
  DELETE FROM _gen_cap WHERE scenario_id = target_scenario_id;
  DELETE FROM _gen_cap_summary_fuel_la WHERE scenario_id = target_scenario_id;
  DELETE FROM _gen_cap_summary_tech WHERE scenario_id = target_scenario_id;
  DELETE FROM _gen_cap_summary_tech_la WHERE scenario_id = target_scenario_id;
  DELETE FROM _gen_hourly_summary_fuel WHERE scenario_id = target_scenario_id;
  DELETE FROM _gen_hourly_summary_fuel_la WHERE scenario_id = target_scenario_id;
  DELETE FROM _gen_hourly_summary_tech WHERE scenario_id = target_scenario_id;
  DELETE FROM _gen_hourly_summary_tech_la WHERE scenario_id = target_scenario_id;
  DELETE FROM _gen_summary_fuel_la WHERE scenario_id = target_scenario_id;
  DELETE FROM _gen_summary_tech WHERE scenario_id = target_scenario_id;
  DELETE FROM _gen_summary_tech_la WHERE scenario_id = target_scenario_id;
  DELETE FROM _local_td_cap WHERE scenario_id = target_scenario_id;
  DELETE FROM _system_load WHERE scenario_id = target_scenario_id;
  DELETE FROM _trans_cap WHERE scenario_id = target_scenario_id;
  DELETE FROM _trans_loss WHERE scenario_id = target_scenario_id;
  DELETE FROM _trans_summary WHERE scenario_id = target_scenario_id;
  DELETE FROM _transmission_avg_directed WHERE scenario_id = target_scenario_id;
  DELETE FROM _transmission_directed_hourly WHERE scenario_id = target_scenario_id;
  DELETE FROM _transmission_dispatch WHERE scenario_id = target_scenario_id;
  DELETE FROM co2_cc WHERE scenario_id = target_scenario_id;
  DELETE FROM gen_cap_summary_fuel WHERE scenario_id = target_scenario_id;
  DELETE FROM gen_summary_fuel WHERE scenario_id = target_scenario_id;
  DELETE FROM power_cost WHERE scenario_id = target_scenario_id;
  DELETE FROM system_load_summary WHERE scenario_id = target_scenario_id;
  DELETE FROM run_times WHERE scenario_id = target_scenario_id;
  
  RETURN 1;
END
$$
