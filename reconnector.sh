#!/data/data/com.termux/files/usr/bin/bash

# Roblox Auto-Reconnector (Termux) Core Logic
# This script runs locally on the device AFTER installation.

# --- Configuration & State Variables ---
GAME_ID=""
IS_RUNNING=0
IS_PAUSED=0
START_TIME=0
ROBLOX_PKG="com.roblox.client"

# --- Utility Functions ---

check_root() {
    if ! su -c 'echo "Root access granted"' >/dev/null 2>&1; then
        echo "Error: Root access is required to run this script. Please grant su permissions."
        exit 1
    fi
}

print_msg() {
    printf "\r\033[K%s\n" "$1"
}

update_logger() {
    if [[ $IS_RUNNING -eq 1 && $START_TIME -gt 0 ]]; then
        local current_time=$(date +%s)
        local elapsed=$((current_time - START_TIME))
        local hours=$((elapsed / 3600))
        local minutes=$(((elapsed % 3600) / 60))
        local seconds=$((elapsed % 60))

        local time_str=""
        if [[ $hours -gt 0 ]]; then
            time_str="${hours} hour "
        fi
        if [[ $minutes -gt 0 || $hours -gt 0 ]]; then
            time_str="${time_str}${minutes} mins "
        fi
        time_str="${time_str}${seconds} secs"

        printf "\rTime we are connected to game [ %s ]" "$time_str"
    fi
}

is_roblox_running() {
    local pid=$(su -c "pidof $ROBLOX_PKG" 2>/dev/null)
    if [[ -z "$pid" ]]; then
        return 1
    else
        return 0
    fi
}

launch_game() {
    print_msg "Roblox is opening..."
    su -c "am start -a android.intent.action.VIEW -d \"roblox://placeId=${GAME_ID}\" >/dev/null 2>&1"
    
    sleep 2
    
    if is_roblox_running; then
        print_msg "Roblox is opened."
        print_msg "Waiting to enter the game..."
        sleep 5
        print_msg "Successfully connected to the game."
        IS_RUNNING=1
        START_TIME=$(date +%s)
    else
        print_msg "Failed to open Roblox. Retrying..."
        IS_RUNNING=0
    fi
}

# --- Main Control Flow ---

echo "======================================"
echo "    Roblox Termux Auto-Reconnector    "
echo "======================================"

check_root

read -p "Enter the Roblox Game ID (e.g., 95878078212429): " GAME_ID
if [[ -z "$GAME_ID" ]]; then
    echo "Game ID cannot be empty. Exiting."
    exit 1
fi

echo "Game ID set to: $GAME_ID"
echo "Type 'Stop' at any time to pause the reconnector."
echo "Starting in 3 seconds..."
sleep 3

launch_game

while true; do
    read -t 1 user_input
    
    if [[ "${user_input,,}" == "stop" ]]; then
        echo ""
        print_msg "Reconnector PAUSED. Roblox auto-reconnect is stopped."
        IS_PAUSED=1
        
        while [[ $IS_PAUSED -eq 1 ]]; do
            read -p "Type 'Resume' to continue or 'Exit' to quit: " pause_input
            if [[ "${pause_input,,}" == "resume" ]]; then
                print_msg "Resuming auto-reconnector..."
                IS_PAUSED=0
                if is_roblox_running; then
                    print_msg "Roblox is still running. Resuming tracking."
                else
                    launch_game
                fi
            elif [[ "${pause_input,,}" == "exit" ]]; then
                print_msg "Exiting Roblox Auto-Reconnector."
                exit 0
            fi
        done
    fi

    if [[ $IS_PAUSED -eq 0 ]]; then
        if is_roblox_running; then
            if [[ $IS_RUNNING -eq 0 ]]; then
                IS_RUNNING=1
                START_TIME=$(date +%s)
                print_msg "Successfully connected to the game."
            fi
            update_logger
        else
            if [[ $IS_RUNNING -eq 1 ]]; then
                echo ""
                print_msg "Game disconnected or closed. Reconnecting..."
                IS_RUNNING=0
            fi
            launch_game
        fi
    fi
done
