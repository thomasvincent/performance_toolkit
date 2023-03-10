#!/usr/bin/env bash

set -eo pipefail

# Set default maximum memory percentage to 65%
: "${MAX_MEM_PERCENT:=65}"

function main {
    local APACHE_SERVER="httpd"

    # Check if Apache is running
    if systemctl is-active "$APACHE_SERVER" > /dev/null 2>&1; then
        echo "Apache is running"
    else
        >&2 echo "Apache is not running. Exiting script"
        exit 1
    fi

    # Get system information
    local mem_total
    mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local cpu_cores
    cpu_cores=$(grep -c ^processor /proc/cpuinfo)

    echo "Analyzing performance before changes:"

    # Measure CPU utilization
    local before_cpu
    before_cpu=$(mpstat | awk '$3 ~ /[0-9.]+/ { print 100 - $3 }')
    echo "CPU utilization: $before_cpu%"

    # Measure average response time
    local before_response_time
    before_response_time=$(tail -n 1000 /var/log/httpd/access_log | awk '{ total += $NF } END { print total/NR }')
    echo "Average response time: $before_response_time ms"

    echo ""

    # Optimize kernel settings for Apache

    # Increase maximum number of open files
    local max_open_files
    max_open_files=$(($mem_total / 8 + $cpu_cores * 1024))
    sysctl -w fs.file-max="$max_open_files"

    # Increase maximum number of connections
    sysctl -w net.core.somaxconn=32768

    # Increase maximum number of memory pages
    sysctl -w vm.nr_hugepages=$((mem_total / 2048))

    # Increase maximum number of threads
    sysctl -w kernel.threads-max=$((cpu_cores * 64))

    # Increase maximum number of processes
    sysctl -w kernel.pid_max=4194304

    # Increase maximum number of inotify watches
    sysctl -w fs.inotify.max_user_watches=1048576

    # Apply changes
    sysctl -p

    echo "Kernel settings optimized for Apache web server"

    # Wait for changes to take effect
    sleep 60

    echo "Analyzing performance after changes:"

    # Measure CPU utilization
    local after_cpu
    after_cpu=$(mpstat | awk '$3 ~ /[0-9.]+/ { print 100 - $3 }')
    echo "CPU utilization: $after_cpu%"

    # Measure average response time
    local after_response_time
    after_response_time=$(tail -n 1000 /var/log/httpd/access_log | awk '{ total += $NF } END { print total/NR }')
    echo "Average response time: $after_response_time ms"

    # Calculate change in CPU utilization
    local cpu_change
    cpu_change=$(echo "($after_cpu-$before_cpu)/$before_cpu*100" | bc -l)
    echo "Change in CPU utilization: $cpu_change%"

    # Calculate change in response time
    local response_time_change
    response_time_change=$(echo "($after_response_time-$before_response_time)/$before_response_time*100" | bc -l)
    echo "Change in response time: $response_time_change%"

    # Check memory usage
    local MAX_MEM_PERCENT=65
    local max_mem
    max_mem=$((mem_total * MAX_MEM_PERCENT / 100))
    local current_mem
    current_mem=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)

    if [ "$current_mem" -lt "$max_mem" ]; then
        >&2 echo "Not enough memory available. Exiting script."
        exit 1
    fi
