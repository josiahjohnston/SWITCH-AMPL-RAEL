

select * from natural_gas_regional_price_adders;

create table natural_gas_regional_price_adders_v3 like natural_gas_regional_price_adders;

select * from natural_gas_regional_price_adders_v3;


-- 1.15 is the inflation between 2007 and 2016 for the US dollar ($1 in 2007 = $1.15 in 2016)
insert into natural_gas_regional_price_adders_v3
select fuel, nems_region, nems_scenario, simulation_year, 1.15 * regional_price_adder
from natural_gas_regional_price_adders;

alter table natural_gas_regional_price_adders_v3 add column notes VARCHAR(300);

update natural_gas_regional_price_adders_v3 set notes = 'Values from natural_gas_regional_price_adders but in US$ 2016';

select * from natural_gas_regional_price_adders_v3;
