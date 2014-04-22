--#######################################################

set search_path to china, public;

-- Clear the existing views in order to allow table dropping
BEGIN TRANSACTION;
    DO $$DECLARE r record;
         DECLARE s TEXT;
        BEGIN
            FOR r IN select table_schema,table_name
                     from information_schema.views
                     where table_schema = 'china'
            LOOP
                s := 'DROP VIEW ' ||  quote_ident(r.table_schema) || '.' || quote_ident(r.table_name) || ';';

                EXECUTE s;

                RAISE NOTICE 's = % ',s;

            END LOOP;
        END$$;
   --ROLLBACK TRANSACTION;
   END TRANSACTION;

-- GENERATION AND STORAGE SUMMARIES--------
select 'Creating generation summaries' as progress;
-- total generation each hour by carbon cost, technology and province
-- this table will be used extensively below to create summaries dependent on generator dispatch
-- note: technology_id and fuel are not quite redundant here as energy stored or released from storage comes in as fuel = 'storage'
drop table if exists china._gen_hourly_summary_tech_la;
create table china._gen_hourly_summary_tech_la(
			scenario_id int, 
			carbon_cost double precision, 
			period smallint, 
			province_id smallint,
			province varchar,
			study_date integer, 
			study_hour integer,
			study_month smallint,
			hour_of_day smallint,
			hours_in_sample double precision, 
			technology_id smallint, 
			fuel varchar,
			variable_o_m_cost double precision, 
			fuel_cost double precision, 
			carbon_cost_hourly double precision, 
			co2_tons double precision, 
			system_power double precision,
			spinning_fuel_cost double precision, 
			spinning_carbon_cost_incurred double precision, 
			spinning_co2_tons double precision, 
			spinning_reserve double precision, 
			quickstart_capacity double precision, 
			total_operating_reserve double precision, 
			deep_cycling_amount double precision, 
			deep_cycling_fuel_cost double precision, 
			deep_cycling_carbon_cost double precision, 
			deep_cycling_co2_tons double precision, 
			total_co2_tons double precision,
			primary key (scenario_id, carbon_cost, period, province_id, study_hour, technology_id, fuel)
			);

insert into china._gen_hourly_summary_tech_la
		(scenario_id, carbon_cost, period, province_id, province, study_date, study_hour, hours_in_sample, technology_id, fuel,
			variable_o_m_cost, fuel_cost, carbon_cost_hourly, co2_tons, system_power,
			spinning_fuel_cost, spinning_carbon_cost_incurred, spinning_co2_tons, spinning_reserve, quickstart_capacity, total_operating_reserve, deep_cycling_amount, deep_cycling_fuel_cost, deep_cycling_carbon_cost, deep_cycling_co2_tons, total_co2_tons)
		select 	scenario_id, carbon_cost, period, province_id, province, study_date, study_hour, hours_in_sample, technology_id, fuel,
			sum(variable_o_m_cost) as variable_o_m_cost, 
			sum(fuel_cost) as fuel_cost, 
			sum(carbon_cost_hourly) as carbon_cost_hourly, 
			sum(co2_tons) as co2_tons, 
			sum(system_power) as system_power,
			sum(spinning_fuel_cost) as spinning_fuel_cost, 
			sum(spinning_carbon_cost_incurred) as spinning_carbon_cost_incurred, 
			sum(spinning_co2_tons) as spinning_co2_tons, 
			sum(spinning_reserve) as spinning_reserve, 
			sum(quickstart_capacity) as quickstart_capacity, 
			sum(total_operating_reserve) as total_operating_reserve, 
			sum(deep_cycling_amount) as deep_cycling_amount, 
			sum(deep_cycling_fuel_cost) as deep_cycling_fuel_cost, 
			sum(deep_cycling_carbon_cost) as deep_cycling_carbon_cost, 
			sum(deep_cycling_co2_tons) as deep_cycling_co2_tons,
			sum(co2_tons + spinning_co2_tons + deep_cycling_co2_tons) as total_co2_tons
    	from china._generator_and_storage_dispatch
    	where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results)
    	--	where scenario_id = (select china.get_scenario())
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
    order by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10;

-- add study_month and hour_of_day. 
update china._gen_hourly_summary_tech_la
set	--study_month = convert(left(right(study_hour, 6),2), decimal),
	study_month = substring(study_date::varchar from 5 for 2)::smallint,
	--hour_of_day = convert(right(study_hour, 2), decimal)
	hour_of_day = substring(study_hour::varchar from 9 for 2)::smallint
	--where scenario_id = (select china.get_scenario())
	;


-- total generation each hour by carbon cost and technology
drop table if exists _gen_hourly_summary_tech;
create table _gen_hourly_summary_tech( 
	scenario_id integer, 
	carbon_cost double precision, 
	period smallint, 
	study_date integer, 
	study_hour integer, 
	hours_in_sample double precision, 
	study_month smallint, 
	hour_of_day smallint, 
	technology_id smallint, 
	system_power double precision, 
	co2_tons double precision, 
	spinning_reserve double precision, 
	spinning_co2_tons double precision, 
	quickstart_capacity double precision, 
	total_operating_reserve double precision, 
	deep_cycling_amount double precision, 
	deep_cycling_co2_tons double precision, 
	total_co2_tons double precision,
	primary key (scenario_id, carbon_cost, period, study_hour,technology_id)
	);
		
insert into _gen_hourly_summary_tech ( scenario_id, carbon_cost, period, study_date, study_hour, hours_in_sample, study_month, hour_of_day, technology_id,
				system_power, co2_tons, spinning_reserve, spinning_co2_tons, quickstart_capacity, total_operating_reserve, deep_cycling_amount, deep_cycling_co2_tons, total_co2_tons )
	select scenario_id, carbon_cost, period, study_date, study_hour, hours_in_sample, study_month, hour_of_day, technology_id,
	sum(system_power) as system_power, 
	sum(co2_tons) as co2_tons,
	sum(spinning_reserve) as spinning_reserve, 
	sum(spinning_co2_tons) as spinning_co2_tons,
	sum(quickstart_capacity) as quickstart_capacity, 
	sum(total_operating_reserve) as total_operating_reserve,
	sum(deep_cycling_amount) as deep_cycling_amount, 
	sum(deep_cycling_co2_tons) as deep_cycling_co2_tons,
	sum(total_co2_tons) as total_co2_tons
	from _gen_hourly_summary_tech_la
	where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results)
	--where scenario_id = (select china.get_scenario()) 
	group by 1, 2, 3, 4, 5, 6, 7, 8, 9
	order by 1, 2, 3, 4, 5, 6, 7, 8, 9;

-- find the total number of hours represented by each period for use in weighting hourly generation
drop table if exists sum_hourly_weights_per_period_table;
create table sum_hourly_weights_per_period_table ( 
	scenario_id smallint, 
	period smallint, 
	sum_hourly_weights_per_period double precision, 
	years_per_period double precision
	);
	
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
				where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results)
				/*where scenario_id = (select china.get_scenario()) */ ) as distinct_hours_table
		group by scenario_id, period;

-- total generation each period by carbon cost, technology and province
drop table if exists _gen_summary_tech_la;
create table _gen_summary_tech_la(
	scenario_id smallint, 
	carbon_cost double precision,
	period smallint, 
	province_id smallint,
	province varchar, 
	technology_id smallint, 
	avg_power double precision, 
	avg_co2_tons double precision, 
	avg_spinning_reserve double precision, 
	avg_spinning_co2_tons double precision, 
	avg_quickstart_capacity double precision, 
	avg_total_operating_reserve double precision, 
	avg_deep_cycling_amount double precision, 
	avg_deep_cycling_co2_tons double precision, 
	avg_total_co2_tons double precision,
	primary key (scenario_id, carbon_cost, period, province_id, technology_id)
	);
	
insert into _gen_summary_tech_la ( scenario_id, carbon_cost, period, province_id, province, technology_id, avg_power, avg_co2_tons,
				avg_spinning_reserve, avg_spinning_co2_tons, avg_quickstart_capacity, avg_total_operating_reserve, avg_deep_cycling_amount, avg_deep_cycling_co2_tons, avg_total_co2_tons )
select scenario_id, carbon_cost, period, province_id, province, technology_id,
	sum(system_power * hours_in_sample) / sum_hourly_weights_per_period as avg_power,
	sum(co2_tons * hours_in_sample) / sum_hourly_weights_per_period as avg_co2_tons,
	sum(spinning_reserve * hours_in_sample) / sum_hourly_weights_per_period as avg_spinning_reserve,
	sum(spinning_co2_tons * hours_in_sample) / sum_hourly_weights_per_period as avg_spinning_co2_tons,
	sum(quickstart_capacity * hours_in_sample) / sum_hourly_weights_per_period as avg_quickstart_capacity,
	sum(total_operating_reserve * hours_in_sample) / sum_hourly_weights_per_period as avg_total_operating_reserve,
	sum(deep_cycling_amount * hours_in_sample) / sum_hourly_weights_per_period as avg_deep_cycling_amount,
	sum(deep_cycling_co2_tons * hours_in_sample) / sum_hourly_weights_per_period as avg_deep_cycling_co2_tons,
	sum(total_co2_tons * hours_in_sample) / sum_hourly_weights_per_period as avg_total_co2_tons
	from _gen_hourly_summary_tech_la join sum_hourly_weights_per_period_table using (scenario_id, period)
    where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results)	
    --where scenario_id = (select china.get_scenario()) 
	group by 1, 2, 3, 4, 5, 6, sum_hourly_weights_per_period_table.sum_hourly_weights_per_period
	order by 1, 2, 3, 4, 5, 6;

-- total generation each period by carbon cost and technology
--insert into _gen_summary_tech ( scenario_id, carbon_cost, period, technology_id, avg_power, avg_co2_tons,
--				avg_spinning_reserve, avg_spinning_co2_tons, avg_quickstart_capacity, avg_total_operating_reserve, avg_deep_cycling_amount, avg_deep_cycling_co2_tons, avg_total_co2_tons )
drop table if exists _gen_summary_tech CASCADE;
select scenario_id, carbon_cost, period, technology_id,
	sum(avg_power) as avg_power, 
	sum(avg_co2_tons) as avg_co2_tons,
	sum(avg_spinning_reserve) as avg_spinning_reserve, 
	sum(avg_spinning_co2_tons) as avg_spinning_co2_tons,
	sum(avg_quickstart_capacity) as avg_quickstart_capacity, 
	sum(avg_total_operating_reserve) as avg_total_operating_reserve,
	sum(avg_deep_cycling_amount) as avg_deep_cycling_amount,
	sum(avg_deep_cycling_co2_tons) as avg_deep_cycling_co2_tons,	
	sum(avg_total_co2_tons) as avg_total_co2_tons
	into _gen_summary_tech
    from _gen_summary_tech_la
    where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results)
    --where scenario_id = (select china.get_scenario()) 
    group by 1, 2, 3, 4
    order by 1, 2, 3, 4;


-- generation by fuel----------

-- total generation each hour by carbon cost, fuel and province
--insert into _gen_hourly_summary_fuel_la (scenario_id, carbon_cost, period, province, study_date, study_hour, hours_in_sample, study_month, hour_of_day, fuel,
--					power, co2_tons, spinning_reserve, spinning_co2_tons, quickstart_capacity, total_operating_reserve, deep_cycling_amount, deep_cycling_co2_tons, total_co2_tons )
drop table if exists _gen_hourly_summary_fuel_la CASCADE;
select scenario_id, carbon_cost, period, province_id, province, study_date, study_hour, hours_in_sample, study_month, hour_of_day, fuel,
	sum(system_power) as system_power, 
	sum(co2_tons) as co2_tons,
	sum(spinning_reserve) as spinning_reserve, 
	sum(spinning_co2_tons) as spinning_co2_tons,
	sum(quickstart_capacity) as quickstart_capacity, 
	sum(total_operating_reserve) as total_operating_reserve,
	sum(deep_cycling_amount) as deep_cycling_amount, 
	sum(deep_cycling_co2_tons) as deep_cycling_co2_tons,
	sum(total_co2_tons) as total_co2_tons
	into _gen_hourly_summary_fuel_la
	from _gen_hourly_summary_tech_la
	where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results)	
	--where scenario_id = (select china.get_scenario()) 
	group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
	order by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11;

-- total generation each hour by carbon cost and fuel
--insert into _gen_hourly_summary_fuel ( scenario_id, carbon_cost, period, study_date, study_hour, hours_in_sample, study_month, hour_of_day, fuel,
--					power, co2_tons, spinning_reserve, spinning_co2_tons, quickstart_capacity, total_operating_reserve, deep_cycling_amount, deep_cycling_co2_tons, total_co2_tons )
drop table if exists _gen_hourly_summary_fuel CASCADE;
select scenario_id, carbon_cost, period, study_date, study_hour, hours_in_sample, study_month, hour_of_day, fuel,
	sum(system_power) as system_power,  
	sum(co2_tons) as co2_tons,
	sum(spinning_reserve) as spinning_reserve,  
	sum(spinning_co2_tons) as spinning_co2_tons,
	sum(quickstart_capacity) as quickstart_capacity, 
	sum(total_operating_reserve) as total_operating_reserve,
	sum(deep_cycling_amount) as deep_cycling_amount, 
	sum(deep_cycling_co2_tons) as deep_cycling_co2_tons,
	sum(total_co2_tons) as total_co2_tons
	into _gen_hourly_summary_fuel
	from _gen_hourly_summary_fuel_la
	where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results)	
	--where scenario_id = (select china.get_scenario()) 
	group by 1, 2, 3, 4, 5, 6, 7, 8, 9
	order by 1, 2, 3, 4, 5, 6, 7, 8, 9;
	
-- total generation each period by carbon cost, fuel and province
--insert into _gen_summary_fuel_la ( scenario_id, carbon_cost, period, province, fuel,
--					avg_power, avg_co2_tons, avg_spinning_reserve, avg_spinning_co2_tons, avg_quickstart_capacity, avg_total_operating_reserve, avg_deep_cycling_amount, avg_deep_cycling_co2_tons, avg_total_co2_tons )
drop table if exists _gen_summary_fuel_la CASCADE;
select scenario_id, carbon_cost, period, province_id, province, fuel,
	sum(system_power * hours_in_sample) / sum_hourly_weights_per_period as avg_power,
	sum(co2_tons * hours_in_sample) / sum_hourly_weights_per_period as avg_co2_tons,
	sum(spinning_reserve * hours_in_sample) / sum_hourly_weights_per_period as avg_spinning_reserve,
	sum(spinning_co2_tons * hours_in_sample) / sum_hourly_weights_per_period as avg_spinning_co2_tons,
	sum(quickstart_capacity * hours_in_sample) / sum_hourly_weights_per_period as avg_quickstart_capacity,
	sum(total_operating_reserve * hours_in_sample) / sum_hourly_weights_per_period as avg_total_operating_reserve,
	sum(deep_cycling_amount * hours_in_sample) / sum_hourly_weights_per_period as avg_deep_cycling_amount,
	sum(deep_cycling_co2_tons * hours_in_sample) / sum_hourly_weights_per_period as avg_deep_cycling_co2_tons,
	sum(total_co2_tons * hours_in_sample) / sum_hourly_weights_per_period as avg_total_co2_tons 	
	into _gen_summary_fuel_la
	from _gen_hourly_summary_fuel_la join sum_hourly_weights_per_period_table using (scenario_id, period)
	where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) 
	--where scenario_id = (select china.get_scenario()) 
	group by scenario_id, carbon_cost, period, province_id, province, fuel, sum_hourly_weights_per_period_table.sum_hourly_weights_per_period
	order by scenario_id, carbon_cost, period, province_id, province, fuel;

-- total generation each period by carbon cost and fuel
--insert into gen_summary_fuel ( scenario_id, carbon_cost, period, fuel,
--				avg_power, avg_co2_tons, avg_spinning_reserve, avg_spinning_co2_tons, avg_quickstart_capacity, avg_total_operating_reserve, avg_deep_cycling_amount, avg_deep_cycling_co2_tons, avg_total_co2_tons )
drop table if exists _gen_summary_fuel CASCADE;
select scenario_id, carbon_cost, period, fuel,
	sum(avg_power) as avg_power, 
	sum(avg_co2_tons) as avg_co2_tons,
	sum(avg_spinning_reserve) as avg_spinning_reserve, 
	sum(avg_spinning_co2_tons) as avg_spinning_co2_tons,
	sum(avg_quickstart_capacity) as avg_quickstart_capacity, 
	sum(avg_total_operating_reserve) as avg_operating_reserve,
	sum(avg_deep_cycling_amount) as avg_deep_cycling_amount, 
	sum(avg_deep_cycling_co2_tons) as avg_deep_cycling_co2_tons,
	sum(avg_total_co2_tons) as avg_total_co2_tons
	into _gen_summary_fuel
	from _gen_summary_fuel_la
    where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) 
    --where scenario_id = (select china.get_scenario()) 
    group by 1, 2, 3, 4
    order by 1, 2, 3, 4;



-- GENERATOR CAPACITY--------------

-- capacity each period by province
--insert into _gen_cap_summary_tech_la (scenario_id, carbon_cost, period, province, technology_id, capacity, capital_cost, fixed_o_m_cost)
drop table if exists _gen_cap_summary_tech_la CASCADE;
select 	scenario_id, carbon_cost, period, province_id, province, technology_id,
  	sum(capacity) as capacity, 
	sum(capital_cost) as capital_cost, 
	sum(fixed_o_m_cost) as fixed_o_m_cost
	into _gen_cap_summary_tech_la
	from _gen_cap 
    where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) 
    --where scenario_id = (select china.get_scenario()) 
    group by 1, 2, 3, 4, 5, 6
    order by 1, 2, 3, 4, 5, 6;

--create temporary table tfuel_carbon_sum_table;
drop table if exists tfuel_carbon_sum_table;
select		scenario_id, carbon_cost, period, province_id, province, technology_id,
			sum(variable_o_m_cost * hours_in_sample) as variable_o_m_cost,		
			sum( ( fuel_cost + spinning_fuel_cost + deep_cycling_fuel_cost ) * hours_in_sample) as fuel_cost,
			sum( ( carbon_cost_hourly + spinning_carbon_cost_incurred + deep_cycling_carbon_cost ) * hours_in_sample) as carbon_cost_total
			into tfuel_carbon_sum_table
			from _gen_hourly_summary_tech_la
		    where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) 
		    --where scenario_id = (select china.get_scenario()) 
		    group by 1, 2, 3, 4, 5, 6;

--alter table tfuel_carbon_sum_table add index fcst_idx (scenario_id, carbon_cost, period, province, technology_id);

alter table _gen_cap_summary_tech_la add column variable_o_m_cost double precision;
alter table _gen_cap_summary_tech_la add column fuel_cost double precision;
alter table _gen_cap_summary_tech_la add column carbon_cost_total double precision;
		   
update 	_gen_cap_summary_tech_la
set 	variable_o_m_cost = t.variable_o_m_cost,
		fuel_cost 		= t.fuel_cost,
		carbon_cost_total = t.carbon_cost_total
from 	tfuel_carbon_sum_table t
where 	_gen_cap_summary_tech_la.scenario_id 		= t.scenario_id
and 	_gen_cap_summary_tech_la.carbon_cost 		= t.carbon_cost
and 	_gen_cap_summary_tech_la.period 			= t.period
and 	_gen_cap_summary_tech_la.province_id 		= t.province_id
and 	_gen_cap_summary_tech_la.province 			= t.province
and 	_gen_cap_summary_tech_la.technology_id 	= t.technology_id;

-- capacity each period
-- carbon_cost column includes carbon costs incurred for power and spinning reserves
--insert into _gen_cap_summary_tech
drop table if exists _gen_cap_summary_tech CASCADE;
select scenario_id, carbon_cost, period, technology_id,
	sum(capacity) as capacity, 
	sum(capital_cost) as capital_cost, 
	sum(fixed_o_m_cost + variable_o_m_cost) as o_m_cost_total, 
	sum(fuel_cost) as fuel_cost, 
	sum(carbon_cost_total) as carbon_cost_total
	into _gen_cap_summary_tech
	from _gen_cap_summary_tech_la join generator_tech_fuel using (technology_id)
    where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) 
    -- where scenario_id = (select china.get_scenario()) 
    group by 1, 2, 3, 4
    order by 1, 2, 3, 4;


-- now aggregated on a fuel basis
--insert into _gen_cap_summary_fuel_la 
drop table if exists _gen_cap_summary_fuel_la CASCADE;
select 	scenario_id, carbon_cost, period, province_id, province, fuel,
	sum(capacity) as capacity, 
	sum(capital_cost) as capital_cost, 
	sum(fixed_o_m_cost) as fixed_o_m_cost,
	sum(variable_o_m_cost) as variable_o_m_cost, 
	sum(fuel_cost) as fuel_cost, 
	sum(carbon_cost_total) as carbon_cost_total
	into _gen_cap_summary_fuel_la
	from _gen_cap_summary_tech_la join generator_tech_fuel using (technology_id)
    where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) 
    -- where scenario_id = (select china.get_scenario()) 
    group by 1, 2, 3, 4, 5, 6
    order by 1, 2, 3, 4, 5, 6;

-- capacity each period
--insert into _gen_cap_summary_fuel
drop table if exists _gen_cap_summary_fuel CASCADE;
select scenario_id, carbon_cost, period, fuel,
	sum(capacity) as capacity, 
	sum(capital_cost) as capital_cost, 
	sum(fixed_o_m_cost + variable_o_m_cost) as o_m_cost_total, 
	sum(fuel_cost) as fuel_cost, 
	sum(carbon_cost_total) as carbon_cost_total
	into _gen_cap_summary_fuel
	from _gen_cap_summary_fuel_la
    where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) 
    -- where scenario_id = (select china.get_scenario()) 
	group by 1, 2, 3, 4
	order by 1, 2, 3, 4;


-- TRANSMISSION ----------------
select 'Creating transmission summaries' as progress;
-- Make a simple transmission capacity table
drop table if exists _trans_cap_summary;
select scenario_id, carbon_cost, period, if_new, sum(trans_mw)/2 as capacity_mw, sum(fixed_cost) as cost
	into _trans_cap_summary
	from _trans_cap
	where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results)
	group by 1,2,3,4
	order by 1,2,3,4;

-- And by LA
drop table if exists _trans_cap_la_summary;
select scenario_id, carbon_cost, period, if_new, start_id, end_id, province_start, province_end, sum(trans_mw) as capacity_mw, sum(fixed_cost) as cost
into _trans_cap_la_summary
from _trans_cap
where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results)
group by 1,2,3,4,5,6,7,8
order by 1,2,3,4,5,6,7,8;

-- add helpful columns to _transmission_dispatch
-- These are commented once _transmission_dispatch has been altered. Better check would be to run them only if the table exists already.
alter table _transmission_dispatch add column study_month smallint;  
alter table _transmission_dispatch add column hour_of_day smallint;
update _transmission_dispatch
set	study_month = substring(study_date::varchar from 5 for 2)::smallint,
	hour_of_day = substring(study_hour::varchar from 9 for 2)::smallint
	where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) 
	--where scenario_id = (select china.get_scenario()) 
	;

-- Transmission summary: net transmission for each zone in each hour
-- NOTE: This table seems to be repeated with transmission_directed_hourly. Check if this one should have built capacity (from trans_cap) rather than dispatch.
-- First add imports, then subtract exports
--insert into _trans_summary (scenario_id, carbon_cost, period, province, study_date, study_hour, study_month, hour_of_day, hours_in_sample, net_power)
drop table if exists _trans_summary_imp;
select 	scenario_id,
  			carbon_cost,
  			period,
  			province_receive_id,
  			study_date,
  			study_hour,
  			study_month,
	 		hour_of_day,
	 		hours_in_sample,
	 		sum(power_received) as net_power
    into _trans_summary_imp
	from _transmission_dispatch
    where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) 
    -- where scenario_id = (select china.get_scenario()) 
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9
    order by 1, 2, 3, 4, 5, 6, 7, 8, 9;
	
  --drop table if exists _trans_summary_exp;
  insert into _trans_summary_imp
  select 	scenario_id,
  			carbon_cost,
  			period,
  			province_from_id,
  			study_date,
  			study_hour,
  			study_month,
	 		hour_of_day,
	 		hours_in_sample,
	 		-sum(power_sent) as net_power
	from _transmission_dispatch
    where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) 
    -- where scenario_id = (select china.get_scenario()) 
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9
    order by 1, 2, 3, 4, 5, 6, 7, 8, 9;

	--Put everything together
drop table if exists _trans_summary;
select 	scenario_id,
		carbon_cost,
		period,
		province_receive_id,
		study_date,
		study_hour,
		study_month,
		hour_of_day,
		hours_in_sample,
		sum(net_power)
    into _trans_summary
    from _trans_summary_imp
    where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) 
    -- where scenario_id = (select china.get_scenario()) 
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9
    order by 1, 2, 3, 4, 5, 6, 7, 8, 9;
	
drop table if exists _trans_summary_imp;

  --on duplicate key update net_power = net_power + VALUES(net_power);

-- Tally transmission losses using a similar method
--insert into _trans_loss (scenario_id, carbon_cost, period, province, study_date, study_hour, study_month, hour_of_day, hours_in_sample, system_power)
  drop table if exists _trans_loss;
  select 	scenario_id,
  			carbon_cost,
  			period,
  			province_from_id,
  			study_date,
  			study_hour,
  			study_month,
  			hour_of_day,
  			hours_in_sample,
  			sum(power_sent - power_received) as system_power
    into _trans_loss
	from _transmission_dispatch
    where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) -- where scenario_id = (select china.get_scenario()) 
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9
    order by 1, 2, 3, 4, 5, 6, 7, 8, 9;


-- directed transmission 
-- TODO: make some indexed temp tables to speed up these queries
-- the sum is still needed in the trans_direction_table as there could be different fuel types transmitted
--insert into _transmission_directed_hourly ( scenario_id, carbon_cost, period, transmission_line_id, province_from_id, province_receive_id, study_hour, hour_of_day, directed_trans_avg )
drop table if exists _transmission_directed_hourly;
select 	scenario_id,
		carbon_cost,
		period,
		transmission_line_id,
		province_from_id,
		province_receive_id,
		study_hour,
		mod(floor(study_hour/1000)::integer,100) as hour_of_day,
		round( directed_trans_avg ) as directed_trans_avg
into _transmission_directed_hourly
-- ** Note change from transmission_lines to transmission_between_la
from	transmission_lines tl,

	(select distinct (scenario_id, carbon_cost), scenario_id, carbon_cost,
			period,
			study_hour,
			(CASE WHEN average_transmission > 0 THEN province_from_id ELSE province_receive_id END) as province_from_id,
			(CASE WHEN average_transmission > 0 THEN province_receive_id ELSE province_from_id END) as province_receive_id,
			abs(average_transmission) as directed_trans_avg
		from
			(select scenario_id,
					carbon_cost,
					period,
					study_hour,
					province_from_id,
					province_receive_id,
					sum(average_transmission) as average_transmission
				from 
					(select scenario_id,
							carbon_cost,
							period,
							study_hour,
							province_from_id,
							province_receive_id,
							sum( ( power_sent + power_received ) / 2 ) as average_transmission
						from _transmission_dispatch
						where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results)
						--where scenario_id = (select china.get_scenario())
						group by 1,2,3,4,5,6
						UNION
					select 	scenario_id,
							carbon_cost,
							period,
							study_hour,
							province_receive_id as province_from_id,
							province_from_id as province_receive_id,
							sum( -1 * ( power_sent + power_received ) / 2 ) as average_transmission
						from _transmission_dispatch 
						where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results)
						--where scenario_id = (select china.get_scenario()) 
						group by 1,2,3,4,5,6
					) as trans_direction_table
				group by 1,2,3,4,5,6) as avg_trans_table
		) as directed_trans_table

where 	directed_trans_table.province_from_id = tl.province_start_id
and		directed_trans_table.province_receive_id = tl.province_end_id
order by 1, 2, 3, 5, 6, 7;

-- now do the same as above, but aggregated
-- TODO: could speed this up by referencing the above table
--insert into _transmission_avg_directed
drop table if exists _transmission_avg_directed;
select 	scenario_id,
		carbon_cost,
		period,
		transmission_line_id,
		province_from_id,
		province_receive_id,
		round( directed_trans_avg ) as directed_trans_avg
into _transmission_avg_directed
-- ** Note change from transmission_lines to transmission_between_la
from	transmission_lines tl,

	(select distinct (scenario_id, carbon_cost), scenario_id, carbon_cost,
			period,
			(CASE WHEN average_transmission > 0 THEN province_from_id ELSE province_receive_id END) as province_from_id,
			(CASE WHEN average_transmission > 0 THEN province_receive_id ELSE province_from_id END) as province_receive_id,
			abs(average_transmission) as directed_trans_avg
		from
			(select scenario_id,
					carbon_cost,
					period,
					province_from_id,
					province_receive_id,
					sum(average_transmission) as average_transmission
				from 
					(select scenario_id,
							carbon_cost,
							period,
							province_from_id,
							province_receive_id,
							sum( hours_in_sample * ( ( power_sent + power_received ) / 2 ) ) / sum_hourly_weights_per_period as average_transmission
						from _transmission_dispatch join sum_hourly_weights_per_period_table using (scenario_id, period) 
						where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results)
						-- where scenario_id = (select china.get_scenario())  
						group by 1,2,3,4,5,sum_hourly_weights_per_period_table.sum_hourly_weights_per_period
						UNION
					select 	scenario_id,
							carbon_cost,
							period,
							province_receive_id as province_from_id,
							province_from_id as province_receive_id,
							-1 * sum( hours_in_sample * ( ( power_sent + power_received ) / 2 ) ) / sum_hourly_weights_per_period as average_transmission
						from _transmission_dispatch join sum_hourly_weights_per_period_table using (scenario_id, period) 
						where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results)
						-- where scenario_id = (select china.get_scenario())  
						group by 1,2,3,4,5,sum_hourly_weights_per_period_table.sum_hourly_weights_per_period
					) as trans_direction_table
				group by 1,2,3,4,5) as avg_trans_table
		) as directed_trans_table

where 	directed_trans_table.province_from_id = tl.province_start_id
and		directed_trans_table.province_receive_id = tl.province_end_id
order by 1, 2, 3, 5, 6; 


-- CO2 Emissions --------------------
select 'Calculating CO2 emissions' as progress;
-- see WECC_Plants_For_Emissions in the Switch_Input_Data folder for a calculation of the yearly 1990 emissions from WECC
--set @co2_tons_1990 := 500,000,000; Source: 
--For China, we can compare carbon emission to year 2005 level, set @co2_tons_2005 := 2286000000 tons; source: Changce Power Sector Climate Change Report.
drop table if exists co2_tons_2005;
select 2286000000 as the_value into co2_tons_2005;
-- The query to get the value now is (select * from co2_tons_2005 limit 1)

--insert into co2_cc
drop table if exists co2_cc;
select 	scenario_id,
			carbon_cost,
			_gen_hourly_summary_tech_la.period,
			sum( ( co2_tons + spinning_co2_tons + deep_cycling_co2_tons ) * hours_in_sample ) / years_per_period as co2_tons, 
     		(select * from co2_tons_2005 limit 1) - sum( ( co2_tons + spinning_co2_tons + deep_cycling_co2_tons ) * hours_in_sample ) / years_per_period as co2_tons_reduced_2005,
    		1 - ( sum( ( co2_tons + spinning_co2_tons + deep_cycling_co2_tons ) * hours_in_sample ) / years_per_period ) / (select * from co2_tons_2005 limit 1) as co2_share_reduced_2005
  	into co2_cc
	from 	_gen_hourly_summary_tech_la join sum_hourly_weights_per_period_table using (scenario_id, period)
  	where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results)
  	--where 	scenario_id = (select china.get_scenario()) 
  	group by 1, 2, 3, sum_hourly_weights_per_period_table.years_per_period
  	order by 1, 2, 3;



-- SYSTEM LOAD ---------------
alter table _system_load add column study_month smallint;
alter table _system_load add column hour_of_day smallint;
update _system_load
set	study_month = substring(study_date::varchar from 5 for 2)::smallint,
	hour_of_day = substring(study_hour::varchar from 9 for 2)::smallint
	where study_month IS NULL
	--where scenario_id = (select china.get_scenario()) 
	;

-- add hourly system load aggregated by province here
--insert into system_load_summary_hourly (scenario_id, carbon_cost, period, study_date, study_hour, study_month, hour_of_day, hour_of_day,
--  										hours_in_sample, system_load, satisfy_load_reduced_cost, satisfy_load_reserve_reduced_cost)
drop table if exists system_load_summary_hourly;
select 	scenario_id,
		carbon_cost,
		period,
		study_date,
		study_hour,
		study_month,
		hour_of_day,
		--mod(hour_of_day - 8, 24) as hour_of_day,
		hours_in_sample,
		sum( system_power ) as system_load,
		sum( satisfy_load_reduced_cost ) as satisfy_load_reduced_cost,
		sum( satisfy_load_reserve_reduced_cost ) as satisfy_load_reserve_reduced_cost
into system_load_summary_hourly
from _system_load
where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results)
--where scenario_id = (select china.get_scenario()) 
group by 1, 2, 3, 4, 5, 6, 7, 8
order by 1, 2, 3, 4, 5, 6, 7, 8;


--insert into system_load_summary
drop table if exists system_load_summary;
select 	scenario_id,
		carbon_cost,
		period,
		sum( hours_in_sample * system_load ) / sum_hourly_weights_per_period as system_load,
		sum( hours_in_sample * satisfy_load_reduced_cost ) / sum_hourly_weights_per_period as satisfy_load_reduced_cost_weighted,
		sum( hours_in_sample * satisfy_load_reserve_reduced_cost ) / sum_hourly_weights_per_period as satisfy_load_reserve_reduced_cost_weighted
into system_load_summary
from system_load_summary_hourly join sum_hourly_weights_per_period_table using (scenario_id, period)
where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results)
--where scenario_id = (select china.get_scenario()) 
group by 1, 2, 3, sum_hourly_weights_per_period_table.sum_hourly_weights_per_period
order by 1, 2, 3;


-- SYSTEM COSTS ---------------
select 'Calculating system costs' as progress;
-- average power costs, for each study period, for each carbon tax

--insert into power_cost (scenario_id, carbon_cost, period, load_in_period_mwh )
drop table if exists power_cost;
select 	scenario_id,
  		carbon_cost,
  		period,
  		system_load * sum_hourly_weights_per_period as load_in_period_mwh,
			0.00::double precision as existing_local_td_cost,
			0.00::double precision as new_local_td_cost,
			0.00::double precision as existing_transmission_cost,
			0.00::double precision as new_transmission_cost,
			0.00::double precision as existing_plant_sunk_cost,
			0.00::double precision as existing_plant_operational_cost,
			0.00::double precision as new_coal_nonfuel_cost,
			0.00::double precision as coal_fuel_cost,
			0.00::double precision as new_gas_nonfuel_cost,
			0.00::double precision as gas_fuel_cost,
			0.00::double precision as new_nuclear_nonfuel_cost,
			0.00::double precision as nuclear_fuel_cost,
			0.00::double precision as new_geothermal_cost,
			0.00::double precision as new_bio_cost,
			0.00::double precision as new_wind_cost,
			0.00::double precision as new_solar_cost,
			0.00::double precision as new_storage_nonfuel_cost,
			0.00::double precision as carbon_cost_total,
			0.00::double precision as total_cost,
			0.00::double precision as cost_per_mwh
  into power_cost
  from system_load_summary join sum_hourly_weights_per_period_table using (scenario_id, period)
  where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results)
  --where scenario_id = (select china.get_scenario()) 
  order by 1, 2, 3;
  
-- now calculated a bunch of costs

-- local_td costs
update power_cost set existing_local_td_cost =
	(select sum(fixed_cost) from _local_td_cap t
		where t.scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) and /*t.scenario_id = (select china.get_scenario())  and*/ t.scenario_id = power_cost.scenario_id
		and t.carbon_cost = power_cost.carbon_cost and t.period = power_cost.period and 
		if_new = false );

update power_cost set new_local_td_cost =
	(select sum(fixed_cost) from _local_td_cap t
		where t.scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) and /*t.scenario_id = (select china.get_scenario())  and*/ t.scenario_id = power_cost.scenario_id
		and t.carbon_cost = power_cost.carbon_cost and t.period = power_cost.period and 
		if_new = true );

-- transmission costs
update power_cost set existing_transmission_cost =
	(select sum(existing_trans_cost) from _existing_trans_cost t
		where t.scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) and /*t.scenario_id = (select china.get_scenario())  and*/ t.scenario_id = power_cost.scenario_id
		and t.carbon_cost = power_cost.carbon_cost and t.period = power_cost.period );

update power_cost set new_transmission_cost =
	(select sum(fixed_cost) from _trans_cap t
		where t.scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) and /*t.scenario_id = (select china.get_scenario())  and*/ t.scenario_id = power_cost.scenario_id
		and t.carbon_cost = power_cost.carbon_cost and t.period = power_cost.period and 
		if_new = true );

-- generation costs
update power_cost set existing_plant_sunk_cost =
	(select sum(capital_cost) from _gen_cap_summary_tech g
		where g.scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) and /*g.scenario_id = (select china.get_scenario())  and*/ g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_tech_fuel where can_build_new = false) );

update power_cost set existing_plant_operational_cost =
	(select sum(o_m_cost_total) from _gen_cap_summary_tech g
		where g.scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) and /*g.scenario_id = (select china.get_scenario())  and*/ g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_tech_fuel where can_build_new = false) );

update power_cost set new_coal_nonfuel_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) from _gen_cap_summary_tech g
		where g.scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) and /*g.scenario_id = (select china.get_scenario())  and*/ g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_tech_fuel where fuel in ('Coal', 'Coal_CCS') and can_build_new = true) );

update power_cost set coal_fuel_cost =
	(select sum(fuel_cost) from _gen_cap_summary_tech g
		where g.scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) and /*g.scenario_id = (select china.get_scenario())  and*/ g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_tech_fuel where fuel in ('Coal', 'Coal_CCS') ) );

update power_cost set new_gas_nonfuel_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) from _gen_cap_summary_tech g
		where g.scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) and /*g.scenario_id = (select china.get_scenario())  and*/ g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_tech_fuel where fuel in ('Gas', 'Gas_CCS') and storage = false and can_build_new = true ) );

update power_cost set gas_fuel_cost =
	(select sum(fuel_cost) from _gen_cap_summary_tech g
		where g.scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) and /*g.scenario_id = (select china.get_scenario())  and*/ g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_tech_fuel where fuel in ('Gas', 'Gas_CCS') ) );

update power_cost set new_nuclear_nonfuel_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) from _gen_cap_summary_tech g
		where g.scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) and /*g.scenario_id = (select china.get_scenario())  and*/ g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_tech_fuel where fuel = 'Uranium' and can_build_new = true) );

update power_cost set nuclear_fuel_cost =
	(select sum(fuel_cost) from _gen_cap_summary_tech g
		where g.scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) and /*g.scenario_id = (select china.get_scenario())  and*/ g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_tech_fuel where fuel = 'Uranium') );

update power_cost set new_geothermal_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _gen_cap_summary_tech g
		where g.scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) and /*g.scenario_id = (select china.get_scenario())  and*/ g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_tech_fuel where fuel = 'Geothermal' and can_build_new = true ) );

update power_cost set new_bio_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _gen_cap_summary_tech g
		where g.scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) and /*g.scenario_id = (select china.get_scenario())  and*/ g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_tech_fuel where fuel in ('Bio_Gas', 'Bio_Solid', 'Bio_Gas_CCS', 'Bio_Solid_CCS') and can_build_new = true ) );

update power_cost set new_wind_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _gen_cap_summary_tech g
		where g.scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) and /*g.scenario_id = (select china.get_scenario())  and*/ g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_tech_fuel where fuel = 'Wind' and can_build_new = true ) );

update power_cost set new_solar_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) + sum(fuel_cost) from _gen_cap_summary_tech g
		where g.scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) and /*g.scenario_id = (select china.get_scenario())  and*/ g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_tech_fuel where fuel = 'Solar' and can_build_new = true ) );

update power_cost set new_storage_nonfuel_cost =
	(select sum(capital_cost) + sum(o_m_cost_total) from _gen_cap_summary_tech g
		where g.scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) and /*g.scenario_id = (select china.get_scenario())  and*/ g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period and 
		technology_id	in (select technology_id from generator_tech_fuel where storage = true and can_build_new = true ) );

update power_cost set carbon_cost_total =
	(select sum(carbon_cost_total) from _gen_cap_summary_tech g
		where g.scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) and /*g.scenario_id = (select china.get_scenario())  and*/ g.scenario_id = power_cost.scenario_id
		and g.carbon_cost = power_cost.carbon_cost and g.period = power_cost.period );
		
--NULL data cannot add to the total cost
update power_cost set new_nuclear_nonfuel_cost = 0
	where new_nuclear_nonfuel_cost is null;

update power_cost set new_geothermal_cost = 0
	where new_geothermal_cost is null;
	
update power_cost set new_bio_cost = 0
	where new_bio_cost is null;
	
update power_cost set new_solar_cost = 0
	where new_solar_cost is null;

update power_cost set total_cost =
	( existing_local_td_cost + new_local_td_cost + existing_transmission_cost + new_transmission_cost 
	+ existing_plant_sunk_cost + existing_plant_operational_cost + new_coal_nonfuel_cost + coal_fuel_cost
	+ new_gas_nonfuel_cost + gas_fuel_cost + new_nuclear_nonfuel_cost + nuclear_fuel_cost
	+ new_geothermal_cost + new_bio_cost 
	+ new_wind_cost + new_solar_cost + new_storage_nonfuel_cost + carbon_cost_total )
	where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results)
	--where scenario_id = (select china.get_scenario()) 
	;

update power_cost set cost_per_mwh = total_cost / load_in_period_mwh
	where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results)
	--where scenario_id = (select china.get_scenario()) 
	;

---- Extract fuel category definitions from the results
--CREATE TEMPORARY TABLE fc_defs as
--  SELECT DISTINCT scenario_id, period, technology_id, fuel, fuel_category
--    FROM _generator_and_storage_dispatch
--    where scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results)
--    --WHERE scenario_id = (select china.get_scenario()) 
--	;
--
----INSERT IGNORE INTO fuel_categories (fuel_category)
--drop table if exists fuel_categories;
--  SELECT DISTINCT fuel_category INTO fuel_categories FROM fc_defs;
--
----INSERT IGNORE INTO fuel_category_definitions (fuel_category_id, scenario_id, period, technology_id, fuel )
----Note: Changed fuel_category_id to fuel_category. Seemed like a typing mistake
--drop table if exists fuel_category_definitions;
--SELECT fuel_category, scenario_id, period, technology_id, fuel 
--  INTO fc_defs
--  FROM fuel_categories JOIN fuel_category_definitions USING (fuel_category);

-- Calculate summary stats based on fuel category
-- We're incorectly adding emissions from spinning reserves to the locally produced power. Really, the spinning emissions need to be apportioned based on what they are spinning for. 
-- Some of the emissions will be based on 5% of load for provinces in the balancing area. 
-- The remainder of the emissions will be based on 3% of renewable output, and needs to be embedded with the renewable power and ultimately assigned to whichever province consumes it. 
-- This is too complicated for me for now and doesn't really matter because emissions from spinning reserves are less than .1% of total emissions. 
--INSERT INTO _gen_hourly_summary_fc_la 
--  (scenario_id, carbon_cost, period, province, study_date, study_hour, hours_in_sample, fuel_category_id, storage, power, total_co2_tons)

--drop table if exists _gen_hourly_summary_fc_la;
--create table _gen_hourly_summary_fc_la (
--	scenario_id smallint, 
--	carbon_cost double precision, 
--	period smallint, 
--	province_id smallint, 
--	province varchar, 
--	study_date int, 
--	study_hour int, 
--	hours_in_sample double precision, 
--	fuel_category varchar, 
--	storage smallint, 
--	system_power double precision,
--	co2_tons double precision,
--	primary key (scenario_id, carbon_cost, period, province_id, study_hour, fuel_category, storage)
--	);
--	
--insert into _gen_hourly_summary_fc_la
--SELECT temp.scenario_id, temp.carbon_cost, temp.period, temp.province_id, temp.province, temp.study_date, temp.study_hour, temp.hours_in_sample, fuel_category, 
--      temp.storage, SUM(system_power) as system_power, SUM(co2_tons + spinning_co2_tons + deep_cycling_co2_tons) as co2_tons
--  --into _gen_hourly_summary_fc_la
--	FROM 	(select scenario_id, carbon_cost, period, province_id, province, study_date, study_hour, hours_in_sample,
--		(CASE WHEN fuel='Storage' THEN 1 ELSE 0 END) as storage from _generator_and_storage_dispatch
--		group by 1,2,3,4,5,6,7,8,9) as temp,
--		_generator_and_storage_dispatch gs
--      JOIN fuel_categories USING( fuel_category)
--    WHERE temp.scenario_id = (SELECT results_scenario_id FROM scenario_id_crunch_results) and /*temp.scenario_id = (select china.get_scenario())
--    and*/  gs.scenario_id = temp.scenario_id
--    and  gs.carbon_cost = temp.carbon_cost 
--    and  gs.period = temp.period
--    and  gs.province_id = temp.province_id
--    and  gs.province = temp.province 
--    and  gs.study_date = temp.study_date
--    and  gs.study_hour = temp.study_hour
--    GROUP BY temp.scenario_id, temp.carbon_cost, temp.period, temp.province_id, temp.province, temp.study_date, temp.study_hour, temp.hours_in_sample, fuel_category, temp.storage;

-- Calculate the carbon intensity of electricity
-- JP: Still have to create/translate this function
--CALL calc_carbon_intensity((select china.get_scenario()) ); */
