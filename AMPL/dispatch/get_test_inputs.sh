# Export SWITCH input data from the Switch inputs database into text files that will be read in by AMPL
# This script assumes that the input database has already been built by the script 'Build WECC Cap Factors.sql'

db_server="switch-db1.erg.berkeley.edu"
DB_name="switch_inputs_wecc_v2_2"
port=3306
base_data_dir="/Volumes/Data/switch_dispatch_all_weeks"

###################################################
# Detect optional command-line arguments
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
  --help)
    help=1
    shift 1
  ;;
  *)
    echo "Unknown option $1"
    help=1
    shift 1
  ;;
esac
done

if [ $help = 1 ]
then
  echo "Usage: $0 [OPTIONS]"
  echo "  --help                   Print this message"
  echo "  -u [DB Username]"
  echo "  -p [DB Password]"
  echo "  -D [DB name]"
  echo "  -P/--port [port number]"
  echo "  -h [DB server]"
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
test_connection=`mysql $connection_string --column-names=false -e "select count(*) from existing_plants;"`
if [ ! -n "$test_connection" ]
then
	connection_string=`echo "$connection_string" | sed -e "s/ -p[^ ]* / -pXXX /"`
	echo "Could not connect to database with settings: $connection_string"
	exit 0
fi


###########################
# These next variables determine which input data is used

read SCENARIO_ID < ../scenario_id.txt

REGIONAL_MULTIPLIER_SCENARIO_ID=$(mysql $connection_string --column-names=false -e "select regional_cost_multiplier_scenario_id from scenarios where scenario_id=$SCENARIO_ID;")
REGIONAL_FUEL_COST_SCENARIO_ID=$(mysql $connection_string --column-names=false -e "select regional_fuel_cost_scenario_id from scenarios where scenario_id=$SCENARIO_ID;")
REGIONAL_GEN_PRICE_SCENARIO_ID=$(mysql $connection_string --column-names=false -e "select regional_gen_price_scenario_id from scenarios where scenario_id=$SCENARIO_ID;") 
ENABLE_RPS=$(mysql $connection_string --column-names=false -e "select enable_rps from scenarios where scenario_id=$SCENARIO_ID;")
DATESAMPLE=`mysql $connection_string --column-names=false -e "select _datesample from scenarios where scenario_id=$SCENARIO_ID;"` 
number_of_years_per_period=$(mysql $connection_string --column-names=false -e "select (max(period)-min(period))/(count(distinct period) - 1 ) from study_dates_all where $DATESAMPLE;")
NUM_HISTORIC_YEARS=$(mysql $connection_string --column-names=false -e "select count(distinct year(datetime_utc)) from hours;")
EXCLUDE_PERIODS=$(mysql $connection_string --column-names=false -e "select exclude_periods from scenarios where scenario_id=$SCENARIO_ID;")


##########################
# Make links to the common input files in the parent directory instead of exporting from the DB again
input_dir="common_inputs"
if [ ! -d $input_dir ]; then
	mkdir $input_dir
fi
for f in enable_rps.txt load_areas.tab rps_load_area_targets.tab transmission_lines.tab existing_plants.tab proposed_projects.tab competing_locations.tab generator_info.tab fuel_costs.tab fuel_info.tab fuel_qualifies_for_rps.tab misc_params.dat carbon_cap_targets.tab biomass_supply_curve_breakpoint.tab biomass_supply_curve_slope.tab scenario_information.txt; do
	if [ ! -L $input_dir/$f ]; then
		ln -s ../../inputs/$f $input_dir/$f
	fi
done
f=scenario_id.txt
if [ ! -L $f ]; then
	ln -s ../$f .
fi


##########################
# Make directories and gather inputs for each dispatch week.
for week_num in $(mysql $connection_string --column-names=false -e "select distinct week_num from dispatch_weeks;"); do
	echo "Week $week_num:"
	week_path=$(printf "week%.3d" $week_num)
	if [ ! -d $week_path ]; then
		mkdir $week_path
	fi
	input_dir=$week_path"/inputs"
	if [ ! -d $input_dir ]; then
		mkdir $input_dir
	fi
	data_dir=$base_data_dir/$week_path
	if [ ! -d $data_dir ]; then
		mkdir $data_dir
	fi

	##########################
	# Make links to the common input files 
	for f in $(ls -1 common_inputs); do
		if [ ! -L $input_dir/$f ]; then
			ln -s ../../common_inputs/$f $input_dir/$f
		fi
	done
		
	# Do the same for the code.
	for f in basicstats.run record_results.run switch.run windsun.run windsun.mod windsun.dat; do
		if [ ! -L $week_path/$f ]; then
			ln -s ../../$f $week_path/$f
		fi
	done
	for f in record_dispatch_sums.run test.run; do
		if [ ! -L $week_path/$f ]; then
			ln -s ../$f $week_path/$f
		fi
	done

	###########################
	# Export data to be read into ampl.
	
	# The general format for the following files is for the first line to be:
	#	ampl.tab [number of key columns] [number of non-key columns]
	# col1_name col2_name ...
	# [rows of data]
	echo "$week_num" > $week_path/week_num.txt

	SAMPLE_RESTRICTIONS="week_num=$week_num and FIND_IN_SET( period, '$EXCLUDE_PERIODS')=0"
	INTERMITTENT_PROJECTS_SELECTION="(( avg_cap_factor_percentile_by_intermittent_tech >= 0.75 or cumulative_avg_MW_tech_load_area <= 3 * total_yearly_load_mwh / 8766 or rank_by_tech_in_load_area <= 5 or avg_cap_factor_percentile_by_intermittent_tech is null) and technology <> 'Concentrating_PV')"

	f="study_hours.tab"
	echo "	$f..."
	if [ ! -f $data_dir/$f ]; then
		echo ampl.tab 1 5 > $data_dir/$f
		mysql $connection_string -e "select study_hour as hour, period, study_date as date, $number_of_years_per_period/$NUM_HISTORIC_YEARS as hours_in_sample, month_of_year, hour_of_day from dispatch_weeks where $SAMPLE_RESTRICTIONS order by 1;" >> $data_dir/$f
	fi
	if [ ! -L $input_dir/$f ]; then
		ln -s $data_dir/$f $input_dir/$f
	fi
	
	
	# TODO: adopt better load forecasts; this assumes a simple 1.0%/year increase - the amount projected for all of WECC from 2010 to 2018 by the EIA AEO 2008
	# currently we hit the middle of the period with number_of_years_per_period/2
	f="system_load.tab"
	echo "	$f..."
	if [ ! -f $data_dir/$f ]; then
		echo ampl.tab 2 2 > $data_dir/$f
		mysql $connection_string -e "select load_area, study_hour as hour, power(1.01, period + $number_of_years_per_period/2 - year(datetime_utc))*power as system_load, power(1.01, $present_year - year(datetime_utc))*power as present_day_system_load from system_load l join dispatch_weeks h on (h.hournum=l.hour) where $SAMPLE_RESTRICTIONS order by study_hour, load_area;" >> $data_dir/$f
	fi
	if [ ! -L $input_dir/$f ]; then
		ln -s $data_dir/$f $input_dir/$f
	fi
	
	f="existing_intermittent_plant_cap_factor.tab"
	echo "	$f..."
	if [ ! -f $data_dir/$f ]; then
		echo ampl.tab 4 1 > $data_dir/$f
		mysql $connection_string -e "select project_id, load_area, technology, study_hour as hour, cap_factor from  existing_intermittent_plant_cap_factor c join dispatch_weeks h on (h.hournum=c.hour) where $SAMPLE_RESTRICTIONS order by 1,2;" >> $data_dir/$f
	fi
	if [ ! -L $input_dir/$f ]; then
		ln -s $data_dir/$f $input_dir/$f
	fi
	
	f="hydro_monthly_limits.tab"
	echo "	$f..."
	if [ ! -f $data_dir/$f ]; then
		echo ampl.tab 4 1 > $data_dir/$f
		mysql $connection_string -e "select project_id, load_area, technology, study_date as date, avg_output from hydro_monthly_limits l, (select distinct week_num, period, study_date, date_utc, month_of_year from dispatch_weeks where $SAMPLE_RESTRICTIONS) d where l.year = year(d.date_utc) and l.month=month(d.date_utc) order by 1, 2, month, year;" >> $data_dir/$f
	fi
	if [ ! -L $input_dir/$f ]; then
		ln -s $data_dir/$f $input_dir/$f
	fi
	
	f="cap_factor.tab"
	echo "	$f..."
	if [ ! -f $data_dir/$f ]; then
		echo ampl.tab 4 1 > $data_dir/$f
		mysql $connection_string -e "select project_id, proposed_projects.load_area, proposed_projects.technology, study_hour as hour, cap_factor from _cap_factor_intermittent_sites c join dispatch_weeks h on (h.hournum=c.hour) join proposed_projects using (project_id) join load_area_info using (area_id) where $INTERMITTENT_PROJECTS_SELECTION and $SAMPLE_RESTRICTIONS;" >> $data_dir/$f
	fi
	if [ ! -L $input_dir/$f ]; then
		ln -s $data_dir/$f $input_dir/$f
	fi

done

