# Part by part of get_switch_input_tables.sh

## here it begins:







# Date of creation: May 8th/2013
# SWITCH CHILE!
# Note: This file was copied and modified from get_switch_input_tables.sh sent by Juan Pablo Carvallo (which was from China model of some time ago)
# C:\University of California, Berkeley\Spring 2013\RAEL\Switch Chile\Switch_china_files\get_switch_input_tables.sh
# the rest of the code follows the original .sh file (with the corresponding editions)



#!/bin/bash
# get_switch_input_tables.sh
# SYNOPSIS
#		./get_switch_input_tables.sh 
# DESCRIPTION
# 	Pull input data for Switch from databases and other sources, formatting it for AMPL
# This script assumes that the input database has already been built by the script compile_switch_chile.sql, DefineScenarios.sql, new_tables_for_db.sql, Setup_Study_Hours.sql, table_edits.sql.
# 
# INPUTS
#  --help                   Print this message
#  -t | --tunnel            Initiate an ssh tunnel to connect to the database. This won't work if ssh prompts you for your password.
#  -u [DB Username]
#  -p [DB Password]
#  -D [DB name]
#  -P/--port [port number]
#  -h [DB server]
#  -np | --no-password      Do not prompt for or use a password to connect to the database
# All arguments are optional.

# This function assumes that the lines at the top of the file that start with a # and a space or tab 
# comprise the help message. It prints the matching lines with the prefix removed and stops at the first blank line.
# Consequently, there needs to be a blank line separating the documentation of this program from this "help" function
#function print_help {
#	last_line=$(( $(egrep '^[ \t]*$' -n -m 1 $0 | sed 's/:.*//') - 1 ))
#	head -n $last_line $0 | sed -e '/^#[ 	]/ !d' -e 's/^#[ 	]//'
#}

# Export SWITCH input data from the Switch inputs database into text files that will be read in by AMPL

write_to_path='inputs'
db_server="switch-db1.erg.berkeley.edu"
DB_name="switch_gis"
port=3306
ssh_tunnel=0
no_password=0

###################################################
# Detect optional command-line arguments
help=0
while [ -n "$1" ]; do
case $1 in
  -t | --tunnel)
    ssh_tunnel=1; shift 1 ;;
  -u)
    user=$2; shift 2 ;;
  -np | --no-password)
    no_password=1; shift 1 ;;
  -p)
    password=$2; shift 2 ;;
  -P)
    port=$2; shift 2 ;;
  --port)
    port=$2; shift 2 ;;
  -D)
    DB_name=$2; shift 2 ;;
  -h)
    db_server=$2; shift 2 ;;
  --help)
		print_help; exit ;;
  *)
    echo "Unknown option $1"
		print_help; exit ;;
esac
done

##########################
# Get the user name and password 
default_user=$(whoami)
if [ ! -n "$user" ]
then 
	printf "User name for PostGreSQL $DB_name on $db_server [$default_user]? "
	read user
	if [ -z "$user" ]; then 
	  user="$default_user"
	fi
fi
#if [ ! -n "$password" ] && [ $no_password -eq 0 ]
#then 
#	printf "Password for PostGreSQL $DB_name on $db_server? "
#	stty_orig=`stty -g`   # Save screen settings
#	stty -echo            # To keep the password vaguely secure, don't let it show to the screen
#	read password
#	stty $stty_orig       # Restore screen settings
#	echo " "
#fi

function clean_up {
  [ $ssh_tunnel -eq 1 ] && kill -9 $ssh_pid # This ensures that the ssh tunnel will be taken down if the program exits abnormally
  unset password
}

function is_port_free {
  target_port=$1
  if [ $(netstat -ant | \
         sed -e '/^tcp/ !d' -e 's/^[^ ]* *[^ ]* *[^ ]* *.*[\.:]\([0-9]*\) .*$/\1/' | \
         sort -g | uniq | \
         grep $target_port | wc -l) -eq 0 ]; then
    return 1
  else
    return 0
  fi
}

#############
# Try starting an ssh tunnel if requested
if [ $ssh_tunnel -eq 1 ]; then 
  echo "Trying to open an ssh tunnel. If it prompts you for your password, this method won't work."
  local_port=5432
  is_port_free $local_port
  while [ $? -eq 0 ]; do
    local_port=$((local_port+1))
    is_port_free $local_port
  done
  ssh -N -p 22 -c 3des $db_server -L $local_port/$db_server/$port &
  ssh_pid=$!
  sleep 1
  if [ $no_password -eq 0 ]; then
	export PGPASSWORD=yourpassword
    connection_string="psql 5432 -d $DB_name -U $user"
  fi
  trap "clean_up;" EXIT INT TERM 
else
  if [ $no_password -eq 0 ]; then
	export PGPASSWORD=yourpassword
    connection_string="psql -d $DB_name -U $user"
  fi
fi

	export PGPASSWORD=yourpassword
test_connection=`$connection_string -t -c "select count(*) from chile.load_area;"`

if [ ! -n "$test_connection" ]
then
	connection_string=`echo "$connection_string" | sed -e "s/ -p[^ ]* / -pXXX /"`
	echo "Could not connect to database with settings: $connection_string"
	exit 0
fi


###########################
# These next variables determine which input data is used

read SCENARIO_ID < scenario_id.txt
# Make sure this scenario id is valid.
if [ $($connection_string -t -c "select count(*) from chile.scenarios_switch_chile where scenario_id=$SCENARIO_ID;") -eq 0 ]; then 
	echo "ERROR! This scenario id ($SCENARIO_ID) is not in the database. Exiting."
	exit;
fi



# PATY: New id (oct/2/2013) #############################################################
export CARBON_CAP_ID=$($connection_string -t -c "select carbon_cap_id from chile.scenarios_switch_chile where scenario_id = $SCENARIO_ID;")
echo $CARBON_CAP_ID

# PATY: ADDED VAR
ENABLE_CARBON_CAP=$($connection_string -t -c "select case when $CARBON_CAP_ID=0 then 0 else 1 end;")
echo $ENABLE_CARBON_CAP

export RPS_ID=$($connection_string -t -c "select rps_id from chile.scenarios_switch_chile where scenario_id = $SCENARIO_ID;")
echo $RPS_ID

# PATY: ADDED VAR
ENABLE_RPS=$($connection_string -t -c "select case when $RPS_ID=0 then 0 else 1 end;")
echo $ENABLE_RPS

export SIC_SING_ID=$($connection_string -t -c "select sic_sing_id from chile.scenarios_switch_chile where scenario_id = $SCENARIO_ID;")
echo $SIC_SING_ID

export FUEL_COST_ID=$($connection_string -t -c "select fuel_cost_id from chile.scenarios_switch_chile where scenario_id = $SCENARIO_ID;")
echo $FUEL_COST_ID

export NEW_PROJECT_PORTFOLIO_ID=$($connection_string -t -c "select new_project_portfolio_id from chile.scenarios_switch_chile where scenario_id = $SCENARIO_ID;")
echo $NEW_PROJECT_PORTFOLIO_ID
# PATY: End of new ids ################################################################

export TRAINING_SET_ID=$($connection_string -t -c "select training_set_id from chile.scenarios_switch_chile where scenario_id = $SCENARIO_ID;")
echo $TRAINING_SET_ID

export DEMAND_SCENARIO_ID=$($connection_string -t -c "select demand_scenario_id from chile.training_sets where training_set_id = $TRAINING_SET_ID;")
echo $DEMAND_SCENARIO_ID

export STUDY_START_YEAR=$($connection_string -t -c "select study_start_year from chile.training_sets where training_set_id=$TRAINING_SET_ID;")
echo $STUDY_START_YEAR

export STUDY_END_YEAR=$($connection_string -t -c "select study_start_year + years_per_period*number_of_periods from chile.training_sets where training_set_id=$TRAINING_SET_ID;")
echo $STUDY_END_YEAR

number_of_years_per_period=$($connection_string -t -c "select years_per_period from chile.training_sets where training_set_id=$TRAINING_SET_ID;")
echo $number_of_years_per_period
# get the present year that will make present day cost optimization possible
#present_year=$($connection_string -t -c "select extract(year from now());")
present_year=$($connection_string -t -c "select 2011;")
echo $present_year
# Export data to be read into ampl.

cd  $write_to_path

echo 'Exporting Scenario Information'
echo 'Scenario Information' > scenario_information.txt
$connection_string -t -c "select * from chile.scenarios_switch_chile where scenario_id = $SCENARIO_ID;" >> scenario_information.txt
echo 'Training Set Information' >> scenario_information.txt
$connection_string -t -c "select * from chile.training_sets where training_set_id=$TRAINING_SET_ID;" >> scenario_information.txt


# The general format for the following files is for the first line to be:
#	ampl.tab [number of key columns] [number of non-key columns]
# col1_name col2_name ...
# [rows of data]

echo 'Copying data from the database to input files...'

echo '	study_hours.tab...'
echo ampl.tab 1 5 > study_hours.tab
echo 'hour	period	date	hours_in_sample	month_of_year	hour_of_day' >> study_hours.tab
$connection_string -A -t -F  $'\t' -c "SELECT \
  to_char(chile.hours.timestamp_cst, 'YYYYMMDDHH24') AS hour, period, \
  to_char(chile.hours.timestamp_cst, 'YYYYMMDD') AS date, hours_in_sample, \
  month_of_year, hour_of_day \
FROM chile.training_set_timepoints JOIN chile.hours USING (hour_number) \
WHERE training_set_id=$TRAINING_SET_ID order by 1;" >> study_hours.tab


# PATY: New col added: rps_compliance_entity IN ORDER TO MAKE RPS WORK
echo '	load_area.tab...'
echo ampl.tab 1 8 > load_area.tab
echo 'la_id	la_system	ccs_distance_km	present_day_existing_distribution_cost	present_day_max_coincident_demand_mwh_for_distribution	distribution_new_annual_payment_per_mw	existing_transmission_sunk_annual_payment	bio_gas_capacity_limit_mmbtu_per_hour rps_compliance_entity' >> load_area.tab
$connection_string -A -t -F  $'\t' -c  "select la_id, la_system, ccs_distance_km, \
present_day_existing_distribution_cost, present_day_max_coincident_demand_mwh_for_distribution, distribution_new_annual_payment_per_mw, \
existing_transmission_sunk_annual_payment, bio_gas_capacity_limit_mmbtu_per_hour, rps_compliance_entity from chile.load_area;" >> load_area.tab



echo '	regional_grid_companies.tab...'
echo ampl.tab 1 4 > regional_grid_companies.tab
echo 'la_system	load_only_spinning_reserve_requirement	wind_spinning_reserve_requirement	solar_spinning_reserve_requirement	quickstart_requirement_relative_to_spinning_reserve_requirement' >> regional_grid_companies.tab
$connection_string -A -t -F  $'\t' -c  "select la_system, load_only_spinning_reserve_requirement, wind_spinning_reserve_requirement, \
solar_spinning_reserve_requirement, quickstart_requirement_relative_to_spinning_reserve_requirement from chile.regional_grid_companies;" >> regional_grid_companies.tab



# JP
echo '	transmission_lines.tab...'
echo ampl.tab 2 6 > transmission_lines.tab
echo 'la_start	la_end	transmission_line_id	existing_transfer_capacity_mw	transmission_length_km	transmission_efficiency	new_transmission_builds_allowed	dc_line' >> transmission_lines.tab
$connection_string -A -t -F  $'\t' -c  "select la_start, la_end, transmission_line_id, existing_transfer_capacity_mw, transmission_length_km, transmission_efficiency, \
new_transmission_builds_allowed, dc_line from chile.transmission_between_la \
where case when $SIC_SING_ID=0 then transmission_line_id <> 127 and transmission_line_id <> 128 else transmission_line_id>0 end order by 1,2;" >> transmission_lines.tab

# PATY: la_id used to be province (not province_id)
echo '	la_hourly_demand.tab...'
echo ampl.tab 2 1 > la_hourly_demand.tab
echo 'la_id	hour	la_demand_mwh' >> la_hourly_demand.tab
$connection_string -A -t -F  $'\t' -c  "SELECT la_id, to_char(chile.training_set_timepoints.timestamp_cst, 'YYYYMMDDHH24') AS hour, la_demand_mwh  \
	FROM chile.la_hourly_demand \
	JOIN chile.training_sets USING (demand_scenario_id) \
	JOIN chile.training_set_timepoints USING (training_set_id, hour_number) \
	JOIN chile.load_area USING (la_id) \
WHERE demand_scenario_id = $DEMAND_SCENARIO_ID \
AND training_set_id = $TRAINING_SET_ID;"  >> la_hourly_demand.tab


#present_day_province_demand_mwh
# PATY: CHECK IF THE COL PROVINCE SHOULD BE LA_ID OR LA_SYSTEM
echo '	max_la_demand.tab...'
echo ampl.tab 2 1 > max_la_demand.tab
echo 'la_id	period	max_la_demand_mwh' >> max_la_demand.tab
$connection_string -A -t -F  $'\t' -c  "\
SELECT la_id, period_start as period, max(la_demand_mwh) as max_la_demand_mwh \
  FROM chile.la_hourly_demand \
    JOIN chile.training_sets USING (demand_scenario_id)  \
    JOIN chile.training_set_periods USING (training_set_id)  \
	JOIN chile.hours USING (hour_number)  \
	JOIN chile.load_area USING (la_id) \
  WHERE training_set_id = $TRAINING_SET_ID  \
    AND year = FLOOR( period_start + years_per_period / 2) \
  GROUP BY la_id, period; " >> max_la_demand.tab


# PATY: To make it work
echo '	existing_plants.tab...'
echo ampl.tab 3 10 > existing_plants.tab
echo 'project_id	la_id	technology	plant_name	capacity_mw	heat_rate	cogen_thermal_demand_mmbtus_per_mwh	start_year	overnight_cost	connect_cost_per_mw	fixed_o_m	variable_o_m	ep_location_id' >> existing_plants.tab
$connection_string -A -t -F  $'\t' -c  "select project_id, la_id, t1.technology, plant_name, capacity_mw, t1.heat_rate, t1.cogen_thermal_demand_mmbtus_per_mwh, start_year, t2.overnight_cost, connect_cost_per_mw, t2.fixed_o_m, t2.variable_o_m, ep_location_id \
from chile.existing_plants as t1 join chile.generator_info_v2 as t2 USING(technology_id) \
where complete_data AND project_id <> 'SING2' AND project_id <> 'SING3' AND project_id <> 'SING4' AND project_id <> 'SING5' \
order by technology, la_id, project_id;" >> existing_plants.tab


# PATY: To make it work
echo '	existing_plant_intermittent_capacity_factor.tab...'
echo ampl.tab 4 1 > existing_plant_intermittent_capacity_factor.tab
echo 'project_id	la_id	technology	hour	capacity_factor' >> existing_plant_intermittent_capacity_factor.tab
$connection_string -A -t -F  $'\t' -c  "SELECT project_id, t1.la_id, existing_plants.technology, to_char(chile.training_set_timepoints.timestamp_cst, 'YYYYMMDDHH24') AS hour,  CASE WHEN capacity_factor > 1.4 THEN 1.4 ELSE capacity_factor END AS capacity_factor  \
FROM chile.existing_plant_intermittent_capacity_factor as t1\
  JOIN chile.training_set_timepoints USING (hour_number) \
  JOIN chile.existing_plants USING (project_id) \
WHERE training_set_id = $TRAINING_SET_ID \
AND t1.technology_id <> 15;" >> existing_plant_intermittent_capacity_factor.tab

# JP: Splitting the hydro monthly limits in two, so they can be handled separately in switch.mod
echo '	hydro_monthly_limits_ep.tab...'
echo ampl.tab 4 1 > hydro_monthly_limits_ep.tab
echo 'project_id	la_id	technology	date	average_output_mw' >> hydro_monthly_limits_ep.tab
$connection_string -A -t -F  $'\t' -c  "\
CREATE TEMPORARY TABLE hydro_study_dates_export AS \
  SELECT distinct period, year as projection_year, month_of_year, to_char(chile.hours.timestamp_cst, 'YYYYMMDD') AS date\
  FROM chile.training_set_timepoints \
  JOIN chile.hours USING (hour_number)\
  WHERE training_set_id = $TRAINING_SET_ID; \
  SELECT project_id, la_id, technology, date, ROUND(cast(average_output_mw as numeric),1) AS average_output_mw \
  FROM chile.hydro_monthly_limits \
  JOIN hydro_study_dates_export USING (projection_year, month_of_year) \
  JOIN chile.existing_plants using (project_id);" >> hydro_monthly_limits_ep.tab

echo '	hydro_monthly_limits_new.tab...'
echo ampl.tab 4 1 > hydro_monthly_limits_new.tab
echo 'project_id	la_id	technology	date	average_output_cf' >> hydro_monthly_limits_new.tab
$connection_string -A -t -F  $'\t' -c  "\
  CREATE TEMPORARY TABLE hydro_study_dates_export AS \
  SELECT distinct period, year as projection_year, month_of_year, to_char(chile.hours.timestamp_cst, 'YYYYMMDD') AS date \
  FROM chile.training_set_timepoints \
  JOIN chile.hours USING (hour_number)\
  WHERE training_set_id = $TRAINING_SET_ID; \
  SELECT hmle.project_id, la_id, technology, date, ROUND(cast(average_output_cf as numeric),3) AS average_output_cf \
  FROM chile.hydro_monthly_limits_new_hydro_from_flow_data hmle \
  JOIN hydro_study_dates_export USING (projection_year, month_of_year) \
  JOIN chile.new_projects_alternative_1 USING (project_id);" >> hydro_monthly_limits_new.tab



# PATY: fixed to make it work (remove cetrales de pasadas)
echo '	new_projects.tab...'
echo ampl.tab 3 11 > new_projects.tab
echo 'project_id	la_id	technology	location_id	ep_project_replacement_id	capacity_limit	capacity_limit_conversion	heat_rate	cogen_thermal_demand	connect_cost_per_mw	overnight_cost	fixed_o_m	variable_o_m	overnight_cost_change' >> new_projects.tab
$connection_string -A -t -F  $'\t' -c  "select t1.project_id, t1.la_id, t1.technology, t1.location_id_num, t1.ep_project_replacement_id, t1.capacity_limit, t1.capacity_limit_conversion, t1.heat_rate, t1.cogen_thermal_demand, t1.connect_cost_per_mw, t2.overnight_cost, t2.fixed_o_m, t2.variable_o_m, t2.overnight_cost_change \
from chile.new_projects_v2 as t1 JOIN chile.generator_info_v2 as t2 USING(technology_id) \
where new_project_portfolio_id = $NEW_PROJECT_PORTFOLIO_ID;" >> new_projects.tab


echo '	generator_info.tab...'
echo ampl.tab 1 30 > generator_info.tab
echo 'technology	technology_id	min_build_year	fuel	construction_time_years	year_1_cost_fraction	year_2_cost_fraction	year_3_cost_fraction	year_4_cost_fraction	year_5_cost_fraction	year_6_cost_fraction	max_age_years	forced_outage_rate	scheduled_outage_rate	can_build_new	ccs	intermittent	resource_limited	baseload	flexible_baseload	dispatchable	cogen	min_build_capacity	competes_for_space	storage	storage_efficiency	max_store_rate	max_spinning_reserve_fraction_of_capacity	heat_rate_penalty_spinning_reserve	minimum_loading	deep_cycling_penalty' >> generator_info.tab
$connection_string -A -t -F  $'\t' -c  "select technology, technology_id, min_build_year, fuel, construction_time_years, \
year_1_cost_fraction, year_2_cost_fraction, year_3_cost_fraction, year_4_cost_fraction, year_5_cost_fraction, year_6_cost_fraction, \
max_age_years, forced_outage_rate, scheduled_outage_rate, \
CASE WHEN can_build_new THEN 1 ELSE 0 END, \
CASE WHEN ccs THEN 1 ELSE 0 END, \
CASE WHEN intermittent THEN 1 ELSE 0 END, \
CASE WHEN resource_limited THEN 1 ELSE 0 END, \
CASE WHEN baseload THEN 1 ELSE 0 END, \
CASE WHEN flexible_baseload THEN 1 ELSE 0 END, \
CASE WHEN dispatchable THEN 1 ELSE 0 END, \
CASE WHEN cogen THEN 1 ELSE 0 END, \
min_build_capacity, \
CASE WHEN competes_for_space THEN 1 ELSE 0 END, \
CASE WHEN storage THEN 1 ELSE 0 END, \
storage_efficiency, max_store_rate, max_spinning_reserve_fraction_of_capacity, heat_rate_penalty_spinning_reserve, \
minimum_loading, deep_cycling_penalty from chile.generator_info_v2;" >> generator_info.tab


# PATY: col rps_fuel_category added to make rps work.
echo '	fuel_info.tab...'
echo ampl.tab 1 4 > fuel_info.tab
echo 'fuel	rps_fuel_category biofuel	carbon_content	carbon_sequestered' >> fuel_info.tab
$connection_string -A -t -F  $'\t' -c  "select fuel, rps_fuel_category, CASE WHEN biofuel THEN 1 ELSE 0 END, carbon_content, carbon_sequestered from chile.fuel_info;" >> fuel_info.tab

# JP: Adjust the query due to the "samples" column in the fuel_prices SQL table
echo '	fuel_prices.tab...'
echo ampl.tab 3 1 > fuel_prices.tab
echo 'la_id	fuel	year	fuel_price' >> fuel_prices.tab
$connection_string -A -t -F  $'\t' -c  "select la_id, fuel, projection_year as year, avg(fuel_price) as fuel_price from chile.fuel_prices  \
where projection_year <= $STUDY_END_YEAR AND fuel_cost_id = $FUEL_COST_ID \
GROUP BY la_id, fuel, year ORDER BY la_id, fuel, projection_year;" >> fuel_prices.tab


echo '	misc_params.dat...'
echo "param scenario_id          := $SCENARIO_ID;" >  misc_params.dat
# PATY: line below added to activate rps 
echo "param enable_rps            := $ENABLE_RPS;"  >> misc_params.dat
# PATY: new enable_carbon_cap param. Oct/3/2013
# echo "param enable_carbon_cap     := $ENABLE_CARBON_CAP;"  >> misc_params.dat
echo "param num_years_per_period	:= $number_of_years_per_period;"  >> misc_params.dat
echo "param present_year  			:= $present_year;"  >> misc_params.dat

  
  
echo '	new_projects_intermittent_capacity_factor.tab...'
echo ampl.tab 4 1 > new_projects_intermittent_capacity_factor.tab
echo 'project_id	la_id	technology	hour	capacity_factor' >> new_projects_intermittent_capacity_factor.tab
$connection_string -A -t -F  $'\t' -c  "select project_id, t1.la_id, technology, to_char(training_set_timepoints.timestamp_cst, 'YYYYMMDDHH24') AS hour, CASE WHEN capacity_factor < -0.1 THEN -0.1 WHEN capacity_factor > 1 THEN 1 ELSE capacity_factor END AS capacity_factor  \
  FROM chile.training_set_timepoints \
    JOIN chile.new_projects_intermittent_capacity_factor as t1 USING (hour_number)\
    JOIN chile.new_projects_v2 USING (project_id)\
  WHERE training_set_id = $TRAINING_SET_ID \
  AND new_project_portfolio_id = $NEW_PROJECT_PORTFOLIO_ID;" >> new_projects_intermittent_capacity_factor.tab
  
# PATY: NEW TAB FOR RPS  
echo '	rps_compliance_entity_targets.tab...'
echo ampl.tab 3 1 > rps_compliance_entity_targets.tab
echo 'rps_compliance_entity	rps_compliance_type	rps_compliance_year	rps_compliance_fraction' >> rps_compliance_entity_targets.tab
$connection_string -A -t -F  $'\t' -c "select rps_compliance_entity, rps_compliance_type, rps_compliance_year, rps_compliance_fraction from chile.rps_compliance_entity_targets_v2 where enable_rps = $ENABLE_RPS AND rps_compliance_year >= $STUDY_START_YEAR and rps_compliance_year <= $STUDY_END_YEAR AND rps_id = $RPS_ID;" >> rps_compliance_entity_targets.tab

# PATY: NEW TAB FOR RPS  
echo '	rps_areas_and_fuel_category.tab...'
echo ampl.tab 2 1 > rps_areas_and_fuel_category.tab
echo 'la_id	fuel_category fuel_qualifies_for_rps' >> rps_areas_and_fuel_category.tab
$connection_string -A -t -F  $'\t' -c "select la_id, fuel_category, fuel_qualifies_for_rps from chile.rps_areas_and_fuel_category;" >> rps_areas_and_fuel_category.tab


cd ..












