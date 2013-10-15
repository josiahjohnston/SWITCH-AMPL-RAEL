#!/bin/bash
# export_carbon_intensity.sh
# SYNOPSIS
#		./export_carbon_intensity.sh --tunnel -np --scenario_id 2105 --carbon_cost 0 --fuel_cat_id 3 --study_date 20490417
# DESCRIPTION
# 
# RECOMMENDED INPUTS
#  -s/--scenario_id [scenario_id] 
#  -c/--carbon_cost [carbon_cost] 
#  -f | --fuel_cat_id [fuel_category_id] 
#  -d | --study_date [study_date_id] 
#
# OPTIONAL INPUTS
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

# Set the umask to give group read & write permissions to all files & directories made by this script.
umask 0002

# Export SWITCH input data from the Switch inputs database into text files that will be read in by AMPL
# This script assumes that the input database has already been built by the script 'Build WECC Cap Factors.sql'

db_server="switch-db1.erg.berkeley.edu"
DB_name="switch_results_wecc_v2_2"
port=3306
ssh_tunnel=0
no_password=0

STUDY_DATE=20490417
FUEL_CAT_ID=3
SCENARIO_ID=2105
CARBON_COST=0


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
  -P | --port)
    port=$2; shift 2 ;;
  -D)
    DB_name=$2; shift 2 ;;
  -h)
    db_server=$2; shift 2 ;;
  -s | --scenario_id)
    SCENARIO_ID=$2; shift 2 ;;
  -d | --study_date)
    STUDY_DATE=$2; shift 2 ;;
  -f | --fuel_cat_id)
    FUEL_CAT_ID=$2; shift 2 ;;
  -c | --carbon_cost)
    CARBON_COST=$2; shift 2 ;;
  --help)
		print_help; exit ;;
  *)
    echo "Unknown option $1"
		print_help; exit ;;
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
if [ ! -n "$password" ] && [ $no_password -eq 0 ]
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
  if [ $no_password -eq 0 ]; then
    connection_string="-h 127.0.0.1 --port $local_port -u $user -p$password $DB_name"
  else
    connection_string="-h 127.0.0.1 --port $local_port -u $user $DB_name"
  fi
  trap "clean_up;" EXIT INT TERM 
else
  if [ $no_password -eq 0 ]; then
    connection_string="-h $db_server --port $port -u $user -p$password $DB_name"
  else
    connection_string="-h $db_server --port $port -u $user $DB_name"
  fi
fi

test_connection=`mysql $connection_string --column-names=false -e "show tables;"`
if [ ! -n "$test_connection" ]
then
	connection_string=`echo "$connection_string" | sed -e "s/ -p[^ ]* / -pXXX /"`
	echo "Could not connect to database with settings: $connection_string"
	exit 0
fi



##############
#
for ITERATION in $(mysql $connection_string --column-names=false -e "\
  SELECT DISTINCT iteration FROM hourly_la_emission_stocks \
  WHERE fuel_category_id=$FUEL_CAT_ID AND study_date=$STUDY_DATE \
    AND scenario_id=$SCENARIO_ID AND carbon_cost=$CARBON_COST;"); 
do

output_file=$(printf "emissions_%d_%d_%d_%d_%d.dot" $SCENARIO_ID $CARBON_COST $FUEL_CAT_ID $STUDY_DATE $ITERATION)
echo "Exporting iteration $ITERATION to $output_file"

printf "\
digraph emission_tracking_${SCENARIO_ID}_${STUDY_DATE}_${CARBON_COST} {\n \
  node [style=filled];\n \
  // Begin hourly load area stocks. \n" > $output_file

max_brightness=1
brightness_range=0.8

# Make nodes for each load area's stock in every hour
max_emissions=$(mysql $connection_string --column-names=false -e "\
SELECT MAX(net_emissions) FROM hourly_la_emission_stocks \
WHERE fuel_category_id=$FUEL_CAT_ID AND study_date=$STUDY_DATE AND \
  scenario_id=$SCENARIO_ID AND carbon_cost=$CARBON_COST" )
min_emissions=$(mysql $connection_string --column-names=false -e "\
SELECT MIN(net_emissions) FROM hourly_la_emission_stocks \
WHERE fuel_category_id=$FUEL_CAT_ID AND study_date=$STUDY_DATE AND \
  scenario_id=$SCENARIO_ID AND carbon_cost=$CARBON_COST" )
(cat <<END 
SELECT CONCAT(
load_area, '_', study_hour, ' [shape="ellipse", fillcolor="0 0 ', round($max_brightness-($brightness_range*(net_emissions-$min_emissions)/$max_emissions), 3), 
'", label="', load_area, '\\n', 
if(gross_power<1000, concat(round(gross_power), ' MW, '), concat(round(gross_power/1000, 1), ' GW, ')),
if(net_power<1000, concat(round(net_power), ' MW\\n'), concat(round(net_power/1000, 1), ' GW\\n')),
if(gross_emissions<1000, concat(round(gross_emissions), ' t, '), concat(round(gross_emissions/1000, 1), ' kt, ')), 
if(net_emissions<1000, concat(round(net_emissions), ' t'), concat(round(net_emissions/1000, 1), ' kt')), '"', 
if(gross_power >= 1000 or net_emissions >= 1000, ', fontsize=20', ''), '];'
) 
FROM hourly_la_emission_stocks
  JOIN load_areas USING(area_id)
WHERE fuel_category_id=$FUEL_CAT_ID AND study_date=$STUDY_DATE 
  AND scenario_id=$SCENARIO_ID AND carbon_cost=$CARBON_COST
  AND iteration=$ITERATION;
END
) | mysql $connection_string --column-names=false >> $output_file

# Make a subgraph for each hour
printf "// Begin hourly subgraph clusters. \n" >> $output_file
(cat <<END 
SELECT CONCAT(
'subgraph cluster_hour_', study_hour, ' { graph [fontsize=20, bgcolor=cornsilk, label="Study hour ', study_hour, ', Round $ITERATION"];', group_concat( concat(load_area, '_', study_hour, ';' ) SEPARATOR ' '), ' }'
) 
FROM hourly_la_emission_stocks
  JOIN load_areas USING(area_id)
WHERE fuel_category_id=$FUEL_CAT_ID AND study_date=$STUDY_DATE 
  AND scenario_id=$SCENARIO_ID AND carbon_cost=$CARBON_COST
  AND iteration=$ITERATION
GROUP BY study_hour;
END
) | mysql $connection_string --column-names=false >> $output_file


# Make nodes for each storage's stock over the day
printf "// Begin storage daily stocks. \n" >> $output_file
max_emissions=$(mysql $connection_string --column-names=false -e "\
SELECT MAX(emissions) FROM daily_storage_emission_stocks \
WHERE fuel_category_id=$FUEL_CAT_ID AND study_date=$STUDY_DATE AND \
  scenario_id=$SCENARIO_ID AND carbon_cost=$CARBON_COST;" )
min_emissions=$(mysql $connection_string --column-names=false -e "\
SELECT MIN(emissions) FROM daily_storage_emission_stocks \
WHERE fuel_category_id=$FUEL_CAT_ID AND study_date=$STUDY_DATE AND \
  scenario_id=$SCENARIO_ID AND carbon_cost=$CARBON_COST;" )
(cat <<END 
SELECT CONCAT(
load_area, '_storage_', study_date, ' [shape="box", fillcolor="0 0 ', round($max_brightness-($brightness_range*(emissions-$min_emissions)/$max_emissions), 3), 
'", label="', load_area, ' Storage\\n', 
if(COALESCE(total_power_stored,0)<1000, concat(round(COALESCE(total_power_stored,0)), ' MW'), concat(round(COALESCE(total_power_stored,0)/1000, 1), ' GW')), ' in\\n',
if(COALESCE(total_power_released,0)<1000, concat(round(COALESCE(total_power_released,0)), ' MW'), concat(round(COALESCE(total_power_released,0)/1000, 1), ' GW')), ' out\\n',
if(emissions<1000, concat(round(emissions), ' t'), concat(round(emissions/1000), ' kt')), '"',
if(total_power_stored>=1000 or emissions >= 1000, ', fontsize=20', ''), '];'
) 
FROM daily_storage_emission_stocks
  JOIN load_areas USING(area_id)
WHERE fuel_category_id=$FUEL_CAT_ID AND study_date=$STUDY_DATE 
  AND scenario_id=$SCENARIO_ID AND carbon_cost=$CARBON_COST
  AND iteration=$ITERATION;
END
) | mysql $connection_string --column-names=false >> $output_file

# For each transmission edge
printf "// Begin transmission dispatch. \n" >> $output_file
max_tx=$(mysql $connection_string --column-names=false -e "\
SELECT MAX(power_sent) FROM _transmission_dispatch JOIN fuel_categories ON(fuel_category = rps_fuel_category) \
WHERE fuel_category_id=$FUEL_CAT_ID AND study_date=$STUDY_DATE AND \
  scenario_id=$SCENARIO_ID AND carbon_cost=$CARBON_COST;" )
min_tx=$(mysql $connection_string --column-names=false -e "\
SELECT MIN(power_sent) FROM _transmission_dispatch JOIN fuel_categories ON(fuel_category = rps_fuel_category) \
WHERE fuel_category_id=$FUEL_CAT_ID AND study_date=$STUDY_DATE AND \
  scenario_id=$SCENARIO_ID AND carbon_cost=$CARBON_COST;" )
min_pen_width=1
max_pen_width=10
(cat <<END 
SELECT CONCAT(
sent.load_area, '_', study_hour, ' -> ', recv.load_area, '_', study_hour,' [penwidth=', round(($max_pen_width-$min_pen_width)*(power_sent-$min_tx)/$max_tx + $min_pen_width, 2), 
', label="', if(power_sent<1000, concat(round(power_sent), ' MW, '), concat(round(power_sent/1000, 1), ' GW, ')), 
if($ITERATION>0,if(gross_emissions * power_sent / gross_power<1000, concat(round(gross_emissions * power_sent / gross_power), ' t'), concat(round(gross_emissions * power_sent / gross_power/1000, 1), ' kt')), ''), '"', 
if(power_sent>=1000, ', fontsize=20', ''), '];'
) 
FROM _transmission_dispatch
  JOIN fuel_categories ON(fuel_category = rps_fuel_category)
  JOIN load_areas sent ON(sent.area_id=send_id)
  JOIN load_areas recv ON(recv.area_id=receive_id)
  LEFT JOIN hourly_la_emission_stocks USING (fuel_category_id, scenario_id, carbon_cost, study_hour)
WHERE fuel_category_id=$FUEL_CAT_ID AND _transmission_dispatch.study_date=$STUDY_DATE 
  AND scenario_id=$SCENARIO_ID AND carbon_cost=$CARBON_COST
  AND send_id=hourly_la_emission_stocks.area_id
  AND iteration=$ITERATION-1;
END
) | mysql $connection_string --column-names=false >> $output_file

# For each storage dispatch
printf "// Begin storage dispatch. \n" >> $output_file
max_power=$(mysql $connection_string --column-names=false -e "\
SELECT MAX(abs(power)) FROM _gen_hourly_summary_fc_la \
WHERE fuel_category_id=$FUEL_CAT_ID AND study_date=$STUDY_DATE AND \
  scenario_id=$SCENARIO_ID AND carbon_cost=$CARBON_COST;" )
min_power=$(mysql $connection_string --column-names=false -e "\
SELECT MIN(abs(power)) FROM _gen_hourly_summary_fc_la \
WHERE fuel_category_id=$FUEL_CAT_ID AND study_date=$STUDY_DATE AND \
  scenario_id=$SCENARIO_ID AND carbon_cost=$CARBON_COST;" )
min_pen_width=1
max_pen_width=10
(cat <<END 
SELECT CONCAT(
  if( power > 0, 
    CONCAT( load_area, '_storage_', study_date, ' -> ', load_area, '_', study_hour ),
    CONCAT( load_area, '_', study_hour, ' -> ', load_area, '_storage_', study_date ) 
  ), ' [penwidth=', round(($max_pen_width-$min_pen_width)*(abs(power)-$min_power)/$max_power + $min_pen_width, 2), 
  ', label="', if(abs(power)<1000, concat(round(abs(power)), ' MW\\n'), concat(round(abs(power)/1000), ' GW\\n')), '"];'
) 
FROM _gen_hourly_summary_fc_la
  JOIN load_areas USING(area_id)
WHERE fuel_category_id=$FUEL_CAT_ID AND study_date=$STUDY_DATE 
  AND scenario_id=$SCENARIO_ID AND carbon_cost=$CARBON_COST
  AND storage = 1
  AND abs(power) > 0;
END
) | mysql $connection_string --column-names=false >> $output_file


printf "\n}\n" >> $output_file

done