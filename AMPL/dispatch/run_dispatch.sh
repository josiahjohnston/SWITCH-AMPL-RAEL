#!/bin/bash
# run_dispatch.sh
# SYNOPSIS
# 	./run_dispatch.sh
# DESCRIPTION
# 	Prepares a dispatch run for a cluster 
# OPTIONAL INPUTS
# 	--help                   Print this usage information

# This function assumes that the lines at the top of the file that start with a # and a space or tab 
# comprise the help message. It prints the matching lines with the prefix removed and stops at the first blank line.
# Consequently, there needs to be a blank line separating the documentation of this program from this "help" function
function print_help {
	last_line=$(( $(egrep '^[ \t]*$' -n -m 1 $0 | sed 's/:.*//') - 1 ))
	head -n $last_line $0 | sed -e '/^#[ 	]/ !d' -e 's/^#[ 	]//'
}

# Set the umask to give group read & write permissions to all files & directories made by this script.
umask 0002

# Parse command-line parameters
while [ -n "$1" ]; do
case $1 in
	-h | --help)
		print_help; exit ;;
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
if [ $( hostname | grep "citris" | wc -l ) -gt 0 ]; then
  cluster_name="citris"
  queue_6hr=short
  queue_24hr=normal
  # Citris qsub files don't need the total number of workers, so that part will just be a comment line instead of a PBS command.
  num_workers_and_node_template='## Num workers: %d\n#PBS -l nodes=%d:ppn=%d\n'
elif [ -n "$NERSC_HOST" ]; then 
  cluster_name="$NERSC_HOST"
  queue_6hr=regular
  queue_24hr=regular
  # NERSC clusters don't need the number of nodes, so that part will just be a comment line instead of a PBS command.
  num_workers_and_node_template='#PBS -l mppwidth=%d\n## Num nodes: %d\n#PBS -L mppnppn=%d\n'
else 
  echo "Unknown cluster."
  exit;
fi
# Most clusters don't require special suffixes for specifying job dependencies. Hopper requires @sdb to be added to the end of the job name. This variable is used in the qsub command below.
if [ "$cluster_name" == "hopper" ]; then
  dependency_suffix='@sdb'
else 
  dependency_suffix='' 
fi



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
for f in dispatch_compile.qsub dispatch_optimize.qsub dispatch_recompile.qsub dispatch_reoptimize.qsub dispatch_export.qsub; do
  printf "$f"
  echo '#!/bin/sh' > $f;
  action=$(echo $f | sed -e 's/\.qsub//')
  echo "#PBS -N ${action}_${scenario_id}" >> $f
  if [ -n "$email" ]; then
    echo "#PBS -M $email" >> $f
    echo "#PBS -m bae" >> $f
  fi
  echo "#PBS -o logs/${action}_out" >> $f     
  echo "#PBS -e logs/${action}_err" >> $f
  echo "#PBS -V"                    >> $f
  case "$f" in
    dispatch_compile.qsub | dispatch_recompile.qsub)
      echo "#PBS -q $queue_6hr" >> $f
      echo "#PBS -l walltime=02:00:00" >> $f
      num_workers=2
      printf "$num_workers_and_node_template" $num_workers 1 $num_workers >> $f  # Num workers, Num nodes, Num workers per node
    ;;
    dispatch_export.qsub)
      echo "#PBS -q $queue_6hr" >> $f
      echo "#PBS -l walltime=02:00:00" >> $f
      num_workers=2
      printf "$num_workers_and_node_template" $num_workers 1 $num_workers >> $f  # Num workers, Num nodes, Num workers per node
    ;;
    dispatch_optimize.qsub)
      echo "#PBS -q $queue_24hr" >> $f
      echo "#PBS -l walltime=24:00:00" >> $f
      num_workers=8
      printf "$num_workers_and_node_template" $num_workers 2 4 >> $f  # Num workers, Num nodes, Num workers per node
      echo "threads_per_cplex=2" >> $f
    ;;
    dispatch_reoptimize.qsub)
      echo "#PBS -q $queue_24hr" >> $f
      echo "#PBS -l walltime=24:00:00" >> $f
      num_workers=4
      printf "$num_workers_and_node_template" $num_workers 2 2 >> $f  # Num workers, Num nodes, Num workers per node
      echo "threads_per_cplex=2" >> $f
    ;;
  esac
  echo "NUM_WORKERS=$num_workers" >> $f
  echo 'cd $PBS_O_WORKDIR'          >> $f
  echo "cluster_name=$cluster_name" >> $f
  # Load modules
  case "$cluster_name" in
    citris) echo 'module load ampl-cplex' >> $f ;;
    *) echo '# No extra modules needed' >> $f ;;
  esac

  if [ "$f" != "dispatch_reoptimize.qsub" ]; then
    cat qsub_templates/$f >> $f
  else # The re-optimize qsub file is identical to optimize except for the files that it looks for. 
    sed -e 's/sol\*dispatch.nl/sol*dispatch_and_peakers.nl/' qsub_templates/dispatch_optimize.qsub >> $f
  fi

  if [ -z "$prior_jobid" ]; then
    prior_jobid=$(qsub $f)
  else
    prior_jobid=$(qsub $f -W depend=afterok:$prior_jobid$dependency_suffix)
  fi
  printf "\t$prior_jobid\n"
done
