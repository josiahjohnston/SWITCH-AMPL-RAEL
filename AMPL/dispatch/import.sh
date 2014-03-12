#!/bin/bash

##########################
# Constants
DB_name='switch_results_wecc_v2_2'
db_server='switch-db2.erg.berkeley.edu'
port=3306
write_over_prior_results="IGNORE"
read SCENARIO_ID < scenario_id.txt

###################################################
# Detect optional command-line arguments
FlushPriorResults=0
SkipImport=0
SkipCrunch=0
help=0
while [ -n "$1" ]; do
case $1 in
  -u)
    user=$2
    shift 2
  ;;
  -p)
    password=$2
    shift 2
  ;;
  -P)
    port=$2
    shift 2
  ;;
  --port)
    port=$2
    shift 2
  ;;
  -D)
    DB_name=$2
    shift 2
  ;;
  -h)
    db_server=$2
    shift 2
  ;;
  --FlushPriorResults) 
    FlushPriorResults=1
    write_over_prior_results="REPLACE"
    shift 1
  ;;
  --SkipImport) 
    SkipImport=1;
    shift 1
  ;;
#  --ExportOnly) 
	--SkipCrunch)
    SkipCrunch=1
    shift 1
  ;;
  --help)
    help=1
    shift 1
  ;;
  *)
    echo "Unknown option $1"
    shift 1
  ;;
esac
done

if [ $help = 1 ]
then
  echo "Usage: $0 [OPTIONS]"
  echo "  --help                   Print this menu"
  echo "  -u [DB Username]"
  echo "  -p [DB Password]"
  echo "  -D [DB name]"
  echo "  -P/--port [port number]"
  echo "  -h [DB server]"
  echo "  --FlushPriorResults      Delete all prior results for this scenario before importing."
  echo "  --SkipImport             Just crunch the results, don't import any files"
  echo "  --SkipCrunch             Just import the raw files, don't crunch the data. "
#  echo "  --ExportOnly             Only export summaries of the results, don't import or crunch data in the DB"
  echo "All arguments are optional. "
  exit 0
fi

##########################
# Get the user name and password 
# Note that passing the password to mysql via a command line parameter is considered insecure
#	http://dev.mysql.com/doc/refman/5.0/en/password-security.html
if [ ! -n "$user" ]
then 
	echo "User name for MySQL $DB_name on $db_server? "
	read user
fi
if [ ! -n "$password" ]
then 
	echo "Password for MySQL $DB_name on $db_server? "
	stty_orig=`stty -g`   # Save screen settings
	stty -echo            # To keep the password vaguely secure, don't let it show to the screen
	read password
	stty $stty_orig       # Restore screen settings
fi

connection_string="-h $db_server --port $port -u $user -p$password $DB_name"
test_connection=`mysql $connection_string --column-names=false -e "show tables;"`
if [ -z "$test_connection" ]
then
  connection_string=`echo "$connection_string" | sed -e "s/ -p[^ ]* / -pXXX /"`
  echo "Could not connect to database with settings: $connection_string"
  exit 0
fi

###################################################
# Import all of the results files into the DB
if [ $SkipImport = 0 ]; then
  echo 'Importing results files...'

	mysql $connection_string -e "drop table if exists tmp_dispatch_weeks; create table if not exists tmp_dispatch_weeks (select week_num, min(datetime_utc) as week_start, max(datetime_utc) as week_end from switch_inputs_wecc_v2_2.dispatch_weeks group by 1 order by 1); alter table tmp_dispatch_weeks add primary key week_num_idx (week_num);"

  file_base_name="dispatch_sums"
  for file_path in $(find $(pwd) -name "${file_base_name}_*txt" | grep "[[:digit:]]"); do
    echo "    ${file_path}  ->  ${DB_name}._dispatch_weekly"
    file_row_count=$(wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g' | awk '{print ($1-1)}')
    WEEK_NUM=$(echo $file_path | sed -e 's|.*/dispatch/week\([0-9]*\)/.*|\1|')
    CARBON_COST=$(echo $file_path | sed -e 's|.*dispatch_sums_\([0-9]*\)\.txt|\1|')
    start_time=$(date +%s)
    mysql $connection_string -e "load data local infile \"$file_path\" $write_over_prior_results into table _dispatch_weekly ignore 1 lines (scenario_id, carbon_cost, period, project_id, area_id, @junk, week_num, technology_id, @junk, new, baseload, cogen, storage, fuel, fuel_category, hours_in_sample, power, co2_tons, heat_rate, fuel_cost, carbon_cost_incurred, variable_o_m_cost); update _dispatch_weekly, tmp_dispatch_weeks set _dispatch_weekly.week_start = tmp_dispatch_weeks.week_start, _dispatch_weekly.week_end = tmp_dispatch_weeks.week_end where tmp_dispatch_weeks.week_num = _dispatch_weekly.week_num and scenario_id=$SCENARIO_ID;"
    end_time=$(date +%s)
    db_row_count=$(mysql $connection_string --column-names=false -e "select count(*) from _dispatch_weekly where scenario_id=$SCENARIO_ID and carbon_cost=$CARBON_COST and week_num=$WEEK_NUM;")
    if [ $db_row_count -eq $file_row_count ]; then
    	printf "%20s seconds to import %s rows\n" $(($end_time - $start_time)) $file_row_count
    else
    	printf " -------------\n -- ERROR! Imported %d rows, but expected %d. (%d seconds.) --\n -------------\n" $db_row_count $file_row_count $(($end_time - $start_time))
    	exit
    fi
  done

	mysql $connection_string -e "drop table if exists tmp_dispatch_weeks;"

else
  echo 'Skipping Import.'
fi

###################################################
# Crunch through the data
if [ $SkipCrunch = 0 ]; then
  echo 'Crunching the data...'
	read SCENARIO_ID < scenario_id.txt
  data_crunch_path=tmp_crunch$$.sql
  echo "set @scenario_id := ${SCENARIO_ID};" >> $data_crunch_path
  cat crunch.sql >> $data_crunch_path
  mysql $connection_string < $data_crunch_path
  rm $data_crunch_path
else
  echo 'Skipping data crunching.'
fi
