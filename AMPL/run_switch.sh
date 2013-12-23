#!/bin/bash

function print_help {
  echo $0 # The name of this file. 
  cat <<END_HELP
SYNOPSIS
./run_switch.sh --num_workers 5
DESCRIPTION
If run on a cluster, starts SWITCH using the qsub job submission tool.
If run on a workstation or server, starts SWITCH using the bash command line. 
This tool attempts to auto-detect the computational environment. If it can find the "getid" tool used on the citris cluster, then it will assume a cluster environment. Otherwise, it will assume a w

INPUTS
  --num_workers X          The cplex part of the optimization workload will be spread between X simultaneous processes, where each process is working on a different carbon cost scenario. 
  --help                   Print this usage information
  --threads_per_cplex X    Allow CPLEX to use up to X threads for the barrier method. This may increase memory requirements.
OPTIONAL INPUTS FOR A CLUSTER ENVIRONMENT
  --email foo@berkeley.edu Send emails on the job progress to this email
  --jobname foo_bar        Give the job this name
  --runtime 10             Request 10 hours of runtime for the optimization step. Whole numbers only. 
END_HELP
}

# Set the umask to give group read & write permissions to all files & directories made by this script.
umask 0002

# Determine if this is being run in a cluster environment
if [ -z $(which getid) ]; then cluster=0; else cluster=1; fi;

# Determine which queues are available
if [ $cluster -eq 1 ]; then 
  cluster_login_name=$(qstat -q | sed -n -e's/^server: //p')
  case $cluster_login_name in
    psi) cluster_name="psi" ;;
    perceus-citris.banatao.berkeley.edu) cluster_name="citris" ;;
  	*) echo "Unknown cluster. Login node is $cluster_login_name."; exit ;;
  esac
  case $cluster_name in
    psi)
      queue_6hr=psi
      queue_24hr=psi
      queue_72hr=psi
      queue_168hr=psi
      ;;
    citris)
      queue_6hr=short
      queue_24hr=normal
      queue_72hr=normal
      queue_168hr=normal
      ;;
  esac
fi

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
opt_runtime=24
num_workers=1
is_worker=0

# Parse the options
while [ -n "$1" ]; do
case $1 in
  -e | --email)
    email=$2; shift 2 ;;
  -j | --jobname)
    jobname=$2; shift 2 ;;
  -r | --runtime)
    opt_runtime=$2; shift 2 ;;
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
mkdir -p logs
mkdir -p results

# Validate the threads_per_cplex input and write it to the load.run file. Default and maximum value are num_cores
if [ -z "$threads_per_cplex" ]; then 
  threads_per_cplex=$num_cores; 
fi
sed -i".orig" -e 's/^\(option cplex_options.*\)\(threads=[0-9]*\)\([^0-9].*\)$/\1threads='$threads_per_cplex'\3/' "load.run"


# If a jobname wasn't given, use the directory name this process is running in
if [ -z "$jobname" ]; then 
	jobname=$(pwd | sed -e 's|^.*/||'); 
fi

# Set up the .qsub files and submit job requests to the queue if this is operating on a cluster
if [ $cluster == 1 ]; then

	qsub_files="compile.qsub   optimize.qsub   export.qsub	transmission_optimization.qsub	present_day_dispatch.qsub"
	# Process parameter values
	working_directory=$(pwd)
	# If the email wasn't specified, try to guess who gets the email notifications
	if [ -z "$email" ]; then
		case `whoami` in
			jnelson) email="jameshenrynelson@gmail.com" ;;
			siah) email="siah@berkeley.edu" ;;
			amileva) email="amileva@berkeley.edu" ;;
			dsanchez) email="dansanch01@gmail.com" ;; 
		esac
	fi

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
		
		# Update the queue parameter in everything mut the optimize file (we do that one below)
		if [ "$action" != "optimize" ]; then
		  runtime=$(sed -n -e 's/^#PBS -l walltime=\([0-9]*\):.*$/\1/p' $f)
		else
		  runtime=$opt_runtime
		  cputime=$(($opt_runtime * $threads_per_cplex))
      sed -i".orig" -e 's/^#PBS -l walltime=.*$/#PBS -l walltime='$runtime':00:00/' "$f"
      sed -i".orig" -e 's/^#PBS -l cput=.*$/#PBS -l cput='$cputime':00:00/' "$f"
		fi
    # Decide which queue to use
    if [ $runtime -le 6 ]; then
      sed -i".orig" -e 's/^#PBS -q .*$/#PBS -q '"$queue_6hr"'/' "$f"
    elif [ $runtime -le 24 ]; then 
      sed -i".orig" -e 's/^#PBS -q .*$/#PBS -q '"$queue_24hr"'/' "$f"
    elif [ $runtime -le 72 ]; then 
      if [ -n "$queue_72hr" ]; then
        echo "This cluster ($cluster_name) does not support jobs with this much runtime. Try 24 hours or less."
        exit;
      fi
      sed -i".orig" -e 's/^#PBS -q .*$/#PBS -q '"$queue_72hr"'/' "$f"
    elif [ $runtime -le 168 ]; then 
      if [ -n "$queue_168hr" ]; then
        echo "This cluster ($cluster_name) does not support jobs with this much runtime. Try 72 hours or less."
        exit;
      fi
      sed -i".orig" -e 's/^#PBS -q .*$/#PBS -q '"$queue_168hr"'/' "$f"
    else
      echo "This cluster ($cluster_name) does not support jobs with this much runtime."
      exit;
    fi
	done

	# Fill in the OPTIMIZE qsub file
	f=optimize.qsub
	# How many nodes & workers per node.
	sed -i".orig" -e 's/^#PBS -l nodes=.*$/#PBS -l nodes=1:ppn='"$threads_per_cplex"'/' "$f"


	
	echo "Submitting jobs to the scheduler."
	compile_jobid=$(qsub compile.qsub)
	optimize_jobid=$(qsub optimize.qsub -W depend=afterok:$compile_jobid)
	results_jobid=$(qsub export.qsub -W depend=afterok:$optimize_jobid)
	transopt_jobid=$(qsub transmission_optimization.qsub -W depend=afterok:$optimize_jobid)
	present_day_dispatch_jobid=$(qsub present_day_dispatch.qsub)
	echo "Submission successful. Job IDs are:"
	printf "\t compile.qsub:                    $compile_jobid\n"
	printf "\t optimize.qsub:                   $optimize_jobid\n"
	printf "\t export.qsub:                     $results_jobid\n"
	printf "\t transmission_optimization.qsub:  $transopt_jobid\n"
	printf "\t present_day_dispatch.qsub:       $present_day_dispatch_jobid\n"
	
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


# Export results with one copy of AMPL
log_base="logs/ampl_transopt_"$(date +'%m_%d_%H_%M_%S')
printf "Optimizing transmission. Logging results to $log_base...\n"
echo 'include load.run; include transmission_optimization.run;' | ampl 1>$log_base".log"  2>$log_base".error_log" 


# Execute present_day_dispatch with one copy of AMPL
log_base="logs/ampl_present_day_dispatch_"$(date +'%m_%d_%H_%M_%S')
printf "Starting AMPL present_day_dispatch. Logging results to $log_base...\n"
echo 'include load.run; include present_day_dispatch.run;' | ampl 1>$log_base".log"  2>$log_base".error_log" 
