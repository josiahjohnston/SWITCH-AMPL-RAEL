#!/bin/bash
# get_test_inputs.sh
# SYNOPSIS
#   ./get_test_inputs.sh
# DESCRIPTION
#   Prepare runtime directories and inputs for dispatch-only  verification on hours that 
# were withheld from the investment/dispatch joint optimization.
#
# INPUTS. 
#  --help                   Print this message
#  -t | --tunnel            Initiate an ssh tunnel to connect to the database. This won't work if ssh prompts you for your password.
#  -u [DB Username]
#  -p [DB Password]
#  -D [DB name]
#  -P/--port [port number]
#  -h [DB server]
# All arguments are optional.

# This function assumes that the lines at the top of the file that start with a # and a space or tab 
# comprise the help message. It prints the matching lines with the prefix removed and stops at the first blank line.
# Consequently, there needs to be a blank line separating the documentation of this program from this "help" function
function print_help {
	last_line=$(( $(egrep '^[ \t]*$' -n -m 1 $0 | sed 's/:.*//') - 1 ))
	head -n $last_line $0 | sed -e '/^#[ 	]/ !d' -e 's/^#[ 	]//'
}


db_server="switch-db1.erg.berkeley.edu"
DB_name="switch_inputs_wecc_v2_2"
port=3306
if [ $(hostname | grep 'citris' | wc -l) -gt 0 ]; then
  base_data_dir="$HOME/shared/data/dispatch"
else
  base_data_dir="/Volumes/vtrak/switch_dispatch_all_weeks"
fi
if [ ! -d "$base_data_dir" ]; then 
  echo "Cannot find a base directory for the dispatch inputs at $base_data_dir."
  exit -1
fi
ssh_tunnel=0

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
    print_help; exit 0 ;;
  *)
    echo "Unknown option $1"; print_help; exit 0 ;;
esac
done

##########################
# Get the DB user name and password 
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
	printf "Password for MySQL $DB_name on $db_server? "
	stty_orig=`stty -g`   # Save screen settings
	stty -echo            # To keep the password vaguely secure, don't let it show to the screen
	read password
	stty $stty_orig       # Restore screen settings
	echo " "
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
  ssh -N -p 22 -c 3des $db_server -L $local_port/$db_server/$port &
  ssh_pid=$!
  sleep 1
  connection_string="-h 127.0.0.1 --port $local_port -u $user -p$password $DB_name"
  trap "clean_up;" EXIT INT TERM 
else
  connection_string="-h $db_server --port $port -u $user -p$password $DB_name"
fi

# Test the database connection
test_connection=$(mysql $connection_string --column-names=false -e "show databases;")
if [ ! -n "$test_connection" ]
then
	connection_string=`echo "$connection_string" | sed -e "s/ -p[^ ]* / -pXXX /"`
	echo "Could not connect to database with settings: $connection_string"
	clean_up
	exit -1
fi

###########################
# These next variables determine which input data is used
read SCENARIO_ID < ../scenario_id.txt
TRAINING_SET_ID=$(mysql $connection_string --column-names=false -e "select training_set_id from scenarios_v3 where scenario_id=$SCENARIO_ID;")
LOAD_SCENARIO_ID=$(mysql $connection_string --column-names=false -e "select load_scenario_id from training_sets where training_set_id=$TRAINING_SET_ID;")

##########################
# Make links to the common input files in the parent directory instead of exporting from the DB again
input_dir="common_inputs"
mkdir -p $input_dir
for f in balancing_areas.tab biomass_supply_curve_breakpoint.tab biomass_supply_curve_slope.tab carbon_cap_targets.tab existing_plants.tab fuel_costs.tab fuel_info.tab fuel_qualifies_for_rps.tab generator_info.tab load_areas.tab max_system_loads.tab misc_params.dat proposed_projects.tab rps_compliance_entity_targets.tab scenario_information.txt transmission_lines.tab; do
  ln -sf ../../inputs/$f $input_dir/
done
for b in InstallGen OperateEPDuringPeriod InstallTrans; do
  for p in $(cd $input_dir; ls ../../results/$b*); do 
    ln -sf $p $input_dir/
  done
done
ln -sf ../scenario_id.txt .

##########################
# Make directories and gather inputs for each dispatch week in the study.
for test_set_id in $(mysql $connection_string --column-names=false -e "select distinct test_set_id from dispatch_test_sets WHERE training_set_id=$TRAINING_SET_ID;"); do
	echo "test_set_id $test_set_id:"
	test_path=$(printf "test_set_%.3d" $test_set_id)
	input_dir=$test_path"/inputs"
	data_dir=$base_data_dir/tr_set_$TRAINING_SET_ID/$test_path
	# Make all the directories and the parent directories if they don't exists. Don't complain if they already exist.
	mkdir -p $test_path $input_dir $data_dir

	##########################
	# Make links to the common input files 
	for f in $(ls -1 common_inputs); do
		if [ ! -L $input_dir/$f ]; then
			ln -s ../../common_inputs/$f $input_dir/$f
		fi
	done
		
	# Do the same for the code.
	for f in load.run compile.run define_params.run basicstats.run export.run switch.mod switch.dat; do
		if [ ! -L $test_path/$f ]; then
			ln -s ../../$f $test_path/$f
		fi
	done
	for f in $(ls -1 *run); do
		if [ ! -L $test_path/$f ]; then
			ln -s ../$f $test_path/$f
		fi
	done

	echo "$test_set_id" > $test_path/test_set_id.txt

	###########################
	# Export data to be read into AMPL.
	
	# The general format for the following files is for the first line to be:
	#	ampl.tab [number of key columns] [number of non-key columns]
	# col1_name col2_name ...
	# [rows of data]

	SAMPLE_RESTRICTIONS="test_set_id=$test_set_id"
	INTERMITTENT_PROJECTS_SELECTION="(( avg_cap_factor_percentile_by_intermittent_tech >= 0.75 or cumulative_avg_MW_tech_load_area <= 3 * total_yearly_load_mwh / 8766 or rank_by_tech_in_load_area <= 5 or avg_cap_factor_percentile_by_intermittent_tech is null) and technology <> 'Concentrating_PV')"

	f="study_hours.tab"
	echo "	$f..."
	if [ ! -f $data_dir/$f ]; then
		echo ampl.tab 1 5 > $data_dir/$f
    mysql $connection_string -e "\
    SELECT \
      DATE_FORMAT(datetime_utc,'%Y%m%d%H') AS hour, IF(period_start IS NULL, YEAR(NOW()), period_start) as period, \
      DATE_FORMAT(datetime_utc,'%Y%m%d') AS date, hours_in_sample, \
      MONTH(datetime_utc) AS month_of_year, HOUR(datetime_utc) as hour_of_day \
    FROM dispatch_test_sets \
      JOIN study_timepoints USING (timepoint_id) \
      LEFT JOIN training_set_periods USING(training_set_id,periodnum) \
    WHERE training_set_id=$TRAINING_SET_ID AND test_set_id=$test_set_id order by 1" >> $data_dir/$f
	fi
	[ -L $input_dir/$f ] && rm $input_dir/$f  # Remove the link if it exists. The 
	ln -s $data_dir/$f $input_dir/$f          # Make a new link
	
	f="system_load.tab"
	echo "	$f..."
	if [ ! -f $data_dir/$f ]; then
		echo ampl.tab 2 2 > $data_dir/$f
    mysql $connection_string -e "\
      SELECT load_area, DATE_FORMAT(datetime_utc,'%Y%m%d%H') as hour, power as system_load, 1 as present_day_system_load \
        FROM load_projections JOIN dispatch_test_sets USING(timepoint_id) \
        WHERE training_set_id=$TRAINING_SET_ID AND test_set_id=$test_set_id AND load_scenario_id=$LOAD_SCENARIO_ID ; "  >> $data_dir/$f
	fi
	[ -L $input_dir/$f ] && rm $input_dir/$f  # Remove the link if it exists
	ln -s $data_dir/$f $input_dir/$f          # Make a new link
	
	f="existing_intermittent_plant_cap_factor.tab"
	echo "	$f..."
	if [ ! -f $data_dir/$f ]; then
		echo ampl.tab 4 1 > $data_dir/$f
		mysql $connection_string -e "\
      SELECT project_id, load_area, technology, DATE_FORMAT(datetime_utc,'%Y%m%d%H') as hour, cap_factor \
      FROM dispatch_test_sets \
        JOIN study_timepoints USING(timepoint_id)\
        JOIN existing_intermittent_plant_cap_factor ON(historic_hour=hour)\
      WHERE training_set_id=$TRAINING_SET_ID AND test_set_id=$test_set_id\
      order by 1,2;" >> $data_dir/$f
	fi
	[ -L $input_dir/$f ] && rm $input_dir/$f  # Remove the link if it exists
	ln -s $data_dir/$f $input_dir/$f          # Make a new link
	
	f="hydro_monthly_limits.tab"
	echo "	$f..."
	if [ ! -f $data_dir/$f ]; then
		echo ampl.tab 4 1 > $data_dir/$f
		mysql $connection_string -e "\
    CREATE TEMPORARY TABLE study_dates_export\
      SELECT distinct \
        IF(period_start IS NULL, YEAR(NOW()), period_start) as period, \
        YEAR(hours.datetime_utc) as year, MONTH(hours.datetime_utc) AS month, \
        DATE_FORMAT(study_timepoints.datetime_utc,'%Y%m%d') AS study_date \
      FROM dispatch_test_sets \
        JOIN _load_projections USING (timepoint_id)\
        JOIN study_timepoints  USING (timepoint_id)\
        JOIN hours ON(dispatch_test_sets.historic_hour=hournum)\
        LEFT JOIN training_set_periods USING(training_set_id,periodnum)\
      WHERE training_set_id=$TRAINING_SET_ID \
        AND load_scenario_id = $LOAD_SCENARIO_ID\
        AND test_set_id=$test_set_id\
      ORDER BY 1,2;\
    SELECT project_id, load_area, technology, study_date as date, ROUND(avg_output,1) AS avg_output\
      FROM hydro_monthly_limits \
        JOIN study_dates_export USING(year, month);" >> $data_dir/$f
	fi
	[ -L $input_dir/$f ] && rm $input_dir/$f  # Remove the link if it exists
	ln -s $data_dir/$f $input_dir/$f          # Make a new link
	
	f="cap_factor.tab"
	echo "	$f..."
	if [ ! -f $data_dir/$f ]; then
		echo ampl.tab 4 1 > $data_dir/$f
		if [ $LOAD_SCENARIO_ID -lt 10 ]; then 
      mysql $connection_string -e "\
      select project_id, load_area, technology, DATE_FORMAT(datetime_utc,'%Y%m%d%H') as hour, cap_factor  \
        FROM dispatch_test_sets \
          JOIN study_timepoints USING(timepoint_id)\
          JOIN _cap_factor_intermittent_sites ON(historic_hour=hour)\
          JOIN _proposed_projects_v2 USING(project_id)\
          JOIN load_area_info USING(area_id)\
        WHERE training_set_id=$TRAINING_SET_ID \
          AND $INTERMITTENT_PROJECTS_SELECTION\
          AND test_set_id=$test_set_id;" >> $data_dir/$f
    else
      mysql $connection_string -e "\
      select project_id, load_area, technology, DATE_FORMAT(datetime_utc,'%Y%m%d%H') as hour, cap_factor  \
        FROM dispatch_test_sets \
          JOIN study_timepoints USING(timepoint_id)\
          JOIN _cap_factor_intermittent_sites ON(historic_hour=hour)\
          JOIN _proposed_projects_v2 USING(project_id)\
          JOIN load_area_info USING(area_id)\
        WHERE training_set_id=$TRAINING_SET_ID \
          AND $INTERMITTENT_PROJECTS_SELECTION \
          AND technology_id NOT IN (select technology_id from generator_info_v2 WHERE fuel='Solar')\
          AND test_set_id=$test_set_id;" >> $data_dir/$f
      # Get solar cap factors from 2005
      mysql $connection_string -sN -e "\
      CREATE TEMPORARY TABLE solar_tp_mapping \
        SELECT distinct historic_hour, historic_hour-8760 as hour_2005 from load_scenario_historic_timepoints WHERE load_scenario_id=$LOAD_SCENARIO_ID; \
      ALTER TABLE solar_tp_mapping ADD INDEX ( historic_hour, hour_2005 ), ADD INDEX ( hour_2005, historic_hour ); \
      select project_id, load_area, technology, DATE_FORMAT(datetime_utc,'%Y%m%d%H') as hour, cap_factor  \
        FROM dispatch_test_sets \
          JOIN study_timepoints USING(timepoint_id)\
          JOIN solar_tp_mapping USING (historic_hour) \
          JOIN _cap_factor_intermittent_sites ON(hour_2005=hour)\
          JOIN _proposed_projects_v2 USING(project_id)\
          JOIN load_area_info USING(area_id)\
        WHERE training_set_id=$TRAINING_SET_ID \
          AND test_set_id=$test_set_id \
          AND $INTERMITTENT_PROJECTS_SELECTION \
          AND technology_id IN (select technology_id from generator_info_v2 WHERE fuel='Solar');" >> $data_dir/$f
    fi
	fi
	[ -L $input_dir/$f ] && rm $input_dir/$f  # Remove the link if it exists
	ln -s $data_dir/$f $input_dir/$f          # Make a new link

# clean_up
# exit

done

#clean_up
