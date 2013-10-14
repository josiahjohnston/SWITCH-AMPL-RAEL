-- This sql defines the training sets that can be used. In this case (v3) only 3 training_sets are generated, the rest of the permutations are not included. 
-- Refer to previous versions of DefineScenarios.SQL for the complete code (training_set posibilities = permutations) 



-- Add additional methods of sample selection to this file.
-- You can either add specific permutations individually, or add entries to the *_permutations table that will be expanded combinatorially.
set search_path to chile;


--PATY EDIT: row below, so the script can be run many times (until it works properly).
--If everything was dropped and setup_study_hours.sql was run, the line below has to be commented (because there is no such tabe anymore)
delete from training_sets;

-- PATY EDIT: the line below was added by me so the training_set_id serial (sequence) from the training_sets table would start with 1.
-- Everytime a new row is inserted in training_sets table, the training_set_id increases by 1. So since I'm trying to make all the scripts work, I need to run this more than once.
ALTER SEQUENCE training_sets_training_set_id_seq RESTART WITH 1;






-- Example of defining a single training set:

-- id # 1 (the set we want to use)
INSERT INTO training_sets ( demand_scenario_id, study_start_year, years_per_period, number_of_periods, exclude_peaks, months_between_samples, start_month, hours_between_samples, start_hour, selection_method, notes ) 
-- PATY'S EDITION: I changed a 3 for a 1 in the line below (it used to be: 3 as demand_scenario_id)
		select 1 as demand_scenario_id, 2014, 4, 4, --BEFORE: 2011, 3, 4 
		false, 1, 1, 2, 0, --BEFORE: false, 1, 1, 4, 0, 
		'MEDIAN', 
		'For each month, the day with peak load and a representative day with near-median load were selected. The peak day was selected system-wide, while the median was based on total consumption during the day.'
		;
		
-- update number_of_timepoints
UPDATE training_sets
	SET number_of_timepoints = number_of_periods * (2 - CASE WHEN exclude_peaks THEN 1 ELSE 0 END) * 
		FLOOR(12/months_between_samples) * FLOOR(24/hours_between_samples)
		WHERE number_of_timepoints IS NULL;


select define_new_training_sets();



-- The original code used to define many training sets using all permutations of subsampling parameters given below. Which has now been "commented."
-- -- START OF PERMUTATIONS ---------------------------------------------------------------------------------------------------------

-- INSERT INTO training_sets ( demand_scenario_id, study_start_year, years_per_period, number_of_periods, exclude_peaks, months_between_samples, start_month, hours_between_samples, start_hour, selection_method, notes ) 
-- -- PATY'S EDITION: I changed a 3 for a 1 in the line below (it used to be: 3 as demand_scenario_id)
--	SELECT 1 as demand_scenario_id, study_start_year, years_per_period, number_of_periods, 
--		false as exclude_peaks, months_between_samples, start_month, hours_between_samples, start_hour, 
--		'MEDIAN' as selection_method, 
--		'For each month, the day with peak load and a representative day with near-median load were selected. The peak day was selected system-wide, while the median was based on total consumption during the day.' as notes
--	FROM 
--
--	(
--	-- PATY EDIT: SELECT 2016 as study_start_year, 3 as years_per_period, 4 as number_of_periods
--		SELECT 2011 as study_start_year, 3 as years_per_period, 6 as number_of_periods --UNION
-- --		SELECT 2015, 10, 4 UNION
-- --		SELECT 2018, 8 , 2 UNION
-- --		SELECT 2025, 20, 2
--	) AS period_permutations,
--
--	(	
--		SELECT 12 AS months_between_samples, 1 AS start_month UNION
--		SELECT 6, 1 UNION
--		SELECT 4, 1 UNION
--		SELECT 2, 1 UNION
--		SELECT 2, 2 UNION
--		SELECT 1, 1
--	) AS month_permutations, 
--
--	(
--		SELECT 4 AS hours_between_samples, 0 AS start_hour UNION
--		SELECT 4, 1 UNION
--		SELECT 4, 2 UNION
--		SELECT 4, 3 UNION
--		SELECT 2, 0 UNION
--		SELECT 2, 1 UNION
--		SELECT 1, 0
--	) AS hour_permutations
-- ;

-- -- update number_of_timepoints
-- --future hours in the trinainig sets
-- UPDATE training_sets
--	SET number_of_timepoints = number_of_periods * (2 - CASE WHEN exclude_peaks THEN 1 ELSE 0 END) * 
--		FLOOR(12/months_between_samples) * FLOOR(24/hours_between_samples)
--		WHERE number_of_timepoints IS NULL;

-- --PATY EDIT: Line below has been added. training_set_id 28, 33, 34, 40 was giving problems with a double which should be an int 
-- --(in the script new_tables (extract from compile script))
-- -- the aim of new_tables script is to build the tables for training sets.
-- delete from training_sets where training_set_id = 20; --new
-- delete from training_sets where training_set_id = 22; --new
-- delete from training_sets where training_set_id = 24; --new
-- delete from training_sets where training_set_id = 28;
-- delete from training_sets where training_set_id = 32; --new
-- delete from training_sets where training_set_id = 33;
-- delete from training_sets where training_set_id = 34;
-- delete from training_sets where training_set_id = 36; --new
-- delete from training_sets where training_set_id = 38; --new
--delete from training_sets where training_set_id = 40;
-- delete from training_sets where training_set_id = 42; --new




-- --PATY EDIT: Line below has been added.
-- SELECT * FROM training_sets;

-- --PATY EDIT: Line below has been commented in the script because it might be unuseful for now (and it's presenting problems)
-- select define_new_training_sets();

-- -- END OF PERMUTATIONS ---------------------------------------------------------------------------------------------------------



-- New training sets (useful ones for switch Chile):

-- id # 2 (orignal set that has been used until now)
INSERT INTO training_sets ( demand_scenario_id, study_start_year, years_per_period, number_of_periods, exclude_peaks, months_between_samples, start_month, hours_between_samples, start_hour, selection_method, notes ) 
	select 1 as demand_scenario_id, 2011, 3, 6, --BEFORE: 2016, 3, 4 
		false, 1, 1, 4, 0, 
		'MEDIAN', 
		'For each month, the day with peak load and a representative day with near-median load were selected. The peak day was selected system-wide, while the median was based on total consumption during the day.'
		;

-- id # 3
INSERT INTO training_sets ( demand_scenario_id, study_start_year, years_per_period, number_of_periods, exclude_peaks, months_between_samples, start_month, hours_between_samples, start_hour, selection_method, notes ) 
	select 1 as demand_scenario_id, 2014, 2, 6, 
		false, 1, 1, 2, 0, 
		'MEDIAN', 
		'For each month, the day with peak load and a representative day with near-median load were selected. The peak day was selected system-wide, while the median was based on total consumption during the day.'
		;
		
-- id # 4
INSERT INTO training_sets ( demand_scenario_id, study_start_year, years_per_period, number_of_periods, exclude_peaks, months_between_samples, start_month, hours_between_samples, start_hour, selection_method, notes ) 
	select 1 as demand_scenario_id, 2014, 1, 12, 
		false, 2, 1, 2, 0, 
		'MEDIAN', 
		'For each month, the day with peak load and a representative day with near-median load were selected. The peak day was selected system-wide, while the median was based on total consumption during the day.'
		;

-- id # 5 (toy-original)
INSERT INTO training_sets ( demand_scenario_id, study_start_year, years_per_period, number_of_periods, exclude_peaks, months_between_samples, start_month, hours_between_samples, start_hour, selection_method, notes ) 
	select 1 as demand_scenario_id, 2011, 3, 6, 
		false, 12, 1, 4, 0, 
		'MEDIAN', 
		'For each month, the day with peak load and a representative day with near-median load were selected. The peak day was selected system-wide, while the median was based on total consumption during the day.'
		;
		
-- update number_of_timepoints
UPDATE training_sets
	SET number_of_timepoints = number_of_periods * (2 - CASE WHEN exclude_peaks THEN 1 ELSE 0 END) * 
		FLOOR(12/months_between_samples) * FLOOR(24/hours_between_samples)
		WHERE number_of_timepoints IS NULL;


select define_new_training_sets();


-- SWITCH US code:
-- insert ignore into scenarios_v2 (
-- 	training_set_id, regional_cost_multiplier_scenario_id, regional_fuel_cost_scenario_id, 
-- 	gen_price_scenario_id, enable_rps, enable_carbon_cap )
-- 	SELECT 
-- 		training_set_id, 
-- 	  1 as regional_cost_multiplier_scenario_id,
-- 		1 as regional_fuel_cost_scenario_id,
-- 		1 as gen_price_scenario_id,
-- 		enable_rps,
-- 		enable_carbon_cap
-- 	FROM training_sets, 
-- 	(
-- 		SELECT 0 AS enable_rps UNION
-- 		SELECT 1
-- 	) AS rps_permutations,
-- 	(
-- 		SELECT 0 AS enable_carbon_cap UNION
-- 		SELECT 1
-- 	) AS carbon_cap_permutations
-- ;
-- 



