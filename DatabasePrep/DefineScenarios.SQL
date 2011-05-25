-- Add additional methods of sample selection to this file.
-- You can either add specific permutations individually, or add entries to the *_permutations table that will be expanded combinatorially.
USE switch_inputs_wecc_v2_2;

set @BAU_load_scenario_id := 1;

-- Example of defining a single training set:
INSERT IGNORE INTO training_sets ( load_scenario_id, study_start_year, years_per_period, number_of_periods, exclude_peaks, months_between_samples, start_month, hours_between_samples, start_hour, selection_method, notes ) 
	VALUES @BAU_load_scenario_id, 2015, 10, 4, 
		0, 12, 12, 4, 0, 
		'MEDIAN', 
		'For each month, the day with peak load and a representative day with near-median load were selected. The peak day was selected system-wide, while the median was based on total consumption during the day.'
;
CALL define_new_training_sets();

-- Define many training sets using all permutations of subsampling parameters given below.
set @BAU_load_scenario_id := 1;
INSERT IGNORE INTO training_sets ( load_scenario_id, study_start_year, years_per_period, number_of_periods, exclude_peaks, months_between_samples, start_month, hours_between_samples, start_hour, selection_method, notes ) 
	SELECT @BAU_load_scenario_id as load_scenario_id, study_start_year, years_per_period, number_of_periods, 
		0 as exclude_peaks, months_between_samples, start_month, hours_between_samples, start_hour, 
		'MEDIAN' as selection_method, 
		'For each month, the day with peak load and a representative day with near-median load were selected. The peak day was selected system-wide, while the median was based on total consumption during the day.' as notes
	FROM 

	(
		SELECT 2014 as study_start_year, 4 as years_per_period, 4 as number_of_periods UNION
		SELECT 2015, 10, 4 UNION
		SELECT 2018, 8 , 2 UNION
		SELECT 2025, 20, 2
	) AS period_permutations,

	(	
		SELECT 12 AS months_between_samples, 1 AS start_month UNION
		SELECT 6, 1 UNION
		SELECT 4, 1 UNION
		SELECT 2, 1 UNION
		SELECT 2, 2 UNION
		SELECT 1, 1
	) AS month_permutations, 

	(
		SELECT 4 AS hours_between_samples, 0 AS start_hour UNION
		SELECT 4, 1 UNION
		SELECT 4, 2 UNION
		SELECT 4, 3 UNION
		SELECT 2, 0 UNION
		SELECT 2, 1 UNION
		SELECT 1, 0
	) AS hour_permutations
;


CALL define_new_training_sets();


insert ignore into scenarios_v2 (
	training_set_id, regional_cost_multiplier_scenario_id, regional_fuel_cost_scenario_id, 
	gen_price_scenario_id, enable_rps, enable_carbon_cap )
	SELECT 
		training_set_id, 
	  1 as regional_cost_multiplier_scenario_id,
		1 as regional_fuel_cost_scenario_id,
		1 as gen_price_scenario_id,
		enable_rps,
		enable_carbon_cap
	FROM training_sets, 
	(
		SELECT 0 AS enable_rps UNION
		SELECT 1
	) AS rps_permutations,
	(
		SELECT 0 AS enable_carbon_cap UNION
		SELECT 1
	) AS carbon_cap_permutations
;
