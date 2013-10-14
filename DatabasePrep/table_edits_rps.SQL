
-- Data base prep to be able to run rps
-- Jul 30th, 2013. Paty.

set search_path to chile;

-- add col rps_fuel_category to table chile.fuel_info
-- ALTER TABLE chile.fuel_info ADD COLUMN rps_fuel_category VARCHAR;

UPDATE chile.fuel_info SET rps_fuel_category = 'fossilish'
WHERE fuel = 'Gas' 
OR fuel = 'DistillateFuelOil'
OR fuel = 'ResidualFuelOil'
OR fuel = 'Coal'
OR fuel = 'Uranium'
OR fuel = 'Water' --  Obs: water is not renewable for switch wecc
OR fuel = 'Gas_CCS'
OR fuel = 'DistillateFuelOil_CCS'
OR fuel = 'ResidualFuelOil_CCS'
OR fuel = 'Coal_CCS';

UPDATE chile.fuel_info SET rps_fuel_category = 'renewable'
WHERE fuel = 'Wind' 
OR fuel = 'Solar'
OR fuel = 'Bio_Solid'
OR fuel = 'Bio_Liquid'
OR fuel = 'Bio_Gas'
OR fuel = 'Geothermal'
OR fuel = 'Bio_Solid_CCS'
OR fuel = 'Bio_Liquid_CCS'
OR fuel = 'Bio_Gas_CCS';

-- Obs: 'Storage' (fuel) is nothing.
UPDATE chile.fuel_info SET rps_fuel_category = 'na'
WHERE fuel = 'Storage'; 

-- create rps_compliance_entity_targets table

DROP TABLE IF EXISTS years;
CREATE TEMP TABLE years ( year INT);

INSERT INTO years VALUES (2009);
INSERT INTO years VALUES (2010);
INSERT INTO years VALUES (2011);
INSERT INTO years VALUES (2012);
INSERT INTO years VALUES (2013);
INSERT INTO years VALUES (2014);
INSERT INTO years VALUES (2015);
INSERT INTO years VALUES (2016);
INSERT INTO years VALUES (2017);
INSERT INTO years VALUES (2018);
INSERT INTO years VALUES (2019);
INSERT INTO years VALUES (2020);
INSERT INTO years VALUES (2021);
INSERT INTO years VALUES (2022);
INSERT INTO years VALUES (2023);
INSERT INTO years VALUES (2024);
INSERT INTO years VALUES (2025);
INSERT INTO years VALUES (2026);
INSERT INTO years VALUES (2027);
INSERT INTO years VALUES (2028);
INSERT INTO years VALUES (2029);
INSERT INTO years VALUES (2030);
INSERT INTO years VALUES (2031);
INSERT INTO years VALUES (2032);
INSERT INTO years VALUES (2033);
INSERT INTO years VALUES (2034);
INSERT INTO years VALUES (2035);
INSERT INTO years VALUES (2036);
INSERT INTO years VALUES (2037);
INSERT INTO years VALUES (2038);
INSERT INTO years VALUES (2039);
INSERT INTO years VALUES (2040);
INSERT INTO years VALUES (2041);
INSERT INTO years VALUES (2042);
INSERT INTO years VALUES (2043);
INSERT INTO years VALUES (2044);
INSERT INTO years VALUES (2045);
INSERT INTO years VALUES (2046);
INSERT INTO years VALUES (2047);
INSERT INTO years VALUES (2048);
INSERT INTO years VALUES (2049);
INSERT INTO years VALUES (2050);
INSERT INTO years VALUES (2051);
INSERT INTO years VALUES (2052);

INSERT INTO years VALUES (2053);
INSERT INTO years VALUES (2054);
INSERT INTO years VALUES (2055);
INSERT INTO years VALUES (2056);
INSERT INTO years VALUES (2057);
INSERT INTO years VALUES (2058);
INSERT INTO years VALUES (2059);
INSERT INTO years VALUES (2060);
INSERT INTO years VALUES (2061);
INSERT INTO years VALUES (2062);
INSERT INTO years VALUES (2063);
INSERT INTO years VALUES (2064);
INSERT INTO years VALUES (2065);

INSERT INTO years VALUES (2066);
INSERT INTO years VALUES (2067);
INSERT INTO years VALUES (2068);
INSERT INTO years VALUES (2069);
INSERT INTO years VALUES (2070);
INSERT INTO years VALUES (2071);
INSERT INTO years VALUES (2072);
INSERT INTO years VALUES (2073);
INSERT INTO years VALUES (2074);

INSERT INTO years VALUES (2075);
INSERT INTO years VALUES (2076);
INSERT INTO years VALUES (2077);
INSERT INTO years VALUES (2078);
INSERT INTO years VALUES (2079);
INSERT INTO years VALUES (2080);
INSERT INTO years VALUES (2081);
INSERT INTO years VALUES (2082);
INSERT INTO years VALUES (2083);
INSERT INTO years VALUES (2084);

INSERT INTO years VALUES (2085);
INSERT INTO years VALUES (2086);
INSERT INTO years VALUES (2087);
INSERT INTO years VALUES (2088);
INSERT INTO years VALUES (2089);
INSERT INTO years VALUES (2090);
INSERT INTO years VALUES (2091);
INSERT INTO years VALUES (2092);
INSERT INTO years VALUES (2093);
INSERT INTO years VALUES (2094);

INSERT INTO years VALUES (2095);
INSERT INTO years VALUES (2096);
INSERT INTO years VALUES (2097);
INSERT INTO years VALUES (2098);
INSERT INTO years VALUES (2099);
INSERT INTO years VALUES (2100);


DROP TABLE IF EXISTS compliance;

CREATE TEMP TABLE compliance(
compliance_type VARCHAR);

INSERT INTO compliance VALUES ('Distributed');
INSERT INTO compliance VALUES ('Primary');



DROP TABLE IF EXISTS rps_compliance_entity_targets;
CREATE TABLE rps_compliance_entity_targets (
rps_compliance_entity VARCHAR,
rps_compliance_type VARCHAR,
rps_compliance_year INT,
rps_compliance_fraction DOUBLE PRECISION,
enable_rps INT
);

INSERT INTO rps_compliance_entity_targets (rps_compliance_entity, rps_compliance_type, 
rps_compliance_year, enable_rps)
SELECT la_id as rps_compliance_entity, compliance_type as compliance_type, 
year as rps_compliance_year,  
1 AS enable_rps 
FROM chile.load_area, years, compliance
ORDER BY 1,2,3;

UPDATE chile.rps_compliance_entity_targets SET rps_compliance_fraction = 0.05
WHERE rps_compliance_year <= 2014; 

UPDATE chile.rps_compliance_entity_targets SET rps_compliance_fraction = 0.055
WHERE rps_compliance_year = 2015; 

UPDATE chile.rps_compliance_entity_targets SET rps_compliance_fraction = 0.06
WHERE rps_compliance_year = 2016; 

UPDATE chile.rps_compliance_entity_targets SET rps_compliance_fraction = 0.065
WHERE rps_compliance_year = 2017; 

UPDATE chile.rps_compliance_entity_targets SET rps_compliance_fraction = 0.07
WHERE rps_compliance_year = 2018; 

UPDATE chile.rps_compliance_entity_targets SET rps_compliance_fraction = 0.075
WHERE rps_compliance_year = 2019; 

UPDATE chile.rps_compliance_entity_targets SET rps_compliance_fraction = 0.08
WHERE rps_compliance_year = 2020; 

UPDATE chile.rps_compliance_entity_targets SET rps_compliance_fraction = 0.085
WHERE rps_compliance_year = 2021; 

UPDATE chile.rps_compliance_entity_targets SET rps_compliance_fraction = 0.09
WHERE rps_compliance_year = 2022; 

UPDATE chile.rps_compliance_entity_targets SET rps_compliance_fraction = 0.095
WHERE rps_compliance_year = 2023; 

UPDATE chile.rps_compliance_entity_targets SET rps_compliance_fraction = 0.1
WHERE rps_compliance_year = 2024; 

UPDATE chile.rps_compliance_entity_targets SET rps_compliance_fraction = 0.1
WHERE rps_compliance_year > 2024; 


ALTER TABLE rps_compliance_entity_targets ADD PRIMARY KEY (rps_compliance_entity, rps_compliance_type, rps_compliance_year);



-- Tables to load the set RPS_AREAS_AND_FUEL_CATEGORY in AMPL

DROP TABLE IF EXISTS fuel_categories;

CREATE TEMP TABLE fuel_categories(
fuel_category VARCHAR);

INSERT INTO fuel_categories VALUES ('renewable');
INSERT INTO fuel_categories VALUES ('fossilish');
INSERT INTO fuel_categories VALUES ('na');

DROP TABLE IF EXISTS rps_areas_and_fuel_category;
CREATE TABLE rps_areas_and_fuel_category (
la_id VARCHAR,
fuel_category VARCHAR,
fuel_qualifies_for_rps SMALLINT
);

INSERT INTO rps_areas_and_fuel_category (la_id, fuel_category)
SELECT la_id, fuel_category
FROM chile.load_area, fuel_categories
ORDER BY 1,2;

UPDATE chile.rps_areas_and_fuel_category SET fuel_qualifies_for_rps = 1
WHERE fuel_category = 'renewable'; 

UPDATE chile.rps_areas_and_fuel_category SET fuel_qualifies_for_rps = 0
WHERE fuel_category = 'fossilish' OR fuel_category = 'na'; 


ALTER TABLE rps_areas_and_fuel_category ADD PRIMARY KEY (la_id, fuel_category);

-- End of tables to lad the set RPS_AREAS_AND_FUEL_CATEGORY in AMPL


-- One column (rps_compliance_entity) needs to be added to load_area table in order to load a param in switch.mod

ALTER TABLE load_area ADD COLUMN  rps_compliance_entity VARCHAR;

UPDATE chile.load_area SET rps_compliance_entity = load_area.la_id; 



