#!/bin/bash
# run_switch.sh
# SYNOPSIS
# 	./run_switch.sh --num_workers 5
# DESCRIPTION
# 	If run on a cluster, starts SWITCH using the qsub job submission tool.
# 	If run on a workstation or server, starts SWITCH using the bash command line. 
# This tool attempts to auto-detect the computational environment. If it can find the "getid" tool used on the citris cluster, then it will assume a cluster environment. Otherwise, it will assume a workstation environment.
# 
# INPUTS
# 	--num_workers X          The cplex part of the optimization workload will be spread between X simultaneous processes, where each process is working on a different carbon cost scenario. 
# 	--help                   Print this usage information
#		--threads_per_cplex X    Allow CPLEX to use up to X threads for its parallel mode. This will increase the memory requirements by a factor of X.
# OPTIONAL INPUTS FOR A CLUSTER ENVIRONMENT
# 	--workers_per_node Y     Do not start more than Y workers on a node. 
# 	--email foo@berkeley.edu Send emails on the job progress to this email
# 	--jobname foo_bar        Give the job this name
# 	--queue long             Put this in the specified queue. Available queues are express, short, normal and long with maximum runtimes of 30 minutes, 6 hours, 24 hours and 72 hours. 

# This function assumes that the lines at the top of the file that start with a # and a space or tab 
# comprise the help message. It prints the matching lines with the prefix removed and stops at the first blank line.
# Consequently, there needs to be a blank line separating the documentation of this program from this "help" function
function print_help {
	last_line=$(( $(egrep '^[ \t]*$' -n -m 1 $0 | sed 's/:.*//') - 1 ))
	head -n $last_line $0 | sed -e '/^#[ 	]/ !d' -e 's/^#[ 	]//'
}

# Determine if this is being run in a cluster environment
if [ -z $(which getid) ]; then cluster=0; else cluster=1; fi;
# Determine the number of cores available. Different platform require different strategies.
if [ $(uname) == "Linux" ]; then 
	num_cores=$(grep processor /proc/cpuinfo | wc -l | awk '{print $1}')
elif [ $(uname) == "Darwin" ]; then 
	num_cores=$(sysctl hw.ncpu | awk '{print $2}')
else
	echo "Unknown platform "$(uname); exit; 
fi

# Default values
runtime_path='results/run_times.txt'
num_workers=1
workers_per_node=1
is_worker=0
# default number of cores is 3/4 of the total to cap memory usage on the cluster: (|cut -f1 -d".") is a shell script floor function
threads_per_cplex=$(echo - | awk "{ print $num_cores*0.5}" | cut -f1 -d".")

# Parse the options
while [ -n "$1" ]; do
case $1 in
  -n | --num_workers)
    num_workers=$2; shift 2 ;;
  -w | --workers_per_node)
    workers_per_node=$2; shift 2 ;;
  -e | --email)
    email=$2; shift 2 ;;
  -j | --jobname)
    jobname=$2; shift 2 ;;
  -q | --queue)
    queue=$2; shift 2 ;;
	--is_worker)
		is_worker=1; shift ;;
	--worker)
		worker_id=$2; shift 2 ;;
	--problems)
		problems=$2; shift 2 ;;
	--threads_per_cplex)
		threads_per_cplex=$2; shift 2 ;;
	-h | --help)
		print_help; exit ;;
	*)
    echo "Unknown option $1"; print_help; exit ;;
esac
done

# Make directories for logs & results if they don't already exist
[ -d logs ] || mkdir logs
[ -d results ] || mkdir results

# Update the number of threads cplex is allowed to use
[ -n "$threads_per_cplex" ] && sed -i".orig" -e 's/^\(option cplex_options.*\)\(threads=[0-9]*\)\([^0-9].*\)$/\1threads='$threads_per_cplex'\3/' "load.run"

# Set up the .qsub files and submit job requests to the queue if this is operating on a cluster
if [ $cluster == 1 ]; then

	qsub_files="compile.qsub   optimize.qsub   export.qsub	present_day_dispatch.qsub"
	# Process parameter values
	working_directory=$(pwd)
	# Try to guess who gets the email notifications
	if [ -z "$email" ]; then
		case `whoami` in
			jnelson) email="jameshenrynelson@gmail.com" ;;
			siah) email="siah@berkeley.edu" ;;
			amileva) email="amileva@berkeley.edu" ;;
		esac
	fi
	# Translate the number of processes and processes per node into number of nodes
	nodes=$(printf "%.0f" $(echo "scale=1; $num_workers/$workers_per_node" | bc))
	[ $nodes -le 8 ] || nodes=8       # Set the number of nodes to 8 unless it is less than or equal to 8

	# Process each qsub file for boilerplate stuff
	for f in $qsub_files; do
		# Make sure the qsub templates exists and we can write to them
		if [ ! -f "$f" ]; then 
			echo "Expected to find a qsub template file in this directory named $f. Please copy that file to this directory and try again. "; exit; 
		elif [ ! -w "$f" ]; then 
			case `uname` in 
				Linux)  owner=$(stat -c "%U" "$f") ;;
				Darwin) owner=$(stat -f "%Su" "$f") ;;
				*) owner="the owner" ;;
			esac
			echo "Cannot rewrite the qsub template file $f. Ask $owner to change the permissions ('chmod g+w $f' will probably do). "; exit; 
		fi
		action=$(echo $f | sed -e 's/\.qsub//')

		# Update these default parameters in each qsub file.
		[ -n "$jobname" ] && sed -i".orig" -e 's/^#PBS -N .*$/#PBS -N '"$jobname-$action"'/' "$f"
		[ -n "$email" ] && sed -i".orig" -e 's/^#PBS -M .*$/#PBS -M '"$email"'/' "$f"
		sed -i".orig" -e 's|^working_dir=.*$|working_dir="'"$working_directory"'"|' "$f"
	done

	# Fill in the OPTIMIZE qsub file
	f=optimize.qsub
	# How many nodes & workers per node.
	sed -i".orig" -e 's/^#PBS -l nodes=.*$/#PBS -l nodes='"$nodes"':ppn='"$workers_per_node"'/' "$f"
	# Which queue to use. Assume we'll need all of the time the queue can offer
	if [ -n "$queue" ]; then
		case "$queue" in
			express) sed -i".orig" -e 's/^#PBS -l walltime=.*$/#PBS -l walltime=00:30:00/' "$f" ;;
			short)   sed -i".orig" -e 's/^#PBS -l walltime=.*$/#PBS -l walltime=06:00:00/' "$f" ;;
			normal)  sed -i".orig" -e 's/^#PBS -l walltime=.*$/#PBS -l walltime=24:00:00/' "$f" ;;
			long)    sed -i".orig" -e 's/^#PBS -l walltime=.*$/#PBS -l walltime=72:00:00/' "$f" ;;
			dkammen) sed -i".orig" -e 's/^#PBS -l walltime=.*$/#PBS -l walltime=168:00:00/' "$f" ;;
			*) echo "queue option $queue not known. Please read the help message and try again"; print_help; exit ;;
		esac
		sed -i".orig" -e 's/^#PBS -q .*$/#PBS -q '"$queue"'/' "$f"
	fi
	
	echo "Submitting jobs to the scheduler."
	compile_jobid=$(qsub compile.qsub)
	optimize_jobid=$(qsub optimize.qsub -W depend=afterok:$compile_jobid)
	results_jobid=$(qsub export.qsub -W depend=afterok:$optimize_jobid)
	present_day_dispatch_jobid=$(qsub present_day_dispatch.qsub)
	echo "Submission successful. Job IDs are:"
	printf "\t compile.qsub:               $compile_jobid\n"
	printf "\t optimize.qsub:              $optimize_jobid\n"
	printf "\t export.qsub:                $results_jobid\n"
	printf "\t present_day_dispatch.qsub:  $present_day_dispatch_jobid\n"
	
	exit;
fi
# END OF CLUSTER STUFF



# If we've made it here, we aren't in a cluster environment. Execute SWITCH appropriately. 

function cpu_usage() {
	pid=$1
	tmp_path='logs/tmp.txt'
	ps S -o ppid,pid,pcpu,pmem > $tmp_path
	pid_list=$pid
	op=""
	while [ "$pid_list" != "$op" ]; do 
		op="$pid_list"
		pid_list=$(egrep '^'"$pid_list" $tmp_path | awk 'BEGIN {buf="'$pid'";} {if(buf=="") buf=$2; else buf=sprintf("%s|%d",buf,$2)} END{print buf}')
	done
	egrep '^[0-9]* '"$pid_list" $tmp_path | awk '{sum += $3} END{printf "%.2f\n", sum/100}'
	rm $tmp_path
}


# Compile the problems sequentially with one copy of AMPL
log_base="logs/ampl_compilation_"$(date +'%m_%d_%H_%M_%S')
printf "Compiling optimization problems. Logging results to $log_base...\n"
echo 'include load.run; include compile.run;' | ampl 1>$log_base".log"  2>$log_base".error_log" 

# Optimize the problems with N copies of cplex
problems=$(                  # Find problems that lack solutions
  find results -name '*nl' | # Search for files in the results directory with an 'nl' suffix. Pipe the results (if any) to the next step. 
  sed -e 's/.nl$//' |        # Strip the '.nl' suffix off the end of the paths. 
  while read b; do           # Filter the list of base file names. 
    if [ ! -f "$b.sol" ];    # Pass the base file name to the next step if it doesn't have a .sol file. 
    then 
      echo $b; 
    fi; 
  done |                     # Pass whatever made it through the filter to the next step
  tr '\n' ' '                # Replace the line returns with spaces so the list of problems is easier to pass around
) 
if [ -n "$problems" ]; then  # Only start the optimization step if there are problems to solve
  printf "Spawning %d workers for cplex optimization...\n" $num_workers
  log_base="logs/worker_"$(date +'%m_%d_%H_%M_%S')
  pids=''
  printf "Worker pids are: "
  for ((i=0; i<$num_workers; i++)); do
    ./cplex_worker.sh --num_workers $num_workers --worker $i --problems "$problems" 1>$log_base"-$i.log" 2>$log_base"-$i.log" &
    pids[$i]=$!
    printf "%d " ${pids[$i]}
  done
  printf "\n";
  echo "Workers' cpu usage..."
  still_running=$num_workers
  while [ $still_running -gt 0 ]; do
    still_running=0
    status_line=""
    for ((i=0; i<$num_workers; i++)); do
      if [ $(ps -p ${pids[$i]} | wc -l | awk '{print $1}') -gt 1 ]; then
        status[$i]=$(cpu_usage ${pids[$i]})
        still_running=$(($still_running + 1))
      else
        status[$i]=done
      fi
      status_line="$status_line $i: "${status[$i]}
    done
    echo -ne "\r$status_line"
    sleep 2
  done
  printf "\nOptimization done.\n"
else 
  printf "No unsolved problem files found."
fi


# Export results with one copy of AMPL
log_base="logs/ampl_export_"$(date +'%m_%d_%H_%M_%S')
printf "Exporting results from AMPL to text files. Logging results to $log_base...\n"
echo 'include load.run; include export.run;' | ampl 1>$log_base".log"  2>$log_base".error_log" 


# Execute present_day_dispatch with one copy of AMPL
log_base="logs/ampl_present_day_dispatch_"$(date +'%m_%d_%H_%M_%S')
printf "Starting AMPL present_day_dispatch. Logging results to $log_base...\n"
echo 'include load.run; include present_day_dispatch.run;' | ampl 1>$log_base".log"  2>$log_base".error_log" 
