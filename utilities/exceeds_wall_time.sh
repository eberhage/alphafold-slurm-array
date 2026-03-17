#!/bin/bash
# usage: ./exceeds_wall_time.sh PARTITION MINUTES
# returns: Checks if a given time exceeds the effective walltime limit

slurm_time_to_minutes() {
    local t=$1
    [[ $t =~ UNLIMITED|infinite ]] && echo -1 && return

    local days=0 time_part
    if [[ $t == *-* ]]; then
        days=${t%%-*}
        time_part=${t#*-}
    else
        time_part=$t
    fi

    IFS=: read -r h m s <<<"$time_part"
    echo $(( days*1440 + h*60 + m ))
}

partition=$1
requested_minutes=$2

part_raw=$(scontrol show partition "$partition"  | awk 'match($0,/MaxTime=([^ ]+)/,a){print a[1]}')
part_limit=$(slurm_time_to_minutes "$part_raw")

part_qos=$(scontrol show partition "$partition"  | awk 'match($0,/QoS=([^ ]+)/,a){print a[1]}')
[[ "$part_qos" == "N/A" ]] && part_qos=""

acct=$(sacctmgr -n -P show user "$USER" format=DefaultAccount)
dqos=$(sacctmgr -n -P show assoc user="$USER" account="$acct" partition="$partition" format=DefaultQOS | awk -F'|' '$1!="" {print $1; exit}')

qos_list=$(printf "%s\n%s\n" "$part_qos" "$dqos"  | awk 'NF && $0!="(null)"' | sort -u)

qos_limit=-1

for q in $qos_list; do
    raw=$(sacctmgr -n -P show qos where name="$q" format=MaxWall)
    if [[ -z "$raw" ]]; then
        limit=-1
    else
        limit=$(slurm_time_to_minutes "$raw")
    fi

    if (( limit >= 0 )); then
        if (( qos_limit < 0 || limit < qos_limit )); then
            qos_limit=$limit
        fi
    fi
done

if (( part_limit < 0 )); then
    effective_limit=$qos_limit
elif (( qos_limit < 0 )); then
    effective_limit=$part_limit
else
    effective_limit=$(( part_limit < qos_limit ? part_limit : qos_limit ))
fi

(( effective_limit < 0 )) && exit 1
(( requested_minutes > effective_limit ))