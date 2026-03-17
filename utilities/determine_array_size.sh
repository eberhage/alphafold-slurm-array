#!/bin/bash
# usage: ./determine_array_size.sh PARTITION
# returns: the number of jobs/tasks we can submit safely

set -euo pipefail

partition=$1

max_array_size=$(scontrol show config | awk -F= '/MaxArraySize/ {gsub(/ /,"",$2); print $2}')
max_job_count=$(scontrol show config | awk -F= '/MaxJobCount/ {gsub(/ /,"",$2); print $2}')

if ! [[ "$max_array_size" =~ ^[0-9]+$ && "$max_job_count" =~ ^[0-9]+$ ]]; then
    echo "Error: Could not determine MaxArraySize or MaxJobCount from Slurm config." >&2
    exit 1
fi

acct=$(sacctmgr -n -P show user $USER format=DefaultAccount)
dqos=$(sacctmgr -n -P show assoc user=$USER account=$acct partition="$partition" format=DefaultQOS)

if [[ -n "$dqos" ]]; then
    maxsubmitpu=$(sacctmgr -P -n show qos where name="$dqos" format=MaxSubmitPU)
    max_jobs_limit=$(( max_job_count < maxsubmitpu ? max_job_count : maxsubmitpu ))
else
    max_jobs_limit=$max_job_count
fi

current_jobs_in_queue=$(squeue -h -r -u $USER | wc -l)
available_jobs=$(( max_jobs_limit - current_jobs_in_queue ))
(( available_jobs < 0 )) && available_jobs=0

# apply 50% safety factor
safe_jobs=$(( available_jobs / 2 ))

submit_count=$(( safe_jobs < max_array_size ? safe_jobs : max_array_size ))

echo "$submit_count"