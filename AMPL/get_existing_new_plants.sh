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

echo '	existing_plants.tab...'
echo ampl.tab 3 11 > existing_plants.tab
echo 'project_id	province	technology	plant_name	carma_plant_id	capacity_mw	heat_rate	cogen_thermal_demand_mmbtus_per_mwh	start_year	overnight_cost	connect_cost_per_mw	fixed_o_m	variable_o_m	ep_location_id' >> existing_plants.tab
$connection_string -A -t -F  $'\t' -c  "select project_id, province, technology, plant_name, carma_plant_id, ROUND(cast(capacity_mw as numeric),2)  AS capacity_mw, heat_rate,\
cogen_thermal_demand_mmbtus_per_mwh, start_year, overnight_cost, connect_cost_per_mw, fixed_o_m, variable_o_m, ep_location_id \
from existing_plants order by technology, province, project_id;" >> existing_plants.tab

 echo '	new_projects.tab...'
echo ampl.tab 3 11 > new_projects.tab
echo 'project_id	province	technology	location_id	ep_project_replacement_id	capacity_limit	capacity_limit_conversion	heat_rate	cogen_thermal_demand	connect_cost_per_mw	overnight_cost	fixed_o_m	variable_o_m	overnight_cost_change' >> new_projects.tab
$connection_string -A -t -F  $'\t' -c  "select project_id, province, technology, location_id, ep_project_replacement_id, \
capacity_limit, capacity_limit_conversion, heat_rate, cogen_thermal_demand, connect_cost_per_mw, overnight_cost, fixed_o_m, variable_o_m, overnight_cost_change \
from new_projects;" >> new_projects.tab

cd ..
