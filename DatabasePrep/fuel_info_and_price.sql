-- compliles information relating to fuels

-- ---------------------------------------------------------------------
--        FUEL INFO
-- ---------------------------------------------------------------------
SET search_path TO wecc_info, public;


DROP TABLE IF EXISTS fuel_info;
CREATE TABLE fuel_info (
	fuel varchar(64) PRIMARY KEY,
	rps_fuel_category varchar(10),
	biofuel boolean,
	carbon_content_tons_per_mmbtu NUMERIC(5,5),
	carbon_content_without_carbon_accounting NUMERIC(5,5),
	carbon_sequestered_tons_per_mmbtu  NUMERIC(5,5)
);

COMMENT ON COLUMN fuel_info.carbon_content_tons_per_mmbtu IS 'carbon content before you account for the biomass being NET carbon neutral (or carbon negative for biomass CCS) (tonnes CO2 per million Btu)';

-- carbon content in tCO2/MMBtu from http://www.eia.doe.gov/oiaf/1605/coefficients.html:
-- Voluntary Reporting of Greenhouse Gases Program (Voluntary Reporting of Greenhouse Gases Program Fuel Carbon Dioxide Emission Coefficients)

-- Nuclear, Geothermal, Biomass, Water, Wind and Solar have non-zero LCA emissions
-- To model those emissions, we'd need to divide carbon content into capital, fixed, and variable emissions. Currently, this only lists variable emissions. 

-- carbon_content_without_carbon_accounting represents the amount of carbon actually emitted by a technology
-- before you sequester carbon or before you account for the biomass being NET carbon neutral (or carbon negative for biomass CCS)
-- the Bio_Solid value comes from: Biomass integrated gasiﬁcation combined cycle with reduced CO2emissions:
-- Performance analysis and life cycle assessment (LCA), A. Corti, L. Lombardi / Energy 29 (2004) 2109–2124
-- on page 2119 they say that biomass STs are 23% efficient and emit 1400 kg CO2=MWh, which converts to .094345 tCO2/MMBtu
-- the Bio_Liquid value is derived from http://www.ipst.gatech.edu/faculty/ragauskas_art/technical_reviews/Black%20Liqour.pdf
-- in the spreadsheet /Volumes/switch/Models/USA_CAN/Biomass/black_liquor_emissions_calc.xlsx

INSERT INTO fuel_info (fuel, rps_fuel_category, carbon_content_without_carbon_accounting) values
	('Bio_Solid', 'renewable', 0.094345),
	('Bio_Liquid', 'renewable', 0.07695),
	('Bio_Gas', 'renewable', 0.05306),
	('Coal', 'fossilish', 0.09552),
	('Gas', 'fossilish', 0.05306),
	('DistillateFuelOil', 'fossilish', 0.07315),
	('ResidualFuelOil', 'fossilish', 0.07880),
	('Wind', 'renewable', 0),
	('Solar', 'renewable', 0),
	('Uranium', 'fossilish', 0),
	('Geothermal', 'renewable', 0),
	('Water', 'fossilish', 0);

UPDATE fuel_info
SET carbon_content_tons_per_mmbtu =
	CASE WHEN fuel LIKE 'Bio%' THEN 0 ELSE carbon_content_without_carbon_accounting END;

-- currently we assume that CCS captures all but 15% of the carbon emissions of a plant (the ( 0.15 - 1 ) term)
-- this assumption also affects carbon_sequestered below
INSERT INTO fuel_info (fuel, rps_fuel_category, carbon_content_tons_per_mmbtu, carbon_content_without_carbon_accounting)
SELECT 	fuel || '_CCS' as fuel,
		rps_fuel_category,
		CASE WHEN fuel like 'Bio%' THEN ( 0.15 - 1 ) * carbon_content_without_carbon_accounting
			ELSE 0.15 * carbon_content_without_carbon_accounting END
				as carbon_content_tons_per_mmbtu,
		carbon_content_without_carbon_accounting
	FROM 	fuel_info
	WHERE 	carbon_content_without_carbon_accounting > 0;

UPDATE fuel_info SET biofuel = CASE WHEN fuel like 'Bio%' THEN TRUE ELSE FALSE END;

UPDATE fuel_info set carbon_sequestered_tons_per_mmbtu =
	CASE WHEN fuel like '%CCS' THEN ( 1 - 0.15 ) * carbon_content_without_carbon_accounting ELSE 0 END;


COPY
(SELECT	fuel,
		rps_fuel_category,
 		CASE WHEN TRUE THEN 1 ELSE 0 END as biofuel,
 		carbon_content_tons_per_mmbtu,
  		carbon_content_without_carbon_accounting,
  		carbon_sequestered_tons_per_mmbtu
FROM	fuel_info
ORDER BY fuel)
TO '/Volumes/switch/Models/USA_CAN/Fuels/fuel_info.csv'
WITH CSV HEADER;


-- ---------------------------------------------------------------------
--        CONSUMER PRICE INDEX
-- ---------------------------------------------------------------------
-- SWITCH cost data comes from various dollar years and thus needs to be unified to a single year
-- this is done through the consumer price index (CPI)

-- downloaded CPI data through 2012 from the U.S. Department Of Labor, Bureau of Labor Statistics
-- at ftp://ftp.bls.gov/pub/special.requests/cpi/cpiai.txt

-- right now SWITCH works on $2007, but we should update at some point, so we have $2012 as well here
DROP TABLE IF EXISTS cpi_conversion_table;
CREATE TABLE cpi_conversion_table (
	year smallint PRIMARY KEY,
	cpi NUMERIC(6,3),
	dollar_ratio_to_2007 NUMERIC(6,3),
	dollar_ratio_to_2012 NUMERIC(6,3)
	);
	
COPY cpi_conversion_table (year, cpi)
FROM '/Volumes/switch/Models/USA_CAN/GeneratorInfo_usa/cpi_yearly.txt'
WITH CSV HEADER DELIMITER E'\t'; 

-- we're going to reference everything to $2007 to make things current
-- the column dollar_ratio_to_2007 will help convert any dollar value to $2007 by joining with 'year'
UPDATE 	cpi_conversion_table SET dollar_ratio_to_2007 = cpi_2007 / cpi
FROM	(SELECT cpi as cpi_2007 FROM cpi_conversion_table WHERE year = 2007) as cpi_2007_table;

-- also do $2012
UPDATE 	cpi_conversion_table SET dollar_ratio_to_2012 = cpi_2012 / cpi
FROM	(SELECT cpi as cpi_2012 FROM cpi_conversion_table WHERE year = 2012) as cpi_2012_table;



