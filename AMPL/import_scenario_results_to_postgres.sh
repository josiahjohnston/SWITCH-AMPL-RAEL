#!/bin/bash
# import_results_into_postgres.sh
# SYNOPSIS
#		./import_results_into_postgres.sh 
# DESCRIPTION
# 	Pull input data for Switch from databases and other sources, formatting it for AMPL
# This script assumes that the input database has already been built by the script compile_switch_china.sql, DefineScenarios.sql, new_tables_for_db.sql, Setup_Study_Hours.sql, table_edits.sql.
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

# Import SWITCH input data from the results text files into the Switch database

##########################
# Default values
#write_to_path='results'
read SCENARIO_ID < scenario_id.txt
db_server="switch-db2.erg.berkeley.edu"
DB_name="switch_china"
port=3306
ssh_tunnel=0

results_dir="results"
path_dir=$(pwd)

###################################################
# Detect optional command-line arguments
help=0
while [ -n "$1" ]; do
case $1 in
  -t | --tunnel)
    ssh_tunnel=1; shift 1 ;;
  -u)
    user=$2; shift 2 ;;
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
  connection_string="psql -p $local_port -d $DB_name -U $user -h 127.0.0.1 "
  trap "clean_up;" EXIT INT TERM 
else
  connection_string="psql -U $user -h $db_server -d $DB_name "
fi

test_connection=`$connection_string -t -c "select count(*) from province_info;"`

if [ ! -n "$test_connection" ]
then
	connection_string=`echo "$connection_string" | sed -e "s/ -p[^ ]* / -pXXX /"`
	echo "Could not connect to database with settings: $connection_string"
	exit 0
fi


echo 'Clean the results table ready for import, DELETE the result if imported previously'
$connection_string  -A -t -c  "DELETE FROM china._gen_cap WHERE scenario_id = $SCENARIO_ID;"
$connection_string  -A -t -c  "DELETE FROM china._trans_cap WHERE scenario_id = $SCENARIO_ID;"
$connection_string  -A -t -c  "DELETE FROM china._local_td_cap WHERE scenario_id = $SCENARIO_ID;"
$connection_string  -A -t -c  "DELETE FROM china._transmission_dispatch system_load WHERE scenario_id = $SCENARIO_ID;"
$connection_string  -A -t -c  "DELETE FROM china._system_load WHERE scenario_id = $SCENARIO_ID;"
$connection_string  -A -t -c  "DELETE FROM china._existing_trans_cost WHERE scenario_id = $SCENARIO_ID;"
$connection_string  -A -t -c  "DELETE FROM china._generator_and_storage_dispatch WHERE scenario_id = $SCENARIO_ID;"
$connection_string  -A -t -c  "DELETE FROM china._load_wind_solar_operating_reserve_levels WHERE scenario_id = $SCENARIO_ID;"
$connection_string  -A -t -c  "DELETE FROM china._consume_and_redirect_variables WHERE scenario_id = $SCENARIO_ID;"
$connection_string  -A -t -c  "DELETE FROM china._gen_cap WHERE scenario_id = $SCENARIO_ID;"


echo 'Importing results files...'
  ###################################################
  # import a summary of run times for various processes
  # To do: add time for database export, storing results, compiling, etc.
 echo 'Importing run times...'
  #printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string  -e  "load data local infile \"$results_dir/run_times.txt\" REPLACE into table run_times ignore 1 lines (scenario_id, carbon_cost, process_type, time_seconds);") 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$results_dir/run_times.txt" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
 printf "%20s seconds to import %s rows\n" `(time -p $connection_string  -A -t -c  "\\COPY china.run_times FROM '$path_dir/$results_dir/run_times.txt' (format csv, delimiter e'\t', header); \
 ") 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$results_dir/run_times.txt" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
 
 
 # now import all of the non-runtime results
  for file_base_name in gen_cap trans_cap local_td_cap transmission_dispatch system_load existing_trans_cost generator_and_storage_dispatch load_wind_solar_operating_reserve_levels consume_variables
  do
   for file_name in $(ls $results_dir/*${file_base_name}_*txt | grep "[[:digit:]]")
   do
  file_path="$current_dir/$file_name"
  echo "    ${file_name}  ->  ${DB_name}.china._${file_base_name}"
  # Import the file in question into the DB
  case $file_base_name in
    #gen_cap) printf "%20s seconds to import %s rows\n" `(time -p $connection_string -A -t -c "COPY china._gen_cap (scenario_id, carbon_cost, period, project_id, area_id, @junk, technology_id, @junk, @junk, new, baseload, cogen, fuel, capacity, capital_cost, fixed_o_m_cost) FROM \"$file_path\" WITH CSV HEADER;") 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`

# Josiah commented this out. I moved the create table statement to svn_checkout/DatabasePrep/create_results_tables.sql
#     gen_cap) printf "%20s seconds to import %s rows\n" `(time -p $connection_string  -A -t -c  "CREATE TABLE IF NOT EXISTS china._gen_cap (scenario_id smallint, carbon_cost double precision, period smallint, project_id varchar, area_id varchar, technology_id smallint, technology varchar, site varchar, new boolean, baseload boolean, cogen boolean, fuel varchar, capacity double precision, capital_cost double precision, fixed_o_m_cost double precision); \
# 	\COPY china._gen_cap FROM '$path_dir/$file_name' (format csv, delimiter e'\t', header); \
# 	") 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$results_dir/run_times.txt" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
# 	;;
# The backslash \ has a special meaning inside double-quotes - it is the escape character to let you use literals. For example,  `echo "$foo"` will print the contents of the variable foo, and `echo "\$foo"`, will print $foo instead, translating the $ special character to a literal. If you want a literal \, you use two of them \\. This does not happen with single quotes because the shell only performs variable substitution with double quotes, not single. 
# I also re-wrote the commands to make it more legible. The current version of import_results_to_mysql.sh (available at /Volumes/switch/Users/pehidalg/src/switch/AMPL/import_results_to_mysql.sh) uses this style, plus an extra trick the row count of things imported to the database matches the row count of the file. 
    gen_cap) 
      file_row_count=$(wc -l "$path_dir/$file_name" | awk '{print ($1-1)}')
      start_time=$(date +%s)
      $connection_string  -A -t -c  "\\COPY china._gen_cap FROM '$path_dir/$file_name' (format csv, delimiter e'\t', header);"
      end_time=$(date +%s)
      printf "%20s seconds to import %s rows\n" $(($end_time - $start_time)) $file_row_count
	;;



    #trans_cap) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" into table _trans_cap ignore 1 lines (scenario_id,carbon_cost,period,transmission_line_id, start_id,end_id,@junk,@junk,new,trans_mw,fixed_cost);") 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
    
# Josiah's help: comment this and create the table in /Volumes/switch/Users/pehidalg/Switch_china/Switch_china_files_by_Paty/JP_BAU_Inter/DatabasePrep/create_results_tables.sql
#
#    trans_cap) printf "%20s seconds to import %s rows\n" `(time -p $connection_string  -A -t -c  "CREATE TABLE IF NOT EXISTS china._trans_cap #(scenario_id smallint, carbon_cost double precision, period smallint, transmission_line_id varchar, start_id varchar, end_id varchar, new boolean, #trans_mw double precision, fixed_cost double precision); \
#	\COPY china._trans_cap FROM '$path_dir/$file_name' (format csv, delimiter e'\t', header); \
#	") 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$results_dir/run_times.txt" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
#	;;
    trans_cap) 
      file_row_count=$(wc -l "$path_dir/$file_name" | awk '{print ($1-1)}')
      start_time=$(date +%s)
      $connection_string  -A -t -c  "\\COPY china._trans_cap FROM '$path_dir/$file_name' (format csv, delimiter e'\t', header);"
      end_time=$(date +%s)
      printf "%20s seconds to import %s rows\n" $(($end_time - $start_time)) $file_row_count
	;;	
	
	#local_td_cap) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" into table _local_td_cap ignore 1 lines (scenario_id, carbon_cost, period, area_id, @junk, new, local_td_mw, fixed_cost);" ) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`

# Josiah's help: comment this and create the table in /Volumes/switch/Users/pehidalg/Switch_china/Switch_china_files_by_Paty/JP_BAU_Inter/DatabasePrep/create_results_tables.sql
#
#    local_td_cap) printf "%20s seconds to import %s rows\n" `(time -p $connection_string  -A -t -c  "CREATE TABLE IF NOT EXISTS  china._local_td_cap (scenario_id smallint, carbon_cost double precision, period smallint, area_id varchar, new boolean, local_td_mw double precision, fixed_cost double precision); \
#	\COPY china._local_td_cap FROM '$path_dir/$file_name' (format csv, delimiter e'\t', header); \
#	") 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$results_dir/run_times.txt" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
#	;;

    local_td_cap) 
      file_row_count=$(wc -l "$path_dir/$file_name" | awk '{print ($1-1)}')
      start_time=$(date +%s)
      $connection_string  -A -t -c  "\\COPY china._local_td_cap FROM '$path_dir/$file_name' (format csv, delimiter e'\t', header);"
      end_time=$(date +%s)
      printf "%20s seconds to import %s rows\n" $(($end_time - $start_time)) $file_row_count
	;;




    #transmission_dispatch) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" into table _transmission_dispatch ignore 1 lines (scenario_id, carbon_cost, period, transmission_line_id, receive_id, send_id, @junk, @junk, study_date, study_hour, rps_fuel_category, power_sent, power_received, hours_in_sample);" ) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`

# Josiah's help: comment this and create the table in /Volumes/switch/Users/pehidalg/Switch_china/Switch_china_files_by_Paty/JP_BAU_Inter/DatabasePrep/create_results_tables.sql
#    
#   transmission_dispatch) printf "%20s seconds to import %s rows\n" `(time -p $connection_string  -A -t -c  "CREATE TABLE IF NOT EXISTS china._transmission_dispatch (scenario_id smallint, carbon_cost double precision, period smallint, transmission_line_id smallint, receive_id varchar, send_id varchar, study_date int, study_hour int, rps_fuel_category varchar, power_sent double precision, power_received double precision, hours_in_sample double precision); \
#	COPY china._transmission_dispatch FROM '$path_dir/$file_name' (format csv, delimiter e'\t', header); \
#	") 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$results_dir/run_times.txt" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
#	;;
	
    transmission_dispatch) 
      file_row_count=$(wc -l "$path_dir/$file_name" | awk '{print ($1-1)}')
      start_time=$(date +%s)
      $connection_string  -A -t -c  "\\COPY china._transmission_dispatch FROM '$path_dir/$file_name' (format csv, delimiter e'\t', header);"
      end_time=$(date +%s)
      printf "%20s seconds to import %s rows\n" $(($end_time - $start_time)) $file_row_count
	;;	
	
	
    #system_load) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" into table _system_load ignore 1 lines (scenario_id, carbon_cost, period, area_id, @junk, study_date, study_hour, hours_in_sample, power, satisfy_load_reduced_cost, satisfy_load_reserve_reduced_cost);" ) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
    
# Josiah's help: comment this and create the table in /Volumes/switch/Users/pehidalg/Switch_china/Switch_china_files_by_Paty/JP_BAU_Inter/DatabasePrep/create_results_tables.sql
#  
 #   la_demand_mwh) printf "%20s seconds to import %s rows\n" `(time -p $connection_string  -A -t -c  "CREATE TABLE IF NOT EXISTS china._system_load (scenario_id smallint, carbon_cost double precision, period smallint, area_id varchar, study_date int, study_hour int, hours_in_sample double precision, power double precision, satisfy_load_reduced_cost double precision, satisfy_load_reserve_reduced_cost double precision); \
#	COPY china._system_load FROM '$path_dir/$file_name' (format csv, delimiter e'\t', header); \
#	") 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$results_dir/run_times.txt" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
#	;;

    system_load) 
      file_row_count=$(wc -l "$path_dir/$file_name" | awk '{print ($1-1)}')
      start_time=$(date +%s)
      $connection_string  -A -t -c  "\\COPY china._system_load FROM '$path_dir/$file_name' (format csv, delimiter e'\t', header);"
      end_time=$(date +%s)
      printf "%20s seconds to import %s rows\n" $(($end_time - $start_time)) $file_row_count
	;;	


    #existing_trans_cost) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" into table _existing_trans_cost ignore 1 lines (scenario_id, carbon_cost, period, area_id, @junk, existing_trans_cost);" ) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
    
# Josiah's help: comment this and create the table in /Volumes/switch/Users/pehidalg/Switch_china/Switch_china_files_by_Paty/JP_BAU_Inter/DatabasePrep/create_results_tables.sql
#
#    existing_trans_cost) printf "%20s seconds to import %s rows\n" `(time -p $connection_string  -A -t -c  "CREATE TABLE IF NOT EXISTS china._existing_trans_cost (scenario_id smallint, carbon_cost double precision, period smallint, area_id varchar, existing_trans_cost double precision); \
#	COPY china._existing_trans_cost FROM '$path_dir/$file_name' (format csv, delimiter e'\t', header); \
#	") 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$results_dir/run_times.txt" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
#	;;

    existing_trans_cost) 
      file_row_count=$(wc -l "$path_dir/$file_name" | awk '{print ($1-1)}')
      start_time=$(date +%s)
      $connection_string  -A -t -c  "\\COPY china._existing_trans_cost FROM '$path_dir/$file_name' (format csv, delimiter e'\t', header);"
      end_time=$(date +%s)
      printf "%20s seconds to import %s rows\n" $(($end_time - $start_time)) $file_row_count
	;;	



    #rps_reduced_cost) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" into table _rps_reduced_cost ignore 1 lines (scenario_id, carbon_cost, period, rps_compliance_entity, rps_compliance_type, rps_reduced_cost);" ) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
    
    #generator_and_storage_dispatch) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" into table _generator_and_storage_dispatch ignore 1 lines (scenario_id, carbon_cost, period, project_id, area_id, @junk, @junk, study_date, study_hour, technology_id, @junk, new, baseload, cogen, storage, fuel, fuel_category, hours_in_sample, power, co2_tons, heat_rate, fuel_cost, carbon_cost_incurred, variable_o_m_cost, spinning_reserve, quickstart_capacity, total_operating_reserve, spinning_co2_tons, spinning_fuel_cost, spinning_carbon_cost_incurred, deep_cycling_amount, deep_cycling_fuel_cost, deep_cycling_carbon_cost, deep_cycling_co2_tons);" ) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
  
# Josiah's help: comment this and create the table in /Volumes/switch/Users/pehidalg/Switch_china/Switch_china_files_by_Paty/JP_BAU_Inter/DatabasePrep/create_results_tables.sql
#
#    generator_and_storage_dispatch) printf "%20s seconds to import %s rows\n" `(time -p $connection_string  -A -t -c  "CREATE TABLE IF NOT EXISTS china._generator_and_storage_dispatch (scenario_id smallint, carbon_cost double precision, period smallint, project_id varchar, area_id varchar, la_system varchar, study_date int, study_hour int, technology_id smallint, technology varchar, new boolean, baseload boolean, cogen boolean, storage boolean, fuel varchar, fuel_category varchar, hours_in_sample double precision, power double precision, co2_tons double precision, heat_rate double precision, fuel_cost double precision, carbon_cost_incurred double precision, variable_o_m_cost double precision, spinning_reserve double precision, quickstart_capacity double precision, total_operating_reserve double precision, spinning_co2_tons double precision, spinning_fuel_cost double precision, spinning_carbon_cost_incurred double precision, deep_cycling_amount double precision, deep_cycling_fuel_cost double precision, deep_cycling_carbon_cost double precision, deep_cycling_co2_tons double precision); \
#	\COPY china._generator_and_storage_dispatch FROM '$path_dir/$file_name' (format csv, delimiter e'\t', header); \
#	") 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$results_dir/run_times.txt" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
#	;;

    generator_and_storage_dispatch) 
      file_row_count=$(wc -l "$path_dir/$file_name" | awk '{print ($1-1)}')
      start_time=$(date +%s)
      $connection_string  -A -t -c  "\\COPY china._generator_and_storage_dispatch FROM '$path_dir/$file_name' (format csv, delimiter e'\t', header);"
      end_time=$(date +%s)
      printf "%20s seconds to import %s rows\n" $(($end_time - $start_time)) $file_row_count
	;;	


    #load_wind_solar_operating_reserve_levels) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" into table _load_wind_solar_operating_reserve_levels ignore 1 lines (scenario_id, carbon_cost, period, balancing_area, study_date, study_hour, hours_in_sample, load_level, wind_generation, noncsp_solar_generation, csp_generation, spinning_reserve_requirement, quickstart_capacity_requirement, total_spinning_reserve_provided, total_quickstart_capacity_provided, spinning_thermal_reserve_provided, spinning_nonthermal_reserve_provided, quickstart_thermal_capacity_provided, quickstart_nonthermal_capacity_provided);" ) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`

# Josiah's help: comment this and create the table in /Volumes/switch/Users/pehidalg/Switch_china/Switch_china_files_by_Paty/JP_BAU_Inter/DatabasePrep/create_results_tables.sql
#    
    
#    load_wind_solar_operating_reserve_levels) printf "%20s seconds to import %s rows\n" `(time -p $connection_string  -A -t -c  "CREATE TABLE IF NOT EXISTS china._load_wind_solar_operating_reserve_levels (scenario_id smallint, carbon_cost double precision, period smallint, balancing_area varchar, study_date int, study_hour int, hours_in_sample smallint, load_level double precision, wind_generation double precision, noncsp_solar_generation double precision, csp_generation double precision, spinning_reserve_requirement double precision, quickstart_capacity_requirement double precision, total_spinning_reserve_provided double precision, total_quickstart_capacity_provided double precision, spinning_thermal_reserve_provided double precision, spinning_nonthermal_reserve_provided double precision, quickstart_thermal_capacity_provided double precision, quickstart_nonthermal_capacity_provided double precision); \
#	COPY china._load_wind_solar_operating_reserve_levels FROM '$path_dir/$file_name' (format csv, delimiter e'\t', header); \
#	") 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$results_dir/run_times.txt" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
#	;;

    load_wind_solar_operating_reserve_levels) 
      file_row_count=$(wc -l "$path_dir/$file_name" | awk '{print ($1-1)}')
      start_time=$(date +%s)
      $connection_string  -A -t -c  "\\COPY china._load_wind_solar_operating_reserve_levels FROM '$path_dir/$file_name' (format csv, delimiter e'\t', header);"
      end_time=$(date +%s)
      printf "%20s seconds to import %s rows\n" $(($end_time - $start_time)) $file_row_count
	;;	




    #consume_variables) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" into table _consume_and_redirect_variables ignore 1 lines (scenario_id, carbon_cost, period, area_id, @junk, study_date, study_hour, hours_in_sample, rps_fuel_category, consume_nondistributed_power, consume_distributed_power);" ) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`

# Josiah's help: comment this and create the table in /Volumes/switch/Users/pehidalg/Switch_china/Switch_china_files_by_Paty/JP_BAU_Inter/DatabasePrep/create_results_tables.sql
#        
#    consume_variables) printf "%20s seconds to import %s rows\n" `(time -p $connection_string  -A -t -c  "CREATE TABLE IF NOT EXISTS china._consume_and_redirect_variables (scenario_id smallint, carbon_cost double precision, period smallint, area_id varchar, study_date int, study_hour int, hours_in_sample smallint, rps_fuel_category varchar, consume_nondistributed_power double precision, consume_distributed_power double precision); \
#	COPY china._consume_and_redirect_variables FROM '$path_dir/$file_name' (format csv, delimiter e'\t', header); \
#	") 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$results_dir/run_times.txt" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
#	;;
   
    consume_variables) 
      file_row_count=$(wc -l "$path_dir/$file_name" | awk '{print ($1-1)}')
      start_time=$(date +%s)
      $connection_string  -A -t -c  "\\COPY china._consume_and_redirect_variables FROM '$path_dir/$file_name' (format csv, delimiter e'\t', header);"
      end_time=$(date +%s)
      printf "%20s seconds to import %s rows\n" $(($end_time - $start_time)) $file_row_count
	;;	
   
 
   esac
   done
  done