#!/bin/bash

exec > >(tee -a "server-stats-$(date '+%F_%H-%M-%S').log") 2>&1

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RESET='\033[0m'
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

separator="================================================================================"

print_header() {
    echo -e "\n${CYAN}${BOLD}$1${RESET}"
    echo "$separator"
}

print_header "Server Stats Run: $(date '+%F %T')"

# Detect environment
OS_NAME=$(uname)
IS_WINDOWS=false
if [[ "$OS_NAME" == MINGW* || "$OS_NAME" == CYGWIN* ]]; then
    IS_WINDOWS=true
fi

# ------------------------ OS Info ------------------------
print_header "OS Info"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo -e "${GREEN}${NAME} ${VERSION}${RESET}"
else
    uname -a
fi

# ------------------------ CPU Uptime ------------------------
read system_uptime idle_time < /proc/uptime 2>/dev/null

if [ -n "$system_uptime" ]; then
    total_seconds=${system_uptime%.*}
    fractional_part=${system_uptime#*.}

    days=$((total_seconds / 86400 ))
    hours=$(((total_seconds % 86400) / 3600 ))
    minutes=$(((total_seconds % 3600) / 60 ))
    seconds=$((total_seconds % 60 ))

    print_header "CPU Uptime"
    [[ $days -gt 0 ]] && echo "$days days"
    [[ $hours -gt 0 ]] && echo "$hours hours"
    [[ $minutes -gt 0 ]] && echo "$minutes minutes"
    [[ $seconds -gt 0 || $fractional_part -ne 0 ]] && echo "$seconds.${fractional_part} seconds"
else
    print_header "CPU Uptime"
    echo "Skipped: Not supported in this environment"
fi

# ------------------------ CPU Usage ------------------------
print_header "🖥️  CPU Usage"

if $IS_WINDOWS || ! command -v top &> /dev/null; then
    echo "Skipped: CPU usage not supported in this environment"
else
    top_output=$(top -bn1)
    cpu_idle=$(echo "$top_output" | grep "Cpu(s)" | sed 's/.*, *\([0-9.]*\)%* id.*/\1/')
    cpu_usage=$(awk -v idle="$cpu_idle" 'BEGIN { printf("%.1f", 100 - idle) }')
    echo -e "Usage         : ${GREEN}${cpu_usage}%${RESET}"
fi

# ------------------------ Memory Usage ------------------------
print_header "🧠 Memory Usage"

read total_memory available_memory <<< $(awk '/MemTotal/ {t=$2} /MemAvailable/ {a=$2} END {print t, a}' /proc/meminfo)
used_memory=$((total_memory - available_memory))

used_memory_percent=$(awk -v u=$used_memory -v t=$total_memory 'BEGIN { printf("%.1f", (u / t) * 100) }')
free_memory_percent=$(awk -v a=$available_memory -v t=$total_memory 'BEGIN { printf("%.1f", (a / t) * 100) }')

# Convert from kB to MB 
total_memory_mb=$(awk -v t=$total_memory 'BEGIN { printf("%.1f", t/1024) }')
used_memory_mb=$(awk -v u=$used_memory 'BEGIN { printf("%.1f", u/1024) }')
available_memory_mb=$(awk -v a=$available_memory 'BEGIN { printf("%.1f", a/1024) }')

printf "Total Memory    : ${YELLOW}%-10s MB${RESET}\n" "$total_memory_mb"
printf "Used Memory     : ${YELLOW}%-10s MB${RESET} (%s%%)\n" "$used_memory_mb" "$used_memory_percent"
printf "Free/Available  : ${YELLOW}%-10s MB${RESET} (%s%%)\n" "$available_memory_mb" "$free_memory_percent"

# ------------------------ Disk Usage ------------------------
print_header "💾 Disk Usage"

if df_output=$(df -h / 2>/dev/null); then
    size=$(echo "$df_output" | awk 'NR==2 {print $2}')
    used=$(echo "$df_output" | awk 'NR==2 {print $3}')
    avail=$(echo "$df_output" | awk 'NR==2 {print $4}')
    percent=$(echo "$df_output" | awk 'NR==2 {print $5}')

    # Extract numeric values for calculations (Linux only)
    if [ "$IS_WINDOWS" = false ]; then
        df_output_raw=$(df / | awk 'NR==2 {print $2, $3, $4}')
        read size_kb used_kb avail_kb <<< "$df_output_raw"

        if [[ "$size_kb" =~ ^[0-9]+$ && "$size_kb" -ne 0 ]]; then
            if command -v bc &> /dev/null; then
                used_pct=$(echo "scale=2; $used_kb * 100 / $size_kb" | bc)
                avail_pct=$(echo "scale=2; $avail_kb * 100 / $size_kb" | bc)
            else
                used_pct=$(( used_kb * 100 / size_kb ))
                avail_pct=$(( avail_kb * 100 / size_kb ))
            fi
        else
            used_pct="N/A"
            avail_pct="N/A"
        fi
    else
        used_pct=$percent
        avail_pct="N/A"
    fi

    printf "Disk Size       : ${YELLOW}%-10s${RESET}\n" "$size"
    printf "Used Space      : ${YELLOW}%-10s${RESET} ($used_pct)\n" "$used"
    printf "Available Space : ${YELLOW}%-10s${RESET} ($avail_pct)\n" "$avail"
else
    echo "Disk info not available"
fi

# ------------------------ Top Processes ------------------------
print_header "🔥 Top 5 Processes by CPU"
if ! $IS_WINDOWS && command -v ps &> /dev/null; then
    ps aux --sort=-%cpu | awk 'NR==1 || NR<=6 { printf "%-10s %-6s %-5s %-5s %s\n", $1, $2, $3, $4, $11 }'
else
    echo "Skipped: Not supported in this environment"
fi

print_header "🧠 Top 5 Processes by Memory"
if ! $IS_WINDOWS && command -v ps &> /dev/null; then
    ps aux --sort=-%mem | awk 'NR==1 || NR<=6 { printf "%-10s %-6s %-5s %-5s %s\n", $1, $2, $3, $4, $11 }'
else
    echo "Skipped: Not supported in this environment"
fi

# ------------------------ Users currently Logged In ------------------------
print_header "Users currently Logged In"
users 2>/dev/null || echo "Not supported"

print_header "More info on Logged In Users"
if ! $IS_WINDOWS && command -v who &> /dev/null; then
    echo "USER     TTY          LOGIN-TIME        FROM"
    who
else
    echo "Skipped: 'who' command not supported in this environment"
fi

# ------------------------ Failed Log In Attempts ------------------------
print_header "🔐 Failed Login Attempts"
if $IS_WINDOWS; then
    echo "Skipped: Login logs not available on Windows"
elif [ -f /var/log/auth.log ]; then
    print_header "Top IPs causing failed logins:"
    grep "Failed password" /var/log/auth.log | awk '{for(i=1;i<=NF;i++){if($i=="from"){print $(i+1)}}}' | sort | uniq -c | sort -nr
    print_header "Logs of Failed Log In Attempts"
    grep -E "Failed|Failure" /var/log/auth.log
elif [ -f /var/log/secure ]; then
    print_header "Top IPs causing failed logins:"
    grep "Failed password" /var/log/secure | awk '{for(i=1;i<=NF;i++){if($i=="from"){print $(i+1)}}}' | sort | uniq -c | sort -nr
    print_header "Logs of Failed Log In Attempts"
    grep -E "Failed|Failure" /var/log/secure
else
    echo "No recognised authentication log file found"
fi
