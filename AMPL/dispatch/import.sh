#!/bin/bash
# import.sh
# SYNOPSIS
#		./import.sh -h 127.0.0.1 -P 3307 # For connecting through an ssh tunnel you created
#		./import.sh --tunnel             # Initiates an ssh tunnel and uses it to connect.
# INPUTS
#   --help                   Print this message
#   -t | --tunnel            Initiate an ssh tunnel to connect to the database. This won't work if ssh prompts you for your password.
#   -u [DB Username]
#   -p [DB Password]
#   -D [DB name]
#   -P/--port [port number]
#   -h [DB server]
#   --SkipImport             Just crunch the results, don't import any files
#   --SkipCrunch             Just import the raw files, don't crunch the data.
# All arguments are optional.

# This function assumes that the lines at the top of the file that start with a # and a space or tab 
# comprise the help message. It prints the matching lines with the prefix removed and stops at the first blank line.
# Consequently, there needs to be a blank line separating the documentation of this program from this "help" function
function print_help {
	last_line=$(( $(egrep '^[ \t]*$' -n -m 1 $0 | sed 's/:.*//') - 1 ))
	head -n $last_line $0 | sed -e '/^#[ 	]/ !d' -e 's/^#[ 	]//'
}


##########################
# Constants
read SCENARIO_ID < scenario_id.txt
DB_name='switch_results_wecc_v2_2'
db_server='switch-db1.erg.berkeley.edu'
port=3306
ssh_tunnel=1

###################################################
# Detect optional command-line arguments
FlushPriorResults=0
SkipImport=0
SkipCrunch=0
help=0
while [ -n "$1" ]; do
case $1 in
  -t | --tunnel)
    ssh_tunnel=1; shift 1 ;;
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
#	http://dev.mysql.com/doc/refman/5.0/en/password-security.html
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
  ssh -N -p 22 -c 3des $db_server -L $local_port/127.0.0.1/$port &
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

###################################################
# Import all of the results files into the DB
if [ $SkipImport == 0 ]; then

  echo 'Clearing old results...'
  mysql $connection_string -e "\
    delete from _dispatch_decisions where scenario_id=$SCENARIO_ID; \
    delete from _dispatch_extra_cap where scenario_id=$SCENARIO_ID; "

  echo 'Importing results files...'

  # Setting the timepoint ids via a join can take over 15 hours. 
  # Look up the parameters of the id numbering convention & validate that it works
  starting_timestamp=$(mysql $connection_string --column-names=false -e "select datetime_utc from switch_inputs_wecc_v2_2.study_timepoints where timepoint_id=0";)
  time_id_shortcut_works=$(mysql $connection_string --column-names=false -e "select (timepoint_id=timestampdiff(HOUR,'$starting_timestamp',datetime_utc)) from switch_inputs_wecc_v2_2.study_timepoints order by datetime_utc desc limit 1";)
  if [ $time_id_shortcut_works -eq 0 ]; then
    echo "The timepoint id lookup trick didn't work! You know, the one where the id of EVERY study timepoint is just the number of hours from the first timepoint? Bailing out!\n"
    exit 1
  fi

  file_base_name="dispatch_sums"
  for file_path in $(find $(pwd) -name "${file_base_name}_*txt" | grep "[[:digit:]]"); do
    echo "    ${file_path}  ->  ${DB_name}._dispatch_decisions"
    file_row_count=$(wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g' | awk '{print ($1-1)}')
    TEST_SET_ID=$(echo $file_path | sed -e 's|.*/test_set_\([0-9]*\)/.*|\1|')
    CARBON_COST=$(echo $file_path | sed -e 's|.*dispatch_sums_\([0-9]*\)\.txt|\1|')
    start_time=$(date +%s)
    mysql $connection_string -e "\
      load data local infile \"$file_path\" \
        into table _dispatch_decisions ignore 1 lines \
        (scenario_id, carbon_cost, period, area_id, @load_area, @balancing_area, @date, @hour, test_set_id, technology_id, @tech, new, baseload, cogen, storage, fuel, fuel_category, hours_in_sample, power, co2_tons, heat_rate, fuel_cost, carbon_cost_incurred, variable_o_m_cost, spinning_reserve, quickstart_capacity, total_operating_reserve, spinning_co2_tons, spinning_fuel_cost, spinning_carbon_cost_incurred, deep_cycling_amount, deep_cycling_fuel_cost, deep_cycling_carbon_cost, deep_cycling_co2_tons, mw_started_up, startup_fuel_cost, startup_nonfuel_cost, startup_carbon_cost, startup_co2_tons )\
        set study_timepoint_utc = str_to_date( @hour, '%Y%m%d%H'), \
            study_timepoint_id = timestampdiff(HOUR,'$starting_timestamp',study_timepoint_utc);"
    end_time=$(date +%s)
    db_row_count=$(mysql $connection_string --column-names=false -e "\
      select count(*) from _dispatch_decisions \
        where scenario_id=$SCENARIO_ID and carbon_cost=$CARBON_COST and test_set_id=$TEST_SET_ID;" \
    )
    if [ $db_row_count -eq $file_row_count ]; then
    	printf "%20s seconds to import %s rows\n" $(($end_time - $start_time)) $file_row_count
    else
    	printf " -------------\n -- ERROR! Imported %d rows, but expected %d. (%d seconds.) --\n -------------\n" $db_row_count $file_row_count $(($end_time - $start_time))
    	exit
    fi
  done


  file_base_name="dispatch_extra_peakers"
  for file_path in $(find $(pwd) -name "${file_base_name}_*txt" | grep "[[:digit:]]"); do
    echo "    ${file_path}  ->  ${DB_name}._dispatch_extra_cap"
    file_row_count=$(wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g' | awk '{print ($1-1)}')
    
    TEST_SET_ID=$(echo $file_path | sed -e 's|.*/test_set_\([0-9]*\)/.*|\1|')
    CARBON_COST=$(echo $file_path | sed -e 's|.*dispatch_extra_peakers_\([0-9]*\)\.txt|\1|')

    start_time=$(date +%s)
    mysql $connection_string -e "\
    load data local infile \"$file_path\" into table _dispatch_extra_cap ignore 1 lines \
      (scenario_id, carbon_cost, period, project_id, area_id, @load_area, test_set_id, technology_id, @technology, new, baseload, cogen, storage, fuel, additional_capacity, updated_capacity, capital_cost, fixed_o_m_cost );"
    end_time=$(date +%s)
    db_row_count=$(mysql $connection_string --column-names=false -e "select count(*) from _dispatch_extra_cap where scenario_id=$SCENARIO_ID and carbon_cost=$CARBON_COST and test_set_id=$TEST_SET_ID;")
    if [ -n "$db_row_count" ] && [ $db_row_count -eq $file_row_count ]; then
    	printf "%20s seconds to import %s rows\n" $(($end_time - $start_time)) $file_row_count
    else
    	printf " -------------\n -- ERROR! Imported %d rows, but expected %d. (%d seconds.) --\n -------------\n" $db_row_count $file_row_count $(($end_time - $start_time))
    	exit
    fi
  done

else
  echo 'Skipping Import.'
fi

###################################################
# Crunch through the data
if [ $SkipCrunch == 0 ]; then
  echo 'Crunching the data...'
	read SCENARIO_ID < scenario_id.txt
  data_crunch_path=$(mktemp -p tmp import_crunch_sql-XXX);
  echo "set @scenario_id := ${SCENARIO_ID};" >> $data_crunch_path
  cat crunch.sql >> $data_crunch_path
  mysql $connection_string < $data_crunch_path
#  rm $data_crunch_path
else
  echo 'Skipping data crunching.'
fi
