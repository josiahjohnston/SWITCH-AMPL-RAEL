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

# Set the umask to give group read & write permissions to all files & directories made by this script.
umask=0002

db_server="switch-db1.erg.berkeley.edu"
DB_name="switch_inputs_wecc_v2_2"
port=3306
if [ $(hostname | grep 'citris' | wc -l) -gt 0 ]; then
  base_data_dir="$HOME/shared/data/dispatch/daily"
else
  base_data_dir="/Volumes/switch/switch_dispatch_all_weeks/daily"
fi
if [ ! -d "$base_data_dir" ]; then 
  echo "Cannot find a base directory for the dispatch inputs at $base_data_dir."
  exit -1
fi
ssh_tunnel=1

###################################################
# Detect optional command-line arguments
help=0
while [ -n "$1" ]; do
case $1 in
  -t | --tunnel)
    ssh_tunnel=1; shift 1 ;;
  --notunnel)
    ssh_tunnel=0; shift 1 ;;
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
  ssh -N -p 22 -c 3des "$user"@"$db_server" -L $local_port/127.0.0.1/$port &
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
else 
	echo "Database connection is working. "
fi

###########################
# These next variables determine which input data is used
read SCENARIO_ID < ../scenario_id.txt
TRAINING_SET_ID=$(mysql $connection_string --column-names=false -e "select training_set_id from scenarios_v3 where scenario_id=$SCENARIO_ID;")
LOAD_SCENARIO_ID=$(mysql $connection_string --column-names=false -e "select load_scenario_id from training_sets where training_set_id=$TRAINING_SET_ID;")
GEN_INFO_SCENARIO_ID=$(mysql $connection_string --column-names=false -e "select gen_info_scenario_id from scenarios_v3 where scenario_id=$SCENARIO_ID;")

##########################
# Make links to the common input files in the parent directory instead of exporting from the DB again
input_dir="common_inputs"
mkdir -p $input_dir
for f in balancing_areas.tab biomass_supply_curve.tab carbon_cap_targets.tab existing_plants.tab fuel_costs.tab fuel_info.tab generator_costs.tab generator_info.tab load_areas.tab max_system_loads.tab misc_params.dat misc_options.run ng_supply_curve.tab  ng_regional_price_adders.tab proposed_projects.tab rps_compliance_entity_targets.tab scenario_information.txt transmission_lines.tab shiftable_res_comm_load.tab shiftable_ev_load.tab; do
  if [ -f ../inputs/$f ]; then
    ln -sf ../../inputs/$f $input_dir/
  else
    echo "Warning! $f does not exist in the input directory."
  fi;
done
cd $input_dir;
for b in InstallGen OperateEPDuringPeriod InstallTrans carbon_cost_by_period ng_consumption_and_prices_by_period biomass_consumption_and_prices_by_period; do
  for p in $(ls ../../results/$b*); do 
    ln -sf $p .
  done
done
cd ..
ln -sf ../scenario_id.txt .

####################################################
# Goal: Make a list of project IDs used by the optimization that we need capacity factors for. 
mkdir -p tmp
projects_that_need_cap_factors=tmp/projects_that_need_cap_factors.txt
# First make a list of technologies that need capacity factors. The criteria are taken from the AMPL check: check: card({(pid, a, t) in PROJECTS: intermittent[t] and resource_limited[t] and not ccs[t]} diff PROJ_INTERMITTENT) = 0;
awk '{ if(NF >= 18) { tech=$1; intermittent=$17; resource_limited=$18; ccs=$16; if(intermittent == 1 && resource_limited == 1 && ccs == 0) { print tech; } } }' ../inputs/generator_info.tab > tmp/tech_that_needs_cap_factors.txt
# Make a regular expression to match any member in the list of technologies
techs_needed=$(awk '{if (NR>1 && length($1)>0) printf "|"$1; else if (NR==1 && length($1) > 0) printf $1; }' tmp/tech_that_needs_cap_factors.txt)
# Use the tech list to pull project ids
awk '{ if( $3 ~ /'$techs_needed'/) print $1; }' ../inputs/proposed_projects.tab > $projects_that_need_cap_factors


##########################
# Make directories and gather inputs for each dispatch week in the study.
for test_set_id in $(mysql $connection_string --column-names=false -e "select distinct test_set_id from dispatch_test_sets WHERE training_set_id=$TRAINING_SET_ID;"); do
	echo "test_set_id $test_set_id:"
	test_path=$(printf "test_set_%.3d" $test_set_id)
	input_dir=$test_path"/inputs"
	data_dir=$base_data_dir/tr_set_$TRAINING_SET_ID/$test_path
	start_hour=$(mysql $connection_string --column-names=false -e "select historic_hour from dispatch_test_sets WHERE training_set_id=$TRAINING_SET_ID AND test_set_id=$test_set_id ORDER BY historic_hour ASC LIMIT 1;")
	end_hour=$(mysql $connection_string --column-names=false -e "select historic_hour from dispatch_test_sets WHERE training_set_id=$TRAINING_SET_ID AND test_set_id=$test_set_id ORDER BY historic_hour DESC LIMIT 1;")
	data_dir_historical_cap_factor=$base_data_dir/historical_cap_factors/${start_hour}_to_${end_hour}
	# Make all the directories and the parent directories if they don't exists. Don't complain if they already exist.
	mkdir -p $test_path $input_dir $data_dir $data_dir_historical_cap_factor

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

  ###############################
  # New way of gathering cap factors based on historical hour of every project and a mapping from historical hour to future hour
	f="cap_factor_historical.tab"
	echo "	$f..."
	if [ ! -f $data_dir_historical_cap_factor/$f ]; then
    echo ampl.tab 4 1 > $data_dir_historical_cap_factor/$f
    mysql $connection_string -e "\
      select project_id, load_area, technology, DATE_FORMAT(datetime_utc,'%Y%m%d%H') as historical_hour, cap_factor as cap_factor_historical \
        FROM dispatch_test_sets \
          JOIN hours ON(historic_hour=hournum) \
          JOIN _cap_factor_intermittent_sites ON(historic_hour=hour) \
          JOIN _proposed_projects_v2 USING(project_id) \
          JOIN load_area_info USING(area_id) \
        WHERE training_set_id=$TRAINING_SET_ID \
          AND test_set_id=$test_set_id \
          AND periodnum=0;" >> $data_dir_historical_cap_factor/$f
  fi
	[ -L $input_dir/$f ] && rm $input_dir/$f  # Remove the link if it exists
	ln -s $data_dir_historical_cap_factor/$f $input_dir/$f          # Make a new link

	f="historical_to_future_timepoint_mapping.tab"
	echo "	$f..."
	if [ ! -f $data_dir/$f ]; then
    echo ampl.tab 3 0 > $data_dir/$f
    if [ $LOAD_SCENARIO_ID -lt 10 ]; then 
      mysql $connection_string -e "\
        select DATE_FORMAT(hours.datetime_utc,'%Y%m%d%H') as historical_hour, DATE_FORMAT(study_timepoints.datetime_utc,'%Y%m%d%H') as future_hour, technology \
          FROM dispatch_test_sets \
            JOIN hours ON(historic_hour=hournum)\
            JOIN study_timepoints USING(timepoint_id)\
            JOIN (SELECT DISTINCT technology FROM generator_info_v2 WHERE intermittent=1) AS gen_info \
          WHERE training_set_id=$TRAINING_SET_ID \
            AND test_set_id=$test_set_id;" >> $data_dir/$f
    else 
      # Non-solar projects get cap factors from 2006
      mysql $connection_string -e "\
        select DATE_FORMAT(hours.datetime_utc,'%Y%m%d%H') as historical_hour, DATE_FORMAT(study_timepoints.datetime_utc,'%Y%m%d%H') as future_hour, technology \
          FROM dispatch_test_sets \
            JOIN hours ON(historic_hour=hournum) \
            JOIN study_timepoints USING(timepoint_id) \
            JOIN (SELECT DISTINCT technology FROM generator_info_v2 WHERE intermittent=1 AND fuel <> 'Solar') AS gen_info \
          WHERE training_set_id=$TRAINING_SET_ID \
            AND test_set_id=$test_set_id;" >> $data_dir/$f
      # Solar projects get cap factors from 2005
      mysql $connection_string -e "\
        CREATE TEMPORARY TABLE solar_tp_mapping \
          SELECT distinct historic_hour, historic_hour-8760 as hour_2005 from load_scenario_historic_timepoints WHERE load_scenario_id=$LOAD_SCENARIO_ID; \
        ALTER TABLE solar_tp_mapping ADD INDEX ( historic_hour, hour_2005 ), ADD INDEX ( hour_2005, historic_hour ); \
        SELECT DATE_FORMAT(hours.datetime_utc,'%Y%m%d%H') as historical_hour, DATE_FORMAT(study_timepoints.datetime_utc,'%Y%m%d%H') as future_hour, technology \
            FROM dispatch_test_sets \
              JOIN study_timepoints USING(timepoint_id)\
              JOIN solar_tp_mapping USING (historic_hour) \
              JOIN hours ON(hour_2005=hournum) \
              JOIN (SELECT DISTINCT technology FROM generator_info_v2 WHERE intermittent=1 AND fuel='Solar') AS gen_info \
          WHERE training_set_id=$TRAINING_SET_ID \
            AND test_set_id=$test_set_id;" >> $data_dir/$f
    fi
  fi
	[ -L $input_dir/$f ] && rm $input_dir/$f  # Remove the link if it exists
	ln -s $data_dir/$f $input_dir/$f          # Make a new link

done
