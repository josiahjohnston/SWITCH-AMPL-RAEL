
-- capacity each period
replace into _gen_cap_summary_tech_test (scenario_id, carbon_cost, period, technology_id, capacity, capital_cost, o_m_cost_total)
  select 	scenario_id, carbon_cost, period, technology_id,
  			sum(capacity) as capacity, 
  			sum(capital_cost) as capital_cost, 
  			sum(fixed_o_m_cost) as o_m_cost_total
	from _gen_cap_summary_tech_la 
    where scenario_id = @scenario_id
    group by 2, 3, 4
    order by 2, 3, 4;

drop temporary table if exists tfuel_carbon_sum_table;
create temporary table tfuel_carbon_sum_table
	select carbon_cost, period, technology_id,
				sum(variable_o_m_cost * hours_in_sample) as variable_o_m_cost,		
				sum(fuel_cost * hours_in_sample) as fuel_cost,
				sum(carbon_cost_incurred * hours_in_sample) as carbon_cost_total
			from _dispatch_weekly
		    where scenario_id = @scenario_id
		    group by 1, 2, 3;
alter table tfuel_carbon_sum_table add index fcst_idx (carbon_cost, period, technology_id);

update _gen_cap_summary_tech_test s, tfuel_carbon_sum_table t
	set
		s.o_m_cost_total    = s.o_m_cost_total + t.variable_o_m_cost,
		s.fuel_cost         = t.fuel_cost,
		s.carbon_cost_total = t.carbon_cost_total
  where s.scenario_id   = @scenario_id
		and s.carbon_cost   = t.carbon_cost
		and s.period        = t.period
		and s.technology_id = t.technology_id;


set @number_of_years_per_period := (select (max(period)-min(period))/(count(distinct period) - 1 ) from switch_inputs_wecc_v2_2.study_dates_all);
set @num_historic_years := (select count( distinct year(date_utc)) from switch_inputs_wecc_v2_2.dispatch_weeks);
create table if not exists test_sys_load_summary (
	select period, 
	sum( power(1.01, period + @number_of_years_per_period/2 - year(datetime_utc))*power) * (@number_of_years_per_period/@num_historic_years)
		as load_in_period_mwh 
	from switch_inputs_wecc_v2_2.system_load l join switch_inputs_wecc_v2_2.dispatch_weeks h on (h.hournum=l.hour)
	group by 1);

replace into power_cost_test (scenario_id, carbon_cost, period, load_in_period_mwh )
  select 	scenario_id,
  			carbon_cost,
  			period,
  			load_in_period_mwh
  from system_load_summary join test_sys_load_summary using (period)
  where scenario_id = @scenario_id
  order by 1,2,3;


  
-- now calculated a bunch of costs

-- local_td costs
update power_cost_test set existing_local_td_cost =
	(select sum(fixed_cost) from _local_td_cap t
		where t.scenario_id = @scenario_id 
		and t.carbon_cost = power_cost_test.carbon_cost and t.period = power_cost_test.period and 
		new = 0 )
	where scenario_id = @scenario_id;

update power_cost_test set new_local_td_cost =
	(select sum(fixed_cost) from _local_td_cap t
		where t.scenario_id = @scenario_id 
		and t.carbon_cost = power_cost_test.carbon_cost and t.period = power_cost_test.period and 
		new = 1 )
	where scenario_id = @scenario_id;

-- transmission costs
update power_cost_test set existing_transmission_cost =
	(select sum(existing_trans_cost) from _existing_trans_cost_and_rps_reduced_cost t
		where t.scenario_id = @scenario_id 
		and t.carbon_cost = power_cost_test.carbon_cost and t.period = power_cost_test.period )
	where scenario_id = @scenario_id;

update power_cost_test set new_transmission_cost =
	(select sum(fixed_cost) from _trans_cap t
		where t.scenario_id = @scenario_id 
		and t.carbon_cost = power_cost_test.carbon_cost and t.period = power_cost_test.period and 
		new = 1 )
	where scenario_id = @scenario_id;

-- generation costs
update power_cost_test set existing_plant_sunk_cost =
	(select sum(capital_cost) from _gen_cap_summary_tech_test g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = power_cost_test.carbon_cost and g.period = power_cost_test.period and 
		technology_id	in (select technology_id from technologies where can_build_new = 0) )
	where scenario_id = @scenario_id;

update power_cost_test set existing_plant_operational_cost =
	(select sum(o_m_cost_total) from _gen_cap_summary_tech_test g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = power_cost_test.carbon_cost and g.period = power_cost_test.period and 
		technology_id	in (select technology_id from technologies where can_build_new = 0) )
	where scenario_id = @scenario_id;

update power_cost_test set new_coal_nonfuel_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) from _gen_cap_summary_tech_test g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = power_cost_test.carbon_cost and g.period = power_cost_test.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Coal' and can_build_new = 1) )
	where scenario_id = @scenario_id;

update power_cost_test set coal_fuel_cost =
	(select sum(fuel_cost) from _gen_cap_summary_tech_test g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = power_cost_test.carbon_cost and g.period = power_cost_test.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Coal') )
	where scenario_id = @scenario_id;

update power_cost_test set new_gas_nonfuel_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) from _gen_cap_summary_tech_test g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = power_cost_test.carbon_cost and g.period = power_cost_test.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Gas' and can_build_new = 1) )
	where scenario_id = @scenario_id;

update power_cost_test set gas_fuel_cost =
	(select sum(fuel_cost) from _gen_cap_summary_tech_test g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = power_cost_test.carbon_cost and g.period = power_cost_test.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Gas') )
	where scenario_id = @scenario_id;

update power_cost_test set new_nuclear_nonfuel_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) from _gen_cap_summary_tech_test g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = power_cost_test.carbon_cost and g.period = power_cost_test.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Uranium' and can_build_new = 1) )
	where scenario_id = @scenario_id;

update power_cost_test set nuclear_fuel_cost =
	(select sum(fuel_cost) from _gen_cap_summary_tech_test g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = power_cost_test.carbon_cost and g.period = power_cost_test.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Uranium') )
	where scenario_id = @scenario_id;

update power_cost_test set new_geothermal_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _gen_cap_summary_tech_test g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = power_cost_test.carbon_cost and g.period = power_cost_test.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Geothermal' and can_build_new = 1 ) )
	where scenario_id = @scenario_id;

update power_cost_test set new_bio_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _gen_cap_summary_tech_test g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = power_cost_test.carbon_cost and g.period = power_cost_test.period and 
		technology_id	in (select technology_id from technologies where fuel in ('Bio_Gas', 'Bio_Solid') and can_build_new = 1 ) )
	where scenario_id = @scenario_id;

update power_cost_test set new_wind_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _gen_cap_summary_tech_test g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = power_cost_test.carbon_cost and g.period = power_cost_test.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Wind' and can_build_new = 1 ) )
	where scenario_id = @scenario_id;

update power_cost_test set new_solar_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _gen_cap_summary_tech_test g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = power_cost_test.carbon_cost and g.period = power_cost_test.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Solar' and can_build_new = 1 ) )
	where scenario_id = @scenario_id;

update power_cost_test set carbon_cost_total =
	(select sum(carbon_cost_total) from _gen_cap_summary_tech_test g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = power_cost_test.carbon_cost and g.period = power_cost_test.period )
	where scenario_id = @scenario_id;

update power_cost_test set total_cost =
	existing_local_td_cost + new_local_td_cost + existing_transmission_cost + new_transmission_cost
	+ existing_plant_sunk_cost + existing_plant_operational_cost + new_coal_nonfuel_cost + coal_fuel_cost
	+ new_gas_nonfuel_cost + gas_fuel_cost + new_nuclear_nonfuel_cost + nuclear_fuel_cost
	+ new_geothermal_cost + new_bio_cost + new_wind_cost + new_solar_cost + carbon_cost_total
	where scenario_id = @scenario_id;

update power_cost_test set cost_per_mwh = total_cost / load_in_period_mwh
	where scenario_id = @scenario_id;
