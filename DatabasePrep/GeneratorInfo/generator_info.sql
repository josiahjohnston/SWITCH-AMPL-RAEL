-- create tables containing the relevant information about different generation technologies
-- must be run AFTER fuel_info_and_price.sql
-- because of foreign keys on the column 'fuel' from the table fuel_info

set search_path to wecc_inputs, public;

-- ---------------------------------------------------------------------
--        TECHNOLOGY IDs
-- ---------------------------------------------------------------------

-- create a table that will hold the relationship between technology_id and the name of each technology
-- DO NOT delete this table!
-- will be updated using a rule on insert to generator_info below
CREATE TABLE IF NOT EXISTS technology_to_id_map (
	technology_id serial PRIMARY KEY,
	technology varchar(64) NOT NULL UNIQUE
);

-- right now these are the exact same as in mysql, that's whey they're hard-coded in.
INSERT INTO technology_to_id_map (technology_id, technology) VALUES
(1,'CCGT'),
(103,'CCGT_Cogen'),
(110,'CCGT_Cogen_CCS'),
(34,'CCGT_CCS'),
(20,'CCGT_EP'),
(32,'CCGT_Cogen_EP'),
(2,'Gas_Combustion_Turbine'),
(101,'Gas_Combustion_Turbine_Cogen'),
(111,'Gas_Combustion_Turbine_Cogen_CCS'),
(35,'Gas_Combustion_Turbine_CCS'),
(17,'Gas_Combustion_Turbine_EP'),
(29,'Gas_Combustion_Turbine_Cogen_EP'),
(104,'Gas_Internal_Combustion_Engine_Cogen'),
(112,'Gas_Internal_Combustion_Engine_Cogen_CCS'),
(24,'Gas_Internal_Combustion_Engine_EP'),
(40,'Gas_Internal_Combustion_Engine_Cogen_EP'),
(102,'Gas_Steam_Turbine_Cogen'),
(113,'Gas_Steam_Turbine_Cogen_CCS'),
(19,'Gas_Steam_Turbine_EP'),
(31,'Gas_Steam_Turbine_Cogen_EP'),
(60,'DistillateFuelOil_Combustion_Turbine_EP'),
(61,'DistillateFuelOil_Internal_Combustion_Engine_EP'),
(12,'Coal_Steam_Turbine'),
(39,'Coal_Steam_Turbine_CCS'),
(100,'Coal_Steam_Turbine_Cogen'),
(117,'Coal_Steam_Turbine_Cogen_CCS'),
(18,'Coal_Steam_Turbine_EP'),
(30,'Coal_Steam_Turbine_Cogen_EP'),
(11,'Coal_IGCC'),
(38,'Coal_IGCC_CCS'),
(10,'Biomass_IGCC'),
(37,'Biomass_IGCC_CCS'),
(90,'Bio_Solid_Steam_Turbine_EP'),
(91,'Bio_Solid_Steam_Turbine_Cogen_EP'),
(107,'Bio_Solid_Steam_Turbine_Cogen'),
(116,'Bio_Solid_Steam_Turbine_Cogen_CCS'),
(8,'Bio_Gas'),
(105,'Bio_Gas_Internal_Combustion_Engine_Cogen'),
(80,'Bio_Gas_Internal_Combustion_Engine_EP'),
(81,'Bio_Gas_Internal_Combustion_Engine_Cogen_EP'),
(82,'Bio_Gas_Steam_Turbine_EP'),
(85,'Bio_Liquid_Steam_Turbine_Cogen_EP'),
(106,'Bio_Liquid_Steam_Turbine_Cogen'),
(22,'Nuclear_EP'),
(13,'Nuclear'),
(21,'Geothermal_EP'),
(14,'Geothermal'),
(6,'Residential_PV'),
(25,'Commercial_PV'),
(26,'Central_PV'),
(27,'CSP_Trough_No_Storage'),
(7,'CSP_Trough_6h_Storage'),
(23,'Wind_EP'),
(4,'Wind'),
(5,'Offshore_Wind'),
(15,'Hydro_NonPumped_EP'),
(16,'Hydro_Pumped_EP'),
(28,'Compressed_Air_Energy_Storage'),
(33,'Battery_Storage');

-- must reset sequence to above the max value from above otherwise inserting new technologies makes postgresql very unhappy
ALTER SEQUENCE technology_to_id_map_technology_id_seq RESTART WITH 120;

-- ---------------------------------------------------------------------
--        GENERATOR INFO
-- ---------------------------------------------------------------------
-- needs to be run after existing_plants.sql because this script will insert entries for existing plants into the generator_info table

-- add scenarios to be able to easily change generator parameters
CREATE TABLE IF NOT EXISTS generator_info_scenarios (
	gen_info_scenario_id serial PRIMARY KEY,
	notes varchar(256) NOT NULL UNIQUE
);

INSERT INTO generator_info_scenarios (gen_info_scenario_id, notes)
	VALUES	(8, 'Baseline with battery lifetime updated');

-- the checks make sure boolean flags for generator types don't conflict
CREATE TABLE IF NOT EXISTS generator_info(
	gen_info_scenario_id smallint NOT NULL REFERENCES generator_info_scenarios,
	technology_id smallint REFERENCES technology_to_id_map,
	technology varchar(64) NOT NULL REFERENCES technology_to_id_map (technology),
	prime_mover char(2) NOT NULL,
	min_online_year smallint DEFAULT NULL,
	fuel varchar(64) NOT NULL REFERENCES fuel_info,
	connect_cost_dollars_per_mw_generic NUMERIC(7,1),
	heat_rate_mmbtu_per_mwh NUMERIC(5,3) DEFAULT NULL,
	construction_time_years smallint CHECK (construction_time_years BETWEEN 1 AND 6),
	year_1_cost_fraction NUMERIC(3,2) NOT NULL CHECK (year_1_cost_fraction BETWEEN 0 AND 1),
	year_2_cost_fraction NUMERIC(3,2) NOT NULL CHECK (year_2_cost_fraction BETWEEN 0 AND 1),
	year_3_cost_fraction NUMERIC(3,2) NOT NULL CHECK (year_3_cost_fraction BETWEEN 0 AND 1),
	year_4_cost_fraction NUMERIC(3,2) NOT NULL CHECK (year_4_cost_fraction BETWEEN 0 AND 1),
	year_5_cost_fraction NUMERIC(3,2) NOT NULL CHECK (year_5_cost_fraction BETWEEN 0 AND 1),
	year_6_cost_fraction NUMERIC(3,2) NOT NULL CHECK (year_6_cost_fraction BETWEEN 0 AND 1),
	max_age_years smallint NOT NULL CHECK (max_age_years BETWEEN 0 AND 100),
	forced_outage_rate NUMERIC(4,4) NOT NULL CHECK (forced_outage_rate BETWEEN 0 AND 1),
	scheduled_outage_rate NUMERIC(4,4) NOT NULL CHECK (scheduled_outage_rate BETWEEN 0 AND 1),
	intermittent boolean NOT NULL DEFAULT FALSE,
	distributed boolean DEFAULT FALSE NOT NULL,
	resource_limited boolean NOT NULL DEFAULT FALSE,
	baseload boolean DEFAULT FALSE NOT NULL,
	flexible_baseload boolean DEFAULT FALSE NOT NULL,
	dispatchable boolean DEFAULT FALSE NOT NULL,
	cogenerator boolean DEFAULT FALSE NOT NULL,
	min_build_capacity_mw NUMERIC(4,0) DEFAULT 0 NOT NULL,
	can_build_new boolean,
	competes_for_space boolean DEFAULT FALSE NOT NULL,
	ccs boolean DEFAULT FALSE NOT NULL,
	storage boolean DEFAULT FALSE NOT NULL,
	storage_efficiency NUMERIC(5,4) DEFAULT 0 NOT NULL CHECK (storage_efficiency BETWEEN 0 AND 1),
	max_store_rate NUMERIC(4,2) DEFAULT 0 NOT NULL,
	max_spinning_reserve_fraction_of_capacity NUMERIC(4,4) DEFAULT 0 CHECK (max_spinning_reserve_fraction_of_capacity BETWEEN 0 AND 1),
	heat_rate_penalty_spinning_reserve NUMERIC(5,4) DEFAULT 0 CHECK (heat_rate_penalty_spinning_reserve BETWEEN 0 AND 1),
	minimum_loading NUMERIC(5,4) CHECK (minimum_loading BETWEEN 0 AND 1),
	deep_cycling_penalty NUMERIC(5,4) DEFAULT 0 CHECK (deep_cycling_penalty BETWEEN 0 AND 1),
	startup_mmbtu_per_mw NUMERIC(5,2) DEFAULT 0 CHECK (startup_mmbtu_per_mw >= 0),
	startup_cost_dollars_per_mw NUMERIC(5,2) DEFAULT 0 CHECK (startup_cost_dollars_per_mw >= 0),
	PRIMARY KEY (gen_info_scenario_id, technology),
	UNIQUE (gen_info_scenario_id, technology_id),
	CHECK (NOT intermittent OR (intermittent AND NOT baseload AND NOT flexible_baseload AND NOT dispatchable AND NOT cogenerator AND NOT ccs AND NOT storage)),
	CHECK (NOT baseload OR (baseload AND NOT intermittent AND NOT flexible_baseload AND NOT dispatchable AND NOT storage)),
	CHECK (NOT flexible_baseload OR (flexible_baseload AND NOT intermittent AND NOT baseload AND NOT dispatchable AND NOT cogenerator AND NOT storage)),
	CHECK (NOT dispatchable OR (dispatchable AND NOT intermittent AND NOT baseload AND NOT flexible_baseload AND NOT cogenerator)),
	CHECK (NOT cogenerator OR (cogenerator AND NOT intermittent AND NOT flexible_baseload AND NOT dispatchable)),
	CHECK (NOT can_build_new OR (can_build_new AND NOT technology like '%_EP')),
	CHECK (NOT ccs OR (ccs AND NOT intermittent AND NOT storage)),
	CHECK (NOT storage OR (storage AND NOT intermittent AND NOT baseload AND NOT flexible_baseload AND NOT cogenerator AND NOT ccs)),
	CHECK (min_online_year >= 2010 OR (NOT can_build_new AND min_online_year = 0)),
	CHECK ((can_build_new AND heat_rate_mmbtu_per_mwh >= 0) OR (NOT can_build_new AND heat_rate_mmbtu_per_mwh IS NULL))
);	

CREATE INDEX ON generator_info (technology_id, technology);
CREATE INDEX ON generator_info (technology);

-- the next two blocks of sql (FUNCTION, TRIGGER)
-- work together to add the technology name being inserted into generator_info into technology_to_id_map first (before insert to generator_info)
-- then actually add rows to generator_info (now not violiating the reference to technology on technology_to_id_map
DROP FUNCTION IF EXISTS insert_tech_name_if_not_exists() CASCADE;
CREATE FUNCTION insert_tech_name_if_not_exists() RETURNS trigger AS $$
 BEGIN
 	INSERT INTO technology_to_id_map (technology)
 		SELECT 	NEW.technology
    			WHERE NEW.technology NOT IN (SELECT technology FROM technology_to_id_map);
    	RETURN NEW;
 END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS keep_tech_map_current ON generator_info;
CREATE TRIGGER keep_tech_map_current BEFORE INSERT
     ON generator_info FOR EACH ROW
     EXECUTE PROCEDURE insert_tech_name_if_not_exists();

-- INSERT NEW TECHS-----------------------------------------

-- We start by inserting all of the technologies that SWITCH may be able to build, except those that replace existing plants (which includes cogen)
-- a few will get deleted subsequently (Gas Steam and Hydro) because we aren't going to build new of those for now

-- sources:Black&Veatch 2012 and CEC COG Model Version 2.02-4-5-10 unless otherwise stated
-- Bio_Gas: NREL REF/EPRI McGowin 2007
-- Offshore wind is fixed bottom
-- Gas Steam Turbine: OGS (Oil Gas Steam) Tidball et al (NREL cost comparison), outage rates from 2006-2010 NERC Generating Availability Report, construction schedule like Coal Steam Turbine

-- We didn't have consistent data on Biomass_IGCC_CCS and Gas_Combustion_Turbine_CCS heat rates, 
-- so we assumed that the CCS heat rate increases by the same fraction relative to a non-CCS similar technology
-- with Gas CT <---> CCGT and Biomass_IGCC <---> Coal IGCC

COPY generator_info (gen_info_scenario_id, technology, prime_mover, fuel, heat_rate_mmbtu_per_mwh, forced_outage_rate, scheduled_outage_rate,
		storage, storage_efficiency, distributed, max_age_years,
		year_1_cost_fraction, year_2_cost_fraction, year_3_cost_fraction, year_4_cost_fraction, year_5_cost_fraction, year_6_cost_fraction)
FROM '/Volumes/switch/Models/USA_CAN/GeneratorInfo_usa/generator_info_new_projects_only.txt'
WITH CSV HEADER DELIMITER E'\t'; 

-- fill in some obvious values
UPDATE generator_info SET can_build_new = TRUE;
UPDATE generator_info SET ccs = TRUE WHERE technology like '%CCS%';

-- USE NEW TECHS TO POPULATE VALUES FOR EXISTING TECHS-----------------------------------------
-- in order to control the amount of redundant information floating around,
-- we generate existing plant technologies from similar new plants
-- the problem is that there are some existing plants for which the technology doesn't exist
-- so we create a map table between new and existing fuel-prime_mover combos

-- the existing_plants_avg_heat_rate contains all unique combos of prime_mover, cogenerator and fuel
-- the prime_mover names here should match those in existing_plants.sql
-- if the existing_new_tech_map table doesn't contain all existing fuel-prime_mover combos that we want to model 
-- then these ones will be lost in the 'INSERT INTO generator_info' below
DROP TABLE IF EXISTS existing_new_tech_map;
CREATE TABLE existing_new_tech_map (
	existing_fuel varchar(64) REFERENCES fuel_info (fuel),
	existing_prime_mover char(2),
	new_fuel varchar(64) REFERENCES fuel_info (fuel),
	new_prime_mover char(2),
	PRIMARY KEY (existing_fuel, existing_prime_mover, new_fuel, new_prime_mover) );

-- pairs for which existing and new technologies match on both fuel and prime_mover
INSERT INTO existing_new_tech_map (existing_fuel, existing_prime_mover, new_fuel, new_prime_mover) 
	SELECT 	DISTINCT fuel, prime_mover, fuel, prime_mover
	FROM 	generator_info;

-- pairs for which fuel and/or prime_mover DON'T match between existing and new
INSERT INTO existing_new_tech_map (existing_fuel, existing_prime_mover, new_fuel, new_prime_mover) VALUES 
	('Bio_Gas', 'CC', 'Gas', 'CC'),
	('Bio_Gas', 'ST', 'Gas', 'ST'),
	('Bio_Liquid', 'ST', 'Gas', 'ST'),
	('Bio_Solid', 'ST', 'Gas', 'ST'),
	('DistillateFuelOil', 'CC', 'Gas', 'CC'),
	('DistillateFuelOil', 'GT', 'Gas', 'GT'),
	('DistillateFuelOil', 'IC', 'Gas', 'GT'),
	('DistillateFuelOil', 'ST', 'Gas', 'ST'),
	('Gas', 'IC', 'Gas', 'GT'),
	('ResidualFuelOil', 'IC', 'Gas', 'GT'),
	('ResidualFuelOil', 'ST', 'Gas', 'ST');


-- heat rate doesn't appear here because it's calculated in existing_plants.sql
-- only insert for the baseline gen_info_scenario_id right now
-- note that if any of the parameters listed here can't be easily translated between new and existing technologies,
-- then these params should be updated or entered separately
INSERT INTO generator_info (gen_info_scenario_id, technology, prime_mover, fuel, forced_outage_rate, scheduled_outage_rate,
		storage, storage_efficiency, distributed, max_age_years, 
		year_1_cost_fraction, year_2_cost_fraction, year_3_cost_fraction, year_4_cost_fraction, year_5_cost_fraction, year_6_cost_fraction,
		cogenerator, can_build_new)
SELECT	gen_info_scenario_id,
		CASE WHEN technology = 'CCGT' AND existing_fuel != 'Gas' THEN existing_fuel || '_CC'
			 WHEN technology = 'CCGT' AND existing_fuel = 'Gas' THEN 'CCGT'
			 WHEN new_prime_mover = 'ST' AND new_fuel = 'Gas' THEN existing_fuel || '_Steam_Turbine'
			 WHEN new_prime_mover = 'GT' AND existing_prime_mover = 'IC' THEN existing_fuel || '_Internal_Combustion_Engine'
			 WHEN new_prime_mover = 'GT' AND existing_prime_mover = 'GT' THEN existing_fuel || '_Combustion_Turbine'
			 WHEN existing_prime_mover = 'IC' AND existing_fuel = 'Bio_Gas' THEN existing_fuel || '_Internal_Combustion_Engine'
			 ELSE technology END
			|| CASE WHEN e.cogenerator THEN '_Cogen' ELSE '' END
			|| '_EP' as technology,
		existing_prime_mover,
		existing_fuel,
		forced_outage_rate, scheduled_outage_rate,
		storage, storage_efficiency,
		distributed,
		max_age_years,
		year_1_cost_fraction, year_2_cost_fraction, year_3_cost_fraction, year_4_cost_fraction, year_5_cost_fraction, year_6_cost_fraction,
		e.cogenerator,
		FALSE as can_build_new
FROM	existing_plants_avg_heat_rate e,
		existing_new_tech_map m,
		generator_info g
WHERE	gen_info_scenario_id = 8
AND		e.prime_mover = existing_prime_mover
AND		e.fuel = existing_fuel
AND		g.prime_mover = new_prime_mover
AND		g.fuel = new_fuel
ORDER BY technology;

DROP TABLE existing_new_tech_map;

-- SWITCH can't build new gas steam turbines or pumped hydro or non-pumped hydro
-- but these had entries in generator_info to help create existing technologies,
-- so delete the new technologies here
DELETE FROM generator_info
WHERE 	( fuel = 'Water' AND can_build_new)
OR		( fuel = 'Gas' AND prime_mover = 'ST' and not cogenerator and can_build_new);

-- now that we know what cogeneration technologies exist from the existing plants,
-- add their cogen replacement technologies here in both non-CCS and CCS flavors
-- the first insert here gets the non-ccs versions
INSERT INTO generator_info (gen_info_scenario_id, technology, prime_mover, fuel, forced_outage_rate, scheduled_outage_rate,
		max_age_years, year_1_cost_fraction, year_2_cost_fraction, year_3_cost_fraction, year_4_cost_fraction, year_5_cost_fraction, year_6_cost_fraction,
		cogenerator, can_build_new)
SELECT	gen_info_scenario_id,
		replace(technology, '_EP', '') as technology,
		prime_mover,
		fuel,
		forced_outage_rate, scheduled_outage_rate,
		max_age_years,
		year_1_cost_fraction, year_2_cost_fraction, year_3_cost_fraction, year_4_cost_fraction, year_5_cost_fraction, year_6_cost_fraction,
		TRUE as cogenerator,
		TRUE as can_build_new
FROM	generator_info g
WHERE	gen_info_scenario_id = 8
AND		cogenerator
ORDER BY technology;

-- the CCS versions are only added for fuels that we currently CCS (Bio_Solid, Coal, Gas)
INSERT INTO generator_info (gen_info_scenario_id, technology, prime_mover, fuel, forced_outage_rate, scheduled_outage_rate,
		max_age_years, year_1_cost_fraction, year_2_cost_fraction, year_3_cost_fraction, year_4_cost_fraction, year_5_cost_fraction, year_6_cost_fraction,
		cogenerator, can_build_new, ccs)
SELECT	gen_info_scenario_id,
		technology || '_CCS' as technology,
		prime_mover,
		fuel || '_CCS',
		forced_outage_rate, scheduled_outage_rate,
		max_age_years,
		year_1_cost_fraction, year_2_cost_fraction, year_3_cost_fraction, year_4_cost_fraction, year_5_cost_fraction, year_6_cost_fraction,
		TRUE as cogenerator,
		TRUE as can_build_new,
		TRUE as ccs
FROM	generator_info g
WHERE	gen_info_scenario_id = 8
AND		fuel in (SELECT DISTINCT replace(fuel, '_CCS', '') from generator_info where fuel like '%_CCS%')
AND		cogenerator
AND		can_build_new
ORDER BY technology;

-- internal combustion engines are generally very fast to build but the above yields a construction time of two years
-- change it to one year here unless the project is a CCS project
UPDATE 	generator_info
SET		year_1_cost_fraction = 1,
		year_2_cost_fraction = 0
WHERE 	prime_mover = 'IC'
AND 	NOT ccs;

-- add the technology_id of each technology from the technology_to_id_map
UPDATE 	generator_info
SET 	technology_id = m.technology_id
FROM 	technology_to_id_map m
WHERE 	generator_info.technology = m.technology;

-- add construction time using the year_X_cost_fraction
UPDATE  generator_info SET construction_time_years = 6 WHERE year_6_cost_fraction > 0 AND construction_time_years IS NULL;
UPDATE  generator_info SET construction_time_years = 5 WHERE year_5_cost_fraction > 0 AND construction_time_years IS NULL;
UPDATE  generator_info SET construction_time_years = 4 WHERE year_4_cost_fraction > 0 AND construction_time_years IS NULL;
UPDATE  generator_info SET construction_time_years = 3 WHERE year_3_cost_fraction > 0 AND construction_time_years IS NULL;
UPDATE  generator_info SET construction_time_years = 2 WHERE year_2_cost_fraction > 0 AND construction_time_years IS NULL;
UPDATE  generator_info SET construction_time_years = 1 WHERE year_1_cost_fraction > 0 AND construction_time_years IS NULL;

-- add min_online_year
-- CCS can't be built until 2020
-- other generators can START to be built now but won't be complete until they've gone through their construction schedule
UPDATE 	generator_info
SET		min_online_year =
	CASE WHEN ccs THEN 2020
		 WHEN not ccs and can_build_new THEN 2010
		 ELSE 0 END;

-- add min_build_capacity_mw... only for new nuclear at the moment... default is 0
UPDATE generator_info SET min_build_capacity_mw = 1000 WHERE fuel = 'Uranium' and can_build_new;

-- add resource_limited flag... default is FALSE
UPDATE generator_info SET resource_limited = TRUE
	WHERE	fuel in ('Wind', 'Solar', 'Water', 'Geothermal', 'Bio_Solid', 'Bio_Solid_CCS', 'Bio_Liquid', 'Bio_Gas')
	OR		cogenerator
	OR		NOT can_build_new
	-- compressed air
	OR		(storage and fuel = 'Gas');

-- add intermittent flag... default is FALSE
UPDATE generator_info SET intermittent = TRUE WHERE fuel in ('Wind', 'Solar');

-- add baseload flag... default is FALSE.
-- baseload has the same output 24/7, whereas the flexible baseload designation below can be ramped up and down
-- cogeneration is considered baseload as we presume that the heat demand is relativly constant
UPDATE generator_info SET baseload = TRUE
	WHERE	cogenerator
	OR		fuel like 'Bio%'
	OR		fuel in ('Uranium', 'Geothermal');

-- add flexible_baseload flag... default is FALSE.
UPDATE generator_info SET flexible_baseload = TRUE
	WHERE 	fuel like 'Coal%'
	AND		NOT baseload;

-- add dispatchable flag... default is FALSE.
UPDATE generator_info SET dispatchable = TRUE
	WHERE 	fuel in ('Gas', 'Gas_CCS', 'DistillateFuelOil', 'ResidualFuelOil')
	AND		NOT baseload
	AND		NOT flexible_baseload;

-- add competes_for_space flag... default is FALSE.
-- this flag is a bit old and should perhaps be updated at some time...
UPDATE generator_info SET competes_for_space = TRUE
	WHERE 	cogenerator
	OR		fuel like 'Bio%'
	-- central station PV and solar thermal compete for space
	OR		( fuel = 'Solar' AND NOT distributed );
	
-- max_store_rate of storage intake in MW to output, so greater than 1 means that it can store faster than it can release
-- default 0 (for non-storage projects), 1 for pumped hydro and batteries, 1.2 for compressed air
UPDATE generator_info SET max_store_rate =
	CASE WHEN fuel = 'Gas' THEN 1.2 ELSE 1 END
	WHERE storage;

-- RESERVES + DEEP CYCLING
-- Calculated and referenced in spinning_and_deep_cycling_calcs.xlsx

-- max_spinning_reserve_fraction_of_capacity... default 0
-- should be greater than 0 for technologies that can provide spinning reserve
-- (i.e. not baseload techs... could someday be updated to provide a bit of reserve)
-- broken down by prime_mover here
UPDATE generator_info SET max_spinning_reserve_fraction_of_capacity =
	CASE WHEN prime_mover = 'ST' THEN 0.31
		 WHEN prime_mover = 'CC' THEN 0.38
		 WHEN prime_mover in ('IC', 'GT', 'CE') THEN 0.50
		 ELSE 0 END
	WHERE 	dispatchable;

-- heat_rate_penalty_spinning_reserve... default 0
-- the penalty for going below full load
UPDATE generator_info SET heat_rate_penalty_spinning_reserve =
	CASE WHEN prime_mover = 'ST' THEN 0.04
		 WHEN prime_mover = 'CC' THEN 0.33
		 WHEN prime_mover in ('IC', 'GT', 'CE') THEN 0.10
		 ELSE 0 END
	WHERE 	dispatchable;

-- startup_mmbtu_per_mw... default 0
-- the heat required to start a unit up from cold
UPDATE generator_info SET startup_mmbtu_per_mw =
	CASE WHEN prime_mover = 'ST' THEN 8.92
		 WHEN prime_mover = 'CC' THEN 9.16
		 WHEN prime_mover in ('IC', 'GT') THEN 0.22
		 ELSE 0 END
	WHERE 	dispatchable;

-- startup_cost_dollars_per_mw... default 0
-- the non-fuel cost is specified in $2007 to start up a unit
UPDATE generator_info SET startup_cost_dollars_per_mw =
	CASE WHEN prime_mover in ('CC', 'ST') THEN 10.3
		 WHEN prime_mover in ('IC', 'GT', 'CE') THEN 0.86
		 ELSE 0 END
	WHERE 	dispatchable;

-- minimum_loading... no default
-- the minimum fraction of capacity at which the generator must operate
UPDATE generator_info SET minimum_loading =
	-- hydro and storage are very flexible
	CASE WHEN storage OR fuel = 'Water' THEN 0
	-- intermittent projects can only dispatch when they have energy, so they're not restricted here
		 WHEN intermittent THEN 0
	-- combustion turbines and internal combustion engines are flexible, hence zero here
		 WHEN prime_mover in ('IC', 'GT') AND not baseload THEN 0
	-- combined cycles and steam turbines are require some minimum load
	-- exclude existing coal steam turbines... to be added below
		 WHEN prime_mover in ('CC', 'ST') AND not baseload
		 		AND NOT (prime_mover = 'ST' AND fuel = 'Coal' AND NOT can_build_new) THEN 0.4
	-- existing coal steam turbines are even less flexible 
		 WHEN prime_mover = 'ST' AND fuel = 'Coal' AND NOT can_build_new AND NOT baseload THEN 0.7
	-- full baseload techs in SWITCH are forced to full output all the time
		 WHEN baseload THEN 1
	END;
	
-- deep_cycling_penalty... default 0
-- the heat rate penalty for going below full load
UPDATE generator_info SET deep_cycling_penalty =
	CASE WHEN	prime_mover = 'CC' AND fuel not like 'Coal%' THEN 0.33
		 WHEN	prime_mover = 'ST' AND fuel not like 'Coal%' THEN 0.04
		 WHEN	prime_mover = 'CC' AND fuel like 'Coal%' THEN 0.29
		 WHEN	prime_mover = 'ST' AND fuel like 'Coal%' THEN 0.05
		 ELSE 0 END
	WHERE 	flexible_baseload
	OR		dispatchable;
	

-- CONNECTION COST--------------------------------
-- calculates the connection cost for renewables and non renewables from eia860 interconnection cost data

-- the field 'transmission_line' denotes whether a transmission line had to be added to get the generator on the grid
-- so for the way SWITCH does connection costs, this means that that for renewables with specific sites from which
-- we calculate the distance to the grid, the cost of building a transmission line is already included,
-- so only a generic charge for hooking up a line to a substation should be included,
-- i.e. transmission_line IS FALSE

-- but for other technologies that we build anywhere in a load area, there may or may not need to be added transmission
-- but we would have no way of knowing until we scoped specific sites, so we should include an average cost of transmission
-- therefore transmission_line IS TRUE

-- we want to include grid_enhancement_cost in either scenario as in SWITCH it represents
-- the cost to get power from the generator's busbar connection to the grid out to the nearest load center/primary substation
-- grid_enhancement_cost isn't included in distributed PV as the distribution costs are added in via load_areas_usa_can

-- note that the cost columns of eia_form_860_interconnection are in THOUSANDS of $2011 dollars

DROP TABLE IF EXISTS connect_cost_calc_tmp;
CREATE TABLE connect_cost_calc_tmp AS 
	SELECT	transmission_line,
			sum(interconnection_cost) / sum(capacity_mw) as connect_cost_dollars_per_mw_generic
	FROM
		(SELECT	facility_code,
				generator_id,
				nameplate as capacity_mw,
				( interconnection_cost +
					CASE WHEN grid_enhancement_cost IS NULL THEN 0 ELSE grid_enhancement_cost END )
					* 1000 * dollar_ratio_to_2007
					as interconnection_cost,
				transmission_line
		FROM	eia_form_860_interconnection
		JOIN	eia_form_860_generator USING (facility_code, generator_id)
		JOIN	cpi_conversion_table ON (year = interconnection_year)
		WHERE 	interconnection_cost IS NOT NULL
		AND 	transmission_line IS NOT NULL
		) as gen_cost_table
	GROUP BY transmission_line;

-- now update the three cases in generator_info
UPDATE 	generator_info
SET 	connect_cost_dollars_per_mw_generic = 0
WHERE 	distributed;

UPDATE 	generator_info
SET 	connect_cost_dollars_per_mw_generic = t.connect_cost_dollars_per_mw_generic
FROM 	(SELECT connect_cost_dollars_per_mw_generic FROM connect_cost_calc_tmp WHERE NOT transmission_line) as t
WHERE 	can_build_new
AND 	NOT distributed
AND 	fuel in ('Wind', 'Solar', 'Geothermal');

UPDATE 	generator_info
SET 	connect_cost_dollars_per_mw_generic = t.connect_cost_dollars_per_mw_generic
FROM 	(SELECT connect_cost_dollars_per_mw_generic FROM connect_cost_calc_tmp WHERE transmission_line) as t
WHERE	generator_info.connect_cost_dollars_per_mw_generic IS NULL;
	
DROP TABLE connect_cost_calc_tmp;

-- add not null and check constraints at the end to keep everything nice
-- we didn't add these initially because it would have made the nice, simple update statements very ugly
ALTER TABLE generator_info ALTER COLUMN technology_id SET NOT NULL;
ALTER TABLE generator_info ALTER COLUMN connect_cost_dollars_per_mw_generic SET NOT NULL;
ALTER TABLE generator_info ALTER COLUMN construction_time_years SET NOT NULL;
ALTER TABLE generator_info ALTER COLUMN can_build_new SET NOT NULL;


-- can change this later, but delete all entries that SWITCH can't handle yet... these are all technology_id >= 120
DELETE FROM generator_info WHERE technology_id >= 120;

-- export to MySQL for the moment.  Boolean export is difficult, so have to specify all columns.
copy ( SELECT
	gen_info_scenario_id,
	technology_id,
	technology,
	prime_mover,
	min_online_year,
	fuel,
	connect_cost_dollars_per_mw_generic,
	heat_rate_mmbtu_per_mwh,
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
	CASE WHEN intermittent THEN 1 ELSE 0 END as intermittent,
	CASE WHEN distributed THEN 1 ELSE 0 END as distributed,
	CASE WHEN resource_limited THEN 1 ELSE 0 END as resource_limited,
	CASE WHEN baseload THEN 1 ELSE 0 END as baseload,
	CASE WHEN flexible_baseload THEN 1 ELSE 0 END as flexible_baseload,
	CASE WHEN dispatchable THEN 1 ELSE 0 END as dispatchable,
	CASE WHEN cogenerator THEN 1 ELSE 0 END as cogenerator,
	min_build_capacity_mw,
	CASE WHEN can_build_new THEN 1 ELSE 0 END as can_build_new,
	CASE WHEN competes_for_space THEN 1 ELSE 0 END as competes_for_space,
	CASE WHEN ccs THEN 1 ELSE 0 END as ccs,
	CASE WHEN storage THEN 1 ELSE 0 END as storage,
	storage_efficiency,
	max_store_rate,
	max_spinning_reserve_fraction_of_capacity,
	heat_rate_penalty_spinning_reserve,
	minimum_loading,
	deep_cycling_penalty,
	startup_mmbtu_per_mw,
	startup_cost_dollars_per_mw
FROM generator_info
order by technology_id )
to 'GeneratorInfo/generator_info.csv'
WITH CSV HEADER NULL '';

