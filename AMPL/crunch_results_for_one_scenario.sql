-- #######################################################
-- This is to be done, file is not ready yet
--
-- #######################################################
-- First, function to handle the scenario id
CREATE OR REPLACE FUNCTION chile.get_scenario() RETURNS int AS $$
-- This function is useless right now. The idea would it be that reads the environment variable @SCENARIO_ID instead
-- but I couldn't find a way to do it from plpgsql
-- Another chance is to pass at least the path, so its more flexible. Don't know how to do that either.

    declare output integer;
	
    BEGIN
	
	--drop table if exists chile.temp_scenario;
	--create table chile.temp_scenario(scenario int);
	--copy chile.temp_scenario from '/Volumes/switch/Users/pehidalg/Switch_Chile/Switch_chile_files_by_Paty/1018_carbon_cap_11MT_revised/AMPL/scenario_id.txt';

	select * from chile.temp_scenario limit 1 into output;
	--select 1 from chile.temp_scenario limit 1 into output;
	
	RETURN output;
	
    END;
$$ LANGUAGE plpgsql;


-- Export results for graphing
set search_path to chile, public;

-- GENERATION AND STORAGE SUMMARIES--------
select 'Creating generation summaries' as progress;
-- total generation each hour by carbon cost, technology and load area
-- this table will be used extensively below to create summaries dependent on generator dispatch
-- note: technology_id and fuel are not quite redundant here as energy stored or released from storage comes in as fuel = 'storage'

insert into chile._gen_hourly_summary_tech_la
		(scenario_id, carbon_cost, period, area_id, study_date, study_hour, hours_in_sample, technology_id, fuel,
			variable_o_m_cost, fuel_cost, carbon_cost_incurred, co2_tons, power,
			spinning_fuel_cost, spinning_carbon_cost_incurred, spinning_co2_tons, spinning_reserve, quickstart_capacity, total_operating_reserve, deep_cycling_amount, deep_cycling_fuel_cost, deep_cycling_carbon_cost, deep_cycling_co2_tons, total_co2_tons)
select 	scenario_id, carbon_cost, period, area_id, study_date, study_hour, hours_in_sample, technology_id, fuel,
			sum(variable_o_m_cost), sum(fuel_cost), sum(carbon_cost_incurred), sum(co2_tons), sum(power),
			sum(spinning_fuel_cost), sum(spinning_carbon_cost_incurred), sum(spinning_co2_tons), sum(spinning_reserve), sum(quickstart_capacity), sum(total_operating_reserve), sum(deep_cycling_amount), sum(deep_cycling_fuel_cost), sum(deep_cycling_carbon_cost), sum(deep_cycling_co2_tons),
			sum(co2_tons + spinning_co2_tons + deep_cycling_co2_tons) as total_co2_tons
from 	chile._generator_and_storage_dispatch
where scenario_id = (select * from chile.temp_scenario limit 1)
group by 1, 2, 3, 4, 5, 6, 7, 8, 9
order by 1, 2, 3, 4, 5, 6, 7, 8, 9;

-- add month and hour_of_day_UTC. 
update chile._gen_hourly_summary_tech_la
set		month = substring(study_date::varchar from 5 for 2)::smallint,
		hour_of_day_UTC = substring(study_hour::varchar from 9 for 2)::smallint
		where scenario_id = (select * from chile.temp_scenario limit 1);


-- total generation each hour by carbon cost and technology

insert into _gen_hourly_summary_tech ( scenario_id, carbon_cost, period, study_date, study_hour, hours_in_sample, month, hour_of_day_UTC, technology_id,
				power, co2_tons, spinning_reserve, spinning_co2_tons, quickstart_capacity, total_operating_reserve, deep_cycling_amount, deep_cycling_co2_tons, total_co2_tons )
	select scenario_id, carbon_cost, period, study_date, study_hour, hours_in_sample, month, hour_of_day_UTC, technology_id,
	sum(power) as power, sum(co2_tons) as co2_tons,
	sum(spinning_reserve) as spinning_reserve, sum(spinning_co2_tons) as spinning_co2_tons,
	sum(quickstart_capacity) as quickstart_capacity, sum(total_operating_reserve) as total_operating_reserve,
	sum(deep_cycling_amount) as deep_cycling_amount, sum(deep_cycling_co2_tons) as deep_cycling_co2_tons,
	sum(total_co2_tons) as total_co2_tons
		from _gen_hourly_summary_tech_la
		where scenario_id = (select * from chile.temp_scenario limit 1) 
		group by 1, 2, 3, 4, 5, 6, 7, 8, 9
		order by 1, 2, 3, 4, 5, 6, 7, 8, 9;

-- find the total number of hours represented by each period for use in weighting hourly generation

insert into sum_hourly_weights_per_period_table ( scenario_id, period, sum_hourly_weights_per_period, years_per_period )
	select 	scenario_id,
			period,
			sum(hours_in_sample) as sum_hourly_weights_per_period,
			sum(hours_in_sample)/8766 as years_per_period
		from
			(SELECT distinct
					scenario_id,
					period,
					study_hour,
					hours_in_sample
				from _gen_hourly_summary_tech
				where scenario_id = (select * from chile.temp_scenario limit 1) ) as distinct_hours_table
		group by scenario_id, period;

-- total generation each period by carbon cost, technology and load area

insert into _gen_summary_tech_la ( scenario_id, carbon_cost, period, area_id, technology_id, avg_power, avg_co2_tons,
				avg_spinning_reserve, avg_spinning_co2_tons, avg_quickstart_capacity, avg_total_operating_reserve, avg_deep_cycling_amount, avg_deep_cycling_co2_tons, avg_total_co2_tons )
  select scenario_id, carbon_cost, period, area_id, technology_id,
    	sum(power * hours_in_sample) / sum_hourly_weights_per_period as avg_power,
    	sum(co2_tons * hours_in_sample) / sum_hourly_weights_per_period as avg_co2_tons,
    	sum(spinning_reserve * hours_in_sample) / sum_hourly_weights_per_period as avg_spinning_reserve,
    	sum(spinning_co2_tons * hours_in_sample) / sum_hourly_weights_per_period as avg_spinning_co2_tons,
    	sum(quickstart_capacity * hours_in_sample) / sum_hourly_weights_per_period as avg_quickstart_capacity,
    	sum(total_operating_reserve * hours_in_sample) / sum_hourly_weights_per_period as avg_total_operating_reserve,
    	sum(deep_cycling_amount * hours_in_sample) / sum_hourly_weights_per_period as avg_deep_cycling_amount,
    	sum(deep_cycling_co2_tons * hours_in_sample) / sum_hourly_weights_per_period as avg_deep_cycling_co2_tons,
    	sum(total_co2_tons * hours_in_sample) / sum_hourly_weights_per_period as avg_total_co2_tons
		from _gen_hourly_summary_tech_la join sum_hourly_weights_per_period_table using (scenario_id, period)
    	where scenario_id = (select * from chile.temp_scenario limit 1) 
    	group by 1, 2, 3, 4, 5, sum_hourly_weights_per_period_table.sum_hourly_weights_per_period
    	order by 1, 2, 3, 4, 5;

-- total generation each period by carbon cost and technology
insert into _gen_summary_tech ( scenario_id, carbon_cost, period, technology_id, avg_power, avg_co2_tons,
				avg_spinning_reserve, avg_spinning_co2_tons, avg_quickstart_capacity, avg_total_operating_reserve, avg_deep_cycling_amount, avg_deep_cycling_co2_tons, avg_total_co2_tons )
	--insert into _gen_summary_tech
	select scenario_id, carbon_cost, period, technology_id,
	sum(avg_power) as avg_power, sum(avg_co2_tons) as avg_co2_tons,
	sum(avg_spinning_reserve) as avg_spinning_reserve, sum(avg_spinning_co2_tons) as avg_spinning_co2_tons,
	sum(avg_quickstart_capacity) as avg_quickstart_capacity, sum(avg_total_operating_reserve) as avg_total_operating_reserve,
	sum(avg_deep_cycling_amount) as avg_deep_cycling_amount,
	sum(avg_deep_cycling_co2_tons) as avg_deep_cycling_co2_tons,	
	sum(avg_total_co2_tons) as avg_total_co2_tons
    from _gen_summary_tech_la
    where scenario_id = (select * from chile.temp_scenario limit 1) 
    group by 1, 2, 3, 4
    order by 1, 2, 3, 4;


-- generation by fuel----------

-- total generation each hour by carbon cost, fuel and load area
insert into _gen_hourly_summary_fuel_la (scenario_id, carbon_cost, period, area_id, study_date, study_hour, hours_in_sample, month, hour_of_day_UTC, fuel,
					power, co2_tons, spinning_reserve, spinning_co2_tons, quickstart_capacity, total_operating_reserve, deep_cycling_amount, deep_cycling_co2_tons, total_co2_tons )

	select scenario_id, carbon_cost, period, area_id, study_date, study_hour, hours_in_sample, month, hour_of_day_UTC, fuel,
	sum(power) as power, sum(co2_tons) as co2_tons,
	sum(spinning_reserve) as spinning_reserve, sum(spinning_co2_tons) as spinning_co2_tons,
	sum(quickstart_capacity) as quickstart_capacity, sum(total_operating_reserve) as total_operating_reserve,
	sum(deep_cycling_amount) as deep_cycling_amount, sum(deep_cycling_co2_tons) as deep_cycling_co2_tons,
	sum(total_co2_tons) as total_co2_tons
	from _gen_hourly_summary_tech_la
	where scenario_id = (select * from chile.temp_scenario limit 1) 
	group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
	order by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10;

-- total generation each hour by carbon cost and fuel
insert into _gen_hourly_summary_fuel ( scenario_id, carbon_cost, period, study_date, study_hour, hours_in_sample, month, hour_of_day_UTC, fuel,
					power, co2_tons, spinning_reserve, spinning_co2_tons, quickstart_capacity, total_operating_reserve, deep_cycling_amount, deep_cycling_co2_tons, total_co2_tons )

	select scenario_id, carbon_cost, period, study_date, study_hour, hours_in_sample, month, hour_of_day_UTC, fuel,
	sum(power) as power,  sum(co2_tons) as co2_tons,
	sum(spinning_reserve) as spinning_reserve,  sum(spinning_co2_tons) as spinning_co2_tons,
	sum(quickstart_capacity) as quickstart_capacity, sum(total_operating_reserve) as total_operating_reserve,
	sum(deep_cycling_amount) as deep_cycling_amount, sum(deep_cycling_co2_tons) as deep_cycling_co2_tons,
	sum(total_co2_tons) as total_co2_tons
	
	from _gen_hourly_summary_fuel_la
	where scenario_id = (select * from chile.temp_scenario limit 1) 
	group by 1, 2, 3, 4, 5, 6, 7, 8, 9
	order by 1, 2, 3, 4, 5, 6, 7, 8, 9;
	
-- total generation each period by carbon cost, fuel and load area
insert into _gen_summary_fuel_la ( scenario_id, carbon_cost, period, area_id, fuel,
					avg_power, avg_co2_tons, avg_spinning_reserve, avg_spinning_co2_tons, avg_quickstart_capacity, avg_total_operating_reserve, avg_deep_cycling_amount, avg_deep_cycling_co2_tons, avg_total_co2_tons )

  select scenario_id, carbon_cost, period, area_id, fuel,
    	sum(power * hours_in_sample) / sum_hourly_weights_per_period as avg_power,
    	sum(co2_tons * hours_in_sample) / sum_hourly_weights_per_period as avg_co2_tons,
    	sum(spinning_reserve * hours_in_sample) / sum_hourly_weights_per_period as avg_spinning_reserve,
    	sum(spinning_co2_tons * hours_in_sample) / sum_hourly_weights_per_period as avg_spinning_co2_tons,
    	sum(quickstart_capacity * hours_in_sample) / sum_hourly_weights_per_period as avg_quickstart_capacity,
    	sum(total_operating_reserve * hours_in_sample) / sum_hourly_weights_per_period as avg_total_operating_reserve,
    	sum(deep_cycling_amount * hours_in_sample) / sum_hourly_weights_per_period as avg_deep_cycling_amount,
    	sum(deep_cycling_co2_tons * hours_in_sample) / sum_hourly_weights_per_period as avg_deep_cycling_co2_tons,
    	sum(total_co2_tons * hours_in_sample) / sum_hourly_weights_per_period as avg_total_co2_tons 	
		
		from _gen_hourly_summary_fuel_la join sum_hourly_weights_per_period_table using (scenario_id, period)
    	where scenario_id = (select * from chile.temp_scenario limit 1) 
    	group by 1, 2, 3, 4, 5, sum_hourly_weights_per_period_table.sum_hourly_weights_per_period
    	order by 1, 2, 3, 4, 5;

-- total generation each period by carbon cost and fuel
insert into gen_summary_fuel ( scenario_id, carbon_cost, period, fuel,
				avg_power, avg_co2_tons, avg_spinning_reserve, avg_spinning_co2_tons, avg_quickstart_capacity, avg_operating_reserve, avg_deep_cycling_amount, avg_deep_cycling_co2_tons, avg_total_co2_tons )

	select scenario_id, carbon_cost, period, fuel,
	sum(avg_power) as avg_power, sum(avg_co2_tons) as avg_co2_tons,
	sum(avg_spinning_reserve) as avg_spinning_reserve, sum(avg_spinning_co2_tons) as avg_spinning_co2_tons,
	sum(avg_quickstart_capacity) as avg_quickstart_capacity, sum(avg_total_operating_reserve) as avg_operating_reserve,
	sum(avg_deep_cycling_amount) as avg_deep_cycling_amount, 
	sum(avg_deep_cycling_co2_tons) as avg_deep_cycling_co2_tons,
	sum(avg_total_co2_tons) as avg_total_co2_tons
    
	from _gen_summary_fuel_la
    where scenario_id = (select * from chile.temp_scenario limit 1) 
    group by 1, 2, 3, 4
    order by 1, 2, 3, 4;



-- GENERATOR CAPACITY--------------

-- capacity each period by load area
insert into _gen_cap_summary_tech_la (scenario_id, carbon_cost, period, area_id, technology_id, capacity, capital_cost, fixed_o_m_cost)
 
  select 	scenario_id, carbon_cost, period, area_id, technology_id,
  			sum(capacity) as capacity, sum(capital_cost) as capital_cost, sum(fixed_o_m_cost) as fixed_o_m_cost
	
	from _gen_cap 
    where scenario_id = (select * from chile.temp_scenario limit 1) 
    group by 1, 2, 3, 4, 5
    order by 1, 2, 3, 4, 5;

--create temporary table tfuel_carbon_sum_table;
	--drop table if exists tfuel_carbon_sum_table cascade;
	delete from tfuel_carbon_sum_table;
	insert into tfuel_carbon_sum_table
	select		scenario_id, carbon_cost, period, area_id, technology_id,
				sum(variable_o_m_cost * hours_in_sample) as variable_o_m_cost,		
				sum( ( fuel_cost + spinning_fuel_cost + deep_cycling_fuel_cost ) * hours_in_sample) as fuel_cost,
				sum( ( carbon_cost_incurred + spinning_carbon_cost_incurred + deep_cycling_carbon_cost ) * hours_in_sample) as carbon_cost_total
	--into tfuel_carbon_sum_table
	from _gen_hourly_summary_tech_la
	where scenario_id = (select * from chile.temp_scenario limit 1) 
	group by 1, 2, 3, 4, 5;

--alter table tfuel_carbon_sum_table add index fcst_idx (scenario_id, carbon_cost, period, area_id, technology_id);
		   
update 	_gen_cap_summary_tech_la
set 	variable_o_m_cost 	= t.variable_o_m_cost,
		fuel_cost 			= t.fuel_cost,
		carbon_cost_total 	= t.carbon_cost_total
from 	tfuel_carbon_sum_table t
where 	_gen_cap_summary_tech_la.scenario_id 		= t.scenario_id
and 	_gen_cap_summary_tech_la.carbon_cost 		= t.carbon_cost
and 	_gen_cap_summary_tech_la.period 			= t.period
and 	_gen_cap_summary_tech_la.area_id 			= t.area_id
and 	_gen_cap_summary_tech_la.technology_id 		= t.technology_id;

-- capacity each period
-- carbon_cost column includes carbon costs incurred for power and spinning reserves
insert into _gen_cap_summary_tech

select scenario_id, carbon_cost, period, technology_id,
    sum(capacity) as capacity, sum(capital_cost) as capital_cost, sum(fixed_o_m_cost + variable_o_m_cost) as o_m_cost_total, 
	sum(fuel_cost) as fuel_cost, sum(carbon_cost_total) as carbon_cost_total

from _gen_cap_summary_tech_la join generator_info_v2 using (technology_id)
where scenario_id = (select * from chile.temp_scenario limit 1) 
group by 1, 2, 3, 4
order by 1, 2, 3, 4;

-- now aggregated on a fuel basis
insert into _gen_cap_summary_fuel_la 

select 	scenario_id, carbon_cost, period, area_id, fuel,
  			sum(capacity) as capacity, sum(capital_cost) as capital_cost, sum(fixed_o_m_cost) as fixed_o_m_cost,
  			sum(variable_o_m) as variable_o_m_cost, sum(fuel_cost) as fuel_cost, sum(carbon_cost_total) as carbon_cost_total

from _gen_cap_summary_tech_la join generator_info_v2 using (technology_id)
where scenario_id = (select * from chile.temp_scenario limit 1) 
group by 1, 2, 3, 4, 5
order by 1, 2, 3, 4, 5;

-- capacity each period
insert into gen_cap_summary_fuel

  select scenario_id, carbon_cost, period, fuel,
    sum(capacity) as capacity, sum(capital_cost) as capital_cost, sum(fixed_o_m_cost + variable_o_m_cost) as o_m_cost_total, 
	sum(fuel_cost) as fuel_cost, sum(carbon_cost_total) as carbon_cost_total

	from _gen_cap_summary_fuel_la
    where scenario_id = (select * from chile.temp_scenario limit 1) 
    group by 1, 2, 3, 4
    order by 1, 2, 3, 4;


-- TRANSMISSION ----------------
select 'Creating transmission summaries' as progress;
-- Make a simple transmission capacity table
insert into _trans_cap_summary
select scenario_id, carbon_cost, period, new, sum(trans_mw)/2 as capacity_mw, sum(fixed_cost) as cost
from _trans_cap
where scenario_id = (select * from chile.temp_scenario limit 1) 
group by 1,2,3,4
order by 1,2,3,4;

-- And by LA
insert into _trans_cap_la_summary
select scenario_id, carbon_cost, period, start_id, end_id, new, sum(trans_mw) as capacity_mw, sum(fixed_cost) as cost
from _trans_cap
where scenario_id = (select * from chile.temp_scenario limit 1) 
group by 1,2,3,4,5,6
order by 1,2,3,4,5,6;

-- Transmission summary: net transmission for each zone in each hour
-- NOTE: This table seems to be repeated with transmission_directed_hourly. Check if this one should have built capacity (from trans_cap) rather than dispatch.
-- First add imports, then subtract exports
--insert into _trans_summary (scenario_id, carbon_cost, period, area_id, study_date, study_hour, month, hour_of_day_UTC, hours_in_sample, net_power)

  select 	scenario_id,
  			carbon_cost,
  			period,
  			receive_id,
  			study_date,
  			study_hour,
  			substring(study_date::varchar from 5 for 2)::smallint as month,
	 		substring(study_hour::varchar from 9 for 2)::smallint as hour_of_day_UTC,
	 		hours_in_sample,
	 		sum(power_received) as net_power
    into _trans_summary_imp
	from _transmission_dispatch
    where scenario_id = (select * from chile.temp_scenario limit 1) 
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9
    order by 1, 2, 3, 4, 5, 6, 7, 8, 9;
	
  --drop table if exists _trans_summary_exp;
  insert into _trans_summary_imp
  select 	scenario_id,
  			carbon_cost,
  			period,
  			send_id,
  			study_date,
  			study_hour,
  			substring(study_date::varchar from 5 for 2)::smallint as month,
	 		substring(study_hour::varchar from 9 for 2)::smallint as hour_of_day_UTC,
	 		hours_in_sample,
	 		-sum(power_sent) as net_power
	from _transmission_dispatch
    where scenario_id = (select * from chile.temp_scenario limit 1) 
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9
    order by 1, 2, 3, 4, 5, 6, 7, 8, 9;

	--Put everything together
	insert into _trans_summary
    select 	scenario_id,
  			carbon_cost,
  			period,
  			receive_id,
  			study_date,
  			study_hour,
  			month,
	 		hour_of_day_UTC,
	 		hours_in_sample,
	 		sum(net_power)
    
    from _trans_summary_imp
    where scenario_id = (select * from chile.temp_scenario limit 1) 
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9
    order by 1, 2, 3, 4, 5, 6, 7, 8, 9;
	
	drop table if exists chile._trans_summary_imp cascade;

  --on duplicate key update net_power = net_power + VALUES(net_power);

-- Tally transmission losses using a similar method
  insert into _trans_loss (scenario_id, carbon_cost, period, send_id, study_date, study_hour, month, hour_of_day_UTC, hours_in_sample, power)
  
  select 	scenario_id,
  			carbon_cost,
  			period,
  			send_id,
  			study_date,
  			study_hour,
  			substring(study_date::varchar from 5 for 2)::smallint as month,
	 		substring(study_hour::varchar from 9 for 2)::smallint as hour_of_day_UTC,	 	
  			hours_in_sample,
  			sum(power_sent - power_received) as power
    
	from _transmission_dispatch
    where scenario_id = (select * from chile.temp_scenario limit 1) 
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9
    order by 1, 2, 3, 4, 5, 6, 7, 8, 9;


-- directed transmission 
-- TODO: make some indexed temp tables to speed up these queries
-- the sum is still needed in the trans_direction_table as there could be different fuel types transmitted

insert into _transmission_directed_hourly ( scenario_id, carbon_cost, period, transmission_line_id, send_id, receive_id, study_hour, hour_of_day_UTC, directed_trans_avg )
select 	scenario_id,
		carbon_cost,
		period,
		transmission_line_id,
		send_id,
		receive_id,
		study_hour,
		mod(floor(study_hour/1000)::int,100) as hour_of_day_UTC,
		round( directed_trans_avg ) as directed_trans_avg

-- ** Note change from transmission_lines to transmission_between_la
from	transmission_between_la tl,

	(select distinct (scenario_id, carbon_cost), scenario_id, carbon_cost,
			period,
			study_hour,
			(CASE WHEN average_transmission > 0 THEN send_id ELSE receive_id END) as send_id,
			(CASE WHEN average_transmission > 0 THEN receive_id ELSE send_id END) as receive_id,
			abs(average_transmission) as directed_trans_avg
		from
			(select scenario_id,
					carbon_cost,
					period,
					study_hour,
					send_id,
					receive_id,
					sum(average_transmission) as average_transmission
				from 
					(select scenario_id,
							carbon_cost,
							period,
							study_hour,
							send_id,
							receive_id,
							sum( ( power_sent + power_received ) / 2 ) as average_transmission
						from _transmission_dispatch where scenario_id = (select * from chile.temp_scenario limit 1)
						group by 1,2,3,4,5,6
						UNION
					select 	scenario_id,
							carbon_cost,
							period,
							study_hour,
							receive_id as send_id,
							send_id as receive_id,
							sum( -1 * ( power_sent + power_received ) / 2 ) as average_transmission
						from _transmission_dispatch where scenario_id = (select * from chile.temp_scenario limit 1) 
						group by 1,2,3,4,5,6
					) as trans_direction_table
				group by 1,2,3,4,5,6) as avg_trans_table
		) as directed_trans_table

where 	directed_trans_table.send_id = tl.la_start
and		directed_trans_table.receive_id = tl.la_end
order by 1, 2, 3, 5, 6, 7;

-- now do the same as above, but aggregated
-- TODO: could speed this up by referencing the above table
--insert into _transmission_avg_directed
insert into _transmission_avg_directed
select 	scenario_id,
		carbon_cost,
		period,
		transmission_line_id,
		send_id,
		receive_id,
		round( directed_trans_avg ) as directed_trans_avg

-- ** Note change from transmission_lines to transmission_between_la
from	transmission_between_la tl,

	(select distinct (scenario_id, carbon_cost), scenario_id, carbon_cost,
			period,
			(CASE WHEN average_transmission > 0 THEN send_id ELSE receive_id END) as send_id,
			(CASE WHEN average_transmission > 0 THEN receive_id ELSE send_id END) as receive_id,
			abs(average_transmission) as directed_trans_avg
		from
			(select scenario_id,
					carbon_cost,
					period,
					send_id,
					receive_id,
					sum(average_transmission) as average_transmission
				from 
					(select scenario_id,
							carbon_cost,
							period,
							send_id,
							receive_id,
							sum( hours_in_sample * ( ( power_sent + power_received ) / 2 ) ) / sum_hourly_weights_per_period as average_transmission
						from _transmission_dispatch join sum_hourly_weights_per_period_table using (scenario_id, period) where scenario_id = (select * from chile.temp_scenario limit 1)  
						group by 1,2,3,4,5,sum_hourly_weights_per_period_table.sum_hourly_weights_per_period
						UNION
					select 	scenario_id,
							carbon_cost,
							period,
							receive_id as send_id,
							send_id as receive_id,
							-1 * sum( hours_in_sample * ( ( power_sent + power_received ) / 2 ) ) / sum_hourly_weights_per_period as average_transmission
						from _transmission_dispatch join sum_hourly_weights_per_period_table using (scenario_id, period) where scenario_id = (select * from chile.temp_scenario limit 1)  
						group by 1,2,3,4,5,sum_hourly_weights_per_period_table.sum_hourly_weights_per_period
					) as trans_direction_table
				group by 1,2,3,4,5) as avg_trans_table
		) as directed_trans_table

where 	directed_trans_table.send_id = tl.la_start
and		directed_trans_table.receive_id = tl.la_end
order by 1, 2, 3, 5, 6; 


-- CO2 Emissions --------------------
select 'Calculating CO2 emissions' as progress;
-- see WECC_Plants_For_Emissions in the Switch_Input_Data folder for a calculation of the yearly 1990 emissions from WECC
--set @co2_tons_1990 := 284800000;
-- The query to get the value now is (select * from co2_tons_1990 limit 1)

--insert into co2_cc
	insert into co2_cc
	select 	scenario_id,
			carbon_cost,
			_gen_hourly_summary_tech_la.period,
			sum( ( co2_tons + spinning_co2_tons + deep_cycling_co2_tons ) * hours_in_sample ) / years_per_period as co2_tons, 
     		(select * from co2_tons_1990 limit 1) - sum( ( co2_tons + spinning_co2_tons + deep_cycling_co2_tons ) * hours_in_sample ) / years_per_period as co2_tons_reduced_1990,
    		1 - ( sum( ( co2_tons + spinning_co2_tons + deep_cycling_co2_tons ) * hours_in_sample ) / years_per_period ) / (select * from co2_tons_1990 limit 1) as co2_share_reduced_1990
  	
	from 	_gen_hourly_summary_tech_la join sum_hourly_weights_per_period_table using (scenario_id, period)
  	where 	scenario_id = (select * from chile.temp_scenario limit 1) 
  	group by 1, 2, 3, sum_hourly_weights_per_period_table.years_per_period
  	order by 1, 2, 3;



-- SYSTEM LOAD ---------------

-- add hourly system load aggregated by load area here
insert into system_load_summary_hourly (scenario_id, carbon_cost, period, study_date, study_hour, month, hour_of_day_UTC, hour_of_day_PST,
  										hours_in_sample, system_load, satisfy_load_reduced_cost, satisfy_load_reserve_reduced_cost)

	select 	scenario_id,
			carbon_cost,
			period,
			study_date,
			study_hour,
			substring(study_date::varchar from 5 for 2)::smallint as month,
			substring(study_hour::varchar from 9 for 2)::smallint as hour_of_day_UTC,
			mod(substring(study_hour::varchar from 9 for 2)::smallint - 8, 24) as hour_of_day_PST,
			hours_in_sample,
			sum( power ) as system_load,
			sum( satisfy_load_reduced_cost ) as satisfy_load_reduced_cost,
			sum( satisfy_load_reserve_reduced_cost ) as satisfy_load_reserve_reduced_cost

	from _system_load
	where scenario_id = (select * from chile.temp_scenario limit 1) 
	group by 1, 2, 3, 4, 5, 6, 7, 8, 9
	order by 1, 2, 3, 4, 5, 6, 7, 8, 9;


--insert into system_load_summary
	insert into system_load_summary
	select 	scenario_id,
			carbon_cost,
			period,
			sum( hours_in_sample * system_load ) / sum_hourly_weights_per_period as system_load,
			sum( hours_in_sample * satisfy_load_reduced_cost ) / sum_hourly_weights_per_period as satisfy_load_reduced_cost_weighted,
			sum( hours_in_sample * satisfy_load_reserve_reduced_cost ) / sum_hourly_weights_per_period as satisfy_load_reserve_reduced_cost_weighted

	from system_load_summary_hourly join sum_hourly_weights_per_period_table using (scenario_id, period)
	where scenario_id = (select * from chile.temp_scenario limit 1) 
	group by 1, 2, 3, sum_hourly_weights_per_period_table.sum_hourly_weights_per_period
	order by 1, 2, 3;


-- SYSTEM COSTS ---------------
select 'Calculating system costs' as progress;
-- average power costs, for each study period, for each carbon tax

insert into power_cost (scenario_id, carbon_cost, period, load_in_period_mwh )

select 		scenario_id,
  			carbon_cost,
  			period,
  			system_load * sum_hourly_weights_per_period as load_in_period_mwh

  from system_load_summary join sum_hourly_weights_per_period_table using (scenario_id, period)
  where scenario_id = (select * from chile.temp_scenario limit 1) 
  order by 1, 2, 3;
  
-- now calculated a bunch of costs

-- local_td costs
update power_cost set existing_local_td_cost =
	(select sum(fixed_cost) from _local_td_cap t
		where t.scenario_id = power_cost.scenario_id
		and t.carbon_cost = power_cost.carbon_cost and t.period = power_cost.period and 
		new = false )
	where scenario_id = (select * from chile.temp_scenario limit 1);

update power_cost set new_local_td_cost =
	(select sum(fixed_cost) from _local_td_cap t
		where t.scenario_id = power_cost.scenario_id
		and t.carbon_cost = power_cost.carbon_cost and t.period = power_cost.period and 
		new = true )
	where scenario_id = (select * from chile.temp_scenario limit 1);

-- transmission costs
update power_cost set existing_transmission_cost =
	(select sum(existing_trans_cost) from _existing_trans_cost t
		where t.scenario_id = power_cost.scenario_id
		and t.carbon_cost = power_cost.carbon_cost and t.period = power_cost.period )
	where scenario_id = (select * from chile.temp_scenario limit 1);

update power_cost set new_transmission_cost =
	(select sum(fixed_cost) from _trans_cap t
		where t.scenario_id = power_cost.scenario_id
		and t.carbon_cost = power_cost.carbon_cost and t.period = power_cost.period and 
		new = true )
	where scenario_id = (select * from chile.temp_scenario limit 1);

-- generation costs
update power_cost set existing_plant_sunk_cost =
	(select sum(capital_cost) from _gen_cap_summary_tech g
		where g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_info_v2 where can_build_new = false) )
	where scenario_id = (select * from chile.temp_scenario limit 1);

update power_cost set existing_plant_operational_cost =
	(select sum(o_m_cost_total) from _gen_cap_summary_tech g
		where g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_info_v2 where can_build_new = false) )
	where scenario_id = (select * from chile.temp_scenario limit 1);

update power_cost set new_coal_nonfuel_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) from _gen_cap_summary_tech g
		where g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_info_v2 where fuel in ('Coal', 'Coal_CCS') and can_build_new = true) )
	where scenario_id = (select * from chile.temp_scenario limit 1);

update power_cost set coal_fuel_cost =
	(select sum(fuel_cost) from _gen_cap_summary_tech g
		where g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_info_v2 where fuel in ('Coal', 'Coal_CCS') ) )
	where scenario_id = (select * from chile.temp_scenario limit 1);

update power_cost set new_gas_nonfuel_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) from _gen_cap_summary_tech g
		where g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_info_v2 where fuel in ('Gas', 'Gas_CCS') and storage = false and can_build_new = true ) )
	where scenario_id = (select * from chile.temp_scenario limit 1);

update power_cost set gas_fuel_cost =
	(select sum(fuel_cost) from _gen_cap_summary_tech g
		where g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_info_v2 where fuel in ('Gas', 'Gas_CCS') ) )
	where scenario_id = (select * from chile.temp_scenario limit 1);

update power_cost set new_nuclear_nonfuel_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) from _gen_cap_summary_tech g
		where g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_info_v2 where fuel = 'Uranium' and can_build_new = true) )
	where scenario_id = (select * from chile.temp_scenario limit 1);

update power_cost set nuclear_fuel_cost =
	(select sum(fuel_cost) from _gen_cap_summary_tech g
		where g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_info_v2 where fuel = 'Uranium') )
		where scenario_id = (select * from chile.temp_scenario limit 1);

update power_cost set new_geothermal_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _gen_cap_summary_tech g
		where g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_info_v2 where fuel = 'Geothermal' and can_build_new = true ) )
	where scenario_id = (select * from chile.temp_scenario limit 1);

update power_cost set new_bio_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _gen_cap_summary_tech g
		where g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_info_v2 where fuel in ('Bio_Gas', 'Bio_Solid', 'Bio_Gas_CCS', 'Bio_Solid_CCS') and can_build_new = true ) )
	where scenario_id = (select * from chile.temp_scenario limit 1);

update power_cost set new_wind_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _gen_cap_summary_tech g
		where g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_info_v2 where fuel = 'Wind' and can_build_new = true ) )
	where scenario_id = (select * from chile.temp_scenario limit 1);

update power_cost set new_solar_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _gen_cap_summary_tech g
		where g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_info_v2 where fuel = 'Solar' and can_build_new = true ) )
	where scenario_id = (select * from chile.temp_scenario limit 1);

update power_cost set new_hydro_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _gen_cap_summary_tech g
		where g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_info_v2 where fuel in ('Water', 'Water_RPS') and can_build_new = true ) )
	where scenario_id = (select * from chile.temp_scenario limit 1);

update power_cost set new_storage_nonfuel_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) from _gen_cap_summary_tech g
		where g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_info_v2 where storage = true and can_build_new = true ) )
	where scenario_id = (select * from chile.temp_scenario limit 1);

update power_cost set carbon_cost_total =
	(select sum(carbon_cost_total) from _gen_cap_summary_tech g
		where g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period )
	where scenario_id = (select * from chile.temp_scenario limit 1);

update power_cost
set total_cost =  coalesce(existing_local_td_cost,0) + coalesce(new_local_td_cost,0) + coalesce(existing_transmission_cost,0) +
        coalesce(new_transmission_cost,0) + coalesce(existing_plant_sunk_cost,0) + coalesce(existing_plant_operational_cost,0) + 
        coalesce(new_coal_nonfuel_cost,0) + coalesce(coal_fuel_cost,0) +
	coalesce(new_gas_nonfuel_cost,0) + coalesce(gas_fuel_cost,0) + coalesce(new_nuclear_nonfuel_cost,0) + coalesce(nuclear_fuel_cost,0) + 
	coalesce(new_geothermal_cost,0) + coalesce(new_bio_cost,0) + coalesce(new_wind_cost,0) + coalesce(new_solar_cost,0) + 
	coalesce(new_hydro_cost,0) + coalesce(new_storage_nonfuel_cost,0) + coalesce(carbon_cost_total,0)
where scenario_id = (select * from chile.temp_scenario limit 1);

update power_cost set cost_per_mwh = total_cost / load_in_period_mwh
where scenario_id = (select * from chile.temp_scenario limit 1);

-- Extract fuel category definitions from the results
CREATE TEMPORARY TABLE fc_defs as
  SELECT DISTINCT scenario_id, period, technology_id, fuel, fuel_category
    FROM _generator_and_storage_dispatch
    WHERE scenario_id = (select * from chile.temp_scenario limit 1) 
	;

--INSERT IGNORE INTO fuel_categories (fuel_category)
drop table if exists chile.fuel_categories cascade;
  SELECT DISTINCT fuel_category INTO fuel_categories FROM fc_defs;

--INSERT IGNORE INTO fuel_category_definitions (fuel_category_id, scenario_id, period, technology_id, fuel )
--Note: Changed fuel_category_id to fuel_category. Seemed like a typing mistake
  drop table if exists chile.fuel_category_definitions cascade;
  SELECT fuel_category, scenario_id, period, technology_id, fuel 
  INTO fuel_category_definitions
  FROM fuel_categories JOIN fc_defs USING (fuel_category);

-- Calculate summary stats based on fuel category
-- We're incorectly adding emissions from spinning reserves to the locally produced power. Really, the spinning emissions need to be apportioned based on what they are spinning for. 
-- Some of the emissions will be based on 5% of load for load areas in the balancing area. 
-- The remainder of the emissions will be based on 3% of renewable output, and needs to be embedded with the renewable power and ultimately assigned to whichever load area consumes it. 
-- This is too complicated for me for now and doesn't really matter because emissions from spinning reserves are less than .1% of total emissions. 
INSERT INTO _gen_hourly_summary_fc_la 
  (scenario_id, carbon_cost, period, area_id, study_date, study_hour, hours_in_sample, fuel_category, storage, power, co2_tons)

SELECT temp.scenario_id, temp.carbon_cost, temp.period, temp.area_id, temp.study_date, temp.study_hour, temp.hours_in_sample, fuel_category, 
      temp.storage, SUM(power) as power, SUM(co2_tons + spinning_co2_tons + deep_cycling_co2_tons) as co2_tons
  --into _gen_hourly_summary_fc_la
	FROM 	(select scenario_id, carbon_cost, period, area_id, study_date, study_hour, hours_in_sample,
		(CASE WHEN fuel='Storage' THEN 1 ELSE 0 END) as storage from _generator_and_storage_dispatch
		group by 1,2,3,4,5,6,7,8) as temp,
		_generator_and_storage_dispatch gs
      JOIN fuel_categories USING( fuel_category)
    WHERE temp.scenario_id = (select * from chile.temp_scenario limit 1)
    and  gs.scenario_id = temp.scenario_id
    and  gs.carbon_cost = temp.carbon_cost 
    and  gs.period = temp.period
    and  gs.area_id = temp.area_id 
    and  gs.study_date = temp.study_date
    and  gs.study_hour = temp.study_hour
    GROUP BY temp.scenario_id, temp.carbon_cost, temp.period, temp.area_id, temp.study_date, temp.study_hour, temp.hours_in_sample, fuel_category, temp.storage;
-- Calculate the carbon intensity of electricity
-- JP: Still have to create/translate this function
--CALL calc_carbon_intensity((select * from chile.temp_scenario limit 1) ); */
