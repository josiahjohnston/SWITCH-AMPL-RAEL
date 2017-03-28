-- ng_supply_curve.tab


select * from natural_gas_supply_curve;

create table natural_gas_supply_curve_v3 like natural_gas_supply_curve;

select * from natural_gas_supply_curve_v3;


-- 1.15 is the inflation between 2007 and 2016 for the US dollar ($1 in 2007 = $1.15 in 2016)
insert into natural_gas_supply_curve_v3
select fuel, nems_scenario, simulation_year, breakpoint_id, consumption_breakpoint, 1.15 * price_surplus_adjusted
from natural_gas_supply_curve;

select * from natural_gas_supply_curve_v3;


alter table natural_gas_supply_curve_v3 add column notes VARCHAR(300);

update natural_gas_supply_curve_v3 set notes = 'Values from natural_gas_supply_curve but in US$ 2016';

select * from natural_gas_supply_curve_v3;