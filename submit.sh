#!/bin/bash

#- Job parameters

# (TODO)
# Please modify job name

#SBATCH -J test              # The job name
#SBATCH -o ret-%j.out        # Write the standard output to file named 'ret-<job_number>.out'
#SBATCH -e ret-%j.err        # Write the standard error to file named 'ret-<job_number>.err'


#- Resources

# (TODO)
# Please modify your requirements

#SBATCH -p partion               # Submit to 'partion' Partitiion
#SBATCH -t 0-12:00:00                # Run for a maximum time of 0 days, 12 hours, 00 mins, 00 secs
#SBATCH --nodes=1                    # Request N nodes
#SBATCH --gres=gpu:1                 # Request M GPU per node
#SBATCH --gres-flags=enforce-binding # CPU-GPU Affinity
#SBATCH --qos=gpu-normal             # Request QOS Type

###
### The system will alloc 8 or 16 cores per gpu by default.
### If you need more or less, use following:
### #SBATCH --cpus-per-task=K            # Request K cores
###
### 
### Without specifying the constraint, any available nodes that meet the requirement will be allocated
### You can specify the characteristics of the compute nodes, and even the names of the compute nodes
###
### #SBATCH --nodelist=a1          # Request a specific list of hosts 
### #SBATCH --constraint="A100"      # Request GPU Type: A30 or A100_40GB
###

#- Log information

echo "Job start at $(date "+%Y-%m-%d %H:%M:%S")"
echo "Job run at:"
echo "$(hostnamectl)"
echo "$(df -h | grep -v tmpfs)"

#- Important settings!!!
# 1. Prevents RDMA resource exhaustion errors:
ulimit -l unlimited
# 2. Prevents virtual memory exhaustion errors, which are critical
#    when loading Large Language Models (LLMs):
ulimit -v unlimited
# 3. Increases the maximum number of open file descriptors to avoid
#    issues with too many concurrent connections or file accesses:
ulimit -n 65535
# 4. Raises the maximum number of user processes to support
#    large-scale parallel workloads:
ulimit -u 4125556

echo $(module list)              # list modules loaded
echo $(which gcc)
echo $(which python)
echo $(which python3)

#- Other

cluster-quota                    # nas quota

nvidia-smi --format=csv --query-gpu=name,driver_version,power.limit # gpu info

#- WARNING! DO NOT MODIFY your CUDA_VISIBLE_DEVICES
#- in `.bashrc`, `env.sh`, or your job script
echo "Using GPU(s) ${CUDA_VISIBLE_DEVICES}"                         # which GPUs
#- The CUDA_VISIBLE_DEVICES variable is assigned and specified by SLURM
echo "This job is assigned the following resources by SLURM:"
scontrol show jobid $SLURM_JOB_ID -dd | awk '/IDX/ {print $2, $4}'

##- Monitor
# The script continues executing other tasks while the following command will execute after a while
module load slurm-tools/v1.0
(sleep 3h && slurm-gpu-atop-log-stats $SLURM_JOB_ID $CUDA_VISIBLE_DEVICES) &
echo "Main program continues to run. Monitoring information will be exported after three hours."

#- Main program execution

##- Job step TODO
uv run train.py
# Insert your main job operation. 
# This can include running other scripts, executing Python programs, C++ binaries, or any relevant task.
# [Example: python my_script.py or ./my_program]

#- End
slurm-gpu-atop-log-stats $SLURM_JOB_ID $CUDA_VISIBLE_DEVICES
echo "Job end at $(date "+%Y-%m-%d %H:%M:%S")"
# This will overwrite any existing atop logs from previous runs.
# WARNING: If your program times out or is terminated by scancel,
#          the above script part might not execute correctly.
