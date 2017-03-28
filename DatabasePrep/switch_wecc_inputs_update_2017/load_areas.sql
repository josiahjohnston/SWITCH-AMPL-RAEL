

-- load areas dollars in US$ 2016

select load_area, area_id as load_area_id, primary_state, primary_nerc_subregion as balancing_area, rps_compliance_entity, 
economic_multiplier, max_coincident_load_for_local_td, local_td_new_annual_payment_per_mw, local_td_sunk_annual_payment, 
transmission_sunk_annual_payment, ccs_distance_km, bio_gas_capacity_limit_mmbtu_per_hour, nems_fuel_region 
from load_area_info;

select * from load_area_info;

create table load_area_info_v3 like load_area_info;


insert into load_area_info_v3
select area_id, load_area, primary_nerc_subregion, primary_state, economic_multiplier_archive, total_yearly_load_mwh, 1.15 * local_td_new_annual_payment_per_mw,
1.15 * local_td_sunk_annual_payment, 1.15 * transmission_sunk_annual_payment, max_coincident_load_for_local_td, ccs_distance_km, rps_compliance_entity,
bio_gas_capacity_limit_mmbtu_per_hour, nems_fuel_region, economic_multiplier, eia_fuel_region
from load_area_info;

select * from load_area_info_v3;