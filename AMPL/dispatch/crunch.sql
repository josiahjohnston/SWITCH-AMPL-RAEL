SET @first_period := (
  SELECT study_start_year 
  FROM switch_inputs_wecc_v2_2.scenarios_v3 
    JOIN switch_inputs_wecc_v2_2.training_sets USING (training_set_id) 
  WHERE scenario_id=@scenario_id);
SET @hours_per_period = (
  SELECT SUM(hours_in_sample) 
    FROM switch_inputs_wecc_v2_2.scenarios_v3 JOIN
         switch_inputs_wecc_v2_2.training_sets USING (training_set_id) JOIN
         switch_inputs_wecc_v2_2.dispatch_test_sets USING (training_set_id) 
    WHERE scenario_id=@scenario_id AND periodnum = 0);

-- Make an updated list of capacity in each period. 
-- Start by clearing out any old entries. 
DELETE FROM _gen_cap_dispatch_update where scenario_id = @scenario_id;
-- Next, copy the projects that needed extra capacity according to the dispatch check. 
INSERT INTO _gen_cap_dispatch_update
  SELECT scenario_id, carbon_cost, period, area_id, technology_id, project_id, 
    max(updated_capacity) as capacity, max(capital_cost) as capital_cost, max(fixed_o_m_cost) as fixed_o_m_cost 
  from _dispatch_extra_cap
  where scenario_id = @scenario_id and period >= @first_period
  group by 1, 2, 3, 4, 5, 6
  order by 1, 2, 3, 4, 5, 6;
-- Next, insert all of the remaining projects. The IGNORE clause will prevent any of these from overwriting the ones we just inserted. 
INSERT IGNORE INTO _gen_cap_dispatch_update
  select scenario_id, carbon_cost, period, area_id, technology_id, project_id, capacity, capital_cost, fixed_o_m_cost 
  from _gen_cap
  where scenario_id = @scenario_id and period >= @first_period;


-- Summarize each period / technology combo. Set O&M total cost to the fixed component for now. Will add variable costs a few lines down.
delete from _dispatch_gen_cap_summary_tech_v2 where scenario_id = @scenario_id;
insert into _dispatch_gen_cap_summary_tech_v2 (scenario_id, carbon_cost, period, technology_id, capacity, capital_cost, o_m_cost_total)
  select 	scenario_id, carbon_cost, period, technology_id,
  			sum(_gen_cap_dispatch_update.capacity), 
  			sum(_gen_cap_dispatch_update.capital_cost), 
  			sum(_gen_cap_dispatch_update.fixed_o_m_cost)
	from _gen_cap_dispatch_update 
  where _gen_cap_dispatch_update.scenario_id = @scenario_id 
  group by 1, 2, 3, 4
  order by 1, 2, 3, 4;

-- Update summary table entries for projects that got retired early and will consequently have no dispatch decisions
update _dispatch_gen_cap_summary_tech_v2 s
	set
		s.energy                     = 0,
		s.spinning_reserve          = 0,
		s.quickstart_capacity       = 0,
		s.total_operating_reserve   = 0,
		s.deep_cycling_amount       = 0,
		s.mw_started_up             = 0,
		s.fuel_cost                 = 0,
		s.carbon_cost_total         = 0,
		s.co2_tons                  = 0,
		s.spinning_co2_tons         = 0,
		s.deep_cycling_co2_tons     = 0,
		s.startup_co2_tons          = 0,
    s.total_co2_tons            = 0
  where s.scenario_id = @scenario_id
    and capacity=0;

-- Calculate the totals of dispatch and variable costs by period & technology
drop temporary table if exists temp_sum_table;
create temporary table temp_sum_table
	select carbon_cost, period, technology_id,
				sum(power * hours_in_sample) as energy,
				sum(spinning_reserve * hours_in_sample) as spinning_reserve,
				sum(quickstart_capacity * hours_in_sample) as quickstart_capacity,
				sum(total_operating_reserve * hours_in_sample) as total_operating_reserve,
				sum(deep_cycling_amount * hours_in_sample) as deep_cycling_amount,
				sum(mw_started_up * hours_in_sample) as mw_started_up,
				sum(variable_o_m_cost * hours_in_sample) as variable_o_m_cost,		
				sum(fuel_cost * hours_in_sample) as fuel_cost,
				sum(carbon_cost_incurred * hours_in_sample) as carbon_cost_total,
				sum(co2_tons * hours_in_sample) as co2_tons,		
				sum(spinning_co2_tons * hours_in_sample) as spinning_co2_tons,		
				sum(deep_cycling_co2_tons * hours_in_sample) as deep_cycling_co2_tons,
				sum(startup_co2_tons * hours_in_sample) as startup_co2_tons
			from _dispatch_decisions
		    where scenario_id = @scenario_id
		    group by 1, 2, 3;
alter table temp_sum_table add index fcst_idx (carbon_cost, period, technology_id);

-- Copy the variable costs into the summary table
update _dispatch_gen_cap_summary_tech_v2 s, temp_sum_table t
	set
		s.energy                    = t.energy,
		s.spinning_reserve          = t.spinning_reserve,
		s.quickstart_capacity       = t.quickstart_capacity,
		s.total_operating_reserve   = t.total_operating_reserve,
		s.deep_cycling_amount       = t.deep_cycling_amount,
		s.mw_started_up             = t.mw_started_up,
		s.o_m_cost_total            = s.o_m_cost_total + t.variable_o_m_cost,
		s.fuel_cost                 = t.fuel_cost,
		s.carbon_cost_total         = t.carbon_cost_total,
		s.co2_tons                  = t.co2_tons,
		s.spinning_co2_tons         = t.spinning_co2_tons,
		s.deep_cycling_co2_tons     = t.deep_cycling_co2_tons,
		s.startup_co2_tons          = t.startup_co2_tons,
    s.total_co2_tons            = t.co2_tons + t.spinning_co2_tons + t.deep_cycling_co2_tons + t.startup_co2_tons
  where s.scenario_id   = @scenario_id
		and s.carbon_cost   = t.carbon_cost
		and s.period        = t.period
		and s.technology_id = t.technology_id;

-- Calculate the average values from the sums
update _dispatch_gen_cap_summary_tech_v2 
  set
    avg_power = energy / @hours_per_period,
    avg_spinning_reserve = spinning_reserve / @hours_per_period,
    avg_quickstart_capacity = quickstart_capacity / @hours_per_period,
    avg_total_operating_reserve = total_operating_reserve / @hours_per_period,
    avg_deep_cycling_amount = deep_cycling_amount / @hours_per_period,
    avg_mw_started_up = mw_started_up / @hours_per_period,
    avg_co2_tons = co2_tons / @hours_per_period,
    avg_spinning_co2_tons = spinning_co2_tons / @hours_per_period,
    avg_deep_cycling_co2_tons = deep_cycling_co2_tons / @hours_per_period,
    avg_startup_co2_tons = startup_co2_tons / @hours_per_period,
    avg_total_co2_tons = total_co2_tons / @hours_per_period
  where scenario_id = @scenario_id;

-- Make a new record for the system-wide power cost in each period. Populate the cost fields down below.
delete from _dispatch_power_cost where scenario_id = @scenario_id;
insert into _dispatch_power_cost (scenario_id, carbon_cost, period, load_in_period_mwh )
  select scenario_id, carbon_cost, period, load_in_period_mwh
  from (
    select distinct scenario_id, carbon_cost, period from _dispatch_gen_cap_summary_tech_v2
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
	(select sum(capital_cost) from _dispatch_gen_cap_summary_tech_v2 g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where can_build_new = 0) )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set existing_plant_operational_cost =
	(select sum(o_m_cost_total) from _dispatch_gen_cap_summary_tech_v2 g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where can_build_new = 0) )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set new_coal_nonfuel_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) from _dispatch_gen_cap_summary_tech_v2 g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Coal' and can_build_new = 1) )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set coal_fuel_cost =
	(select sum(fuel_cost) from _dispatch_gen_cap_summary_tech_v2 g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Coal') )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set new_gas_nonfuel_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) from _dispatch_gen_cap_summary_tech_v2 g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Gas' and can_build_new = 1) )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set gas_fuel_cost =
	(select sum(fuel_cost) from _dispatch_gen_cap_summary_tech_v2 g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Gas') )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set new_nuclear_nonfuel_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) from _dispatch_gen_cap_summary_tech_v2 g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Uranium' and can_build_new = 1) )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set nuclear_fuel_cost =
	(select sum(fuel_cost) from _dispatch_gen_cap_summary_tech_v2 g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Uranium') )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set new_geothermal_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _dispatch_gen_cap_summary_tech_v2 g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Geothermal' and can_build_new = 1 ) )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set new_bio_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _dispatch_gen_cap_summary_tech_v2 g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel in ('Bio_Gas', 'Bio_Solid') and can_build_new = 1 ) )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set new_wind_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _dispatch_gen_cap_summary_tech_v2 g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Wind' and can_build_new = 1 ) )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set new_solar_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _dispatch_gen_cap_summary_tech_v2 g
		where g.scenario_id = @scenario_id 
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Solar' and can_build_new = 1 ) )
	where scenario_id = @scenario_id;

update _dispatch_power_cost set new_storage_nonfuel_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) from _dispatch_gen_cap_summary_tech_v2 g
		where g.scenario_id = _dispatch_power_cost.scenario_id
		and g.carbon_cost = _dispatch_power_cost.carbon_cost and g.period = _dispatch_power_cost.period and 
		technology_id	in (select technology_id from technologies where storage = 1 and can_build_new = 1 ) )
where scenario_id = @scenario_id;

update _dispatch_power_cost set carbon_cost_total =
	(select sum(carbon_cost_total) from _dispatch_gen_cap_summary_tech_v2 g
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

-- see WECC_Plants_For_Emissions in the Switch_Input_Data folder for a calculation of the yearly 1990 emissions from WECC
set @co2_tons_1990 := 284800000;
set @years_per_period := (
SELECT years_per_period 
  FROM switch_inputs_wecc_v2_2.scenarios_v3 
    JOIN switch_inputs_wecc_v2_2.training_sets USING (training_set_id)
	WHERE scenario_id = @scenario_id);

delete from dispatch_co2_cc where scenario_id = @scenario_id;
insert into dispatch_co2_cc 
	select 	scenario_id,
			carbon_cost,
			period,
			sum( ( co2_tons + spinning_co2_tons + deep_cycling_co2_tons + startup_co2_tons ) ) / @years_per_period as co2_tons, 
     		@co2_tons_1990 - sum( ( co2_tons + spinning_co2_tons + deep_cycling_co2_tons + startup_co2_tons ) ) / @years_per_period as co2_tons_reduced_1990,
    		1 - ( sum( ( co2_tons + spinning_co2_tons + deep_cycling_co2_tons + startup_co2_tons ) ) / @years_per_period ) / @co2_tons_1990 as co2_share_reduced_1990
  	from 	_dispatch_gen_cap_summary_tech_v2 
  	where 	scenario_id = @scenario_id
  	group by 1, 2, 3
  	order by 1, 2, 3;

-- Average directed transmission..
-- the sum is still needed in the trans_direction_table as there could be different fuel types transmitted
create temporary table trans_direction_table_tmp
  select carbon_cost, period, send_id, receive_id,
    sum( hours_in_sample * ( ( power_sent + power_received ) / 2 ) ) 
      / @hours_per_period as average_transmission
  from _dispatch_transmission_decisions 
  where scenario_id = @scenario_id 
  group by 1,2,3,4
  UNION
  select 	carbon_cost, period, receive_id as send_id, send_id as receive_id,
    -1 * sum( hours_in_sample * ( ( power_sent + power_received ) / 2 ) ) 
      / @hours_per_period as average_transmission
  from _dispatch_transmission_decisions 
  where scenario_id = @scenario_id 
  group by 1,2,3,4;
alter table trans_direction_table_tmp
  add key (carbon_cost, period, send_id, receive_id);

create temporary table avg_trans_table
  select carbon_cost, period, send_id, receive_id,
    sum(average_transmission) as average_transmission
  from trans_direction_table_tmp
  group by 1,2,3,4;
alter table avg_trans_table 
  add primary key (carbon_cost, period, send_id, receive_id);

create temporary table directed_trans_table
  select distinct carbon_cost, period,
    if(average_transmission > 0, send_id, receive_id) as send_id,
    if(average_transmission > 0, receive_id, send_id) as receive_id,
    abs(average_transmission) as directed_trans_avg
  from avg_trans_table;
alter table directed_trans_table 
  add primary key (carbon_cost, period, send_id, receive_id);

DELETE FROM _dispatch_transmission_avg_directed where scenario_id = @scenario_id;
insert into _dispatch_transmission_avg_directed
select 	@scenario_id, carbon_cost, period, transmission_line_id, send_id, receive_id,
		round( directed_trans_avg ) as directed_trans_avg
from	transmission_lines tl, directed_trans_table
where directed_trans_table.send_id = tl.start_id and
      directed_trans_table.receive_id = tl.end_id
order by 1, 2, 3, 4, 5, 6;
