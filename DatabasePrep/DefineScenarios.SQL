USE switch_inputs_wecc_v2;

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



INSERT INTO scenarios ( training_set_id,exclude_peaks,exclude_periods,period_reduced_by,regional_cost_multiplier_scenario_id,regional_fuel_cost_scenario_id,regional_gen_price_scenario_id,months_between_samples,start_month,hours_between_samples,start_hour,enable_rps )
  SELECT 
    1 as training_set_id, 
    0 as exclude_peaks, 
    exclude_periods, 
    period_reduced_by,
    1 as regional_cost_multiplier_scenario_id,
    1 as regional_fuel_cost_scenario_id,
    1 as regional_gen_price_scenario_id,
    months_between_samples,
    start_month,
    hours_between_samples,
    start_hour,
    enable_rps
  FROM 
    (SELECT "2010,2018" AS exclude_periods, 2 AS period_reduced_by
       UNION
     SELECT "" AS exclude_periods, 1 AS period_reduced_by
    ) AS period_subselect,
    
    (SELECT * from 
       (SELECT 12 AS months_between_samples) as mo,
       (SELECT  0 AS start_month UNION
        SELECT  2 AS start_month UNION
        SELECT  4 AS start_month UNION
        SELECT  6 AS start_month UNION
        SELECT  8 AS start_month UNION
        SELECT 10 AS start_month
       ) as sm
     UNION
     SELECT * from 
       (SELECT 6 AS months_between_samples) as mo,
       (SELECT 0 AS start_month UNION
        SELECT 2 AS start_month UNION
        SELECT 4 AS start_month
       ) as sm
     UNION
     SELECT * from 
       (SELECT 4 AS months_between_samples) as mo,
       (SELECT 0 AS start_month UNION
        SELECT 2 AS start_month
       ) as sm
     UNION
     SELECT * from 
       (SELECT 3 AS months_between_samples) as mo,
       (SELECT 0 AS start_month UNION
        SELECT 1 AS start_month UNION
        SELECT 2 AS start_month
       ) as sm
     UNION
     SELECT * from 
       (SELECT 2 AS months_between_samples) as mo,
       (SELECT 0 AS start_month UNION
        SELECT 1 AS start_month
       ) as sm
     UNION
     SELECT 1 AS months_between_samples, 0 AS start_month 
    ) as month_subselect, 
    
    (SELECT * from 
       (SELECT 12 AS hours_between_samples) as mo,
       (SELECT  0 AS start_hour UNION
        SELECT  2 AS start_hour UNION
        SELECT  4 AS start_hour UNION
        SELECT  6 AS start_hour UNION
        SELECT  8 AS start_hour UNION
        SELECT 10 AS start_hour
       ) as sm
     UNION
     SELECT * from 
       (SELECT 6 AS hours_between_samples) as mo,
       (SELECT 0 AS start_hour UNION
        SELECT 2 AS start_hour UNION
        SELECT 4 AS start_hour
       ) as sm
     UNION
     SELECT * from 
       (SELECT 4 AS hours_between_samples) as mo,
       (SELECT 0 AS start_hour UNION
        SELECT 2 AS start_hour
       ) as sm
     UNION
     SELECT * from 
       (SELECT 3 AS hours_between_samples) as mo,
       (SELECT 0 AS start_hour UNION
        SELECT 1 AS start_hour UNION
        SELECT 2 AS start_hour
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
    
-- This function sets the _datesample, _timesample, _hours_in_sample, num_timepoints, and scenario_name fields for records in the table with ids greater than or equal to 1.
SELECT set_scenarios_sql_columns( 1 ) as `Number of New Scenarios`;
