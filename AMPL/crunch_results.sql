--#######################################################
-- Export results for graphing

-- Determine investment period length
set @first_period  := (select min( period) from gen_cap where scenario_id=@scenario_id);
set @second_period := (select min(period) from gen_cap where period != @first_period and scenario_id=@scenario_id);
set @period_length := (@second_period - @first_period);
set @last_period := (select max(period) from gen_cap where scenario_id=@scenario_id);

-- -------------------------------------

-- GENERATION AND STORAGE SUMMARIES--------
select 'Creating generation summaries' as progress;
-- total generation each hour by carbon cost, technology and load area
-- this table will be used extensively below to create summaries dependent on generator dispatch
-- note: technology_id and fuel are not quite redundant here as energy stored or released from storage comes in as fuel = 'storage'
replace into _gen_hourly_summary_tech_la
		(scenario_id, carbon_cost, period, area_id, study_date, study_hour, hours_in_sample, technology_id,
			variable_o_m_cost, fuel_cost, carbon_cost_incurred, co2_tons, power)
	select 	scenario_id, carbon_cost, period, area_id, study_date, study_hour, hours_in_sample, technology_id,
			sum(variable_o_m_cost), sum(fuel_cost), sum(carbon_cost_incurred), sum(co2_tons), sum(power)
    	from _generator_and_storage_dispatch
    	where scenario_id = @scenario_id
    group by 2, 3, 4, 5, 6, 7, 8
    order by 2, 3, 4, 5, 6, 7, 8;

-- add month and hour_of_day_UTC. 
update _gen_hourly_summary_tech_la
set	month = mod(floor(study_hour/100000),100),
	hour_of_day_UTC = mod(floor(study_hour/1000),100)
	where scenario_id = @scenario_id;


-- total generation each hour by carbon cost and technology
replace into _gen_hourly_summary_tech
	select scenario_id, carbon_cost, period, study_date, study_hour, hours_in_sample, month, hour_of_day_UTC, technology_id, sum(power) as power
		from _gen_hourly_summary_tech_la
		where scenario_id = @scenario_id
		group by 2, 3, 4, 5, 6, 7, 8, 9
		order by 2, 3, 4, 5, 6, 7, 8, 9;

-- find the total number of hours represented by each period for use in weighting hourly generation
set @sum_hourly_weights_per_period :=
	(SELECT sum( hours_in_sample ) from
		(select distinct study_hour, hours_in_sample
				from _gen_hourly_summary_tech
 			where 	scenario_id=@scenario_id and
					carbon_cost = (select carbon_cost from _gen_hourly_summary_tech where scenario_id=@scenario_id limit 1) and 
					period = (select period from _gen_hourly_summary_tech where scenario_id=@scenario_id limit 1)
		) as  distinct_hours_in_sample_table);

-- total generation each period by carbon cost, technology and load area
replace into _gen_summary_tech_la
  select scenario_id, carbon_cost, period, area_id, technology_id,
    	sum(power * hours_in_sample) / @sum_hourly_weights_per_period as avg_power
		from _gen_hourly_summary_tech_la
    	where scenario_id = @scenario_id
    	group by 2, 3, 4, 5
    	order by 2, 3, 4, 5;

-- total generation each period by carbon cost and technology
replace into _gen_summary_tech
	select scenario_id, carbon_cost, period, technology_id,	sum(avg_power) as avg_power
    from _gen_summary_tech_la
    where scenario_id = @scenario_id
    group by 2, 3, 4
    order by 2, 3, 4;


-- generation by fuel----------

-- total generation each hour by carbon cost, fuel and load area
replace into _gen_hourly_summary_fuel_la
	select scenario_id, carbon_cost, period, area_id, study_date, study_hour, hours_in_sample, month, hour_of_day_UTC, fuel, sum(power) as power
		from _gen_hourly_summary_tech_la join technologies using (technology_id)
		where scenario_id = @scenario_id
		group by 2, 3, 4, 5, 6, 7, 8, 9, 10
		order by 2, 3, 4, 5, 6, 7, 8, 9, 10;

-- total generation each hour by carbon cost and fuel
replace into _gen_hourly_summary_fuel
	select scenario_id, carbon_cost, period, study_date, study_hour, hours_in_sample, month, hour_of_day_UTC, fuel, sum(power) as power
		from _gen_hourly_summary_fuel_la
		where scenario_id = @scenario_id
		group by 2, 3, 4, 5, 6, 7, 8, 9
		order by 2, 3, 4, 5, 6, 7, 8, 9;
	
-- total generation each period by carbon cost, fuel and load area
replace into _gen_summary_fuel_la
  select scenario_id, carbon_cost, period, area_id, fuel,
    	sum(power * hours_in_sample) / @sum_hourly_weights_per_period as avg_power
		from _gen_hourly_summary_fuel_la
    	where scenario_id = @scenario_id
    	group by 2, 3, 4, 5
    	order by 2, 3, 4, 5;

-- total generation each period by carbon cost and fuel
replace into gen_summary_fuel
	select scenario_id, carbon_cost, period, fuel, sum(avg_power) as avg_power
    from _gen_summary_fuel_la
    where scenario_id = @scenario_id
    group by 2, 3, 4
    order by 2, 3, 4;



-- GENERATOR CAPACITY--------------

-- capacity each period by load area
replace into _gen_cap_summary_tech_la (scenario_id, carbon_cost, period, area_id, technology_id, capacity, capital_cost, fixed_o_m_cost)
  select 	scenario_id, carbon_cost, period, area_id, technology_id,
  			sum(capacity) as capacity, sum(capital_cost) as capital_cost, sum(fixed_o_m_cost) as fixed_o_m_cost
	from _gen_cap 
    where scenario_id = @scenario_id
    group by 2, 3, 4, 5
    order by 2, 3, 4, 5;

drop temporary table if exists tfuel_carbon_sum_table;
create temporary table tfuel_carbon_sum_table
	select		scenario_id, carbon_cost, period, area_id, technology_id,
				sum(variable_o_m_cost * hours_in_sample) as variable_o_m_cost,		
				sum(fuel_cost * hours_in_sample) as fuel_cost,
				sum(carbon_cost_incurred * hours_in_sample) as carbon_cost_total
			from _gen_hourly_summary_tech_la
		    where scenario_id = @scenario_id
		    group by 2, 3, 4, 5;
alter table tfuel_carbon_sum_table add index fcst_idx (scenario_id, carbon_cost, period, area_id, technology_id);
		   
update 	_gen_cap_summary_tech_la s, tfuel_carbon_sum_table t
set 	s.variable_o_m_cost = t.variable_o_m_cost,
		s.fuel_cost 		= t.fuel_cost,
		s.carbon_cost_total = t.carbon_cost_total
where 	s.scenario_id 		= t.scenario_id
and 	s.carbon_cost 		= t.carbon_cost
and 	s.period 			= t.period
and 	s.area_id 			= t.area_id
and 	s.technology_id 	= t.technology_id;

-- capacity each period
replace into _gen_cap_summary_tech
  select scenario_id, carbon_cost, period, technology_id,
    sum(capacity) as capacity, sum(capital_cost), sum(fixed_o_m_cost + variable_o_m_cost) as o_m_cost_total, sum(fuel_cost), sum(carbon_cost_total)
    from _gen_cap_summary_tech_la join technologies using (technology_id)
    where scenario_id = @scenario_id
    group by 2, 3, 4
    order by 2, 3, 4;


-- now aggregated on a fuel basis
replace into _gen_cap_summary_fuel_la 
  select 	scenario_id, carbon_cost, period, area_id, fuel,
  			sum(capacity) as capacity, sum(capital_cost) as capital_cost, sum(fixed_o_m_cost) as fixed_o_m_cost,
  			sum(variable_o_m_cost) as variable_o_m_cost, sum(fuel_cost) as fuel_cost, sum(carbon_cost_total) as carbon_cost_total
	from _gen_cap_summary_tech_la join technologies using (technology_id)
    where scenario_id = @scenario_id
    group by 2, 3, 4, 5
    order by 2, 3, 4, 5;

-- capacity each period
replace into gen_cap_summary_fuel
  select scenario_id, carbon_cost, period, fuel,
    sum(capacity) as capacity, sum(capital_cost), sum(fixed_o_m_cost + variable_o_m_cost) as o_m_cost_total, sum(fuel_cost), sum(carbon_cost_total)
    from _gen_cap_summary_fuel_la
    where scenario_id = @scenario_id
    group by 2, 3, 4
    order by 2, 3, 4;


-- TRANSMISSION ----------------
select 'Creating transmission summaries' as progress;

-- add helpful columns to _transmission_dispatch
update _transmission_dispatch
	set month = mod(floor(study_hour/100000),100),
		hour_of_day_UTC = mod(floor(study_hour/1000),100)
	where scenario_id = @scenario_id;


-- Transmission summary: net transmission for each zone in each hour
-- First add imports, then subtract exports
replace into _trans_summary (scenario_id, carbon_cost, period, area_id, study_date, study_hour, month, hour_of_day_UTC, hours_in_sample, net_power)
  select 	scenario_id,
  			carbon_cost,
  			period,
  			receive_id,
  			study_date,
  			study_hour,
  			month,
	 		hour_of_day_UTC,
	 		hours_in_sample,
	 		sum(power_received)
    from _transmission_dispatch
    where scenario_id = @scenario_id
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9
    order by 1, 2, 3, 4, 5, 6, 7, 8, 9;
insert into _trans_summary (scenario_id, carbon_cost, period, area_id, study_date, study_hour, month, hour_of_day_UTC, hours_in_sample, net_power)
  select 	scenario_id,
  			carbon_cost,
  			period,
  			send_id,
  			study_date,
  			study_hour,
  			month,
	 		hour_of_day_UTC,
  			hours_in_sample,
  			-1*sum(power_sent) as net_sent
    from _transmission_dispatch
    where scenario_id = @scenario_id
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9
    order by 1, 2, 3, 4, 5, 6, 7, 8, 9
  on duplicate key update net_power = net_power + VALUES(net_power);

-- Tally transmission losses using a similar method
replace into _trans_loss (scenario_id, carbon_cost, period, area_id, study_date, study_hour, month, hour_of_day_UTC, hours_in_sample, power)
  select 	scenario_id,
  			carbon_cost,
  			period,
  			send_id,
  			study_date,
  			study_hour,
  			month,
  			hour_of_day_UTC,
  			hours_in_sample,
  			sum(power_sent - power_received) as power
    from _transmission_dispatch
    where scenario_id = @scenario_id
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9
    order by 1, 2, 3, 4, 5, 6, 7, 8, 9;


-- directed transmission 
-- TODO: make some indexed temp tables to speed up these queries
-- the sum is still needed in the trans_direction_table as there could be different fuel types transmitted
replace into _transmission_directed_hourly ( scenario_id, carbon_cost, period, transmission_line_id, send_id, receive_id, study_hour, hour_of_day_UTC, directed_trans_avg )
select 	@scenario_id,
		carbon_cost,
		period,
		transmission_line_id,
		send_id,
		receive_id,
		study_hour,
		mod(floor(study_hour/1000),100) as hour_of_day_UTC,
		round( directed_trans_avg ) as directed_trans_avg
from	transmission_lines tl,

	(select distinct carbon_cost,
			period,
			study_hour,
			if(average_transmission > 0, send_id, receive_id) as send_id,
			if(average_transmission > 0, receive_id, send_id) as receive_id,
			abs(average_transmission) as directed_trans_avg
		from
			(select carbon_cost,
					period,
					study_hour,
					send_id,
					receive_id,
					sum(average_transmission) as average_transmission
				from 
					(select carbon_cost,
							period,
							study_hour,
							send_id,
							receive_id,
							sum( ( power_sent + power_received ) / 2 ) as average_transmission
						from _transmission_dispatch where scenario_id = @scenario_id
						UNION
					select 	carbon_cost,
							period,
							study_hour,
							receive_id as send_id,
							send_id as receive_id,
							sum( -1 * ( power_sent + power_received ) / 2 ) as average_transmission
						from _transmission_dispatch where scenario_id = @scenario_id
					) as trans_direction_table
				group by 1,2,3,4,5) as avg_trans_table
		) as directed_trans_table

where 	directed_trans_table.send_id = tl.start_id
and		directed_trans_table.receive_id = tl.end_id
order by 2,3,5,6,7;

update _transmission_directed_hourly set hour_of_day_UTC = mod(floor(study_hour/1000),100);

-- now do the same as above, but aggregated
-- TODO: could speed this up by referencing the above table
replace into _transmission_avg_directed
select 	@scenario_id,
		carbon_cost,
		period,
		transmission_line_id,
		send_id,
		receive_id,
		round( directed_trans_avg ) as directed_trans_avg
from	transmission_lines tl,

	(select distinct carbon_cost,
			period,
			if(average_transmission > 0, send_id, receive_id) as send_id,
			if(average_transmission > 0, receive_id, send_id) as receive_id,
			abs(average_transmission) as directed_trans_avg
		from
			(select carbon_cost,
					period,
					send_id,
					receive_id,
					sum(average_transmission) as average_transmission
				from 
					(select carbon_cost,
							period,
							send_id,
							receive_id,
							sum( hours_in_sample * ( ( power_sent + power_received ) / 2 ) ) / @sum_hourly_weights_per_period as average_transmission
						from _transmission_dispatch where scenario_id = @scenario_id group by 1,2,3,4
						UNION
					select 	carbon_cost,
							period,
							receive_id as send_id,
							send_id as receive_id,
							-1 * sum( hours_in_sample * ( ( power_sent + power_received ) / 2 ) ) / @sum_hourly_weights_per_period as average_transmission
						from _transmission_dispatch where scenario_id = @scenario_id group by 1,2,3,4
					) as trans_direction_table
				group by 1,2,3,4) as avg_trans_table
		) as directed_trans_table

where 	directed_trans_table.send_id = tl.start_id
and		directed_trans_table.receive_id = tl.end_id
order by 2,3,5,6;


-- CO2 Emissions --------------------
select 'Calculating CO2 emissions' as progress;
-- CALCULATE CO2 EMISSIONS IN 1990
-- 
-- 1990 CO2 Baseline Electricity Sector References: only CO2, not CO2e
-- Canada:
-- http://www.ec.gc.ca/pdb/ghg/inventory_report/2006_report/2006_report_e.pdf
-- Alberta: 53500000t
-- BC: 1450000t (hydro is king!)
-- 
-- US:
-- http://www.eia.doe.gov/cneaf/electricity/epa/epat5p1.html
-- Sum for AZ, CA, CO, ID, MT, NM, NV, OR, UT, WA, WY: 256855733t
-- 
-- Also have to add and subtract plants that are on the wrong side of the state borders,
-- i.e. are counted in the state but aren't in WECC or are in WECC but are not included in the state. 
-- Downloaded EIA form EIA-759 (has monthly generation and fuel consumption data) for 1990 and searched for plants that had the wrong NERC region for the state (i.e. the ones discussed above).
-- Cross referenced with the Ventyx map... seems like I got everything.  Converted fuel consumption to tCO2 emissions using conversion factors from http://www.eia.doe.gov/oiaf/1605/coefficients.html
-- http://www.eia.doe.gov/cneaf/electricity/page/eia906u.html
-- Emissions to be ADDED to WECC from these plants: 430000t
-- See WECC Plants for Emissions.xls in the paper folder.
-- 
-- Mexico:
-- http://www.epa.gov/ttn/chief/conference/ei18/session7/maldonado.pdf
-- http://www.epa.gov/region09/climatechange/pdfs/ghg-baja-executive-summary.pdf
-- The second source gives CO2 emissions for 2005 for Baja... this will have to do for now: 4,817.46 Gg = 4817460t
-- Demand has been going at 7.1% per year for the 10 years before 2005... assume it was for the 15 years... http://www.renewablesg.org/docs/Web/AppendixG.pdf
-- Now scale back to 1990 electricity demand: 4817460t * (1-0.071)^(2005-1990) = 1596076t
-- Total: 53500000t + 1450000t + 256855733t + 430000t + 1596076t = 313831809t CO2
set @co2_tons_1990 := 313831809;

-- find the base case (almost always $0/tCO2) emissions for reference
-- coded here as minimum of the carbon cost such that it doesn't break if there isn't a $0/tCO2 run
replace into co2_cc 
	select 	scenario_id,
			carbon_cost,
			_gen_hourly_summary_tech_la.period,
			sum( co2_tons * hours_in_sample ) / @period_length as co2_tons, 
    		base_co2_tons - sum( co2_tons * hours_in_sample ) / @period_length as co2_tons_reduced, 
   			1 - sum( co2_tons * hours_in_sample ) / @period_length / base_co2_tons as co2_share_reduced, 
    		@co2_tons_1990 - sum( co2_tons * hours_in_sample ) / @period_length as co2_tons_reduced_1990,
    		1 - sum( co2_tons * hours_in_sample ) / @period_length / @co2_tons_1990 as co2_share_reduced_1990
  	from 	_gen_hourly_summary_tech_la,
  			(select period,
					sum(co2_tons * hours_in_sample) / @period_length as base_co2_tons
				from _gen_hourly_summary_tech_la
				where carbon_cost = (select min(carbon_cost) from _gen_hourly_summary_tech_la where scenario_id = @scenario_id)
				and scenario_id = @scenario_id
				group by 1) as base_co2_tons_table
  	where 	scenario_id = @scenario_id
  	and		base_co2_tons_table.period = _gen_hourly_summary_tech_la.period
  	group by 2, 3
  	order by 2, 3;


-- SYSTEM COSTS ---------------
select 'Calculating system costs' as progress;
-- average power costs, for each study period, for each carbon tax
-- Matthias Note:(this should probably use a discounting method for the MWhs, 
-- since the costs are already discounted to the start of each period,
-- but electricity production is spread out over time. But the main model doesn't do that so I don't do it here either.)


-- update load data first
update _system_load
	set month = mod(floor(study_hour/100000),100),
		hour_of_day_UTC = mod(floor(study_hour/1000),100)
	where scenario_id = @scenario_id;

replace into system_load_summary
	select 	scenario_id,
			carbon_cost,
			period,
			sum( hours_in_sample * power ) / ( @sum_hourly_weights_per_period ) as system_load,
			sum( hours_in_sample * satisfy_load_reduced_cost ) / ( @sum_hourly_weights_per_period ) as satisfy_load_reduced_cost_weighted,
			sum( hours_in_sample * satisfy_load_reserve_reduced_cost ) / ( @sum_hourly_weights_per_period ) as satisfy_load_reserve_reduced_cost_weighted
	from _system_load
	where scenario_id = @scenario_id
	group by 2, 3
	order by 2, 3;

replace into power_cost (scenario_id, carbon_cost, period, load_in_period_mwh )
  select 	scenario_id,
  			carbon_cost,
  			period,
  			system_load * ( @sum_hourly_weights_per_period ) as load_in_period_mwh
  from system_load_summary
  where scenario_id = @scenario_id
  order by 1,2,3;
  
-- now calculated a bunch of costs

-- local_td costs
update power_cost set existing_local_td_cost =
	(select sum(fixed_cost) from _local_td_cap t
		where t.scenario_id = @scenario_id and t.scenario_id = power_cost.scenario_id
		and t.carbon_cost = power_cost.carbon_cost and t.period = power_cost.period and 
		new = 0 );

update power_cost set new_local_td_cost =
	(select sum(fixed_cost) from _local_td_cap t
		where t.scenario_id = @scenario_id and t.scenario_id = power_cost.scenario_id
		and t.carbon_cost = power_cost.carbon_cost and t.period = power_cost.period and 
		new = 1 );

-- transmission costs
update power_cost set existing_transmission_cost =
	(select sum(existing_trans_cost) from _existing_trans_cost_and_rps_reduced_cost t
		where t.scenario_id = @scenario_id and t.scenario_id = power_cost.scenario_id
		and t.carbon_cost = power_cost.carbon_cost and t.period = power_cost.period );

update power_cost set new_transmission_cost =
	(select sum(fixed_cost) from _trans_cap t
		where t.scenario_id = @scenario_id and t.scenario_id = power_cost.scenario_id
		and t.carbon_cost = power_cost.carbon_cost and t.period = power_cost.period and 
		new = 1 );

-- generation costs
update power_cost set existing_plant_sunk_cost =
	(select sum(capital_cost) from _gen_cap_summary_tech g
		where g.scenario_id = @scenario_id and g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from technologies where can_build_new = 0) );

update power_cost set existing_plant_operational_cost =
	(select sum(o_m_cost_total) from _gen_cap_summary_tech g
		where g.scenario_id = @scenario_id and g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from technologies where can_build_new = 0) );

update power_cost set new_coal_nonfuel_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) from _gen_cap_summary_tech g
		where g.scenario_id = @scenario_id and g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Coal' and can_build_new = 1) );

update power_cost set coal_fuel_cost =
	(select sum(fuel_cost) from _gen_cap_summary_tech g
		where g.scenario_id = @scenario_id and g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Coal') );

update power_cost set new_gas_nonfuel_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) from _gen_cap_summary_tech g
		where g.scenario_id = @scenario_id and g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Gas' and can_build_new = 1) );

update power_cost set gas_fuel_cost =
	(select sum(fuel_cost) from _gen_cap_summary_tech g
		where g.scenario_id = @scenario_id and g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Gas') );

update power_cost set new_nuclear_nonfuel_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) from _gen_cap_summary_tech g
		where g.scenario_id = @scenario_id and g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Uranium' and can_build_new = 1) );

update power_cost set nuclear_fuel_cost =
	(select sum(fuel_cost) from _gen_cap_summary_tech g
		where g.scenario_id = @scenario_id and g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Uranium') );

update power_cost set new_geothermal_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _gen_cap_summary_tech g
		where g.scenario_id = @scenario_id and g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Geothermal' and can_build_new = 1 ) );

update power_cost set new_bio_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _gen_cap_summary_tech g
		where g.scenario_id = @scenario_id and g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel in ('Bio_Gas', 'Bio_Solid') and can_build_new = 1 ) );

update power_cost set new_wind_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _gen_cap_summary_tech g
		where g.scenario_id = @scenario_id and g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Wind' and can_build_new = 1 ) );

update power_cost set new_solar_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _gen_cap_summary_tech g
		where g.scenario_id = @scenario_id and g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from technologies where fuel = 'Solar' and can_build_new = 1 ) );

update power_cost set carbon_cost_total =
	(select sum(carbon_cost_total) from _gen_cap_summary_tech g
		where g.scenario_id = @scenario_id and g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period );

update power_cost set total_cost =
	existing_local_td_cost + new_local_td_cost + existing_transmission_cost + new_transmission_cost
	+ existing_plant_sunk_cost + existing_plant_operational_cost + new_coal_nonfuel_cost + coal_fuel_cost
	+ new_gas_nonfuel_cost + gas_fuel_cost + new_nuclear_nonfuel_cost + nuclear_fuel_cost
	+ new_geothermal_cost + new_bio_cost + new_wind_cost + new_solar_cost + carbon_cost_total
	where scenario_id = @scenario_id;

update power_cost set cost_per_mwh = total_cost / load_in_period_mwh
	where scenario_id = @scenario_id;
