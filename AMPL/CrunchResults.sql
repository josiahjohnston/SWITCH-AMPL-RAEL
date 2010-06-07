--#######################################################
-- Export results for graphing

-- Determine investment period length
set @first_period  := (select min( period) from gen_cap where scenario_id=@scenario_id);
set @second_period := (select min(period) from gen_cap where period != @first_period and scenario_id=@scenario_id);
set @period_length := (@second_period - @first_period);
set @last_period := (select max(period) from gen_cap where scenario_id=@scenario_id);
set @sum_hourly_weights_per_period = ( SELECT sum(hours_in_sample)
    from _dispatch 
    where
      scenario_id=@scenario_id and
      project_id = (select project_id from _dispatch where scenario_id=@scenario_id limit 1) and 
      carbon_cost = (select carbon_cost from _dispatch where scenario_id=@scenario_id limit 1) and 
      area_id = (select area_id from _dispatch where scenario_id=@scenario_id limit 1) and 
      period = (select period from _dispatch where scenario_id=@scenario_id limit 1)
    );


-- GENERATION SUMMARIES--------
select 'Creating generation summaries' as progress;
-- total generation each hour by carbon cost, technology and load area
-- this table will be used extensively below to create summaries dependent on generator dispatch
replace into _gen_hourly_summary_la
		(scenario_id, carbon_cost, period, area_id, study_date, study_hour, hours_in_sample, technology_id,
			variable_o_m_cost, fuel_cost, carbon_cost_incurred, co2_tons, power)
	select 	scenario_id, carbon_cost, period, area_id, study_date, study_hour, hours_in_sample, technology_id,
			sum(variable_o_m_cost), sum(fuel_cost), sum(carbon_cost_incurred), sum(co2_tons), sum(power)
    	from _dispatch
    	where scenario_id = @scenario_id
    	group by 2, 3, 4, 5, 6, 7, 8;
  
-- add month and hour_of_day. 
update _gen_hourly_summary_la
set	month = mod(floor(study_hour/100000),100),
	hour_of_day = mod(floor(study_hour/1000),100)
	where scenario_id = @scenario_id;


-- total generation each period by carbon cost, technology and load area
replace into _gen_summary_la
  select scenario_id, carbon_cost, period, area_id, technology_id,
    	sum(power * hours_in_sample) / @sum_hourly_weights_per_period as avg_power
		from _gen_hourly_summary_la
    	where scenario_id = @scenario_id
    	group by 2, 3, 4, 5;

-- total generation each hour by carbon cost and technology
replace into _gen_hourly_summary
	select scenario_id, carbon_cost, period, study_date, study_hour, hours_in_sample, month, hour_of_day, technology_id, sum(power) as power
		from _gen_hourly_summary_la
		where scenario_id = @scenario_id
		group by 2, 3, 4, 5, 6, 7, 8, 9;

-- total generation each period by carbon cost and technology
replace into _gen_summary
	select scenario_id, carbon_cost, period, technology_id,	
    sum(power * hours_in_sample) / @sum_hourly_weights_per_period as avg_power
    from _gen_hourly_summary join technologies using (technology_id)
    where scenario_id = @scenario_id
    group by 2, 3, 4;


-- GENERATOR CAPACITY--------------

-- capacity each period by load area
replace into _gen_cap_summary_la
  select scenario_id, carbon_cost, period, area_id, technology_id, sum(capacity) as capacity
    from _gen_cap
    where scenario_id = @scenario_id
    group by 2, 3, 4, 5;


-- capacity each period
replace into _gen_cap_summary
  select scenario_id, carbon_cost, period, technology_id,
    sum(capacity) as capacity
    from _gen_cap_summary_la  join technologies using (technology_id)
    where scenario_id = @scenario_id
    group by 2, 3, 4;


-- TRANSMISSION ----------------
select 'Creating transmission summaries' as progress;

-- add helpful columns to _transmission_dispatch
update _transmission_dispatch
	set month = mod(floor(study_hour/100000),100),
		hour_of_day = mod(floor(study_hour/1000),100)
	where scenario_id = @scenario_id;


-- Transmission summary: net transmission for each zone in each hour
-- First add imports, then subtract exports
replace into _trans_summary (scenario_id, carbon_cost, period, area_id, study_date, study_hour, month, hour_of_day, hours_in_sample, net_power)
  select 	scenario_id,
  			carbon_cost,
  			period,
  			receive_id,
  			study_date,
  			study_hour,
  			month,
	 		hour_of_day,
	 		hours_in_sample,
	 		sum(power_received)
    from _transmission_dispatch
    where scenario_id = @scenario_id
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9;
insert into _trans_summary (scenario_id, carbon_cost, period, area_id, study_date, study_hour, month, hour_of_day, hours_in_sample, net_power)
  select 	scenario_id,
  			carbon_cost,
  			period,
  			send_id,
  			study_date,
  			study_hour,
  			month,
	 		hour_of_day,
  			hours_in_sample,
  			-1*sum(power_sent) as net_sent
    from _transmission_dispatch
    where scenario_id = @scenario_id
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9
  on duplicate key update net_power = net_power + VALUES(net_power);

-- Tally transmission losses using a similar method
replace into _trans_loss (scenario_id, carbon_cost, period, area_id, study_date, study_hour, month, hour_of_day, hours_in_sample, power)
  select 	scenario_id,
  			carbon_cost,
  			period,
  			send_id,
  			study_date,
  			study_hour,
  			month,
  			hour_of_day,
  			hours_in_sample,
  			sum(power_sent - power_received) as power
    from _transmission_dispatch
    where scenario_id = @scenario_id
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9;


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
			_gen_hourly_summary_la.period,
			sum( co2_tons * hours_in_sample ) / @period_length as co2_tons, 
    		base_co2_tons - sum( co2_tons * hours_in_sample ) / @period_length as co2_tons_reduced, 
   			1 - sum( co2_tons * hours_in_sample ) / @period_length / base_co2_tons as co2_share_reduced, 
    		@co2_tons_1990 - sum( co2_tons * hours_in_sample ) / @period_length as co2_tons_reduced_1990,
    		1 - sum( co2_tons * hours_in_sample ) / @period_length / @co2_tons_1990 as co2_share_reduced_1990
  	from 	_gen_hourly_summary_la,
  			(select period,
					sum(co2_tons * hours_in_sample) / @period_length as base_co2_tons
				from _gen_hourly_summary_la
				where carbon_cost = (select min(carbon_cost) from _gen_hourly_summary_la where scenario_id = @scenario_id)
				and scenario_id = @scenario_id
				group by 1) as base_co2_tons_table
  	where 	scenario_id = @scenario_id
  	and		base_co2_tons_table.period = _gen_hourly_summary_la.period
  	group by 2, 3;


-- SYSTEM COSTS ---------------
select 'Calculating system costs' as progress;
-- average power costs, for each study period, for each carbon tax
-- Matthias Note:(this should probably use a discounting method for the MWhs, 
-- since the costs are already discounted to the start of each period,
-- but electricity production is spread out over time. But the main model doesn't do that so I don't do it here either.)


-- update load data first
update _system_load
	set month = mod(floor(study_hour/100000),100),
		hour_of_day = mod(floor(study_hour/1000),100)
	where scenario_id = @scenario_id;

insert into system_load_summary
	select 	@scenario_id,
			carbon_cost,
			period,
			sum( hours_in_sample * power ) / ( 8760 * @period_length ) as system_load
	from _system_load
	where scenario_id = @scenario_id
	group by 2, 3;

-- now actually calculate costs
drop table if exists tloads;
create temporary table tloads
  select 	carbon_cost,
  			period,
  			system_load as load_in_period_mwh
  from system_load_summary
  where scenario_id = @scenario_id;
alter table tloads add index pc (period, carbon_cost);

drop table if exists tgenerator_capital_and_fixed_cost;
create temporary table tgenerator_capital_and_fixed_cost
  select 	carbon_cost,
  			period,
  			sum(fixed_cost) as generator_capital_and_fixed_cost
    from gen_cap
    where scenario_id = @scenario_id
    group by 1, 2;
alter table tgenerator_capital_and_fixed_cost add index pc (period, carbon_cost);

drop table if exists ttransmission_cost;
create temporary table ttransmission_cost
  select 	carbon_cost,
  			period,
  			sum(fixed_cost) as transmission_cost
    from trans_cap
    where scenario_id = @scenario_id
    group by 1, 2;
alter table ttransmission_cost add index pc (period, carbon_cost);

drop table if exists tlocal_td_cost;
create temporary table tlocal_td_cost
  select 	period,
  			carbon_cost,
  			sum(fixed_cost) as local_td_cost
    from local_td_cap
    where scenario_id = @scenario_id
    group by 1, 2;
alter table tlocal_td_cost add index pc (period, carbon_cost);

drop table if exists tvariable_costs;
create temporary table tvariable_costs
  select 	period,
  			carbon_cost,
  			sum(fuel_cost * hours_in_sample) as fuel_cost, 
    		sum(carbon_cost_incurred * hours_in_sample) as carbon_cost_total,
    		sum(variable_o_m_cost * hours_in_sample) as generator_variable_o_m_cost
    from _gen_hourly_summary_la
    where scenario_id = @scenario_id
    group by 1, 2;
alter table tvariable_costs add index pc (period, carbon_cost);

replace into power_cost (scenario_id, carbon_cost, period, load_in_period_mwh, local_td_cost, transmission_cost, generator_capital_and_fixed_cost, generator_variable_o_m_cost, fuel_cost, carbon_cost_total, total_cost )
  select 	@scenario_id,
  			l.carbon_cost,
  			l.period,
  			load_in_period_mwh, 
    		local_td_cost,
    		transmission_cost,
    		generator_capital_and_fixed_cost,
     		generator_variable_o_m_cost,
	   		fuel_cost,
    		carbon_cost_total,
    		local_td_cost + transmission_cost + generator_capital_and_fixed_cost + generator_variable_o_m_cost + fuel_cost + carbon_cost_total as total_cost
  from tloads l 
    join tgenerator_capital_and_fixed_cost using (period, carbon_cost)
    join ttransmission_cost using (period, carbon_cost)
    join tlocal_td_cost using (period, carbon_cost)
    join tvariable_costs using (period, carbon_cost);
update power_cost set cost_per_mwh = total_cost/load_in_period_mwh where scenario_id=@scenario_id;


