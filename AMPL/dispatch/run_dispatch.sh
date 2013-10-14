#!/bin/bash

function print_help {
  echo $0 # The name of this file. 
  cat <<END_HELP
SYNOPSIS
	./run_dispatch.sh
DESCRIPTION
	Prepares a dispatch run for a cluster 
OPTIONAL INPUTS
	--help                     Print this usage information
  --single_task_mode | -s    Execute the steps of dispatch as a single task and delete
                             problem files as execution progresses. 
  --multiple_task_mode | -m  Execute the steps of dispatch as a separate tasks
END_HELP
}

# Set the umask to give group read & write permissions to all files & directories made by this script.
umask 0002

# Parse command-line parameters
single_task_mode=1
while [ -n "$1" ]; do
case $1 in
	-h | --help)
		print_help; exit ;;
	-s | --single_task_mode)
		single_task_mode=1; shift 1 ;;
	-m | --multiple_task_mode)
		single_task_mode=0; shift 1 ;;
	*)
    echo "Unknown option $1"; print_help; exit ;;
esac
done


# Determine which cluster this is being run on and set cluster-specific parameters appropriately. 
# Different clusters have different queue names and methods of specifying number of workers and number of nodes.
# The cluster_name and queue name variables are self-explanatory. 
# The num_workers_and_node_template variable is used in a printf statement below to format that data to the target cluster.
# It has three slots for Number of workers, Number of nodes, and Number of workers per node. 
# The NERSC clusters need the number of workers and the number of workers per node, while the Citris cluster needs the number of nodes and the number of workers per node. 
# I'm using all three bits of data in the template so allow cluster-specific templates here and generic logic down below. 
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
  ;;
  citris)
    queue_6hr=short
    queue_24hr=normal
  ;;
  *)
    echo "Unknown cluster."
    exit;
  ;;
esac



mkdir -p logs tmp  # Make working directories if they don't exist
scenario_id=$(cat ../scenario_id.txt) 

# Try to guess who gets the email notifications
if [ -z "$email" ]; then
  case `whoami` in
    jnelson) email="jameshenrynelson@gmail.com" ;;
    siah)    email="siah@berkeley.edu" ;;
    amileva) email="amileva@berkeley.edu" ;;
  esac
fi

# Make a qsub file for each task using custom headers and generic templates
echo "Making qsub files for each task. "
for f in dispatch_compile.qsub dispatch_optimize.qsub dispatch_recompile.qsub dispatch_reoptimize.qsub dispatch_export.qsub dispatch_all.qsub; do  
  outlog="logs/${f}.$(date +'%m_%d_%H_%M_%S').out"
  errlog="logs/${f}.$(date +'%m_%d_%H_%M_%S').err"
  # Create the log files if they don't exist so they will have a
  # chance of inheriting good file permissions from this script. 
  # The if statement prevents multi-task mode log files from unnecessarily cluttering the logs directory
  if [ $single_task_mode -eq 0 ] || [ "$f" = "dispatch_all.qsub" ]; then 
    touch $outlog
    touch $errlog
  fi

  if [ $single_task_mode -eq 0 ]; then 
    printf "$f\t"
  fi
  echo '#!/bin/sh' > $f;
  action=$(echo $f | sed -e 's/\.qsub//')
  echo "#PBS -N ${action}_${scenario_id}" >> $f
  if [ -n "$email" ]; then
    echo "#PBS -M $email" >> $f
    echo "#PBS -m bae" >> $f
  fi
  echo "#PBS -o $outlog" >> $f     
  echo "#PBS -e $errlog" >> $f
  echo "#PBS -V"                    >> $f
  case "$f" in
    dispatch_compile.qsub)
      echo "#PBS -q $queue_24hr" >> $f
      echo "#PBS -l walltime=16:00:00" >> $f
      num_workers=16; num_nodes=2; num_workers_per_node=8;
      printf "#PBS -l nodes=%d:ppn=%d\n" $num_nodes $num_workers_per_node  >> $f
    ;;
    dispatch_recompile.qsub)
      echo "#PBS -q $queue_24hr" >> $f
      echo "#PBS -l walltime=24:00:00" >> $f
      num_workers=16; num_nodes=2; num_workers_per_node=8;
      printf "#PBS -l nodes=%d:ppn=%d\n" $num_nodes $num_workers_per_node  >> $f
    ;;
    dispatch_export.qsub)
      echo "#PBS -q $queue_24hr" >> $f
      echo "#PBS -l walltime=16:00:00" >> $f
      num_workers=16; num_nodes=2; num_workers_per_node=8;
      printf "#PBS -l nodes=%d:ppn=%d\n" $num_nodes $num_workers_per_node >> $f
    ;;
    dispatch_optimize.qsub)
      echo "#PBS -q $queue_24hr" >> $f
      echo "#PBS -l walltime=24:00:00" >> $f
      num_workers=16; num_nodes=2; num_workers_per_node=8;
      printf "#PBS -l nodes=%d:ppn=%d\n" $num_nodes $num_workers_per_node >> $f
      echo "threads_per_cplex=1" >> $f
    ;;
    dispatch_reoptimize.qsub)
      echo "#PBS -q $queue_24hr" >> $f
      echo "#PBS -l walltime=24:00:00" >> $f
      num_workers=16; num_nodes=2; num_workers_per_node=8;
      printf "#PBS -l nodes=%d:ppn=%d\n" $num_nodes $num_workers_per_node >> $f
      echo "threads_per_cplex=1" >> $f
    ;;
    dispatch_all.qsub)
      echo "#PBS -q $queue_6hr" >> $f
      echo "#PBS -l walltime=4:00:00" >> $f
      if [ "$cluster_name" == "psi" ]; then 
        num_workers=8; num_nodes=1; num_workers_per_node=8;
      else
        num_workers=16; num_nodes=2; num_workers_per_node=8;
      fi
      echo "#PBS -l cput="$((4*$num_workers))":00:00" >> $f
      printf "#PBS -l nodes=%d:ppn=%d\n" $num_nodes $num_workers_per_node >> $f
      echo "threads_per_cplex=1" >> $f
    ;;
  esac
  echo "NUM_WORKERS=$num_workers" >> $f
  echo 'cd $PBS_O_WORKDIR'          >> $f
  echo "cluster_name=$cluster_name" >> $f
  # Load modules
  case "$cluster_name" in
    citris) printf 'module load ampl-cplex\nmodule load openmpi\n' >> $f ;;
    *) echo '# No extra modules needed' >> $f ;;
  esac

  if [ "$f" != "dispatch_reoptimize.qsub" ]; then
    cat qsub_templates/$f >> $f
  else # The re-optimize qsub file is identical to optimize except for the files that it looks for. 
    sed -e 's/sol\*dispatch.nl/sol*dispatch_and_peakers.nl/' qsub_templates/dispatch_optimize.qsub >> $f
  fi

  if [ $single_task_mode -eq 0 ] && [ $f != "dispatch_all.qsub" ]; then 
    if [ -z "$prior_jobid" ]; then
      prior_jobid=$(qsub $f)
    else
      prior_jobid=$(qsub $f -W depend=afterok:$prior_jobid)
    fi
    printf "$prior_jobid\n"
  fi
done

if [ $single_task_mode -eq 1 ]; then 
  printf "dispatch_all.qsub\n"
  qsub dispatch_all.qsub
fi
