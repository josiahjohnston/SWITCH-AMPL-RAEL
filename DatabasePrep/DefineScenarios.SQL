USE switch_inputs_wecc_v2_2;

-- Simple example of defining a new scenarios:
-- INSERT INTO scenarios ( training_set_id,exclude_peaks,exclude_periods,period_reduced_by,regional_cost_multiplier_scenario_id,regional_fuel_cost_scenario_id,regional_gen_price_scenario_id,months_between_samples,start_month,hours_between_samples,start_hour,enable_rps )
--   SELECT 
--     1 as training_set_id, 
--     0 as exclude_peaks, 
--     "" exclude_periods, 
--     1 period_reduced_by,
--     1 as regional_cost_multiplier_scenario_id,
--     1 as regional_fuel_cost_scenario_id,
--     1 as regional_gen_price_scenario_id,
--     12 months_between_samples,
--     0 start_month,
--     12 hours_between_samples,
--     0 start_hour,
--     1 enable_rps
-- ;
-- set @latest_greatest_scenario := (select max( scenario_id ) from scenarios);
-- -- This function sets the _datesample, _timesample, _hours_in_sample, num_timepoints, and scenario_name fields for records in the table with ids greater than or equal to 1.
-- SELECT set_scenarios_sql_columns( @latest_greatest_scenario ) as `Number of New Scenarios`;



DROP PROCEDURE IF EXISTS make_many_scenarios_for_all_training_sets;
DELIMITER $$
CREATE PROCEDURE make_many_scenarios_for_all_training_sets()
BEGIN

-- create a tmp table off of which to go through the training sets loop
drop table if exists training_sets_tmp;
create table training_sets_tmp as select * from training_sets;

-- start the loop to define training sets
    make_many_scenarios_for_all_training_sets_loop: LOOP

-- find what training_set_id we're going to be using
select 
	@training_set_id := training_set_id,
	@base_year := base_year,
	@years_per_period := years_per_period,
	@number_of_periods := number_of_periods
from (select * from training_sets_tmp limit 1) as training_sets_tmp_top_row;

-- TODO: should be made more general... this only excludes two periods
set @first_period_to_exclude = @base_year;
set @second_period_to_exclude = @base_year + 2 * @years_per_period;


	INSERT IGNORE INTO scenarios ( training_set_id,exclude_peaks,exclude_periods,period_reduced_by,regional_cost_multiplier_scenario_id,regional_fuel_cost_scenario_id,regional_gen_price_scenario_id,months_between_samples,start_month,hours_between_samples,start_hour,enable_rps )
	  SELECT 
	    @training_set_id, 
	    0 as exclude_peaks, 
	    "" as exclude_periods, 
	    1 as period_reduced_by,
	    1 as regional_cost_multiplier_scenario_id,
	    1 as regional_fuel_cost_scenario_id,
	    1 as regional_gen_price_scenario_id,
	    12 months_between_samples,
	    start_month,
	    hours_between_samples,
	    start_hour,
	    enable_rps
	  FROM 
	        
	     (SELECT  0 AS start_month UNION
	      SELECT  1 AS start_month
	     ) as month_subselect, 
	    
	    (SELECT * from 
	       (SELECT  4 AS hours_between_samples) as mo,
	       (SELECT  0 AS start_hour UNION
	        SELECT  1 AS start_hour UNION
	        SELECT  2 AS start_hour UNION
	        SELECT  3 AS start_hour
	       ) as sm
	     UNION
	     SELECT * from 
	       (SELECT 2 AS hours_between_samples) as mo,
	       (SELECT 0 AS start_hour UNION
	        SELECT 1 AS start_hour
	       ) as sm
	     UNION
	     SELECT 1 AS hours_between_samples, 0 AS start_hour 
	    ) as hour_subselect,
	
	    (SELECT 0 AS enable_rps
	       UNION
	     SELECT 1 AS enable_rps
	    ) AS rps_setting;
	-- -------
	INSERT IGNORE INTO scenarios ( training_set_id,exclude_peaks,exclude_periods,period_reduced_by,regional_cost_multiplier_scenario_id,regional_fuel_cost_scenario_id,regional_gen_price_scenario_id,months_between_samples,start_month,hours_between_samples,start_hour,enable_rps )
	  SELECT 
	    @training_set_id, 
	    0 as exclude_peaks, 
	    "" as exclude_periods, 
	    1 as period_reduced_by,
	    1 as regional_cost_multiplier_scenario_id,
	    1 as regional_fuel_cost_scenario_id,
	    1 as regional_gen_price_scenario_id,
	    6 months_between_samples,
	    start_month,
	    hours_between_samples,
	    start_hour,
	    enable_rps
	  FROM 
	        
	     (SELECT  0 AS start_month UNION
	      SELECT  1 AS start_month
	     ) as month_subselect, 
	    
	    (SELECT * from 
	       (SELECT  4 AS hours_between_samples) as mo,
	       (SELECT  0 AS start_hour UNION
	        SELECT  1 AS start_hour UNION
	        SELECT  2 AS start_hour UNION
	        SELECT  3 AS start_hour
	       ) as sm
	     UNION
	     SELECT * from 
	       (SELECT 2 AS hours_between_samples) as mo,
	       (SELECT 0 AS start_hour UNION
	        SELECT 1 AS start_hour
	       ) as sm
	     UNION
	     SELECT 1 AS hours_between_samples, 0 AS start_hour 
	    ) as hour_subselect,
	
	    (SELECT 0 AS enable_rps
	       UNION
	     SELECT 1 AS enable_rps
	    ) AS rps_setting;
	-- -------
	INSERT IGNORE INTO scenarios ( training_set_id,exclude_peaks,exclude_periods,period_reduced_by,regional_cost_multiplier_scenario_id,regional_fuel_cost_scenario_id,regional_gen_price_scenario_id,months_between_samples,start_month,hours_between_samples,start_hour,enable_rps )
	  SELECT 
	    @training_set_id, 
	    0 as exclude_peaks, 
	    "" as exclude_periods, 
	    1 as period_reduced_by,
	    1 as regional_cost_multiplier_scenario_id,
	    1 as regional_fuel_cost_scenario_id,
	    1 as regional_gen_price_scenario_id,
	    4 months_between_samples,
	    start_month,
	    hours_between_samples,
	    start_hour,
	    enable_rps
	  FROM 
	        
	     (SELECT  0 AS start_month UNION
	      SELECT  1 AS start_month
	     ) as month_subselect, 
	    
	    (SELECT * from 
	       (SELECT  4 AS hours_between_samples) as mo,
	       (SELECT  0 AS start_hour UNION
	        SELECT  1 AS start_hour UNION
	        SELECT  2 AS start_hour UNION
	        SELECT  3 AS start_hour
	       ) as sm
	     UNION
	     SELECT * from 
	       (SELECT 2 AS hours_between_samples) as mo,
	       (SELECT 0 AS start_hour UNION
	        SELECT 1 AS start_hour
	       ) as sm
	     UNION
	     SELECT 1 AS hours_between_samples, 0 AS start_hour 
	    ) as hour_subselect,
	
	    (SELECT 0 AS enable_rps
	       UNION
	     SELECT 1 AS enable_rps
	    ) AS rps_setting;
	-- -------
	INSERT IGNORE INTO scenarios ( training_set_id,exclude_peaks,exclude_periods,period_reduced_by,regional_cost_multiplier_scenario_id,regional_fuel_cost_scenario_id,regional_gen_price_scenario_id,months_between_samples,start_month,hours_between_samples,start_hour,enable_rps )
	  SELECT 
	    @training_set_id, 
	    0 as exclude_peaks, 
	    "" as exclude_periods, 
	    1 as period_reduced_by,
	    1 as regional_cost_multiplier_scenario_id,
	    1 as regional_fuel_cost_scenario_id,
	    1 as regional_gen_price_scenario_id,
	    2 months_between_samples,
	    start_month,
	    hours_between_samples,
	    start_hour,
	    enable_rps
	  FROM 
	        
	     (SELECT  0 AS start_month UNION
	      SELECT  1 AS start_month
	     ) as month_subselect, 
	    
	    (SELECT * from 
	       (SELECT  4 AS hours_between_samples) as mo,
	       (SELECT  0 AS start_hour UNION
	        SELECT  1 AS start_hour UNION
	        SELECT  2 AS start_hour UNION
	        SELECT  3 AS start_hour
	       ) as sm
	     UNION
	     SELECT * from 
	       (SELECT 2 AS hours_between_samples) as mo,
	       (SELECT 0 AS start_hour UNION
	        SELECT 1 AS start_hour
	       ) as sm
	     UNION
	     SELECT 1 AS hours_between_samples, 0 AS start_hour 
	    ) as hour_subselect,
	
	    (SELECT 0 AS enable_rps
	       UNION
	     SELECT 1 AS enable_rps
	    ) AS rps_setting;
	-- -------
	INSERT IGNORE INTO scenarios ( training_set_id,exclude_peaks,exclude_periods,period_reduced_by,regional_cost_multiplier_scenario_id,regional_fuel_cost_scenario_id,regional_gen_price_scenario_id,months_between_samples,start_month,hours_between_samples,start_hour,enable_rps )
	  SELECT 
	    @training_set_id, 
	    0 as exclude_peaks, 
	    "" as exclude_periods, 
	    1 as period_reduced_by,
	    1 as regional_cost_multiplier_scenario_id,
	    1 as regional_fuel_cost_scenario_id,
	    1 as regional_gen_price_scenario_id,
	    1 months_between_samples,
	    start_month,
	    hours_between_samples,
	    start_hour,
	    enable_rps
	  FROM 
	        
	     (SELECT  0 AS start_month
	     ) as month_subselect, 
	    
	    (SELECT * from 
	       (SELECT  4 AS hours_between_samples) as mo,
	       (SELECT  0 AS start_hour UNION
	        SELECT  1 AS start_hour UNION
	        SELECT  2 AS start_hour UNION
	        SELECT  3 AS start_hour
	       ) as sm
	     UNION
	     SELECT * from 
	       (SELECT 2 AS hours_between_samples) as mo,
	       (SELECT 0 AS start_hour UNION
	        SELECT 1 AS start_hour
	       ) as sm
	     UNION
	     SELECT 1 AS hours_between_samples, 0 AS start_hour 
	    ) as hour_subselect,
	
	    (SELECT 0 AS enable_rps
	       UNION
	     SELECT 1 AS enable_rps
	    ) AS rps_setting;

	-- add in some period exclusions ------------
	INSERT IGNORE INTO scenarios ( training_set_id,exclude_peaks,exclude_periods,period_reduced_by,regional_cost_multiplier_scenario_id,regional_fuel_cost_scenario_id,regional_gen_price_scenario_id,months_between_samples,start_month,hours_between_samples,start_hour,enable_rps )
	  SELECT 
	    @training_set_id, 
	    0 as exclude_peaks, 
	    concat(@first_period_to_exclude, ',', @second_period_to_exclude) as exclude_periods, 
	    2 as period_reduced_by,
	    1 as regional_cost_multiplier_scenario_id,
	    1 as regional_fuel_cost_scenario_id,
	    1 as regional_gen_price_scenario_id,
	    12 months_between_samples,
	    start_month,
	    hours_between_samples,
	    start_hour,
	    enable_rps
	  FROM 
	        
	     (SELECT  0 AS start_month UNION
	      SELECT  1 AS start_month
	     ) as month_subselect, 
	    
	    (SELECT * from 
	       (SELECT  4 AS hours_between_samples) as mo,
	       (SELECT  0 AS start_hour UNION
	        SELECT  1 AS start_hour UNION
	        SELECT  2 AS start_hour UNION
	        SELECT  3 AS start_hour
	       ) as sm
	     UNION
	     SELECT * from 
	       (SELECT 2 AS hours_between_samples) as mo,
	       (SELECT 0 AS start_hour UNION
	        SELECT 1 AS start_hour
	       ) as sm
	     UNION
	     SELECT 1 AS hours_between_samples, 0 AS start_hour 
	    ) as hour_subselect,
	
	    (SELECT 0 AS enable_rps
	       UNION
	     SELECT 1 AS enable_rps
	    ) AS rps_setting;
	-- -------
	INSERT IGNORE INTO scenarios ( training_set_id,exclude_peaks,exclude_periods,period_reduced_by,regional_cost_multiplier_scenario_id,regional_fuel_cost_scenario_id,regional_gen_price_scenario_id,months_between_samples,start_month,hours_between_samples,start_hour,enable_rps )
	  SELECT 
	    @training_set_id, 
	    0 as exclude_peaks, 
	    concat(@first_period_to_exclude, ',', @second_period_to_exclude) as exclude_periods, 
	    2 as period_reduced_by,
	    1 as regional_cost_multiplier_scenario_id,
	    1 as regional_fuel_cost_scenario_id,
	    1 as regional_gen_price_scenario_id,
	    6 months_between_samples,
	    start_month,
	    hours_between_samples,
	    start_hour,
	    enable_rps
	  FROM 
	        
	     (SELECT  0 AS start_month UNION
	      SELECT  1 AS start_month
	     ) as month_subselect, 
	    
	    (SELECT * from 
	       (SELECT  4 AS hours_between_samples) as mo,
	       (SELECT  0 AS start_hour UNION
	        SELECT  1 AS start_hour UNION
	        SELECT  2 AS start_hour UNION
	        SELECT  3 AS start_hour
	       ) as sm
	     UNION
	     SELECT * from 
	       (SELECT 2 AS hours_between_samples) as mo,
	       (SELECT 0 AS start_hour UNION
	        SELECT 1 AS start_hour
	       ) as sm
	     UNION
	     SELECT 1 AS hours_between_samples, 0 AS start_hour 
	    ) as hour_subselect,
	
	    (SELECT 0 AS enable_rps
	       UNION
	     SELECT 1 AS enable_rps
	    ) AS rps_setting;
	-- -------


		

-- now we're done with that training set
delete from training_sets_tmp where training_set_id = @training_set_id;
    
IF ( (select count(*) from training_sets_tmp) = 0 )
    THEN LEAVE make_many_scenarios_for_all_training_sets_loop;
        END IF;
END LOOP make_many_scenarios_for_all_training_sets_loop;

END;
$$
delimiter ;

-- excute the procedure
CALL make_many_scenarios_for_all_training_sets();
DROP PROCEDURE make_many_scenarios_for_all_training_sets;




-- This function sets the _datesample, _timesample, _hours_in_sample, num_timepoints, and scenario_name fields for records in the table with ids greater than or equal to 1.
SELECT set_scenarios_sql_columns( 1 ) as `Number of New Scenarios`;
