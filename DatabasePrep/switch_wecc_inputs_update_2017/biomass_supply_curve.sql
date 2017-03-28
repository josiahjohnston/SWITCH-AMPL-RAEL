

select * from biomass_solid_supply_curve;

create table biomass_solid_supply_curve_v3 like biomass_solid_supply_curve;

insert into biomass_solid_supply_curve_v3
select breakpoint_id, load_area, year, 1.15 * price_dollars_per_mmbtu_surplus_adjusted, breakpoint_mmbtu_per_year
from biomass_solid_supply_curve;

alter table biomass_solid_supply_curve_v3 add column notes VARCHAR(300);

update biomass_solid_supply_curve_v3 set notes = 'Values from biomass_solid_supply_curve but in US$ 2016';