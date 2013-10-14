#!/bin/bash
# get_switch_input_tables.sh
# SYNOPSIS
#		./get_switch_input_tables.sh 
# DESCRIPTION
# 	Pull input data for Switch from databases and other sources, formatting it for AMPL
# This script assumes that the input database has already been built by the script 'compile_switch_china.sql'
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
function print_help {
	last_line=$(( $(egrep '^[ \t]*$' -n -m 1 $0 | sed 's/:.*//') - 1 ))
	head -n $last_line $0 | sed -e '/^#[ 	]/ !d' -e 's/^#[ 	]//'
}

# Export SWITCH input data from the Switch inputs database into text files that will be read in by AMPL

mkdir -p inputs

write_to_path='inputs'

db_server="switch-db1.erg.berkeley.edu"
DB_name="switch_china"
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
test_connection=`$connection_string -t -c "select count(*) from province_info;"`

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
if [ $($connection_string -t -c "select count(*) from scenarios_switch_china where scenario_id=$SCENARIO_ID;") -eq 0 ]; then 
	echo "ERROR! This scenario id ($SCENARIO_ID) is not in the database. Exiting."
	exit;
fi

export TRAINING_SET_ID=$($connection_string -t -c "select training_set_id from scenarios_switch_china where scenario_id = $SCENARIO_ID;")
export DEMAND_SCENARIO_ID=$($connection_string -t -c "select demand_scenario_id from training_sets where training_set_id = $TRAINING_SET_ID;")
export STUDY_START_YEAR=$($connection_string -t -c "select study_start_year from training_sets where training_set_id=$TRAINING_SET_ID;")
export STUDY_END_YEAR=$($connection_string -t -c "select study_start_year + years_per_period*number_of_periods from training_sets where training_set_id=$TRAINING_SET_ID;")
number_of_years_per_period=$($connection_string -t -c "select years_per_period from training_sets where training_set_id=$TRAINING_SET_ID;")
# get the present year that will make present day cost optimization possible
present_year=$($connection_string -t -c "select extract(year from now());")
###########################
# Export data to be read into ampl.

cd  $write_to_path

echo 'Exporting Scenario Information'
echo 'Scenario Information' > scenario_information.txt
$connection_string -t -c "select * from scenarios_switch_china where scenario_id = $SCENARIO_ID;" >> scenario_information.txt
echo 'Training Set Information' >> scenario_information.txt
$connection_string -t -c "select * from training_sets where training_set_id=$TRAINING_SET_ID;" >> scenario_information.txt

# The general format for the following files is for the first line to be:
#	ampl.tab [number of key columns] [number of non-key columns]
# col1_name col2_name ...
# [rows of data]

echo 'Copying data from the database to input files...'

echo '	study_hours.tab...'
echo ampl.tab 1 5 > study_hours.tab
echo 'hour	period	date	hours_in_sample	month_of_year	hour_of_day' >> study_hours.tab
$connection_string -A -t -F  $'\t' -c "SELECT \
  to_char(hours.timestamp_cst, 'YYYYMMDDHH24') AS hour, period, \
  to_char(hours.timestamp_cst, 'YYYYMMDD') AS date, hours_in_sample, \
  month_of_year, hour_of_day \
FROM training_set_timepoints JOIN hours USING (hour_number) \
WHERE training_set_id=$TRAINING_SET_ID order by 1;" >> study_hours.tab

echo '	province_info.tab...'
echo ampl.tab 1 8 > province_info.tab
echo 'province	province_id	regional_grid_company	ccs_distance_km	present_day_existing_distribution_cost	present_day_max_coincident_demand_mwh_for_distribution	distribution_new_annual_payment_per_mw	existing_transmission_sunk_annual_payment	bio_gas_capacity_limit_mmbtu_per_hour' >> province_info.tab
$connection_string -A -t -F  $'\t' -c  "select province, province_id, regional_grid_company, ccs_distance_km, \
present_day_existing_distribution_cost, present_day_max_coincident_demand_mwh_for_distribution, distribution_new_annual_payment_per_mw, \
existing_transmission_sunk_annual_payment, bio_gas_capacity_limit_mmbtu_per_hour from province_info;" >> province_info.tab

echo '	regional_grid_companies.tab...'
echo ampl.tab 1 4 > regional_grid_companies.tab
echo 'regional_grid_company	load_only_spinning_reserve_requirement	wind_spinning_reserve_requirement	solar_spinning_reserve_requirement	quickstart_requirement_relative_to_spinning_reserve_requirement' >> regional_grid_companies.tab
$connection_string -A -t -F  $'\t' -c  "select regional_grid_company, load_only_spinning_reserve_requirement, wind_spinning_reserve_requirement, \
solar_spinning_reserve_requirement, quickstart_requirement_relative_to_spinning_reserve_requirement from regional_grid_companies;" >> regional_grid_companies.tab

echo '	transmission_lines.tab...'
echo ampl.tab 2 6 > transmission_lines.tab
echo 'province_start	province_end	transmission_line_id	existing_transfer_capacity_mw	transmission_length_km	transmission_efficiency	new_transmission_builds_allowed	dc_line' >> transmission_lines.tab
$connection_string -A -t -F  $'\t' -c  "select province_start, province_end, transmission_line_id, existing_transfer_capacity_mw, transmission_length_km, transmission_efficiency, \
new_transmission_builds_allowed, dc_line from transmission_lines order by 1,2;" >> transmission_lines.tab

echo '	province_hourly_demand.tab...'
echo ampl.tab 2 1 > province_hourly_demand.tab
echo 'province	hour	system_load' >> province_hourly_demand.tab
$connection_string -A -t -F  $'\t' -c  "SELECT province, to_char(training_set_timepoints.timestamp_cst, 'YYYYMMDDHH24') AS hour, province_demand_mwh AS system_load  \
	FROM province_hourly_demand \
	JOIN training_sets USING (demand_scenario_id) \
	JOIN training_set_timepoints USING (training_set_id, hour_number) \
	JOIN province_info USING (province_id) \
WHERE demand_scenario_id = $DEMAND_SCENARIO_ID \
AND training_set_id = $TRAINING_SET_ID;"  >> province_hourly_demand.tab

#present_day_system_load

echo '	max_province_demand.tab...'
echo ampl.tab 2 1 > max_province_demand.tab
echo 'province	period	max_system_load' >> max_province_demand.tab
$connection_string -A -t -F  $'\t' -c  "\
SELECT province, $present_year as period, max(province_demand_mwh) as max_system_load \
  FROM province_hourly_demand \
    JOIN training_sets USING (demand_scenario_id)  \
	JOIN hours USING (hour_number)  \
	JOIN province_info USING (province_id) \
  WHERE training_set_id = $TRAINING_SET_ID \
  AND year = $present_year  \
  GROUP BY province, period \
UNION \
SELECT province, period_start as period, max(province_demand_mwh) as max_system_load \
  FROM province_hourly_demand \
    JOIN training_sets USING (demand_scenario_id)  \
    JOIN training_set_periods USING (training_set_id)  \
	JOIN hours USING (hour_number)  \
	JOIN province_info USING (province_id) \
  WHERE training_set_id = $TRAINING_SET_ID  \
    AND year = FLOOR( period_start + years_per_period / 2) \
  GROUP BY province, period; " >> max_province_demand.tab

echo '	existing_plants.tab...'
echo ampl.tab 3 11 > existing_plants.tab
echo 'project_id	province	technology	plant_name	carma_plant_id	capacity_mw	heat_rate	cogen_thermal_demand_mmbtus_per_mwh	start_year	overnight_cost	connect_cost_per_mw	fixed_o_m	variable_o_m	ep_location_id' >> existing_plants.tab
$connection_string -A -t -F  $'\t' -c  "select project_id, province, technology, plant_name, carma_plant_id, ROUND(cast(capacity_mw as numeric),2)  AS capacity_mw, heat_rate,\
cogen_thermal_demand_mmbtus_per_mwh, start_year, overnight_cost, connect_cost_per_mw, fixed_o_m, variable_o_m, ep_location_id \
from existing_plants order by technology, province, project_id;" >> existing_plants.tab

echo '	existing_plant_intermittent_capacity_factor.tab...'
echo ampl.tab 4 1 > existing_plant_intermittent_capacity_factor.tab
echo 'project_id	province	technology	hour	capacity_factor' >> existing_plant_intermittent_capacity_factor.tab
$connection_string -A -t -F  $'\t' -c  "SELECT project_id, province, technology, to_char(training_set_timepoints.timestamp_cst, 'YYYYMMDDHH24') AS hour, capacity_factor \
FROM existing_plant_intermittent_capacity_factor \
  JOIN hours ON (hours.hour_of_year = existing_plant_intermittent_capacity_factor.hour_number)\
  JOIN training_set_timepoints ON (training_set_timepoints.hour_number = hours.hour_number) \
  JOIN existing_plants USING (project_id) \
WHERE training_set_id = $TRAINING_SET_ID;" >> existing_plant_intermittent_capacity_factor.tab

echo '	hydro_monthly_limits.tab...'
echo ampl.tab 4 1 > hydro_monthly_limits.tab
echo 'project_id	province	technology	date	average_output_mw' >> hydro_monthly_limits.tab
$connection_string -A -t -F  $'\t' -c  "\
CREATE TEMPORARY TABLE hydro_study_dates_export AS \
  SELECT distinct period, year as projection_year, month_of_year, to_char(hours.timestamp_cst, 'YYYYMMDD') AS date\
  FROM training_set_timepoints \
    JOIN hours USING (hour_number)\
  WHERE training_set_id = $TRAINING_SET_ID; \
  SELECT project_id, province, technology, date, ROUND(cast(average_output_mw as numeric),2)  AS average_output_mw\
  FROM hydro_monthly_limits \
    JOIN hydro_study_dates_export USING (projection_year, month_of_year)\
    JOIN existing_plants using (project_id);" >> hydro_monthly_limits.tab
 
echo '	new_projects.tab...'
echo ampl.tab 3 11 > new_projects.tab
echo 'project_id	province	technology	location_id	ep_project_replacement_id	capacity_limit	capacity_limit_conversion	heat_rate	cogen_thermal_demand	connect_cost_per_mw	overnight_cost	fixed_o_m	variable_o_m	overnight_cost_change' >> new_projects.tab
$connection_string -A -t -F  $'\t' -c  "select project_id, province, technology, location_id, ep_project_replacement_id, \
capacity_limit, capacity_limit_conversion, heat_rate, cogen_thermal_demand, connect_cost_per_mw, overnight_cost, fixed_o_m, variable_o_m, overnight_cost_change \
from new_projects;" >> new_projects.tab

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
minimum_loading, deep_cycling_penalty from generator_info;" >> generator_info.tab

echo '	fuel_info.tab...'
echo ampl.tab 1 3 > fuel_info.tab
echo 'fuel	biofuel	carbon_content	carbon_sequestered' >> fuel_info.tab
$connection_string -A -t -F  $'\t' -c  "select fuel, CASE WHEN biofuel THEN 1 ELSE 0 END, carbon_content, carbon_sequestered from fuel_info;" >> fuel_info.tab

echo '	fuel_prices.tab...'
echo ampl.tab 3 1 > fuel_prices.tab
echo 'province	fuel	year	fuel_price' >> fuel_prices.tab
$connection_string -A -t -F  $'\t' -c  "select province, fuel, projection_year as year, fuel_price from fuel_prices where projection_year <= $STUDY_END_YEAR order by province, fuel, projection_year" >> fuel_prices.tab

echo '	misc_params.dat...'
echo "param scenario_id          	:= $SCENARIO_ID;" >  misc_params.dat
echo "param num_years_per_period	:= $number_of_years_per_period;"  >> misc_params.dat
echo "param present_year  			:= $present_year;"  >> misc_params.dat

echo '	new_projects_intermittent_capacity_factor.tab...'
echo ampl.tab 4 1 > new_projects_intermittent_capacity_factor.tab
echo 'project_id	province	technology	hour	capacity_factor' >> new_projects_intermittent_capacity_factor.tab
$connection_string -A -t -F  $'\t' -c  "select project_id, province, technology, to_char(training_set_timepoints.timestamp_cst, 'YYYYMMDDHH24') AS hour, CASE WHEN capacity_factor > -0.1 THEN capacity_factor WHEN capacity_factor <= -0.1 then -0.1 END  \
  FROM training_set_timepoints \
    JOIN hours USING (hour_number) \
    JOIN new_projects_intermittent_capacity_factor ON (new_projects_intermittent_capacity_factor.hour_number = hour_of_year)\
    JOIN new_projects USING (project_id)\
  WHERE training_set_id = $TRAINING_SET_ID;" >> new_projects_intermittent_capacity_factor.tab

cd ..
