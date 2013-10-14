
SET search_path TO chile;


DROP TABLE IF EXISTS generator_info_v2;
CREATE TABLE generator_info_v2 as select * from generator_info;

DROP TABLE IF EXISTS generator_info_temp1;
CREATE TABLE generator_info_temp1 (technology VARCHAR, overnight_cost DOUBLE precision, overnight_cost_change DOUBLE PRECISION,
fuel VARCHAR, spanish_tech_name VARCHAR, 
chilean_overnight_cost2012 DOUBLE PRECISION,
chilean_overnight_cost2030 DOUBLE PRECISION, 
chilean_overnight_cost2012_in2011dollars DOUBLE PRECISION,
chilean_overnight_cost2030_in2011dollars DOUBLE PRECISION,
chilean_overnight_cost_change DOUBLE PRECISION,
new_cost INT);

COPY generator_info_temp1
FROM '/Volumes/switch/Users/pehidalg/Switch_Chile/db_costs_update/generator_info_v2.csv'
DELIMITERS ',' CSV HEADER;


-- I don't think it's worth adding a column saying which technology cost was updated. We can just compare 
-- generator_info_v2 with generator_info

UPDATE generator_info_v2 SET overnight_cost = chilean_overnight_cost2012_in2011dollars FROM generator_info_temp1
WHERE generator_info_v2.technology =  generator_info_temp1.technology AND new_cost = 1;

UPDATE generator_info_v2 SET overnight_cost_change = chilean_overnight_cost_change FROM generator_info_temp1
WHERE generator_info_v2.technology =  generator_info_temp1.technology AND new_cost = 1;




SELECT * FROM generator_info_v2;


