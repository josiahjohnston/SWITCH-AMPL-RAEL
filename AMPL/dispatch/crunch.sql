-- Make an updated list of capacity in each period. 
-- Start by clearing out any old entries. 
DELETE FROM _gen_cap_dispatch_update where scenario_id = @scenario_id;
-- Next, copy the projects that needed extra capacity according to the dispatch check. 
INSERT INTO _gen_cap_dispatch_update
  SELECT scenario_id, carbon_cost, period, area_id, technology_id, project_id, 
    max(updated_capacity) as capacity, max(capital_cost) as capital_cost, max(fixed_o_m_cost) as fixed_o_m_cost 
  from _dispatch_extra_cap
  where scenario_id = @scenario_id
  group by 1, 2, 3, 4, 5, 6
  order by 1, 2, 3, 4, 5, 6;
-- Next, insert all of the remaining projects. The IGNORE clause will prevent any of these from overwriting the ones we just inserted. 
INSERT IGNORE INTO _gen_cap_dispatch_update
  select scenario_id, carbon_cost, period, area_id, technology_id, project_id, capacity, capital_cost, fixed_o_m_cost 
  from _gen_cap
  where scenario_id = @scenario_id;

-- Summarize each period / technology combo. Set O&M total cost to the fixed component for now. Will add variable costs a few lines down.
delete from _dispatch_gen_cap_summary_tech where scenario_id = @scenario_id;
insert into _dispatch_gen_cap_summary_tech (scenario_id, carbon_cost, period, technology_id, capacity, capital_cost, o_m_cost_total)
  select 	scenario_id, carbon_cost, period, technology_id,
  			sum(_gen_cap_dispatch_update.capacity), 
  			sum(_gen_cap_dispatch_update.capital_cost), 
  			sum(_gen_cap_dispatch_update.fixed_o_m_cost)
	from _gen_cap_dispatch_update 
  where _gen_cap_dispatch_update.scenario_id = @scenario_id
  group by 1, 2, 3, 4
  order by 1, 2, 3, 4;

-- Calculate the total variable costs by period & technology
drop temporary table if exists tfuel_carbon_sum_table;
create temporary table tfuel_carbon_sum_table
	select carbon_cost, period, technology_id,
				sum(variable_o_m_cost * hours_in_sample) as variable_o_m_cost,		
				sum(fuel_cost * hours_in_sample) as fuel_cost,
				sum(carbon_cost_incurred * hours_in_sample) as carbon_cost_total
			from _dispatch_decisions
		    where scenario_id = @scenario_id
		    group by 1, 2, 3;
alter table tfuel_carbon_sum_table add index fcst_idx (carbon_cost, period, technology_id);

-- Copy the variable costs into the summary table
update _dispatch_gen_cap_summary_tech s, tfuel_carbon_sum_table t
	set
		s.o_m_cost_total    = s.o_m_cost_total + t.variable_o_m_cost,
		s.fuel_cost         = t.fuel_cost,
		s.carbon_cost_total = t.carbon_cost_total
  where s.scenario_id   = @scenario_id
		and s.carbon_cost   = t.carbon_cost
		and s.period        = t.period
		and s.technology_id = t.technology_id;

-- Make a new record for the system-wide power cost in each period. Populate the cost fields down below.
delete from _dispatch_power_cost where scenario_id = @scenario_id;
insert into _dispatch_power_cost (scenario_id, carbon_cost, period, load_in_period_mwh )
  select scenario_id, carbon_cost, period, load_in_period_mwh
  from (
    select distinct scenario_id, carbon_cost, period from _dispatch_gen_cap_summary_tech
      where scenario_id = @scenario_id
  ) as distinct_scenario_carbon_cost_period_combos 
    JOIN switch_inputs_wecc_v2_2.scenarios_v3 USING (scenario_id)
    JOIN switch_inputs_wecc_v2_2._dispatch_load_summary using (training_set_id,period)
  order by 1,2,3;


  
-- now calculated a bunch of costs

-- local_td costs
update _dispatch_power_cost set existing_local_td_cost =
	(select sum(fixed_cost) from _local_td_cap t
		where t.scenario_id = @scenario_id 
		and t.carbon_cost = _dispatch_power_cost.carbon_cost and t.period = _dispatch_power_cost.period and 
		new = 0 )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set new_local_td_cost =
	(select sum(fixed_cost) from _local_td_cap t
		where t.scenario_id = @scenario_id 
		and t.carbon_cost = _dispatch_power_cost.carbon_cost and t.period = _dispatch_power_cost.period and 
		new = 1 )
	where scenario_id = @scenario_id;

-- transmission costs
update _dispatch_power_cost set existing_transmission_cost =
	(select sum(existing_trans_cost) from _existing_trans_cost t
		where t.scenario_id = @scenario_id 
		and t.carbon_cost = _dispatch_power_cost.carbon_cost and t.period = _dispatch_power_cost.period )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set new_transmission_cost =
	(select sum(fixed_cost) from _trans_cap t
		where t.scenario_id = @scenario_id 
		and t.carbon_cost = _dispatch_power_cost.carbon_cost and t.period = _dispatch_power_cost.period and 
		new = 1 )
	where scenario_id = @scenario_id;

-- generation costs
update _dispatch_power_cost set existing_plant_sunk_cost =
	(select sum(capital_cost) from _dispatch_gen_cap_summary_tech g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where can_build_new = 0) )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set existing_plant_operational_cost =
	(select sum(o_m_cost_total) from _dispatch_gen_cap_summary_tech g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where can_build_new = 0) )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set new_coal_nonfuel_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) from _dispatch_gen_cap_summary_tech g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Coal' and can_build_new = 1) )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set coal_fuel_cost =
	(select sum(fuel_cost) from _dispatch_gen_cap_summary_tech g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Coal') )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set new_gas_nonfuel_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) from _dispatch_gen_cap_summary_tech g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Gas' and can_build_new = 1) )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set gas_fuel_cost =
	(select sum(fuel_cost) from _dispatch_gen_cap_summary_tech g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Gas') )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set new_nuclear_nonfuel_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) from _dispatch_gen_cap_summary_tech g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Uranium' and can_build_new = 1) )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set nuclear_fuel_cost =
	(select sum(fuel_cost) from _dispatch_gen_cap_summary_tech g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Uranium') )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set new_geothermal_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _dispatch_gen_cap_summary_tech g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Geothermal' and can_build_new = 1 ) )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set new_bio_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _dispatch_gen_cap_summary_tech g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel in ('Bio_Gas', 'Bio_Solid') and can_build_new = 1 ) )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set new_wind_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _dispatch_gen_cap_summary_tech g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Wind' and can_build_new = 1 ) )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set new_solar_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _dispatch_gen_cap_summary_tech g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Solar' and can_build_new = 1 ) )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set new_storage_nonfuel_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) from _dispatch_gen_cap_summary_tech g
		where g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from technologies where storage = 1 and can_build_new = 1 ) )
where scenario_id = @scenario_id;

update _dispatch_power_cost set carbon_cost_total =
	(select sum(carbon_cost_total) from _dispatch_gen_cap_summary_tech g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set total_cost =
	existing_local_td_cost + new_local_td_cost + existing_transmission_cost + new_transmission_cost
	+ existing_plant_sunk_cost + existing_plant_operational_cost + new_coal_nonfuel_cost + coal_fuel_cost
	+ new_gas_nonfuel_cost + gas_fuel_cost + new_nuclear_nonfuel_cost + nuclear_fuel_cost
	+ new_geothermal_cost + new_bio_cost + new_wind_cost + new_solar_cost + new_storage_nonfuel_cost + carbon_cost_total
	where scenario_id = @scenario_id;

update _dispatch_power_cost set cost_per_mwh = total_cost / load_in_period_mwh
	where scenario_id = @scenario_id;
