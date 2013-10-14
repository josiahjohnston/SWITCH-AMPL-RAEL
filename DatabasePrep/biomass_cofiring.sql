-- This is work done to implement biomass cofiring in the database
-- It involves insertion of two flags, allow_cofiring and can_cofire_biomass
-- It is accomplished in separate tables, but can be done in original tables (scenarios_v3 and generator_info_v2) later

DROP table if exists scenarios_v3_cofiring;

--Updated CREATE command
delimiter $$

CREATE TABLE `scenarios_v3_cofiring` (
  `scenario_id` int(11) NOT NULL AUTO_INCREMENT,
  `scenario_name` varchar(128) DEFAULT NULL,
  `training_set_id` int(11) NOT NULL,
  `regional_cost_multiplier_scenario_id` int(11) NOT NULL DEFAULT '1',
  `regional_fuel_cost_scenario_id` int(11) NOT NULL DEFAULT '1',
  `gen_costs_scenario_id` mediumint(9) NOT NULL DEFAULT '2' COMMENT 'The default scenario is 2 and has the baseline costs and other generator assumptions.',
  `gen_info_scenario_id` mediumint(9) NOT NULL DEFAULT '2' COMMENT 'The default scenario is 2 and has the baseline costs and other generator assumptions.',
  `enable_rps` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'This controls whether Renewable Portfolio Standards are considered in the optimization.',
  `carbon_cap_scenario_id` int(10) unsigned DEFAULT '0' COMMENT 'The default scenario is no cap. Browse existing scenarios or define new ones in the table carbon_cap_scenarios.',
  `nems_fuel_scenario_id` int(10) unsigned DEFAULT '1' COMMENT 'The default scenario is the reference case. Check out the nems_fuel_scenarios table for other scenarios.',
  `dr_scenario_id` tinyint(4) DEFAULT NULL,
  `ev_scenario_id` int(10) unsigned DEFAULT NULL COMMENT 'The default scenario is NULL: no ev demand response scenario specified. The EV scenario is linked to the load_scenario_id. Browse existing EV scenarios or define new ones in the ev_scenarios table.',
  `notes` text NOT NULL,
  `model_version` varchar(16) NOT NULL,
  `inputs_adjusted` varchar(16) NOT NULL DEFAULT 'no',
  `enforce_ca_dg_mandate` tinyint(1) NOT NULL DEFAULT '0',
  `linearize_optimization` tinyint(1) NOT NULL DEFAULT '0',
  `transmission_capital_cost_per_mw_km` int(11) DEFAULT NULL,
  PRIMARY KEY (`scenario_id`),
  UNIQUE KEY `unique_params` (`scenario_name`,`training_set_id`,`regional_cost_multiplier_scenario_id`,`regional_fuel_cost_scenario_id`,`gen_costs_scenario_id`,`gen_info_scenario_id`,`enable_rps`,`carbon_cap_scenario_id`,`nems_fuel_scenario_id`,`dr_scenario_id`,`ev_scenario_id`,`enforce_ca_dg_mandate`,`linearize_optimization`,`model_version`,`inputs_adjusted`,`transmission_capital_cost_per_mw_km`),
  KEY `scenario_name` (`scenario_name`),
  KEY `scenario_name_3` (`scenario_name`,`scenario_id`)
) ENGINE=InnoDB AUTO_INCREMENT=9126 DEFAULT CHARSET=latin1 COMMENT='This is an alternative to scenarios_v3 used specifically for corfiring inputs. Each record in this table is a specification of how to compile a set of inputs for a specific run. Several fields specify how to subselect timepoints from a given training_set. Other fields indicate which set of regional price data to use.'$$

SELECT * FROM `switch_inputs_wecc_v2_2`.`generator_info_v2`;

# --This is the old CREATE command... not copied directly from the DB. Better one above.
# CREATE table scenarios_v3_cofiring(
#  scenario_id int(11),
#  scenario_name varchar(128),
#  training_set_id int(11),
#  regional_cost_multiplier_scenario_id int(11),
#  regional_fuel_cost_scenario_id int(11),
#  gen_costs_scenario_id mediumint(9),
#  gen_info_scenario_id mediumint(9),
#  enable_rps tinyint(1),
#  carbon_cap_scenario_id int(10),
#  nems_fuel_scenario_id int(10),
#  dr_scenario_id tinyint(4),
#  ev_scenario_id int(10),
#  notes text,
#  model_version varchar(16),
#  inputs_adjusted varchar(16),
#  enforce_ca_dg_mandate tinyint(1),
#  linearize_optimization tinyint(1),
#  transmission_capital_cost_per_mw_km int(11)
# );

ALTER TABLE scenarios_v3_cofiring
ADD cofire_scenario_id integer UNSIGNED;

INSERT INTO scenarios_v3_cofiring 
SELECT scenario_id,
 scenario_name,
 training_set_id,
 regional_cost_multiplier_scenario_id,
 regional_fuel_cost_scenario_id,
 gen_costs_scenario_id,
 gen_info_scenario_id,
 enable_rps,
 carbon_cap_scenario_id,
 nems_fuel_scenario_id,
 dr_scenario_id,
 ev_scenario_id,
 notes,
 model_version,
 inputs_adjusted,
 enforce_ca_dg_mandate,
 linearize_optimization,
 transmission_capital_cost_per_mw_km,
 0
FROM scenarios_v3;

UPDATE scenarios_v3_cofiring
SET cofire_scenario_id = 0;

--For new implementation, change to cofiring_scenario_id
--Before, was allow_cofiring
ALTER TABLE scenarios_v3_cofiring
CHANGE cofiring_scenario_id cofire_scenario_id integer UNSIGNED;

--Now, create new scenarios for toy and full runs with cofiring enabled
Requirements: same information, except:
-gen_cost_scenario_id = 10
-cofire_scenario_id = 1
- Toy: Before: s_id = 7583
- Toy: NEW: s_id = 10001

INSERT INTO scenarios_v3_cofiring 
VALUES ('10001','Cofiring toy (old_s_id=7583) Updated gen_costs and cofire_s_id','508','1','1','10','8','1','1','6',NULL,NULL,'','','no','0','1','1000','1');

INSERT INTO scenarios_v3_cofiring
VALUES ('10002','CCC2_base_update_costs_cofire_base','1112','1','1','10','12','1','20','6',NULL,NULL,'','','no','0','1','1000','1');

INSERT INTO scenarios_v3_cofiring
VALUES ('10003','CCC2_base_cofire_base_NEW_var_O+M','1112','1','1','10','12','1','20','6',NULL,NULL,'','','no','0','1','1000','2');

INSERT INTO scenarios_v3_cofiring
VALUES ('10004','288_CCC2_base_update_costs_cofire_base','1110','1','1','10','12','1','20','6',NULL,NULL,'','','no','0','1','1000','1');

INSERT INTO scenarios_v3_cofiring
VALUES ('10005','288_CCC2_base_cofire_base_NEW_var_O+M','1110','1','1','10','12','1','20','6',NULL,NULL,'','','no','0','1','1000','2');

INSERT INTO scenarios_v3_cofiring
VALUES ('10006','288_cofire_high_heat_rate_Var_O+M','1110','1','1','10','12','1','20','6',NULL,NULL,'','','no','0','1','1000','3');

INSERT INTO scenarios_v3_cofiring
VALUES ('10007','576_cofire_high_heat_rate_Var_O+M','1112','1','1','10','12','1','20','6',NULL,NULL,'','','no','0','1','1000','3');

-- Exclude CCS with gen_info_scenario_id = 13

INSERT INTO scenarios_v3_cofiring
VALUES ('10008','288_CC2_cofire_noCCS','1110','1','1','10','13','1','20','6',NULL,NULL,'','','no','0','1','1000','2');

INSERT INTO scenarios_v3_cofiring
VALUES ('10009','576_CCC2_cofire_noCCS','1112','1','1','10','13','1','20','6',NULL,NULL,'','','no','0','1','1000','2');


-- New bio-CCS scenarios for running with consistent costs and (possibly) enabling cofiring

INSERT INTO scenarios_v3_cofiring VALUES (10101,'CCC2_120percent_new_costs_nocofire',1112,1,1,10,14,1,29,6,NULL,NULL,'','','no',0,1,1000,0);
INSERT INTO scenarios_v3_cofiring VALUES (10102,'CCC2_140percent_new_costs_cofire2',1112,1,1,10,14,1,37,6,NULL,NULL,'','','no',0,1,1000,2);
INSERT INTO scenarios_v3_cofiring VALUES (10103,'CCC2_120percent_new_costs_nocofire_288',1110,1,1,10,14,1,29,6,NULL,NULL,'','','no',0,1,1000,0);
INSERT INTO scenarios_v3_cofiring VALUES (10104,'CCC2_140percent_new_costs_cofire2_288',1110,1,1,10,14,1,37,6,NULL,NULL,'','','no',0,1,1000,2);

-- More toy runs for commits (10010 = cofire id 2, 10011 = cofire id 0)

INSERT INTO scenarios_v3_cofiring 
VALUES ('10010','Cofiring toy, gen info 12, cofire id 2','508','1','1','10','12','1','1','6',NULL,NULL,'','','no','0','1','1000','2');

INSERT INTO scenarios_v3_cofiring 
VALUES ('10011','Cofiring toy, gen info 12, no cofiring','508','1','1','10','12','1','1','6',NULL,NULL,'','','no','0','1','1000','0');


--Now focus on new generator info work

DROP TABLE if exists generator_info_sanchez;

CREATE TABLE generator_info_sanchez(
	gen_info_scenario_id int(11),
	technology_id tinyint(3),
	technology varchar(64),
	min_online_year year(4),
	fuel varchar(64),
	connect_cost_per_mw_generic float,
	heat_rate float,
	construction_time_years float,
	year_1_cost_fraction float,
	year_2_cost_fraction float,
	year_3_cost_fraction float,
	year_4_cost_fraction float,
	year_5_cost_fraction float,
	year_6_cost_fraction float,
	max_age_years float,
	forced_outage_rate float,
	scheduled_outage_rate float,
	intermittent tinyint(1),
	resource_limited tinyint(1),
	baseload tinyint(1),
	flexible_baseload tinyint(1),
	dispatchable tinyint(1),
	cogen tinyint(1),
	min_build_capacity float,
	can_build_new tinyint(4),
	competes_for_space tinyint(4),
	ccs tinyint(4),
	storage tinyint(4),
	storage_efficiency float,
	max_store_rate float,
	max_spinning_reserve_fraction_of_capacity float,
	heat_rate_penalty_spinning_reserve float,
	minimum_loading float,
	deep_cycling_penalty float,
	startup_mmbtu_per_mw float,
	startup_cost_dollars_per_mw float,
	data_source_and_notes varchar(512),
	primary key (gen_info_scenario_id, technology_id)
);

INSERT INTO generator_info_sanchez 
SELECT gen_info_scenario_id,
	technology_id,
	technology,
	min_online_year,
	fuel,
	connect_cost_per_mw_generic,
	heat_rate,
	construction_time_years,
	year_1_cost_fraction,
	year_2_cost_fraction,
	year_3_cost_fraction,
	year_4_cost_fraction,
	year_5_cost_fraction,
	year_6_cost_fraction,
	max_age_years,
	forced_outage_rate,
	scheduled_outage_rate,
	intermittent,
	resource_limited,
	baseload,
	flexible_baseload,
	dispatchable,
	cogen,
	min_build_capacity,
	can_build_new,
	competes_for_space,
	ccs,
	storage,
	storage_efficiency,
	max_store_rate,
	max_spinning_reserve_fraction_of_capacity,
	heat_rate_penalty_spinning_reserve,
	minimum_loading,
	deep_cycling_penalty,
	startup_mmbtu_per_mw,
	startup_cost_dollars_per_mw,
	data_source_and_notes
FROM generator_info_v2;

ALTER TABLE generator_info_sanchez
ADD can_cofire_biomass tinyint(1) default 0;

UPDATE generator_info_sanchez
SET can_cofire_biomass = 1
WHERE 
technology = 'Coal_IGCC'
or technology = 'Coal_IGCC_CCS'
or technology = 'Coal_Steam_Turbine'
or technology = 'Coal_Steam_Turbine_CCS'
or technology = 'Coal_Steam_Turbine_Cogen'
or technology = 'Coal_Steam_Turbine_Cogen_CCS'
or technology = 'Coal_Steam_Turbine_Cogen_EP'
or technology = 'Coal_Steam_Turbine_EP'
;

--original method of cofire_params. Done differently now.

DROP table if exists cofire_params;

CREATE table cofire_params(
heat_rate_cofire float,
heat_rate_cofire_ccs float,
carbon_content_bio_ccs float ,
cost_of_plant_one_year_before_operational_cofire float,
fixed_o_m_cofire_per_period float
);

INSERT INTO cofire_params 
VALUES ('10','13.44','-.0801933', '990000', '20000');

--New cofire_info.tab file

DROP table if exists cofire_info;

CREATE table cofire_info(
cofire_scenario_id integer UNSIGNED,
parent_technology varchar(64),
parent_technology_id tinyint(3),
heat_rate float,
cost_of_plant_one_year_before_operational_cofire float,
fixed_o_m_cofire_per_period float,
variable_o_m_cofire float,
primary key (cofire_scenario_id, parent_technology_id)
);

--techology_ids:
--Coal_IGCC	11
--Coal_Steam_Turbine	12
--Coal_Steam_Turbine_EP	18
--Coal_Steam_Turbine_Cogen_EP	30
--Coal_IGCC_CCS	38
--Coal_Steam_Turbine_CCS	39
--Coal_Steam_Turbine_Cogen	100
--Coal_Steam_Turbine_Cogen_CCS	117
-Heat rate assumptions:
-heat_rate_cofire           := 10; heat_rate_cofire_ccs           := 13.44;
-cost_of_plant_one_year_before_operational_cofire           := 990000; fixed_o_m_cofire_per_period           := 20000;
-var_o+M = 0

INSERT INTO cofire_info 
VALUES ('1','Coal_IGCC','11','10', '990000', '20000','0'),
('1','Coal_Steam_Turbine','12','10', '990000', '20000','0'),
('1','Coal_Steam_Turbine_EP','18','10', '990000', '20000','0'),
('1','Coal_Steam_Turbine_Cogen_EP','30','10', '990000', '20000','0'),
('1','Coal_IGCC_CCS','38','13.44', '990000', '20000','0'),
('1','Coal_Steam_Turbine_CCS','39','13.44', '990000', '20000','0'),
('1','Coal_Steam_Turbine_Cogen','100','10', '990000', '20000','0'),
('1','Coal_Steam_Turbine_Cogen_CCS','117','13.44', '990000', '20000','0')
;

INSERT INTO cofire_info 
VALUES ('2','Coal_IGCC','11','10', '990000', '20000','6.0822'),
('2','Coal_Steam_Turbine','12','10', '990000', '20000','3.4503'),
('2','Coal_Steam_Turbine_EP','18','10', '990000', '20000','3.4503'),
('2','Coal_Steam_Turbine_Cogen_EP','30','10', '990000', '20000','3.4503'),
('2','Coal_IGCC_CCS','38','13.44', '990000', '20000','9.858'),
('2','Coal_Steam_Turbine_CCS','39','13.44', '990000', '20000','5.5986'),
('2','Coal_Steam_Turbine_Cogen','100','10', '990000', '20000','3.4503'),
('2','Coal_Steam_Turbine_Cogen_CCS','117','13.44', '990000', '20000','5.5986')
;

INSERT INTO cofire_info 
VALUES ('3','Coal_IGCC','11','12.5', '990000', '20000','6.0822'),
('3','Coal_Steam_Turbine','12','12.5', '990000', '20000','3.4503'),
('3','Coal_Steam_Turbine_EP','18','12.5', '990000', '20000','3.4503'),
('3','Coal_Steam_Turbine_Cogen_EP','30','12.5', '990000', '20000','3.4503'),
('3','Coal_IGCC_CCS','38','16.3208', '990000', '20000','9.858'),
('3','Coal_Steam_Turbine_CCS','39','16.3208', '990000', '20000','5.5986'),
('3','Coal_Steam_Turbine_Cogen','100','12.5', '990000', '20000','3.4503'),
('3','Coal_Steam_Turbine_Cogen_CCS','117','16.3208', '990000', '20000','5.5986')
;

INSERT INTO cofire_info 
VALUES ('4','Coal_IGCC','11','10', '990000', '20000','6.0822'),
('4','Coal_Steam_Turbine','12','10', '990000', '20000','3.4503'),
('4','Coal_Steam_Turbine_EP','18','10', '990000', '20000','3.4503'),
('4','Coal_Steam_Turbine_Cogen_EP','30','10', '990000', '20000','3.4503'),
('4','Coal_Steam_Turbine_Cogen','100','10', '990000', '20000','3.4503'),
;

-- Consider null values for cofire_id = 0. Running into primary key errors for now.
-- INSERT INTO cofire_info 
-- VALUES ('0','',NULL,NULL,NULL,NULL,NULL)
-- ;