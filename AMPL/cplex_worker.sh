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

# Determine if this is being run in a cluster environment
if [ -z $(which getid) ]; then cluster=0; else cluster=1; fi;

# Determine the worker id of this process
if [ -z "$worker_id" ] && [ "$cluster" == 1 ]; then worker_id=$(getid | awk '{print $1}'); fi

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
  printf "About to run cplex. \n\tLogs are ${log_base}_cplex...\n\tcommand is: cplexamp $base_name -AMPL \"$cplex_options\"\n"
  runtime=$((time -p cplexamp $base_name -AMPL "$cplex_options" 1>>$log_base"_cplex.log" 2>>$log_base"_cplex.error_log" )2>&1 | grep real | awk '{print $2}')
  printf "$scenario_id\t$carbon_cost\tcplex_optimize\t"$(date +'%s')"\t$runtime\n" >> "$runtime_path"
done
