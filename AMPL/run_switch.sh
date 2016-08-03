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

# Guess if this is being run in a cluster environment based on availability of
# a slurm utility for submitting jobs (sbatch).
if [ -z $(which sbatch) ]; then cluster=0; else cluster=1; fi;

# Determine which queues are available
if [ $cluster -eq 1 ]; then 
  # Make an arbitrary default of 8 cores for running cplex.
  num_cores=8

# If this isn't running on a cluster, set the default cores for cplex to the
# number of cpus on this machine.
else
  # Determine the number of cores available. Different platform require different strategies.
  if [ $(uname) == "Linux" ]; then 
    num_cores=$(grep processor /proc/cpuinfo | wc -l | awk '{print $1}')
  elif [ $(uname) == "Darwin" ]; then 
    num_cores=$(sysctl hw.ncpu | awk '{print $2}')
  else
    echo "Unknown platform "$(uname); exit; 
  fi
fi

# Default values
runtime_path='results/run_times.txt'
opt_runtime=24

# Parse the options
while [ -n "$1" ]; do
case $1 in
  -e | --email)
    email=$2; shift 2 ;;
  -j | --jobname)
    jobname=$2; shift 2 ;;
  -r | --runtime)
    opt_runtime=$2; shift 2 ;;
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

# Ensure logs & results directories exist
mkdir -p logs results

# Validate the threads_per_cplex input and write it to the load.run file.
if [ -z "$threads_per_cplex" ]; then 
  threads_per_cplex=$num_cores; 
fi
sed -i".orig" -e 's/^\(option cplex_options.*\)\(threads=[0-9]*\)\([^0-9].*\)$/\1threads='$threads_per_cplex'\3/' "load.run"
rm load.run.orig

# If a jobname wasn't given, use the directory name this process is running in
if [ -z "$jobname" ]; then 
  jobname=$(pwd | sed -e 's|^.*/||'); 
fi

# If this is a cluster, then set up the .slurm files and submit job requests
if [ $cluster == 1 ]; then

  slurm_files="compile.slurm   optimize.slurm   export.slurm"
  # For now, don't bother with transmission optimization or present day dispatch cuz they are buggy
  # transmission_optimization.slurm  present_day_dispatch.slurm

  # If the email wasn't specified, try to look up an email address from /etc/passwd. On the savio cluster, it is part of the comment section:
  # siah:x:40769:501:Josiah Johnston,siah@berkeley.edu:/global/home/users/siah:/bin/bash
  if [ -z "$email" ]; then
    # Use egrep to find the right line, then delete all text up to the comma,
    # then delete all text after the colon.
    email=$(egrep "^$USER" /etc/passwd | sed -e 's/^.*,//' -e 's/:.*$//')
  fi

  # Process each qsub file for boilerplate stuff
  for f in $slurm_files; do
    # Make sure the qsub templates exists and we can write to them
    if [ ! -f "$f" ]; then 
      echo "Expected to find a slurm template file in this directory named $f. Please copy that file to this directory and try again. "
      exit
    elif [ ! -w "$f" ]; then 
      case `uname` in 
        Linux)  owner=$(stat -c "%U" "$f") ;;
        Darwin) owner=$(stat -f "%Su" "$f") ;;
        *) owner="the owner" ;;
      esac
      echo "Cannot rewrite the slurm template file $f. Ask $owner to change the permissions ('chmod g+w $f' will probably do). "; exit; 
    fi
    action=$(echo $f | sed -e 's/\.slurm//')

    # Update default parameters in each qsub file.
    if [ -n "$jobname" ]; then
      sed -i".orig" -e 's/^#SBATCH --job-name=.*$/#SBATCH --job-name='"$jobname-$action"'/' "$f"
    fi
    if [ -n "$email" ]; then
      sed -i".orig" -e 's/^#SBATCH --mail-user=.*$/##SBATCH --mail-user= '"$email"'/' "$f"
    fi
    rm $f.orig
  done

  # Pass the cplex thread count to the optimize slurm file.
  f=optimize.slurm
  sed -i".orig" -e 's/^#SBATCH --cpus-per-task=.*$/#SBATCH --cpus-per-task='"$threads_per_cplex"'/' "$f"
  rm $f.orig

  echo "Submitting jobs to the scheduler."
  # sbatch returns a line like so: "Submitted batch job 798920"
  # Use awk to nab the last column from that line.
  compile_jobid=$(sbatch compile.slurm | awk '{print $NF}')
  optimize_jobid=$(sbatch --dependency=afterok:$compile_jobid optimize.slurm | awk '{print $NF}')
  export_jobid=$(sbatch --dependency=afterok:$optimize_jobid export.slurm | awk '{print $NF}')
  # Disable these until their bugs are fixed.
  #transopt_jobid=$(qsub transmission_optimization.qsub -W depend=afterok:$optimize_jobid)
  #present_day_dispatch_jobid=$(qsub present_day_dispatch.qsub)
  echo "Submission successful. Job IDs are:"
  printf "\t compile.slurm:                    $compile_jobid\n"
  printf "\t optimize.slurm:                   $optimize_jobid\n"
  printf "\t export.slurm:                     $export_jobid\n"
  #printf "\t transmission_optimization.qsub:  $transopt_jobid\n"
  #printf "\t present_day_dispatch.qsub:       $present_day_dispatch_jobid\n"
  
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


# Compile with AMPL
log_base="logs/ampl_compilation_"$(date +'%m_%d_%H_%M_%S')
printf "Compiling optimization problems. Logging results to $log_base...\n"
echo 'include load.run; include compile.run;' | ampl 1>$log_base".log"  2>$log_base".error_log" 

# Optimize with CPLEX
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
resource_sampling_freq_seconds=5
if [ -n "$problems" ]; then  # Only start the optimization step if there are problems to solve
  printf "Starting cplex optimization...\n"
  log_base="logs/cplex_"$(date +'%m_%d_%H_%M_%S')
  ./cplex_worker.sh --problems "$problems" 1>$log_base".log" 2>$log_base".log" &
  pid=$!
  printf "process id is %d\n" $pid
  echo "Cplex cpu usage..."
  still_running=1
  while [ $still_running -gt 0 ]; do
    still_running=0
    if [ $(ps -p $pid | wc -l | awk '{print $1}') -gt 1 ]; then
      statustext=$(cpu_usage $pid)
      still_running=1
    else
      statustext=done
    fi
    echo -ne "\r$statustext"
    sleep $resource_sampling_freq_seconds
  done
  printf "\nOptimization done.\n"
else 
  printf "No unsolved problem files found."
fi


# Export results with AMPL
log_base="logs/ampl_export_"$(date +'%m_%d_%H_%M_%S')
printf "Exporting results from AMPL to text files. Logging results to $log_base...\n"
echo 'include load.run; include export.run;' | ampl 1>$log_base".log"  2>$log_base".error_log" 

# These are buggy, so disable for now.
if [ 1 -eq 0 ]; then 
  # Execute transmission optimization with AMPL
  log_base="logs/ampl_transopt_"$(date +'%m_%d_%H_%M_%S')
  printf "Optimizing transmission. Logging results to $log_base...\n"
  echo 'include load.run; include transmission_optimization.run;' | ampl 1>$log_base".log"  2>$log_base".error_log" 
  
  # Execute present_day_dispatch with AMPL
  log_base="logs/ampl_present_day_dispatch_"$(date +'%m_%d_%H_%M_%S')
  printf "Starting AMPL present_day_dispatch. Logging results to $log_base...\n"
  echo 'include load.run; include present_day_dispatch.run;' | ampl 1>$log_base".log"  2>$log_base".error_log" 
fi