select project_id, load_area, technology, hour, adjusted_cap_factor as cap_factor
  FROM
	( select location_id, DATE_FORMAT(datetime_utc,'%Y%m%d%H') as hour, (2/1.4) * cap_factor as adjusted_cap_factor
		from _training_set_timepoints
          JOIN study_timepoints USING(timepoint_id)
          JOIN load_scenario_historic_timepoints USING(timepoint_id)
          JOIN $cap_factor_table ON(historic_hour=hour)
	      JOIN ( select project_id, location_id from $proposed_projects_table where technology_id = 27) as csp_no_storage_projects
            using (project_id)
            ) as cap_factors_table
    JOIN $proposed_projects_table USING(location_id)
    JOIN load_area_info USING(area_id)
  WHERE training_set_id=$TRAINING_SET_ID 
    AND load_scenario_id=$LOAD_SCENARIO_ID 
    AND $INTERMITTENT_PROJECTS_SELECTION 
    AND technology_id = 7;
    

# new table with adjusted cap factors for CSP with storage that tell us how much energy is being collected by the solar field in each hour
# assumption is that we have a solar multiple of 2 for the CSP with 6h storage and 1.4 for CSP with no storage
# to get at the amount of energy collected by the solar field of the plants with 6h of storage,
# we'll use the cap factors for the plants with no storage and adjust those by the ratio of the solar multiples
    
create table _cap_factor_csp_6h_storage_adjusted (
project_id int(10),
hour smallint(5),
cap_factor_adjusted float,
PRIMARY KEY pid_h (project_id, hour)
);

insert into _cap_factor_csp_6h_storage_adjusted (project_id, hour, cap_factor_adjusted)
select csp_6h_storage_pid, hour, adjusted_cap_factor
from ( select project_id as csp_6h_storage_pid, csp_no_storage_pid
       from _proposed_projects_v3
        join ( select project_id as csp_no_storage_pid, location_id
               from _proposed_projects_v3
               where technology_id = 27 ) as csp_no_storage_table
        using (location_id)
       where _proposed_projects_v3.technology_id = 7 ) as storage_to_no_storage_pid_map
  join ( select project_id, hour, (2/1.4) * cap_factor as adjusted_cap_factor
         from _cap_factor_intermittent_sites_v2 ) as tadjusted_cap_factor
    on ( tadjusted_cap_factor.project_id = csp_no_storage_pid )
;



mysql switch_inputs_wecc_v2_2 -u ana -p -e "\
insert into _cap_factor_csp_6h_storage_adjusted (project_id, hour, adjusted_cap_factor) \
select csp_6h_storage_pid, hour, adjusted_cap_factor \
from ( select project_id as csp_6h_storage_pid, csp_no_storage_pid \
       from _proposed_projects_v3 \
        join ( select project_id as csp_no_storage_pid, location_id \
               from _proposed_projects_v3 \
               where technology_id = 27 ) as csp_no_storage_table \
        using (location_id) \
       where _proposed_projects_v3.technology_id = 7 ) as storage_to_no_storage_pid_map \
  join ( select project_id, hour, (2/1.4) * cap_factor as adjusted_cap_factor \
         from _cap_factor_intermittent_sites_v2 ) as tadjusted_cap_factor \
    on ( tadjusted_cap_factor.project_id = csp_no_storage_pid );"
    


