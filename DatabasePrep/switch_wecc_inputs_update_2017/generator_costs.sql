

-- Updating capital costs


-- select technology, period_start as period, overnight_cost, storage_energy_capacity_cost_per_mwh, fixed_o_m, var_o_m as variable_o_m_by_year 
-- from generator_costs_yearly 
-- join generator_info_v2 g using (technology), 
-- training_set_periods 
-- join training_sets using(training_set_id) 
-- where year = FLOOR( period_start + years_per_period / 2) - g.construction_time_years 
-- and period_start >= g.construction_time_years + $BASE_YEAR 
-- and	period_start >= g.min_online_year 
-- and gen_costs_scenario_id=$GEN_COSTS_SCENARIO_ID 
-- and gen_info_scenario_id=$GEN_INFO_SCENARIO_ID 
-- and training_set_id=$TRAINING_SET_ID 
-- UNION 
-- select technology, $BASE_YEAR as period, overnight_cost, storage_energy_capacity_cost_per_mwh, fixed_o_m, var_o_m as variable_o_m_by_year from generator_costs_yearly 
-- where year = $BASE_YEAR 
-- and gen_costs_scenario_id=$GEN_COSTS_SCENARIO_ID 
-- order by technology, period;

select * from generator_costs_yearly where gen_costs_scenario_id = 10 limit 99999;

select * from generator_info_v2;


create table generator_costs_yearly_v3 (like generator_costs_yearly);

select * from generator_costs_yearly_v3;

insert into generator_costs_yearly_v3
select gen_costs_scenario_id, technology, year, overnight_cost * 1.15, fixed_o_m * 1.15, var_o_m * 1.15, storage_energy_capacity_cost_per_mwh * 1.15
from generator_costs_yearly;

alter table generator_costs_yearly_v3 add column notes VARCHAR(300);

update generator_costs_yearly_v3 set notes = 'Values from generator_costs_yearly but in US$ 2016';

-- ----------------------------------------------------------------------------------------------------------------------------------------------
-- ----------------------------------------------------------------------------------------------------------------------------------------------

create table generator_info_v3 like generator_info_v2;

select * from generator_info_v3;

-- 1.15 is the inflation between 2007 and 2016 for the US dollar ($1 in 2007 = $1.15 in 2016)
insert into generator_info_v3
select gen_info_scenario_id, technology_id, technology, prime_mover, min_online_year, fuel, 1.15 * connect_cost_per_mw_generic, heat_rate, construction_time_years,
year_1_cost_fraction, year_2_cost_fraction, year_3_cost_fraction, year_4_cost_fraction, year_5_cost_fraction, year_6_cost_fraction, max_age_years, forced_outage_rate, 
scheduled_outage_rate, intermittent, distributed, resource_limited, baseload, flexible_baseload, dispatchable, cogen, min_build_capacity, can_build_new, competes_for_space,
ccs, storage, storage_efficiency, max_store_rate, max_spinning_reserve_fraction_of_capacity, heat_rate_penalty_spinning_reserve, minimum_loading, deep_cycling_penalty,
startup_mmbtu_per_mw, 1.15 * startup_cost_dollars_per_mw, 1.15 * connect_cost_per_mw_generic_archive 
from generator_info_v2;

alter table generator_info_v3 add column notes VARCHAR(300);

update generator_info_v3 set notes = 'Values from generator_info_v2 but in US$ 2016';



