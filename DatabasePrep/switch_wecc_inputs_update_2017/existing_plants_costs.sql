
select * from existing_plants_v3;

DROP TABLE existing_plants_v3;

CREATE TABLE IF NOT EXISTS existing_plants_v3 (
	project_id INT,
    load_area varchar(50),
    technology varchar(50),
    ep_id int,
    area_id int,
    plant_name VARCHAR(50),
    eia_id int,
    primemover varchar(50),
    fuel VARCHAR(50),
    capacity_mw double,
    heat_rate double,
    cogen_thermal_demand_mmbtus_per_mwh double,
    start_year int,
    overnight_cost double,
    connect_cost_per_mw double,
    connect_cost_per_mw_archive double,
    fixed_o_m double,
    variable_o_m double,
    forced_outage_rate double,
    scheduled_outage_rate double,
    forced_retirement_year int,
    PRIMARY KEY (project_id, ep_id)
    );


select count(*) from  existing_plants_v2;
  
-- copy data from previous table existing_plants_v2 and update costs to be in dollars of 2016.    
-- 1.15 is the inflation between 2007 and 2016 for the US dollar ($1 in 2007 = $1.15 in 2016)
insert into existing_plants_v3
select project_id, load_area, technology, ep_id, area_id, plant_name, eia_id, primemover, fuel, capacity_mw , heat_rate, cogen_thermal_demand_mmbtus_per_mwh, start_year,
    1.15 * overnight_cost,
    1.15 * connect_cost_per_mw,
    1.15 * connect_cost_per_mw_archive,
    1.15 * fixed_o_m,
    1.15 * variable_o_m,
    forced_outage_rate,
    scheduled_outage_rate,
    forced_retirement_year
from existing_plants_v2 
order by 1, 2, 3;

-- Note: I might have deleted a table existing_plants_v3. But I think it didn't exist before, so it might be fine.