#!/bin/bash
# import_results_into_postgres.sh
# SYNOPSIS
#		./import_results_into_postgres.sh 
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

# Import SWITCH input data from the results text files into the Switch database

function print_help {
  echo $0 # Print the name of this file. 
  # Print the following text, end at the phrase END_HELP
  cat <<END_HELP
SYNOPSIS
	./get_switch_input_tables.sh 
DESCRIPTION
	Pull input data for Switch from databases and format it for AMPL
This script assumes that the input database has already been built by the script compile_switch_chile.sql, DefineScenarios.sql, new_tables_for_db.sql, Setup_Study_Hours.sql, table_edits.sql.

INPUTS
 --help                   Print this message
 -u [DB Username]
 -D [DB name]
 -h [DB server]
All arguments are optional.
END_HELP
}

write_to_path='inputs'
db_server="switch-db2.erg.berkeley.edu"
DB_name="switch_gis"

###################################################
# Detect optional command-line arguments
help=0
while [ -n "$1" ]; do
case $1 in
  -u)
    user=$2; shift 2 ;;
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
# Get the user name (default to system user name of current user) 
default_user=$(whoami)
if [ ! -n "$user" ]
then 
	printf "User name for PostGreSQL $DB_name on $db_server [$default_user]? "
	read user
	if [ -z "$user" ]; then 
	  user="$default_user"
	fi
fi

connection_string="psql -h $db_server -U $user $DB_name"

test_connection=`$connection_string -t -c "select count(*) from chile.load_area;"`

if [ ! -n "$test_connection" ]
then
	connection_string=`echo "$connection_string" | sed -e "s/ -p[^ ]* / -pXXX /"`
	echo "Could not connect to database with settings: $connection_string"
	exit 0
fi

############
# Before anything, we determine which scenario_id we are crunching
read SCENARIO_ID < scenario_id.txt

# Now put this value in a temporary table that the crunch_results_for_one_scenario SQL script can read
$connection_string -A -t -F  $'\t' -c "delete from chile.temp_scenario; \
  insert into chile.temp_scenario SELECT $SCENARIO_ID as scenario;"

####################################################
# Crunch through the data
  echo 'Crunching the data...'
  data_crunch_path=tmp_data_crunch$$.sql
  #echo 'set @scenario_id := '"${SCENARIO_ID};" >> $data_crunch_path
  cat crunch_results_for_one_scenario.sql >> $data_crunch_path
  $connection_string < $data_crunch_path
  rm $data_crunch_path

###################################################
