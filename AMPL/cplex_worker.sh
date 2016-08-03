#!/bin/bash

function print_help {
  echo $0 # The name of this file. 
  cat <<END_HELP
cplex_worker.sh
SYNOPSIS
  ./cplex_worker.sh --problems "results/sol0_investment_cost results/sol30_investment_cost results/sol60_investment_cost"
INPUTS
	--problems "results/prob1 results/prob2 ..." 
	                         Lists the base filename of the optimization problems
	--cplex_options "key=value key2=value2 ..."
END_HELP
}

function is_process_running {
  pid=$1
  ps -p $pid | wc -l | awk '{print $1-1}'
}

# Set the umask to give group read & write permissions to all files & directories made by this script.
umask 0002

# Default values
runtime_path='results/run_times.txt'
resource_sampling_freq_seconds=30

# Parse the options
while [ -n "$1" ]; do
case $1 in
	--problems)
		problems=$2; shift 2 ;;
	--cplex_options)
	    cplex_options=$2; shift 2 ;;
	-h | --help)
		print_help; exit ;;
	*)
    echo "Unknown option $1"; print_help; exit ;;
esac
done

# Basic error checking
if [ -z "$problems" ]; then echo "ERROR! problems was not specified."; exit; fi

# Gather some other parameters
if [ -z "$cplex_options" ]; then cplex_options=$(cat results/cplex_options); fi
scenario_id=$(grep 'scenario_id' inputs/misc_params.dat | sed 's/[^0-9]//g')

# Solve problems that are associated with this worker id
printf "problems are '$problems'\n";
for base_name in $problems; do
  # Skip this problem if there is an available solution.
  if [ -f $base_name".sol" ]; then continue; fi
  # Set up logs
  log_base="logs/cplex_optimization_"$(date +'%m_%d_%H_%M_%S')
  log="$log_base.log"
  errlog="$log_base.error_log"
  profile="$log_base.profile"
  printf "About to run cplex. \n\tLogs are ${log_base}...\n\tcommand is: cplexamp $base_name -AMPL \"$cplex_options\"\n"
  hostname >$log
  date >>$log
  cp $log $errlog
  # Start cplex and prepare to monitor its resource usage and runtime
  start_time=$(date +%s);
  cplexamp $base_name -AMPL "$cplex_options" 1>> $log 2>> $errlog &
  cplex_pid=$! ;
  ps_headers="$(ps -o vsize,rssize,%mem,%cpu,time,comm -p $cplex_pid | head -1)"
  echo "realtime elapsed_wall_time elapsed_cpu_time recent_cpu_usage $ps_headers" > $profile;
  ps_output="$(ps -o vsize,rssize,%mem,%cpu,time,comm -p $cplex_pid | tail -1)"
  realtime=$(date +%s);
  starttime=$realtime
  elapsedtime=$(($realtime-$starttime))
  last_elapsedtime=$elapsedtime
  cputime=$(echo $ps_output | awk '{print $5}' | sed -e 's/-/*24*3600 + /' -e 's/:/*3600 + /' -e 's/:/*60 + /' | bc )
  last_cputime=$cputime
  cpuusage=0
  while [ $( is_process_running $cplex_pid ) -eq 1 ]; do
    printf "%8d %d %d %.2f %s\n" $realtime $elapsedtime $cputime $cpuusage "$ps_output" >> $profile;
    sleep $resource_sampling_freq_seconds;
    ps_output="$(ps -o vsize,rssize,%mem,%cpu,time,comm -p $cplex_pid | tail -1)"
    last_elapsedtime=$elapsedtime
    last_cputime=$cputime
    realtime=$(date +%s);
    elapsedtime=$(($realtime-$starttime))
    cputime=$(echo $ps_output | awk '{print $5}' | sed -e 's/-/*24*3600 + /' -e 's/:/*3600 + /' -e 's/:/*60 + /' | bc )
    cpuusage=$(echo "scale=2; ($cputime - $last_cputime)/($elapsedtime - $last_elapsedtime); " | bc)
  done;
  end_time=$(date +%s);
  runtime=$(($end_time - $start_time))


  printf "$scenario_id\t0\tcplex_optimize\t"$(date +'%s')"\t$runtime\n" >> "$runtime_path"
done
