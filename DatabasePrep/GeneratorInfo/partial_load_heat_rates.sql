drop table switch_inputs_wecc_v2_2.partial_load_heat_rates;
create table switch_inputs_wecc_v2_2.partial_load_heat_rates (
	technology_id tinyint(3) unsigned,
	technology       varchar(64),
	percent_of_full_load decimal(4,3),
	relative_heat_rate decimal(4,3),
	index (technology_id),
	index (technology),
	unique (technology_id, percent_of_full_load)
);

load data local infile 'partial_load_heat_rates.txt' 
	into table switch_inputs_wecc_v2_2.partial_load_heat_rates
	ignore 1 lines
	(technology, percent_of_full_load, relative_heat_rate);

update switch_inputs_wecc_v2_2.partial_load_heat_rates, switch_inputs_wecc_v2_2.generator_info 
	set partial_load_heat_rates.technology_id = generator_info.technology_id
	where partial_load_heat_rates.technology = generator_info.technology;

DROP FUNCTION IF EXISTS switch_inputs_wecc_v2_2.partial_load_heat_rate_linear_interp ;
DELIMITER $$
CREATE FUNCTION switch_inputs_wecc_v2_2.partial_load_heat_rate_linear_interp (tech_id tinyint(3), p float) RETURNS DECIMAL(4,3) DETERMINISTIC
BEGIN
	DECLARE p1 DECIMAL(4,3);
	DECLARE p2 DECIMAL(4,3);
	DECLARE h1 DECIMAL(4,3);
	DECLARE h2 DECIMAL(4,3);
	SET p1 := (SELECT MIN(percent_of_full_load) FROM partial_load_heat_rates WHERE technology_id=tech_id and percent_of_full_load >= p); 
	SET p2 := (SELECT MAX(percent_of_full_load) FROM partial_load_heat_rates WHERE technology_id=tech_id and percent_of_full_load <= p); 
	SET h1 := (SELECT relative_heat_rate FROM partial_load_heat_rates WHERE technology_id=tech_id and percent_of_full_load = p1);
	SET h2 := (SELECT relative_heat_rate FROM partial_load_heat_rates WHERE technology_id=tech_id and percent_of_full_load = p2);
	IF p1 = p2 THEN
		RETURN h1;
	END IF;
	RETURN h1 + (h2-h1)/(p2-p1)*(p-p1);
END
$$
DELIMITER ;

-- Multiply spinning reserves in MW by the heat rate and this number to calculate the fuel penalty.
DROP FUNCTION IF EXISTS switch_inputs_wecc_v2_2.spinning_reserve_heat_rate_factor ;
DELIMITER $$
CREATE FUNCTION switch_inputs_wecc_v2_2.spinning_reserve_heat_rate_factor (tech_id tinyint(3), p float) RETURNS DECIMAL(4,3) DETERMINISTIC
BEGIN
  IF p = 1 THEN
    RETURN 0;
  END IF;
  RETURN (switch_inputs_wecc_v2_2.partial_load_heat_rate_linear_interp(tech_id, p) - 1) * p / (1-p);
END
$$
DELIMITER ;

-- Atomic differences in estimates of fuel needed for spinning reserves.
--  fuel_penalty_0 uses a static heat rate penalty from units running at 75% capacity
--  fuel_penalty_1 uses a dynamic heat rate penalty based on the percentage of unit committment devoted to spinning reserves
CREATE OR REPLACE VIEW switch_results_wecc_v2_2.spinning_fuel_penalties AS
select technology, spinning_reserve, power, spinning_reserve + power as unit_commitment,
  round(spinning_reserve/(spinning_reserve+power),2) as p,
  round(power*heat_rate*(relative_heat_rate-1)) as fuel_penalty_rough_estimate, 
  round(power*heat_rate*switch_inputs_wecc_v2_2.partial_load_heat_rate_linear_interp(technology_id, 1-spinning_reserve/(spinning_reserve+power))) as fuel_penalty_better_estimate,
  _generator_and_storage_dispatch.project_id, _generator_and_storage_dispatch.study_hour, _generator_and_storage_dispatch.hours_in_sample,
  _generator_and_storage_dispatch.fuel, _generator_and_storage_dispatch.fuel_category
from switch_results_wecc_v2_2._generator_and_storage_dispatch 
  join `switch_inputs_wecc_v2_2`.`partial_load_heat_rates` using (technology_id) 
where spinning_reserve > 0 and
   percent_of_full_load = 0.75 and
   technology <> 'Hydro_NonPumped' and
   technology <> 'Hydro_Pumped' and
   technology <> 'Compressed_Air_Energy_Storage'
;


-- Difference in Fuel penalty broken down by tech & load fraction
CREATE OR REPLACE VIEW switch_results_wecc_v2_2.spinning_fuel_penalty_by_tech_and_cap_fraction AS
select scenario_id, carbon_cost, technology, round(power/(spinning_reserve+power),2) as p,
  count(hours_in_sample) as n, 
  round( sum( ( 
      spinning_reserve*g.heat_rate* switch_inputs_wecc_v2_2.spinning_reserve_heat_rate_factor(g.technology_id, 0.75) -- fuel_penalty_0
    - spinning_reserve*g.heat_rate* switch_inputs_wecc_v2_2.spinning_reserve_heat_rate_factor(g.technology_id, power/(spinning_reserve+power))   -- fuel_penalty_1
  ) * hours_in_sample ) / sum(hours_in_sample) ) as avg_error_MBTU
from switch_results_wecc_v2_2._generator_and_storage_dispatch g
  join switch_results_wecc_v2_2.technologies using (technology_id) 
where spinning_reserve>0 and 
   technology <> 'Hydro_NonPumped' and
   technology <> 'Hydro_Pumped' and
   technology <> 'Compressed_Air_Energy_Storage'
group by 1, 2, 3, 4
order by 1, 2, 3, 4
;


-- Difference in Fuel penalty broken down by tech
CREATE OR REPLACE VIEW switch_results_wecc_v2_2.spinning_fuel_penalty_by_tech AS
select scenario_id, carbon_cost, technology, 
  count(hours_in_sample) as n, 
  round( sum( spinning_reserve * hours_in_sample ) / sum(hours_in_sample) ) as avg_spinning_reserve_provided,
  round( sum( ( 
      spinning_reserve*g.heat_rate* switch_inputs_wecc_v2_2.spinning_reserve_heat_rate_factor(g.technology_id, 0.75) -- fuel_penalty_0
    - spinning_reserve*g.heat_rate* switch_inputs_wecc_v2_2.spinning_reserve_heat_rate_factor(g.technology_id, power/(spinning_reserve+power))   -- fuel_penalty_1
  ) * hours_in_sample ) / sum(hours_in_sample) ) as avg_error_MBTU,
	round( sum( ( 
			spinning_reserve*g.heat_rate* switch_inputs_wecc_v2_2.spinning_reserve_heat_rate_factor(g.technology_id, 0.75) -- fuel_penalty_0
		- spinning_reserve*g.heat_rate* switch_inputs_wecc_v2_2.spinning_reserve_heat_rate_factor(g.technology_id, power/(spinning_reserve+power))   -- fuel_penalty_1
	) * hours_in_sample )) as total_error_MBTU,
  round( sum( spinning_reserve*g.heat_rate* switch_inputs_wecc_v2_2.spinning_reserve_heat_rate_factor(g.technology_id, power/(spinning_reserve+power)) * hours_in_sample)) as total_MBTU_for_spinning, 
  round( 
		sum( ( 
				spinning_reserve*g.heat_rate* switch_inputs_wecc_v2_2.spinning_reserve_heat_rate_factor(g.technology_id, 0.75) -- fuel_penalty_0
			- spinning_reserve*g.heat_rate* switch_inputs_wecc_v2_2.spinning_reserve_heat_rate_factor(g.technology_id, power/(spinning_reserve+power))   -- fuel_penalty_1
		) * hours_in_sample )
		/ sum( spinning_reserve*g.heat_rate* switch_inputs_wecc_v2_2.spinning_reserve_heat_rate_factor(g.technology_id, power/(spinning_reserve+power)) * hours_in_sample )
	, 3 ) as percentage_error
from switch_results_wecc_v2_2._generator_and_storage_dispatch g
  join switch_results_wecc_v2_2.technologies using (technology_id) 
where spinning_reserve>0 and 
   technology <> 'Hydro_NonPumped' and
   technology <> 'Hydro_Pumped' and
   technology <> 'Compressed_Air_Energy_Storage'
group by 1, 2, 3
;
