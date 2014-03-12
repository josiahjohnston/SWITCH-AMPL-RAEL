#!/bin/bash


function print_help {
  cat <<END_HELP
import.sh
SYNOPSIS
  ./import.sh
DESCRIPTION
  Import dispatch results into MySQL and crunch some numbers
INPUTS
  --help                   Print this message
  -n/--no-tunnel         Do not try to initiate an ssh tunnel to connect to the database. Overrides default behavior. 
  -u [DB Username]
  -p [DB Password]
  -D [DB name]
  -P/--port [port number]
  -h [DB server]
  --SkipImport             Just crunch the results, don't import any files
  --SkipCrunch             Just import the raw files, don't crunch the data.
All arguments are optional.
END_HELP
}


##########################
# Constants
read SCENARIO_ID < scenario_id.txt
DB_name='switch_results_wecc_v2_2'
db_server='switch-db2.erg.berkeley.edu'
port=3306
ssh_tunnel=1

# Set the umask to give group read & write permissions to all files & directories made by this script.
umask 0002

###################################################
# Detect optional command-line arguments
FlushPriorResults=0
SkipImport=0
SkipCrunch=0
help=0
while [ -n "$1" ]; do
case $1 in
  -n | --no-tunnel)
    ssh_tunnel=0; shift 1 ;;
  -u)
    user=$2; shift 2 ;;
  -p)
    password=$2; shift 2 ;;
  -P | --port)
    port=$2; shift 2 ;;
  -D)
    DB_name=$2; shift 2 ;;
  -h)
    db_server=$2; shift 2 ;;
  --SkipImport) 
    SkipImport=1; shift 1 ;;
  --SkipCrunch)
    SkipCrunch=1; shift 1 ;;
  --help)
    print_help; exit 0 ;;
  *)
    echo "Unknown option $1"; print_help; exit 1 ;;
esac
done


##########################
# Get the user name and password 
# Note that passing the password to mysql via a command line parameter is considered insecure
# http://dev.mysql.com/doc/refman/5.0/en/password-security.html
default_user=$(whoami)
if [ ! -n "$user" ]
then 
  printf "User name for MySQL $DB_name on $db_server [$default_user]? "
  read user
  if [ -z "$user" ]; then 
    user="$default_user"
  fi
fi
if [ ! -n "$password" ]
then 
  echo "Password for MySQL $DB_name on $db_server? "
  stty_orig=`stty -g`   # Save screen settings
  stty -echo            # To keep the password vaguely secure, don't let it show to the screen
  read password
  stty $stty_orig       # Restore screen settings
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
  local_port=3307
  is_port_free $local_port
  while [ $? -eq 0 ]; do
    local_port=$((local_port+1))
    is_port_free $local_port
  done
  ssh -N -p 22 -c 3des "$user"@"$db_server" -L $local_port/127.0.0.1/$port &
  ssh_pid=$!
  sleep 1
  connection_string="-h 127.0.0.1 --port $local_port --local-infile=1 -u $user -p$password $DB_name"
  trap "clean_up;" EXIT INT TERM 
else
  connection_string="-h $db_server --port $port --local-infile=1 -u $user -p$password $DB_name"
fi

test_connection=`mysql $connection_string --column-names=false -e "show tables;"`
if [ -z "$test_connection" ]
then
  connection_string=`echo "$connection_string" | sed -e "s/ -p[^ ]* / -pXXX /"`
  echo "Could not connect to database with settings: $connection_string"
  exit 0
fi

function check_file_and_get_row_count {
  file_path=$1
  if [ ! -f "$file_path" ]; then 
    printf "Mandatory output file $file_path not found. Bailing out. \n";
    exit 1;
  fi;
  file_row_count=$(awk 'END {print NR-1}' "$file_path")
  if [ $file_row_count -le 0 ]; then
    printf "Output file $file_path does not contain any records. Bailing out. \n";
    exit 1;
  fi;
  echo $file_row_count
}

function check_db_row_count {
  table_name=$1
  SCENARIO_ID=$2
  CARBON_COST=$3
  TEST_SET_ID=$4
  file_row_count=$5
  db_row_count=$(mysql $connection_string --column-names=false -e "\
    select count(*) from $table_name \
      where scenario_id=$SCENARIO_ID and carbon_cost=$CARBON_COST and test_set_id=$TEST_SET_ID;" \
  )
  if [ -z "$db_row_count" ]; then
    echo "ERROR! Could not count rows imported into $table_name. Bailing out."
    exit 1
  fi
  if [ $db_row_count -ne $file_row_count ]; then
    printf "ERROR! Imported %d rows, but expected %d. Bailing out. \n" \
      $db_row_count $file_row_count
    exit 1
  fi
}

working_directory=$(pwd)
###################################################
# Import all of the results files into the DB
if [ $SkipImport == 0 ]; then

  # Look up the starting timestamp & validate that the id assignment convention 
  # holds true for the last timestamp in the series. 
  # Setting the timepoint ids via a join can take over 15 hours, so we're going to 
  # set them based on our convention of assigning ids sequentially starting from 0. 
  # This means the id of any timestamp is just the hours between it and the starting 
  # timestamp. 
  starting_timestamp=$(
    mysql $connection_string --column-names=false -e "\
      select datetime_utc from switch_inputs_wecc_v2_2.study_timepoints where timepoint_id=0";
  )
  does_time_id_shortcut_work=$(
    mysql $connection_string --column-names=false -e "\
      select (timepoint_id = timestampdiff(HOUR,'$starting_timestamp',datetime_utc)) \
      from switch_inputs_wecc_v2_2.study_timepoints \
      order by datetime_utc desc limit 1";
  )
  if [ $does_time_id_shortcut_work -eq 0 ]; then
    echo "The timepoint id lookup trick didn't work! You know, the one where the id of EVERY \
          study timepoint is just the number of hours from the first timepoint? Bailing out!\n"
    exit 1
  fi


  echo 'Clearing old results...'
  mysql $connection_string -e "\
    delete from _dispatch_decisions where scenario_id=$SCENARIO_ID; \
    delete from _dispatch_extra_cap where scenario_id=$SCENARIO_ID; \
    delete from _dispatch_transmission_decisions where scenario_id=$SCENARIO_ID; \
    delete from _dispatch_hourly_la_data where scenario_id=$SCENARIO_ID;"

  echo 'Importing results files...'

  # Iterate over test sets
  cat test_set_ids.txt | while read TEST_SET_ID test_path; do
    echo "  $test_path.."

    # Iterate over carbon costs
    sed -n 's/set CARBON_COSTS *:= *\([0-9 ]*\);/\1/ p' ../switch.dat | while read CARBON_COST; do

      # Import generation and storage dispatch decisions 
      # Dispatch is aggregated by load area, timepoint and technology to reduce file size
      file_base_name="dispatch_sums"
      file_name="${file_base_name}_${CARBON_COST}.txt"
      file_path="${working_directory}/${test_path}/results/${file_name}"
      file_row_count=$(check_file_and_get_row_count "$file_path")
      echo "    ${file_name}  ->  ${DB_name}._dispatch_decisions"
      start_time=$(date +%s)
      mysql $connection_string -e "\
        load data local infile \"$file_path\" \
        into table _dispatch_decisions ignore 1 lines \
        ( \
          scenario_id, carbon_cost, period, area_id, @study_hour, test_set_id, technology_id, \
          @load_area, @balancing_area, @tech, fuel, fuel_category, \
          new, baseload, cogen, storage, @date, hours_in_sample, heat_rate, \
          power, co2_tons, fuel_cost, carbon_cost_incurred, variable_o_m_cost, \
          spinning_reserve, quickstart_capacity, total_operating_reserve, \
          spinning_co2_tons, spinning_fuel_cost, spinning_carbon_cost_incurred, \
          deep_cycling_amount, deep_cycling_fuel_cost, deep_cycling_carbon_cost, deep_cycling_co2_tons, \
          mw_started_up, startup_fuel_cost, startup_nonfuel_cost, startup_carbon_cost, startup_co2_tons \
        ) \
        set study_timepoint_utc = str_to_date( @study_hour, '%Y%m%d%H'), \
            study_timepoint_id = timestampdiff(HOUR,'$starting_timestamp',study_timepoint_utc);"
      end_time=$(date +%s)
      check_db_row_count "_dispatch_decisions" $SCENARIO_ID $CARBON_COST $TEST_SET_ID $file_row_count
      printf "      %d seconds to import %s rows\n" $(($end_time - $start_time)) $file_row_count
    
      # Import transmission dispatch decisions
      file_base_name="transmission_dispatch"
      file_name="${file_base_name}_${CARBON_COST}.txt"
      file_path="${working_directory}/${test_path}/results/${file_name}"
      file_row_count=$(check_file_and_get_row_count "$file_path")
      echo "    ${file_name}  ->  ${DB_name}._dispatch_transmission_decisions"
      start_time=$(date +%s)
      mysql $connection_string -e "\
        load data local infile \"$file_path\" \
        into table _dispatch_transmission_decisions ignore 1 lines \
        ( \
          scenario_id, carbon_cost, period, transmission_line_id, \
            study_hour, rps_fuel_category, test_set_id, \
          study_date, hours_in_sample, send_id, receive_id, @send_la, @receive_la, \
          power_sent, power_received);"
      end_time=$(date +%s)
      check_db_row_count "_dispatch_transmission_decisions" $SCENARIO_ID $CARBON_COST $TEST_SET_ID $file_row_count
      printf "      %d seconds to import %s rows\n" $(($end_time - $start_time)) $file_row_count


      # Import hourly load area data that includes demand response, marginal costs and an estimate of reserve capacity
      file_base_name="dispatch_hourly_la"
      file_name="${file_base_name}_${CARBON_COST}.txt"
      file_path="${working_directory}/${test_path}/results/${file_name}"
      file_row_count=$(check_file_and_get_row_count "$file_path")
      echo "    ${file_name}  ->  ${DB_name}._dispatch_hourly_la_data"
      start_time=$(date +%s)
      mysql $connection_string -e "\
        load data local infile \"$file_path\" \
        into table _dispatch_hourly_la_data ignore 1 lines \
        ( \
          scenario_id, carbon_cost, period, test_set_id, area_id, @study_hour, \
          @load_area, @study_date, hours_in_sample, \
          static_load, res_comm_dr, ev_dr, distributed_generation, \
          satisfy_load_dual, satisfy_load_reserve_dual, dr_com_res_from_dual, \
            dr_com_res_to_dual, dr_ev_from_dual, dr_ev_to_dual, \
          reserve_margin_eligible_capacity_mw, reserve_margin_mw, reserve_margin_percent \
        ) \
        set study_timepoint_utc = str_to_date( @study_hour, '%Y%m%d%H'), \
            study_timepoint_id = timestampdiff(HOUR,'$starting_timestamp',study_timepoint_utc);"
      end_time=$(date +%s)
      check_db_row_count "_dispatch_hourly_la_data" $SCENARIO_ID $CARBON_COST $TEST_SET_ID $file_row_count
      printf "      %d seconds to import %s rows\n" $(($end_time - $start_time)) $file_row_count
                
      
      # Import additional capacity (if any) that was required to meet load
      file_base_name="dispatch_extra_peakers"
      file_name="${file_base_name}_${CARBON_COST}.txt"
      file_path="${working_directory}/${test_path}/results/${file_name}"
      # This file won't exist if there was sufficient capacity, so don't worry if it isn't found
      if [ -f "$file_path" ]; then 
        file_row_count=$(awk 'END {print NR-1}' "$file_path")
        if [ $file_row_count -le 0 ]; then
          printf "Output file $file_path does not contain any records. Bailing out. \n";
          exit 1;
        fi;
        echo "    ${file_name}  ->  ${DB_name}._dispatch_extra_cap"
        start_time=$(date +%s)
        mysql $connection_string -e "\
          load data local infile \"$file_path\" \
          into table _dispatch_extra_cap ignore 1 lines \
          ( \
            scenario_id, carbon_cost, period, project_id, area_id, test_set_id, technology_id, \
            @load_area, @technology, new, baseload, cogen, storage, fuel, \
            additional_capacity, updated_capacity, capital_cost, fixed_o_m_cost );"
        end_time=$(date +%s)
        check_db_row_count "_dispatch_extra_cap" $SCENARIO_ID $CARBON_COST $TEST_SET_ID $file_row_count
        printf "      %d seconds to import %s rows\n" $(($end_time - $start_time)) $file_row_count        
      fi;

      
    done # Done iterating over carbon costs
  done # Done iterating over test_sets 

else
  echo 'Skipping Import.'
fi

###################################################
# Crunch through the data
if [ $SkipCrunch == 0 ]; then
  echo 'Crunching the data...'
  mkdir -p tmp
  data_crunch_path=$(mktemp tmp/import_crunch_sql-XXX);
  echo "set @scenario_id := ${SCENARIO_ID};" >> $data_crunch_path
  cat crunch.sql >> $data_crunch_path
  mysql $connection_string < $data_crunch_path
  rm $data_crunch_path
else
  echo 'Skipping data crunching.'
fi
