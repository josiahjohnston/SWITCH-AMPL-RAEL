#!/bin/sh

# To submit this file, use: `sbatch optimize.slurm`

# Job label
#SBATCH --job-name=AMPL-optimize
# Account:
#SBATCH --account=fc_switch
# Queue:
#SBATCH --partition=savio
# Wall clock limit:
#SBATCH --time=24:00:00
# AFAIK SLURM lacks a separate param for cpu time, unlike qsub/torque
# Num nodes
#SBATCH --nodes=1
# Tasks per node
#SBATCH --ntasks-per-node=1
# CPU's per task
#SBATCH --cpus-per-task=8
# Email notification
#SBATCH --mail-type=all
##SBATCH --mail-user= siah@berkeley.edu
# Node RAM requirements
#SBATCH --mem-per-cpu=2G
# Log file paths
#SBATCH --output=logs/compile-%j.log
#SBATCH --error=logs/compile-%j.err
# Export all my environment variables to the job.
#SBATCH --export=ALL

# Go to the working directory
cd "$SLURM_SUBMIT_DIR"
# Ensure that logs and results directories exist
mkdir -p logs results

# Make a list of problems composed from .nl files that don't have accompanying .sol files. 
problems=$(ls results/*nl | sed -e 's/.nl$//' | while read b; do if [ ! -f "$b.sol" ]; then echo $b; fi; done | tr '\n' ' ')
printf "Starting CPLEX optimization\n";
./cplex_worker.sh --problems "$problems"
