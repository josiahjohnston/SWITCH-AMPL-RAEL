#!/bin/bash
# cplex_worker.sh
# SYNOPSIS
#   ./cplex_worker.sh --num_workers W --problems "results/sol0_investment_cost results/sol30_investment_cost results/sol60_investment_cost"
# INPUTS
# 	--problems "results/prob1 results/prob2 ..." 
# 	                         Lists the base filename of the optimization problems that need to be divided among workers
# 	--num_workers W          Specifies the number of worker processes tasked with the given problems
# 	--worker N               Used with is_worker in a non-cluster environment with a fork to indicate the worker id of the child process

# This function assumes that the lines at the top of the file that start with a # and a space or tab 
# comprise the help message. It prints the matching lines with the prefix removed and stops at the first blank line.
# Consequently, there needs to be a blank line separating the documentation of this program from this "help" function
function print_help {
	last_line=$(( $(egrep '^[ \t]*$' -n -m 1 $0 | sed 's/:.*//') - 1 ))
	head -n $last_line $0 | sed -e '/^#[ 	]/ !d' -e 's/^#[ 	]//'
}

function is_process_running {
  pid=$1
  ps -p $pid | wc -l | awk '{print $1-1}'
}

# Set the umask to give group read & write permissions to all files & directories made by this script.
umask 0002

# Default values
runtime_path='results/run_times.txt'
num_workers=1
is_worker=0

# Parse the options
while [ -n "$1" ]; do
case $1 in
  -n | --num_workers)
    num_workers=$2; shift 2 ;;
	--worker)
		worker_id=$2; shift 2 ;;
	--problems)
		problems=$2; shift 2 ;;
	-h | --help)
		print_help; exit ;;
	*)
    echo "Unknown option $1"; print_help; exit ;;
esac
done

# Determine if this is being run in a cluster environment
if [ -z $(which getid) ]; then cluster=0; else cluster=1; fi;

# Determine the worker id of this process in a cluster environment if it wasn't passed in as a command-line argument
if [ -z "$worker_id" ] && [ "$cluster" == 1 ]; then worker_id=$(getid | awk '{print $1}'); fi
# Hack.. If that didn't work, assume this process is the only worker. 
if [ -z "$worker_id" ]; then worker_id=0; num_workers=1; fi

# Basic error checking
if [ -z "$worker_id" ]; then echo "ERROR! worker_id is unspecified."; exit; fi
if [ -z "$num_workers" ]; then echo "ERROR! num_workers was not specified."; exit; fi
if [ -z "$problems" ]; then echo "ERROR! problems was not specified."; exit; fi

# Gather some other parameters
cplex_options=$(cat results/cplex_options)
scenario_id=$(grep 'scenario_id' inputs/misc_params.dat | sed 's/[^0-9]//g')

# Solve problems that are associated with this worker id
prob_number=-1
printf "problems are '$problems'\n";
for base_name in $problems; do
  prob_number=$(($prob_number+1))
  # Skip this problem if there is an available solution.
  if [ -f $base_name".sol" ]; then continue; fi
  # Skip this problem if it doesn't match up with this worker id
  if [ $(( $prob_number % $num_workers )) -ne $worker_id ]; then continue; fi
  # Otherwise, solve this problem
  carbon_cost=$(echo "$base_name" | sed -e 's_^.*[^0-9]\([0-9][0-9]*\)[^/]*$_\1_')
  log_base="logs/cplex_optimization_"$carbon_cost"_"$(date +'%m_%d_%H_%M_%S')
  printf "About to run cplex. \n\tLogs are ${log_base}...\n\tcommand is: cplexamp $base_name -AMPL \"$cplex_options\"\n"
  # Record the date & hostname of the computer this is being run on
  hostname >$log_base".log"
  date >>$log_base".log"
  cat $log_base".log" >$log_base".error_log"
  start_time=$(date +%s);
  cplexamp $base_name -AMPL "$cplex_options" 1>> $log_base".log" 2>> $log_base".error_log" &
  cplex_pid=$! ;
  ps_headers="$(ps -o vsize,rssize,%mem,%cpu,time,comm -p $cplex_pid | head -1)"
  echo "realtime elapsed_wall_time elapsed_cpu_time recent_cpu_usage $ps_headers" > $log_base".profile";
  ps_output="$(ps -o vsize,rssize,%mem,%cpu,time,comm -p $cplex_pid | tail -1)"
  realtime=$(date +%s);
  starttime=$realtime
  elapsedtime=$(($realtime-$starttime))
  last_elapsedtime=$elapsedtime
  cputime=$(echo $ps_output | awk '{print $5}' | sed -e 's/-/*24*3600 + /' -e 's/:/*3600 + /' -e 's/:/*60 + /' | bc )
  last_cputime=$cputime
  cpuusage=0
  while [ $( is_process_running $cplex_pid ) -eq 1 ]; do
    printf "%8d %d %d %.2f %s\n" $realtime $elapsedtime $cputime $cpuusage "$ps_output" >> $log_base".profile";
    sleep 30;
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


  printf "$scenario_id\t$carbon_cost\tcplex_optimize\t"$(date +'%s')"\t$runtime\n" >> "$runtime_path"
done
