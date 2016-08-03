#!/bin/sh

# To submit this file, use: `sbatch export.slurm`

# Job label
#SBATCH --job-name=AMPL-export
# Account:
#SBATCH --account=fc_switch
# Queue:
#SBATCH --partition=savio
# Wall clock limit:
#SBATCH --time=02:00:00
# Num nodes
#SBATCH --nodes=1
# Tasks per node
#SBATCH --ntasks-per-node=1
# CPU's per task
#SBATCH --cpus-per-task=1
# Email notification
#SBATCH --mail-type=all
##SBATCH --mail-user= siah@berkeley.edu
# Node requirements
#SBATCH --mem-per-cpu=1G
# Log file paths
#SBATCH --output=logs/compile-%j.log
#SBATCH --error=logs/compile-%j.err
# Export all my environment variables to the job.
#SBATCH --export=ALL


# Go to the working directory
cd "$SLURM_SUBMIT_DIR"
# Ensure that logs and results directories exist
mkdir -p logs results

# Export with AMPL
ampl_commands="include load.run; include export.run; exit;"
printf "Starting AMPL compilation on "$(hostname)" with commands:\n\t$ampl_commands\n";
log_base="logs/ampl_export_"$(date +'%m_%d_%H_%M_%S')
echo "$ampl_commands" | ampl 1>$log_base".log"  2>$log_base".error_log" 

ampl_lic return ampl
ampl_lic stop

./summarize_results.py
