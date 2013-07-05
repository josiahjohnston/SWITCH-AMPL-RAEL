CREATE DATABASE IF NOT EXISTS switch_results_wecc_v2_2;
USE switch_results_wecc_v2_2;


-- create views that get data from the inputs database
CREATE OR REPLACE VIEW technologies as 
	select technology_id, technology, fuel, storage, can_build_new from switch_inputs_wecc_v2_2.generator_info_v2;
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
  deep_cycling_amount double,
  deep_cycling_fuel_cost double,
  deep_cycling_carbon_cost double,
  deep_cycling_co2_tons double,
  mw_started_up double,
  startup_fuel_cost double,
  startup_nonfuel_cost double,
  startup_carbon_cost double,
  startup_co2_tons double,
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
  			_generator_and_storage_dispatch.fuel, fuel_category, hours_in_sample, power, co2_tons, heat_rate, fuel_cost, carbon_cost_incurred, variable_o_m_cost, spinning_reserve, quickstart_capacity, total_operating_reserve, spinning_co2_tons, spinning_fuel_cost, spinning_carbon_cost_incurred, deep_cycling_amount, deep_cycling_fuel_cost, deep_cycling_carbon_cost, deep_cycling_co2_tons, mw_started_up, startup_fuel_cost, startup_nonfuel_cost, startup_co2_tons, startup_carbon_cost
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
  INDEX site (project_id),
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
  deep_cycling_amount double NOT NULL default 0,
  deep_cycling_fuel_cost double NOT NULL default 0,
  deep_cycling_carbon_cost double NOT NULL default 0,
  deep_cycling_co2_tons double NOT NULL default 0,
  mw_started_up double NOT NULL default 0,
  startup_fuel_cost double NOT NULL default 0,
  startup_nonfuel_cost double NOT NULL default 0,
  startup_carbon_cost double NOT NULL default 0,
  startup_co2_tons double NOT NULL default 0,
  total_co2_tons double NOT NULL default 0,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX technology_id (technology_id),
  INDEX area_id (area_id),
  FOREIGN KEY (area_id) REFERENCES load_areas(area_id), 
  FOREIGN KEY (technology_id) REFERENCES technologies(technology_id),
  PRIMARY KEY (scenario_id, carbon_cost, study_hour, area_id, technology_id, fuel)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_hourly_summary_tech_la as
  SELECT 	scenario_id, carbon_cost, period, load_area, study_date, study_hour, hours_in_sample, month, month_name,
  			hour_of_day_UTC, mod(hour_of_day_UTC - 8, 24) as hour_of_day_PST,
  			technology, _gen_hourly_summary_tech_la.fuel, variable_o_m_cost, fuel_cost, carbon_cost_incurred,
  			co2_tons, power, spinning_fuel_cost, spinning_carbon_cost_incurred, spinning_co2_tons, spinning_reserve, quickstart_capacity, total_operating_reserve, deep_cycling_amount, deep_cycling_fuel_cost, deep_cycling_carbon_cost, deep_cycling_co2_tons, mw_started_up, startup_fuel_cost, startup_nonfuel_cost, startup_carbon_cost, startup_co2_tons, total_co2_tons
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
  deep_cycling_amount double,
  deep_cycling_co2_tons double,
  mw_started_up double,
  startup_co2_tons double,
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
  			technology, fuel, power, co2_tons, spinning_reserve, spinning_co2_tons, quickstart_capacity, total_operating_reserve, deep_cycling_amount, deep_cycling_co2_tons, mw_started_up, startup_co2_tons, total_co2_tons
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
  avg_deep_cycling_amount double,
  avg_deep_cycling_co2_tons double,
  avg_mw_started_up double,
  avg_startup_co2_tons double,
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
  			avg_power, avg_co2_tons, avg_spinning_reserve, avg_spinning_co2_tons, avg_quickstart_capacity, avg_total_operating_reserve, avg_deep_cycling_amount, avg_deep_cycling_co2_tons, avg_mw_started_up, avg_startup_co2_tons, avg_total_co2_tons
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
  avg_deep_cycling_amount double,
  avg_deep_cycling_co2_tons double,
  avg_mw_started_up double,
  avg_startup_co2_tons double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX technology_id (technology_id),
  PRIMARY KEY (scenario_id, carbon_cost, period, technology_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW gen_summary_tech as
  SELECT 	scenario_id, carbon_cost, period, technology,
  			avg_power, avg_co2_tons, avg_spinning_reserve, avg_spinning_co2_tons, avg_quickstart_capacity, avg_total_operating_reserve, avg_deep_cycling_amount, avg_deep_cycling_co2_tons, avg_mw_started_up, avg_startup_co2_tons, avg_total_co2_tons
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
  deep_cycling_amount double NOT NULL default 0,
  deep_cycling_co2_tons double NOT NULL default 0,
  mw_started_up double NOT NULL default 0,
  startup_co2_tons double NOT NULL default 0,
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
  			fuel, power, co2_tons, spinning_reserve, spinning_co2_tons, quickstart_capacity, total_operating_reserve, deep_cycling_amount, deep_cycling_co2_tons, mw_started_up, startup_co2_tons, total_co2_tons
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
  deep_cycling_amount double,
  deep_cycling_co2_tons double,
  mw_started_up double,
  startup_co2_tons double,
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
  			fuel, power, co2_tons, spinning_reserve, spinning_co2_tons, quickstart_capacity, total_operating_reserve, deep_cycling_amount, deep_cycling_co2_tons, mw_started_up, startup_co2_tons, total_co2_tons
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
  avg_deep_cycling_amount,
  avg_deep_cycling_co2_tons double,
  avg_mw_started_up double,
  avg_startup_co2_tons double,
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
  			avg_spinning_reserve, avg_spinning_co2_tons, avg_quickstart_capacity, avg_total_operating_reserve, avg_deep_cycling_amount, avg_deep_cycling_co2_tons, avg_mw_started_up, avg_startup_co2_tons, avg_total_co2_tons
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
  avg_deep_cycling_amount double,
  avg_deep_cycling_co2_tons double,
  avg_mw_started_up double,
  avg_startup_co2_tons double,
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


CREATE TABLE IF NOT EXISTS _load_wind_solar_operating_reserve_levels (
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
	PRIMARY KEY (scenario_id, carbon_cost, period, balancing_area, study_hour)
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

CREATE TABLE _rps_reduced_cost (
  scenario_id int,
  carbon_cost smallint,
  period year,
  rps_compliance_entity varchar(20),
  rps_compilance_type varchar(20),
  rps_reduced_cost double DEFAULT NULL,
  PRIMARY KEY (scenario_id,carbon_cost,period,rps_compliance_entity),
  KEY scenario_id (scenario_id),
  KEY carbon_cost (carbon_cost),
  KEY period (period),
  KEY rps_compliance_entity (rps_compliance_entity)
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


CREATE OR REPLACE VIEW trans_cap_summary AS
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
  existing_trans_cost double DEFAULT NULL,
  PRIMARY KEY (scenario_id, carbon_cost, period, area_id),
  KEY scenario_id (scenario_id),
  KEY carbon_cost (carbon_cost),
  KEY period (period),
  KEY area_id (area_id)
);

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
		

CREATE TABLE IF NOT EXISTS _consume_and_redirect_variables (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint,
  study_date int,
  study_hour int,
  hours_in_sample double,
  rps_fuel_category varchar(20),
  consume_nondistributed_power double,
  consume_distributed_power double,
  redirect_distributed_power double,
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX area_id (area_id),
  INDEX rps_fuel_category (rps_fuel_category),
  PRIMARY KEY (scenario_id, carbon_cost, period, study_hour, area_id, rps_fuel_category)
) ROW_FORMAT=FIXED;

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
  res_comm_dr double default 0,
  ev_dr double default 0,
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX area_id (area_id),
  PRIMARY KEY (scenario_id, carbon_cost, period, study_hour, area_id)
) ROW_FORMAT=FIXED;
CREATE OR REPLACE VIEW system_load as
  SELECT 	scenario_id, carbon_cost, period, load_area, study_date, study_hour, month,
  			hour_of_day_UTC, mod(hour_of_day_UTC - 8, 24) as hour_of_day_PST,
  			hours_in_sample, power, satisfy_load_reduced_cost, satisfy_load_reserve_reduced_cost, res_comm_dr, ev_dr
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
  res_comm_dr double default 0,
  ev_dr double default 0,
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
  res_comm_dr double default 0,
  ev_dr double default 0,
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



CREATE TABLE IF NOT EXISTS carbon_intensity_of_electricity (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint NOT NULL, 
  total_annual_emissions double,
  carbon_intensity double,
  PRIMARY KEY (scenario_id, carbon_cost, period, area_id),
  FOREIGN KEY (area_id) REFERENCES load_areas(area_id)
);

CREATE TABLE IF NOT EXISTS fuel_categories (
  fuel_category_id tinyint unsigned NOT NULL PRIMARY KEY AUTO_INCREMENT,
  fuel_category VARCHAR(64) NOT NULL,
  UNIQUE (fuel_category)
) ROW_FORMAT=FIXED;

CREATE TABLE IF NOT EXISTS fuel_category_definitions (
  fuel_category_id tinyint unsigned NOT NULL,
  scenario_id int NOT NULL,
  period year NOT NULL,
  technology_id tinyint unsigned NOT NULL, 
  fuel VARCHAR(64) NOT NULL,
  PRIMARY KEY (fuel_category_id, scenario_id, period, technology_id, fuel),
  FOREIGN KEY (fuel_category_id) REFERENCES fuel_categories(fuel_category_id),
  FOREIGN KEY (technology_id) REFERENCES technologies(technology_id)
) ROW_FORMAT=FIXED;


CREATE TABLE IF NOT EXISTS _gen_hourly_summary_fc_la (
  scenario_id int,
  carbon_cost smallint,
  period year,
  area_id smallint NOT NULL, 
  study_date int,
  study_hour int,
  hours_in_sample double,
  fuel_category_id tinyint unsigned NOT NULL,
  storage boolean NOT NULL,
  power double NOT NULL default 0,
  total_co2_tons double NOT NULL default 0,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX study_hour (study_hour),
  INDEX study_date (study_date),
  INDEX area_id (area_id),
  INDEX (scenario_id, carbon_cost, study_hour, area_id, fuel_category_id, storage, power),
  FOREIGN KEY (area_id) REFERENCES load_areas(area_id), 
  FOREIGN KEY (fuel_category_id) REFERENCES fuel_categories(fuel_category_id),
  PRIMARY KEY (scenario_id, carbon_cost, study_hour, area_id, fuel_category_id, storage)
) ROW_FORMAT=FIXED;

CREATE TABLE IF NOT EXISTS hourly_la_emission_stocks (
  fuel_category_id tinyint unsigned NOT NULL,
  scenario_id int NOT NULL,
  carbon_cost smallint,
  area_id smallint NOT NULL, 
  study_hour int,
  study_date int,
  iteration smallint NOT NULL, 
  gross_emissions double NOT NULL DEFAULT 0,
  net_emissions double NOT NULL DEFAULT 0,
  generated_emissions double NOT NULL DEFAULT 0,
  gross_power double DEFAULT 0,
  net_power double NOT NULL default 0,
  INDEX (scenario_id, carbon_cost, study_date, area_id, fuel_category_id, iteration),
  FOREIGN KEY (area_id) REFERENCES load_areas(area_id), 
  FOREIGN KEY (fuel_category_id) REFERENCES fuel_categories(fuel_category_id),
  PRIMARY KEY (scenario_id, carbon_cost, study_hour, area_id, fuel_category_id, iteration)
);

CREATE TABLE IF NOT EXISTS carbon_intensity_timing (
  scenario_id int NOT NULL,
  num_carbon_costs smallint,
  iteration smallint NOT NULL, 
  storage_time TIME,
  la_time TIME,
  PRIMARY KEY (scenario_id, iteration)
);

CREATE TABLE IF NOT EXISTS daily_storage_emission_stocks (
  fuel_category_id tinyint unsigned NOT NULL,
  scenario_id INT NOT NULL,
  carbon_cost smallint,
  area_id smallint NOT NULL, 
  study_date int,
  iteration smallint NOT NULL, 
  emissions double default 0,
  total_power_released double default 0,
  total_power_stored double default 0,
  FOREIGN KEY (area_id) REFERENCES load_areas(area_id), 
  FOREIGN KEY (fuel_category_id) REFERENCES fuel_categories(fuel_category_id),
  PRIMARY KEY (scenario_id, carbon_cost, study_date, area_id, fuel_category_id, iteration)
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
				and column_name = 'scenario_id' 
				AND (table_name='_generator_and_storage_dispatch' or table_name='_transmission_dispatch' OR table_name not like '%dispatch%')
      ) as columns_query
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


-- A procedure to calculate the carbon intensity of electricity for each load area.
DROP PROCEDURE IF EXISTS calc_carbon_intensity;
DELIMITER $$
CREATE PROCEDURE calc_carbon_intensity(IN target_scenario_id INT)
BEGIN
  DECLARE round INT;
  DECLARE max_round INT;
  DECLARE num_carbon_costs INT;
  DECLARE storage_time TIME;
  DECLARE la_time TIME;
  DECLARE start_time DATETIME;  
  DECLARE convergence_threshold float;

  SET convergence_threshold = 0.01;  
  SET num_carbon_costs = (SELECT COUNT( DISTINCT carbon_cost ) FROM gen_cap_summary_fuel WHERE scenario_id=target_scenario_id);

  -- Clear out any old results
  DELETE FROM hourly_la_emission_stocks WHERE scenario_id = target_scenario_id;
  DELETE FROM daily_storage_emission_stocks WHERE scenario_id = target_scenario_id;
  DELETE FROM carbon_intensity_timing WHERE scenario_id = target_scenario_id;

  -- Calculate total emissions for each study date / fc
  DROP TABLE IF EXISTS daily_wecc_emissions;
  CREATE TABLE daily_wecc_emissions
    SELECT scenario_id, carbon_cost, study_date, SUM(total_co2_tons) AS total_daily_emissions
      FROM _gen_hourly_summary_fc_la
      WHERE scenario_id = target_scenario_id
      GROUP BY scenario_id, carbon_cost, study_date;
  ALTER TABLE daily_wecc_emissions ADD PRIMARY KEY (scenario_id, carbon_cost, study_date);
  
  -- ROUND 0: Emissions assigned to load areas they originate in
  SET round = 0;
  SET max_round = 100;
  SET start_time = NOW();

  -- Calculate gross power available for each fuel category in each load area and hour.
  
  -- Start the running total with locally-produced power.
  INSERT INTO hourly_la_emission_stocks ( fuel_category_id, scenario_id, carbon_cost, area_id, study_hour, study_date, iteration, gross_power, generated_emissions )
    SELECT fuel_category_id, scenario_id, carbon_cost, area_id, study_hour, study_date, round as iteration, SUM(power), SUM(total_co2_tons)
      FROM _gen_hourly_summary_fc_la
      WHERE scenario_id = target_scenario_id AND power > 0
      GROUP BY fuel_category_id, scenario_id, carbon_cost, area_id, study_hour;
  
  -- Tally power received from transmission
  DROP TABLE IF EXISTS trans_received;
  CREATE TABLE trans_received
    SELECT fuel_category_id, scenario_id, carbon_cost, receive_id as area_id, study_hour, study_date, SUM(power_received) AS trans_power_received
      FROM _transmission_dispatch 
        JOIN fuel_categories ON(fuel_category = rps_fuel_category)
      WHERE scenario_id = target_scenario_id
      GROUP BY fuel_category_id, scenario_id, carbon_cost, area_id, study_hour;
  ALTER TABLE trans_received ADD PRIMARY KEY (fuel_category_id, scenario_id, carbon_cost, area_id, study_hour);
  
  -- Update the running total with power received from transmission. Add rows that aren't in the table yet, and update rows that already exist
  INSERT INTO hourly_la_emission_stocks ( fuel_category_id, scenario_id, carbon_cost, area_id, study_hour, study_date, iteration, gross_power )
    SELECT fuel_category_id, scenario_id, carbon_cost, area_id, study_hour, study_date, round as iteration, 
      trans_power_received
      FROM trans_received
      WHERE scenario_id = target_scenario_id
    ON DUPLICATE KEY UPDATE 
      gross_power = gross_power + trans_power_received;
  
  -- Tally power sent out on transmission lines
  DROP TABLE IF EXISTS trans_sent;
  CREATE TABLE trans_sent
    SELECT fuel_category_id, scenario_id, carbon_cost, send_id as area_id, study_hour, SUM(power_sent) AS trans_power_sent
      FROM _transmission_dispatch 
        JOIN fuel_categories ON(fuel_category = rps_fuel_category)
      WHERE scenario_id = target_scenario_id
      GROUP BY fuel_category_id, scenario_id, carbon_cost, area_id, study_hour;
  ALTER TABLE trans_sent ADD PRIMARY KEY (fuel_category_id, scenario_id, carbon_cost, area_id, study_hour);
  
  -- Tally the power sent to storage
  DROP TABLE IF EXISTS power_stored;
  CREATE TABLE power_stored
    SELECT fuel_category_id, scenario_id, carbon_cost, area_id, study_hour, SUM(power) AS power_stored
      FROM _gen_hourly_summary_fc_la
      WHERE scenario_id = target_scenario_id AND power < 0
      GROUP BY fuel_category_id, scenario_id, carbon_cost, area_id, study_hour;
  ALTER TABLE power_stored ADD PRIMARY KEY (fuel_category_id, scenario_id, carbon_cost, area_id, study_hour);
  
  -- Calculate net power from gross power, storage, and transmission out. Also set gross & net emissions to an initial value of locally-generated emissions.
  UPDATE hourly_la_emission_stocks 
      LEFT JOIN trans_sent USING(fuel_category_id, scenario_id, carbon_cost, area_id, study_hour)
      LEFT JOIN power_stored USING(fuel_category_id, scenario_id, carbon_cost, area_id, study_hour)
    SET net_power = gross_power + COALESCE(power_stored, 0) - COALESCE(trans_power_sent, 0), -- This use of the COALESCE function will replace the variable with 0 when it is NULL
      gross_emissions = generated_emissions, net_emissions = generated_emissions
    WHERE scenario_id = target_scenario_id
      AND iteration=round;

  -- Delete any entries with 0 gross power that snuck in.
  DELETE FROM hourly_la_emission_stocks
    WHERE gross_power = 0 and scenario_id = target_scenario_id;
  SET la_time = TIMEDIFF(NOW(), start_time); -- Record timing info

  -- Update storage emissions. Storage gets the emissions from its load area/fuel category over the whole day
  SET start_time = NOW();
  -- Calculate the total power released from storage over a day for each load area and study date
  DROP TABLE IF EXISTS daily_storage_power_released;
  CREATE TEMPORARY TABLE daily_storage_power_released 
    SELECT fuel_category_id, scenario_id, carbon_cost, area_id, study_date, SUM(power) AS total_power_released, 0 AS total_power_stored
    FROM _gen_hourly_summary_fc_la 
    WHERE scenario_id = target_scenario_id AND storage = 1 AND power > 0
    GROUP BY fuel_category_id, scenario_id, carbon_cost, area_id, study_date;
  ALTER TABLE daily_storage_power_released ADD PRIMARY KEY ( fuel_category_id, scenario_id, carbon_cost, area_id, study_date);
  INSERT INTO daily_storage_power_released (fuel_category_id, scenario_id, carbon_cost, area_id, study_date, total_power_released, total_power_stored)
    SELECT fuel_category_id, scenario_id, carbon_cost, area_id, study_date, NULL AS total_power_released, SUM(-1*power) AS total_power_stored
    FROM _gen_hourly_summary_fc_la 
    WHERE scenario_id = target_scenario_id AND storage = 1 AND power < 0
    GROUP BY fuel_category_id, scenario_id, carbon_cost, area_id, study_date
  ON DUPLICATE KEY UPDATE 
    total_power_stored = VALUES(total_power_stored);
  
  -- This sets the initial carbon emissions going into storage.
  -- The gross_emissions for the first iteration is a low estimate as we haven't calculated any total emissions for transmission yet, so the power for which we have emissions at the start is just the locally generated power
  INSERT INTO daily_storage_emission_stocks (fuel_category_id, scenario_id, carbon_cost, area_id, study_date, iteration, total_power_released, total_power_stored, emissions)
    SELECT fuel_category_id, scenario_id, carbon_cost, area_id, hourly_la_emission_stocks.study_date, iteration, total_power_released, total_power_stored, 
      SUM( gross_emissions * -1 * _gen_hourly_summary_fc_la.power / gross_power )
    FROM hourly_la_emission_stocks
      JOIN _gen_hourly_summary_fc_la    USING (fuel_category_id, scenario_id, carbon_cost, area_id, study_hour)
      JOIN daily_storage_power_released USING (fuel_category_id, scenario_id, carbon_cost, area_id)
    WHERE iteration = round 
      AND scenario_id = target_scenario_id
      AND storage = 1
      AND gross_power > 0
      AND _gen_hourly_summary_fc_la.power < 0
      AND daily_storage_power_released.study_date = hourly_la_emission_stocks.study_date
    GROUP BY fuel_category_id, scenario_id, carbon_cost, area_id, study_date, iteration, total_power_released, total_power_stored
  ;
  SET storage_time = TIMEDIFF(NOW(), start_time);
  INSERT INTO carbon_intensity_timing (scenario_id, num_carbon_costs, iteration, storage_time, la_time)
    VALUES (target_scenario_id, num_carbon_costs, round, storage_time, la_time);

  DROP TABLE IF EXISTS release_from_storage;
  CREATE TABLE release_from_storage
    SELECT fuel_category_id, scenario_id, carbon_cost, area_id, study_hour, power
    FROM _gen_hourly_summary_fc_la
    WHERE scenario_id = target_scenario_id
      AND storage = 1
      AND power > 0;
  ALTER TABLE release_from_storage ADD PRIMARY KEY (fuel_category_id, scenario_id, carbon_cost, area_id, study_hour);
  
  DROP TABLE IF EXISTS put_into_storage;
  CREATE TABLE put_into_storage
    SELECT fuel_category_id, scenario_id, carbon_cost, area_id, study_hour, power
    FROM _gen_hourly_summary_fc_la
    WHERE scenario_id = target_scenario_id
      AND storage = 1
      AND power < 0;
  ALTER TABLE put_into_storage ADD PRIMARY KEY (fuel_category_id, scenario_id, carbon_cost, area_id, study_hour);

  
  -- ROUNDS 1 through N
  -- ..repeat until we reach convergence or get tired of waiting. 
  WHILE round < max_round DO
    SET round = round + 1;
    
    
    -- ROUND X: Update a load area's emissions based on imports & exports to other load areas and storage. 
    SET start_time = NOW();
    
    -- Tally embedded emissions transfered into each load area
    DROP TABLE IF EXISTS emissions_received_via_tx;
    CREATE TABLE emissions_received_via_tx
      SELECT fuel_category_id, scenario_id, carbon_cost, receive_id as area_id, study_hour, 
        SUM( gross_emissions * power_sent / gross_power ) AS emissions_received
      FROM _transmission_dispatch 
        JOIN fuel_categories ON(fuel_category = rps_fuel_category)
        JOIN hourly_la_emission_stocks USING (fuel_category_id, scenario_id, carbon_cost, study_hour)
      WHERE scenario_id = target_scenario_id
        AND area_id = send_id
        AND iteration = round - 1
      GROUP BY fuel_category_id, scenario_id, carbon_cost, receive_id, study_hour;
    ALTER TABLE emissions_received_via_tx ADD PRIMARY KEY (fuel_category_id, scenario_id, carbon_cost, area_id, study_hour);

    INSERT INTO hourly_la_emission_stocks (fuel_category_id, scenario_id, carbon_cost, area_id, study_hour, study_date, iteration, gross_power, net_power, generated_emissions, gross_emissions, net_emissions)
      SELECT fuel_category_id, scenario_id, carbon_cost, area_id, study_hour, hourly_la_emission_stocks.study_date, round as iteration, gross_power, net_power, generated_emissions, 
        ( -- GROSS emissions
          -- Emissions from locally-generated power
          generated_emissions   
            -- Emissions for power released from storage
          + COALESCE(daily_storage_emission_stocks.emissions,0) * COALESCE(released.power,0) / COALESCE(total_power_released, 1)
            -- Emissions embedded in transmission. If no power was sent or received in this load hour, the COALESCE function will change the NULL value to a 0.
          + COALESCE(emissions_received, 0)
        ) as gross_emissions, 
        ( -- NET emissions
          -- Emissions from locally-generated power
          generated_emissions   
            -- Emissions for power released from storage
          + COALESCE(daily_storage_emission_stocks.emissions,0) * COALESCE(released.power,0) / COALESCE(total_power_released, 1)
            -- Emissions embedded in transmission. If no power was sent or received in this load hour, the COALESCE function will change the NULL value to a 0.
          + COALESCE(emissions_received, 0)
        ) * net_power / gross_power as net_emissions
      FROM hourly_la_emission_stocks
        LEFT JOIN daily_storage_emission_stocks      USING (fuel_category_id, scenario_id, carbon_cost, area_id, study_date, iteration) -- Storage's embedded emissions and power released over each day
        LEFT JOIN release_from_storage released      USING (fuel_category_id, scenario_id, carbon_cost, area_id, study_hour) -- Energy released from storage
        LEFT JOIN emissions_received_via_tx          USING (fuel_category_id, scenario_id, carbon_cost, area_id, study_hour) -- Transmission recieved
      WHERE scenario_id = target_scenario_id
        AND iteration = round - 1
        AND gross_power > 0;
    SET la_time = TIMEDIFF(NOW(), start_time);


    -- Update storage emissions. Storage gets the emissions from its load area/fuel category over the whole day
    SET start_time = NOW();
    INSERT INTO daily_storage_emission_stocks (fuel_category_id, scenario_id, carbon_cost, area_id, study_date, iteration, total_power_released, total_power_stored, emissions)
      SELECT fuel_category_id, scenario_id, carbon_cost, area_id, hourly_la_emission_stocks.study_date, iteration, total_power_released, total_power_stored, 
        SUM( gross_emissions * -1 * _gen_hourly_summary_fc_la.power / gross_power )
      FROM hourly_la_emission_stocks
        JOIN _gen_hourly_summary_fc_la  USING (fuel_category_id, scenario_id, carbon_cost, area_id, study_hour)
        JOIN daily_storage_power_released USING (fuel_category_id, scenario_id, carbon_cost, area_id)
      WHERE hourly_la_emission_stocks.iteration = round 
        AND scenario_id = target_scenario_id
        AND storage = 1
        AND gross_power > 0
        AND _gen_hourly_summary_fc_la.power < 0
        AND daily_storage_power_released.study_date = hourly_la_emission_stocks.study_date
      GROUP BY fuel_category_id, scenario_id, carbon_cost, area_id, study_date, iteration, total_power_released, total_power_stored
    ;
    SET storage_time = TIMEDIFF(NOW(), start_time);
    INSERT INTO carbon_intensity_timing (scenario_id, num_carbon_costs, iteration, storage_time, la_time)
      VALUES (target_scenario_id, num_carbon_costs, round, storage_time, la_time);

    DROP TABLE IF EXISTS change_between_iterations;
    CREATE TABLE change_between_iterations
      SELECT scenario_id, carbon_cost, n.study_date, SUM(abs(n.net_emissions - n_minus_1.net_emissions )) as sum_of_deltas
        FROM hourly_la_emission_stocks n
          JOIN hourly_la_emission_stocks n_minus_1 USING(fuel_category_id, scenario_id, carbon_cost, area_id, study_hour)
        WHERE scenario_id = target_scenario_id
          AND n.iteration = round
          AND n_minus_1.iteration = round - 1
        GROUP BY scenario_id, carbon_cost, study_date;
    ALTER TABLE change_between_iterations ADD PRIMARY KEY (scenario_id, carbon_cost, study_date);
    
    SET @worst_delta := (SELECT max(sum_of_deltas/total_daily_emissions) FROM daily_wecc_emissions JOIN change_between_iterations USING (scenario_id, carbon_cost, study_date) WHERE scenario_id = target_scenario_id);
    IF @worst_delta < convergence_threshold THEN
      SET max_round = round;
    END IF;
  
  END WHILE;

  DROP TABLE IF EXISTS overall_emissions;
  CREATE TEMPORARY TABLE overall_emissions
    SELECT scenario_id, carbon_cost, study_hour, area_id, sum(net_emissions) as net_emissions
      FROM hourly_la_emission_stocks 
      WHERE scenario_id = target_scenario_id
        AND iteration = round
      GROUP BY scenario_id, carbon_cost, study_hour, area_id;
  ALTER TABLE overall_emissions ADD PRIMARY KEY (scenario_id, carbon_cost, study_hour, area_id);
  INSERT INTO carbon_intensity_of_electricity (scenario_id, carbon_cost, period, area_id, total_annual_emissions, carbon_intensity)
    SELECT scenario_id, carbon_cost, period, area_id, 
        sum( hours_in_sample * net_emissions ) / years_per_period as total_annual_emissions, 
        sum( hours_in_sample * net_emissions / power ) / sum( hours_in_sample ) as carbon_intensity
      FROM overall_emissions
        JOIN _system_load USING (scenario_id, carbon_cost, study_hour, area_id )
        JOIN sum_hourly_weights_per_period_table USING(scenario_id, period)
      WHERE scenario_id = target_scenario_id
      GROUP BY scenario_id, carbon_cost, period, area_id;
  
END$$
DELIMITER ;

-- Tables for dispatch-only results

CREATE TABLE _dispatch_decisions (
  scenario_id int unsigned NOT NULL,
  carbon_cost smallint NOT NULL DEFAULT '0',
  period year NOT NULL,
  area_id smallint NOT NULL,
  study_timepoint_id int unsigned, 
  study_timepoint_utc datetime,
  test_set_id int unsigned NOT NULL,
  technology_id tinyint unsigned NOT NULL,
  new tinyint(1) NOT NULL,
  baseload tinyint(1) NOT NULL,
  cogen tinyint(1) NOT NULL,
  storage tinyint(1) NOT NULL,
  fuel varchar(64) NOT NULL,
  fuel_category varchar(64) NOT NULL,
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
  deep_cycling_amount double,
  deep_cycling_fuel_cost double,
  deep_cycling_carbon_cost double,
  deep_cycling_co2_tons double,
  mw_started_up double,
  startup_fuel_cost double,
  startup_nonfuel_cost double,
  startup_carbon_cost double,
  startup_co2_tons double,
  PRIMARY KEY (scenario_id, carbon_cost, period, area_id, study_timepoint_utc, technology_id, storage),
  KEY (scenario_id, carbon_cost, study_timepoint_id),
  KEY check_import_count (scenario_id, carbon_cost, test_set_id),
  KEY aggregation (scenario_id, carbon_cost, period, technology_id)
);

CREATE TABLE _dispatch_marg_costs (
  scenario_id int unsigned NOT NULL,
  carbon_cost smallint NOT NULL DEFAULT '0',
  period year NOT NULL,
  area_id smallint NOT NULL,
  study_timepoint_id int unsigned, 
  study_timepoint_utc datetime,
  test_set_id int unsigned NOT NULL,
  hours_in_sample double,
  marg_cost_load double,
  marg_cost_load_reserve double,
  PRIMARY KEY (scenario_id, carbon_cost, period, area_id, study_timepoint_utc ),
  KEY (scenario_id, carbon_cost, study_timepoint_id),
  KEY check_import_count (scenario_id, carbon_cost, test_set_id)
);

CREATE TABLE _dispatch_extra_cap (
  scenario_id int unsigned NOT NULL,
  carbon_cost smallint NOT NULL DEFAULT '0',
  period year NOT NULL,
  test_set_id int unsigned NOT NULL,
  area_id smallint NOT NULL, 
  technology_id tinyint unsigned NOT NULL, 
  project_id int NOT NULL,
  new BOOLEAN,
  baseload BOOLEAN,
  cogen BOOLEAN,
  storage BOOLEAN,
  fuel VARCHAR(64) NOT NULL,
  additional_capacity double,  
  updated_capacity double,
  capital_cost double,
  fixed_o_m_cost double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX test_set_id (test_set_id),
  INDEX area_id (area_id),
  INDEX technology_id (technology_id),
--  FOREIGN KEY (area_id) REFERENCES load_areas(area_id), 
--  FOREIGN KEY (technology_id) REFERENCES technologies(technology_id), 
  INDEX site (project_id),
  PRIMARY KEY (scenario_id, carbon_cost, period, area_id, technology_id, project_id, test_set_id)
);

create table _gen_cap_dispatch_update (
  scenario_id int unsigned NOT NULL,
  carbon_cost smallint NOT NULL DEFAULT '0',
  period year NOT NULL,
  area_id smallint NOT NULL, 
  technology_id tinyint unsigned NOT NULL, 
  project_id int NOT NULL,
  capacity double,
  capital_cost double,
  fixed_o_m_cost double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost,scenario_id),
  INDEX period (period,scenario_id),
  INDEX area_id (area_id,scenario_id),
  INDEX technology_id (technology_id,scenario_id),
  INDEX project_id (project_id,scenario_id),
  PRIMARY KEY (scenario_id, carbon_cost, period, area_id, technology_id, project_id)
);


CREATE TABLE _dispatch_gen_cap_summary_tech (
  scenario_id int unsigned NOT NULL,
  carbon_cost smallint NOT NULL,
  period year NOT NULL,
  technology_id tinyint unsigned NOT NULL,
  capacity double NOT NULL,
  power double DEFAULT 0, 
  avg_power double DEFAULT 0,
  spinning_reserve double DEFAULT 0, 
  avg_spinning_reserve double DEFAULT 0,
  quickstart_capacity double DEFAULT 0,
  avg_quickstart_capacity double DEFAULT 0,
  total_operating_reserve double DEFAULT 0,
  avg_total_operating_reserve double DEFAULT 0,
  deep_cycling_amount double DEFAULT 0,
  avg_deep_cycling_amount double DEFAULT 0,
  mw_started_up double DEFAULT 0,
  avg_mw_started_up double DEFAULT 0,
  capital_cost double NOT NULL,
  o_m_cost_total double NOT NULL,
  fuel_cost double NOT NULL DEFAULT 0,
  carbon_cost_total double NOT NULL DEFAULT 0,
  co2_tons double DEFAULT 0,
  avg_co2_tons double DEFAULT 0,
  spinning_co2_tons double DEFAULT 0,
  avg_spinning_co2_tons double DEFAULT 0,
  deep_cycling_co2_tons double DEFAULT 0,
  avg_deep_cycling_co2_tons double DEFAULT 0,
  startup_co2_tons double DEFAULT 0,
  avg_startup_co2_tons double DEFAULT 0,
  total_co2_tons double DEFAULT 0,
  avg_total_co2_tons double DEFAULT 0,
  PRIMARY KEY (scenario_id, carbon_cost, period, technology_id),
  KEY scenario_id (scenario_id),
  KEY carbon_cost (carbon_cost),
  KEY period (period),
  KEY technology_id (technology_id)
);

CREATE TABLE _dispatch_power_cost (
  scenario_id int unsigned NOT NULL,
  carbon_cost smallint NOT NULL,
  period year NOT NULL,
  load_in_period_mwh double default 0 NOT NULL,
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
  PRIMARY KEY (scenario_id,carbon_cost,period),
  KEY scenario_id (scenario_id),
  KEY carbon_cost (carbon_cost),
  KEY period (period)
); 

CREATE TABLE IF NOT EXISTS dispatch_co2_cc (
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

CREATE TABLE _dispatch_reserve_margin (
  scenario_id int unsigned NOT NULL,
  carbon_cost smallint NOT NULL DEFAULT '0',
  period year NOT NULL,
  test_set_id int unsigned NOT NULL,
  area_id smallint NOT NULL,
  study_timepoint_id int unsigned, 
  study_timepoint_utc datetime,
  static_load double,  
  net_shifted_load double,
  total_load double,
  total_capacity double,
  reserve_margin_total double,
  reserve_margin_percentage double,
  INDEX scenario_id (scenario_id),
  INDEX carbon_cost (carbon_cost),
  INDEX period (period),
  INDEX test_set_id (test_set_id),
  INDEX area_id (area_id),
  INDEX study_timepoint_utc (study_timepoint_utc),
  PRIMARY KEY (scenario_id, carbon_cost, period, test_set_id, area_id, study_timepoint_utc)
);

