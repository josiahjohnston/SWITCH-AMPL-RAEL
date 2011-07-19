CREATE DATABASE IF NOT EXISTS switch_results_wecc_v2_2;
USE switch_results_wecc_v2_2;


-- create views that get data from the inputs database
CREATE OR REPLACE VIEW technologies as 
	select technology_id, technology, fuel, storage, can_build_new from switch_inputs_wecc_v2_2.generator_info;
CREATE OR REPLACE VIEW load_areas as 
	select area_id, load_area from switch_inputs_wecc_v2_2.load_area_info;
CREATE OR REPLACE VIEW load_areas as 
	select area_id, load_area from switch_inputs_wecc_v2_2.load_area_info;
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
  co2_tons_reduced_1990 double,
  co2_share_reduced_1990 double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  PRIMARY KEY (scenario_id, carbon_cost, period)
);


CREATE TABLE IF NOT EXISTS _generator_and_storage_dispatch (
  scenario_id int NOT NULL,
  carbon_cost smallint,
  period year NOT NULL,
  project_id int NOT NULL,
  area_id smallint NOT NULL, 
  study_date int NOT NULL,
  study_hour int NOT NULL,
  technology_id tinyint unsigned NOT NULL, 
  new boolean NOT NULL,
  baseload boolean NOT NULL,
  cogen boolean NOT NULL,
  storage boolean NOT NULL,
  fuel VARCHAR(64) NOT NULL,
  fuel_category VARCHAR(64) NOT NULL,
  hours_in_sample double,
  power double,
  co2_tons double,
  heat_rate double, 
  fuel_cost double,
  carbon_cost_incurred double,
  variable_o_m_cost double,
  spinning_reserve double,
  quickstart_capacity double,
  total_operating_reserve double,
  spinning_co2_tons double,
  spinning_fuel_cost double,
  spinning_carbon_cost_incurred double,
  INDEX scenario_id (scenario_id),
  INDEX period (period),
  INDEX carbon_cost (carbon_cost),
  INDEX study_hour (study_hour),
  PRIMARY KEY (scenario_id, carbon_cost, area_id, study_hour, project_id, fuel, fuel_category), 
  INDEX technology_id (technology_id),
  FOREIGN KEY (technology_id) REFERENCES technologies(technology_id), 
  INDEX area_id (area_id),
  FOREIGN KEY (area_id) REFERENCES load_areas(area_id), 
  INDEX proj (project_id)
) ROW_FORMAT=FIXED;

CREATE OR REPLACE VIEW generator_and_storage_dispatch as
  SELECT 	scenario_id, carbon_cost, period, load_area, study_date, study_hour, technology, new, baseload, cogen, technologies.storage,
  			_generator_and_storage_dispatch.fuel, fuel_category, hours_in_sample, power, co2_tons, heat_rate, fuel_cost, carbon_cost_incurred, variable_o_m_cost, spinning_reserve, quickstart_capacity, total_operating_reserve, spinning_co2_tons, spinning_fuel_cost, spinning_carbon_cost_incurred
    FROM _generator_and_storage_dispatch join load_areas using(area_id) join technologies using(technology_id);

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
  INDEX site (project_id)
  PRIMARY KEY (scenario_id, carbon_cost, period, area_id, technology_id, project_id)
)  ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_cap as
  SELECT scenario_id, carbon_cost, period, load_area, area_id, technology, technology_id, project_id, new, baseload, cogen, _gen_cap.fuel, capacity, capital_cost, fixed_o_m_cost
    FROM _gen_cap join load_areas using(area_id) join technologies using(technology_id);


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
  hours_in_sample double,
  month int,
  hour_of_day_UTC tinyint unsigned,
  technology_id tinyint unsigned NOT NULL,
  fuel VARCHAR(64) NOT NULL,
  variable_o_m_cost double NOT NULL default 0,
  fuel_cost double NOT NULL default 0,
  carbon_cost_incurred double NOT NULL default 0,
  co2_tons double NOT NULL default 0,
  power double NOT NULL default 0,
  spinning_fuel_cost double NOT NULL default 0,
  spinning_carbon_cost_incurred double NOT NULL default 0,
  spinning_co2_tons double NOT NULL default 0,
  spinning_reserve double NOT NULL default 0,
  quickstart_capacity double NOT NULL default 0,
  total_operating_reserve double NOT NULL default 0,
  total_co2_tons double NOT NULL default 0,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX technology_id (technology_id),
  INDEX area_id (area_id),
  INDEX fuel_cat_join (scenario_id, period, fuel, technology_id),
  FOREIGN KEY (area_id) REFERENCES load_areas(area_id), 
  FOREIGN KEY (technology_id) REFERENCES technologies(technology_id),
  PRIMARY KEY (scenario_id, carbon_cost, study_hour, area_id, technology_id, fuel)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_hourly_summary_tech_la as
  SELECT 	scenario_id, carbon_cost, period, load_area, study_date, study_hour, hours_in_sample, month, month_name,
  			hour_of_day_UTC, mod(hour_of_day_UTC - 8, 24) as hour_of_day_PST,
  			technology, _gen_hourly_summary_tech_la.fuel, variable_o_m_cost, fuel_cost, carbon_cost_incurred,
  			co2_tons, power, spinning_fuel_cost, spinning_carbon_cost_incurred, spinning_co2_tons, spinning_reserve, quickstart_capacity, total_operating_reserve, total_co2_tons
    FROM _gen_hourly_summary_tech_la join load_areas using(area_id) join months on(month=month_id) join technologies using (technology_id);

CREATE TABLE IF NOT EXISTS _gen_hourly_summary_tech (
  scenario_id int,
  carbon_cost smallint,
  period year,
  study_date int,
  study_hour int,
  hours_in_sample double,
  month int,
  hour_of_day_UTC tinyint unsigned,
  technology_id tinyint unsigned NOT NULL,
  power double,
  co2_tons double,
  spinning_reserve double,
  spinning_co2_tons double,
  quickstart_capacity double,
  total_operating_reserve double,
  total_co2_tons double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX technology_id (technology_id),
  FOREIGN KEY (technology_id) REFERENCES technologies(technology_id),
  PRIMARY KEY (scenario_id, carbon_cost, study_hour, technology_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_hourly_summary_tech as
  SELECT 	scenario_id, carbon_cost, period, study_date, study_hour, hours_in_sample, month, month_name,
  			hour_of_day_UTC, mod(hour_of_day_UTC - 8, 24) as hour_of_day_PST,
  			technology, fuel, power, co2_tons, spinning_reserve, spinning_co2_tons, quickstart_capacity, total_operating_reserve, total_co2_tons
    FROM _gen_hourly_summary_tech join months on(month = month_id) join technologies using (technology_id);

CREATE TABLE IF NOT EXISTS _gen_summary_tech_la (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint NOT NULL, 
  technology_id tinyint unsigned NOT NULL,
  avg_power double,
  avg_co2_tons double,
  avg_spinning_reserve double,
  avg_spinning_co2_tons double,
  avg_quickstart_capacity double,
  avg_total_operating_reserve double,
  avg_total_co2_tons double,
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
  SELECT 	scenario_id, carbon_cost, period, load_area, technology,
  			avg_power, avg_co2_tons, avg_spinning_reserve, avg_spinning_co2_tons, avg_quickstart_capacity, avg_total_operating_reserve, avg_total_co2_tons
    FROM _gen_summary_tech_la join load_areas using(area_id) join technologies using (technology_id);

CREATE TABLE IF NOT EXISTS _gen_summary_tech (
  scenario_id int,
  carbon_cost smallint,
  period year,
  technology_id tinyint unsigned NOT NULL,
  avg_power double,
  avg_co2_tons double,
  avg_spinning_reserve double,
  avg_spinning_co2_tons double,
  avg_quickstart_capacity double,
  avg_total_operating_reserve double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX technology_id (technology_id),
  PRIMARY KEY (scenario_id, carbon_cost, period, technology_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_summary_tech as
  SELECT 	scenario_id, carbon_cost, period, technology,
  			avg_power, avg_co2_tons, avg_spinning_reserve, avg_spinning_co2_tons, avg_quickstart_capacity, avg_total_operating_reserve, avg_total_co2_tons
    FROM _gen_summary_tech join technologies using (technology_id);


-- generation summaries by FUEL -------------------
CREATE TABLE IF NOT EXISTS _gen_hourly_summary_fuel_la (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint NOT NULL, 
  study_date int,
  study_hour int,
  hours_in_sample double,
  month int,
  hour_of_day_UTC tinyint unsigned,
  fuel VARCHAR(64) NOT NULL,
  power double NOT NULL default 0,
  co2_tons double NOT NULL default 0,
  spinning_reserve double NOT NULL default 0,
  spinning_co2_tons double NOT NULL default 0,
  quickstart_capacity double NOT NULL default 0,
  total_operating_reserve double NOT NULL default 0,
  total_co2_tons double,
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
  SELECT 	scenario_id, carbon_cost, period, load_area, study_date, study_hour, hours_in_sample, month, month_name,
  			hour_of_day_UTC, mod(hour_of_day_UTC - 8, 24) as hour_of_day_PST,
  			fuel, power, co2_tons, spinning_reserve, spinning_co2_tons, quickstart_capacity, total_operating_reserve, total_co2_tons
    FROM _gen_hourly_summary_fuel_la join load_areas using(area_id) join months on(month=month_id);

CREATE TABLE IF NOT EXISTS _gen_hourly_summary_fuel (
  scenario_id int,
  carbon_cost smallint,
  period year,
  study_date int,
  study_hour int,
  hours_in_sample double,
  month int,
  hour_of_day_UTC tinyint unsigned,
  fuel VARCHAR(64) NOT NULL,
  power double,
  co2_tons double,
  spinning_reserve double,
  spinning_co2_tons double,
  quickstart_capacity double,
  total_operating_reserve double,
  total_co2_tons double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX technology_id (fuel),
  FOREIGN KEY (fuel) REFERENCES technologies(fuel),
  PRIMARY KEY (scenario_id, carbon_cost, study_hour, fuel)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_hourly_summary_fuel as
  SELECT 	scenario_id, carbon_cost, period, study_date, study_hour, hours_in_sample, month, month_name,
  			hour_of_day_UTC, mod(hour_of_day_UTC - 8, 24) as hour_of_day_PST,
  			fuel, power, co2_tons, spinning_reserve, spinning_co2_tons, quickstart_capacity, total_operating_reserve, total_co2_tons
    FROM _gen_hourly_summary_fuel join months on(month = month_id);

CREATE TABLE IF NOT EXISTS _gen_summary_fuel_la (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint NOT NULL, 
  fuel VARCHAR(64) NOT NULL,
  avg_power double,
  avg_co2_tons double,
  avg_spinning_reserve double,
  avg_spinning_co2_tons double,
  avg_quickstart_capacity double,
  avg_total_operating_reserve double,
  avg_total_co2_tons double,
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
  SELECT 	scenario_id, carbon_cost, period, load_area, fuel, avg_power, avg_co2_tons,
  			avg_spinning_reserve, avg_spinning_co2_tons, avg_quickstart_capacity, avg_total_operating_reserve, avg_total_co2_tons
    FROM _gen_summary_fuel_la join load_areas using(area_id);

CREATE TABLE IF NOT EXISTS gen_summary_fuel (
  scenario_id int,
  carbon_cost smallint,
  period year,
  fuel VARCHAR(64) NOT NULL,
  avg_power double,
  avg_co2_tons double,
  avg_spinning_reserve double,
  avg_spinning_co2_tons double,
  avg_quickstart_capacity double,
  avg_total_operating_reserve double,
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


CREATE TABLE IF NOT EXISTS load_wind_solar_operating_reserve_levels (
	scenario_id int,
	carbon_cost smallint,
	period year,
	balancing_area VARCHAR(64),
	study_date int,
	study_hour int,
	hours_in_sample double,
	load_level double,
	wind_generation double,
	noncsp_solar_generation double,
	csp_generation double,
	spinning_reserve_requirement double, 
	quickstart_capacity_requirement double,
	total_spinning_reserve_provided double,
	total_quickstart_capacity_provided double,
	spinning_thermal_reserve_provided double, 
	spinning_nonthermal_reserve_provided double,
	quickstart_thermal_capacity_provided double,
	quickstart_nonthermal_capacity_provided double,
	INDEX scenario_id (scenario_id),
	INDEX carbon_cost (carbon_cost),
	INDEX period (period),
	PRIMARY KEY (scenario_id, carbon_cost, period, balancing_area)
);

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
  new_geothermal_cost double default 0 NOT NULL, 
  new_bio_cost double default 0 NOT NULL, 
  new_wind_cost double default 0 NOT NULL, 
  new_solar_cost double default 0 NOT NULL, 
  new_storage_nonfuel_cost double default 0 NOT NULL,
  carbon_cost_total double default 0 NOT NULL, 
  total_cost double default 0 NOT NULL,
  cost_per_mwh double default 0 NOT NULL,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  PRIMARY KEY (scenario_id, carbon_cost, period)
);

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


CREATE TABLE IF NOT EXISTS _existing_trans_cost_and_rps_reduced_cost (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint NOT NULL,
  existing_trans_cost double,
  rps_reduced_cost double,
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
  hour_of_day_UTC tinyint unsigned,
  hours_in_sample double,
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
  SELECT 	scenario_id, carbon_cost, period, transmission_line_id, start.load_area as load_area_receive, end.load_area as load_area_from, 
  			study_date, study_hour, month, hour_of_day_UTC, mod(hour_of_day_UTC - 8, 24) as hour_of_day_PST,
  			hours_in_sample, rps_fuel_category, power_sent, power_received  
    FROM _transmission_dispatch join load_areas start on(receive_id=start.area_id) join load_areas end on(send_id=end.area_id);

CREATE TABLE IF NOT EXISTS _trans_summary (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint,
  study_date int,
  study_hour int,
  month int,
  hour_of_day_UTC tinyint unsigned,
  hours_in_sample double,
  net_power double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX area_id (area_id),
  PRIMARY KEY (scenario_id, carbon_cost, period, study_hour, area_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW trans_summary as
  SELECT 	scenario_id, carbon_cost, period, load_area, study_date, study_hour, month,
  			hour_of_day_UTC, mod(hour_of_day_UTC - 8, 24) as hour_of_day_PST, hours_in_sample, net_power 
    FROM _trans_summary join load_areas using(area_id);

CREATE TABLE IF NOT EXISTS _trans_loss (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint comment "Losses are assigned to areas that transmit power, rather than areas that receive.",
  study_date int,
  study_hour int,
  month int,
  hour_of_day_UTC tinyint unsigned,
  hours_in_sample double,
  power double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX area_id (area_id),
  PRIMARY KEY (scenario_id, carbon_cost, period, study_hour, area_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW trans_loss as
  SELECT 	scenario_id, carbon_cost, period, load_area, study_date, study_hour, month,
  			hour_of_day_UTC, mod(hour_of_day_UTC - 8, 24) as hour_of_day_PST, hours_in_sample, power
    FROM _trans_loss join load_areas using(area_id);


CREATE TABLE IF NOT EXISTS _transmission_directed_hourly (
  scenario_id int,
  carbon_cost smallint,
  period year,
  transmission_line_id int,
  send_id smallint,
  receive_id smallint,
  study_hour int,
  hour_of_day_UTC tinyint unsigned,
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
  SELECT	scenario_id, carbon_cost, period, transmission_line_id, load_area_start as load_area_from, load_area_end as load_area_receive, start_id as send_id, end_id as receive_id,
  			study_hour,	hour_of_day_UTC, mod(hour_of_day_UTC - 8, 24) as hour_of_day_PST, directed_trans_avg
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
  hour_of_day_UTC tinyint unsigned,
  hours_in_sample double,
  power double,
  satisfy_load_reduced_cost double,
  satisfy_load_reserve_reduced_cost double,
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX area_id (area_id),
  PRIMARY KEY (scenario_id, carbon_cost, period, study_hour, area_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW system_load as
  SELECT 	scenario_id, carbon_cost, period, load_area, study_date, study_hour, month,
  			hour_of_day_UTC, mod(hour_of_day_UTC - 8, 24) as hour_of_day_PST,
  			hours_in_sample, power, satisfy_load_reduced_cost, satisfy_load_reserve_reduced_cost
    FROM _system_load join load_areas using(area_id);

CREATE TABLE IF NOT EXISTS system_load_summary_hourly (
  scenario_id int,
  carbon_cost smallint,
  period year,
  study_date int,
  study_hour int,
  month int,
  hour_of_day_UTC tinyint unsigned,
  hour_of_day_PST tinyint unsigned,
  hours_in_sample double,
  system_load double,
  satisfy_load_reduced_cost double,
  satisfy_load_reserve_reduced_cost double,
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  PRIMARY KEY (scenario_id, carbon_cost, period, study_hour)
) ROW_FORMAT=FIXED;
    
CREATE TABLE IF NOT EXISTS system_load_summary (
  scenario_id int,
  carbon_cost smallint,
  period year,
  system_load double,
  satisfy_load_reduced_cost_weighted double,
  satisfy_load_reserve_reduced_cost_weighted double,
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

CREATE TABLE IF NOT EXISTS sum_hourly_weights_per_period_table (
	scenario_id int,
	period year,
	sum_hourly_weights_per_period double,
	years_per_period double,
	PRIMARY KEY (scenario_id, period)
);



-- create a procedure that clears all results for the scenario target_scenario_id
-- by finding all columns in the results database with a scenario_id column
-- and deleteing all entries for the target_scenario_id
	DROP PROCEDURE IF EXISTS clear_scenario_results;
	
	delimiter $$
	create procedure clear_scenario_results
		(IN target_scenario_id int) 
	BEGIN
	
	-- query the inner workings of mysql for a list of tables to clear
	drop table if exists tables_to_clear;
	create temporary table tables_to_clear as 
		select table_name
		from information_schema.tables join
			(select table_name
				from information_schema.columns
				where table_schema = 'switch_results_wecc_v2_2'
				and column_name = 'scenario_id') as columns_query
			using (table_name)
		where table_schema ='switch_results_wecc_v2_2'
		and table_type like 'Base Table'
		;
	
	table_clearing_loop: LOOP
	
	set @current_table_name = (select table_name from tables_to_clear limit 1);
	
	select @current_table_name as progress;
	
	set @clear_statment =
		concat( 'delete from ',
				@current_table_name,
				' where scenario_id = ',
				target_scenario_id,
				';'
				);
	
	PREPARE stmt_name FROM @clear_statment;
	EXECUTE stmt_name;
	DEALLOCATE PREPARE stmt_name;
	
	delete from tables_to_clear where table_name = @current_table_name;
	
	IF ( ( select count(*) from tables_to_clear ) = 0)
	    THEN LEAVE table_clearing_loop;
	        END IF;
	END LOOP table_clearing_loop;

	select 'Finished Clearing Results' as progress;
	
	END;
	$$
	delimiter ;

