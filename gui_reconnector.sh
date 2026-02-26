#!/data/data/com.termux/files/usr/bin/bash

# Roblox Auto-Reconnector (Termux) Core Logic [V2 GUI]
# This script runs locally on the device AFTER installation.

# --- Configuration & State Variables ---
CONFIG_FILE="$HOME/.roblox_reconnector.conf"
GAME_ID=""
IS_RUNNING=0
IS_PAUSED=0
START_TIME=0
ROBLOX_PKG="com.roblox.client"

# --- Utility Functions ---

check_root() {
    if ! su -c 'echo "Root access granted"' >/dev/null 2>&1; then
        echo -e "\e[31mError: Root access is required to run this script. Please grant su permissions.\e[0m"
        sleep 2
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

        printf "\r\e[32mTime we are connected to game [ %s ]\e[0m" "$time_str"
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
    print_msg "\e[36mRoblox is opening...\e[0m"
    su -c "am start -a android.intent.action.VIEW -d \"roblox://placeId=${GAME_ID}\" >/dev/null 2>&1"
    
    sleep 2
    
    if is_roblox_running; then
        print_msg "\e[36mRoblox is opened.\e[0m"
        print_msg "\e[33mWaiting to enter the game...\e[0m"
        sleep 5
        print_msg "\e[32mSuccessfully connected to the game.\e[0m"
        IS_RUNNING=1
        START_TIME=$(date +%s)
    else
        print_msg "\e[31mFailed to open Roblox. Retrying...\e[0m"
        IS_RUNNING=0
    fi
}

# --- Config Management ---
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # Safely source the config file
        source "$CONFIG_FILE"
    fi
}

save_config() {
    echo "LAST_GAME_ID=\"$GAME_ID\"" > "$CONFIG_FILE"
}

# --- GUI Menu ---
show_menu() {
    clear
    echo -e "\e[1;34m==========================================\e[0m"
    echo -e "\e[1;37m      Roblox Termux Auto-Reconnector      \e[0m"
    echo -e "\e[1;34m==========================================\e[0m"
    echo ""
    
    load_config
    
    if [[ -n "$LAST_GAME_ID" ]]; then
        echo -e "  \e[1;32m[1]\e[0m Start Game (Saved ID: \e[1;33m$LAST_GAME_ID\e[0m)"
        echo -e "  \e[1;32m[2]\e[0m Enter New Game ID"
    else
        echo -e "  \e[1;30m[1] Start Game (No User Configuration saved)\e[0m"
        echo -e "  \e[1;32m[2]\e[0m Enter Game ID"
    fi
    echo -e "  \e[1;31m[3]\e[0m Exit Application"
    echo ""
    echo -e "\e[1;34m==========================================\e[0m"
    
    read -p "Select an option (1/2/3): " menu_choice
    
    case $menu_choice in
        1)
            if [[ -n "$LAST_GAME_ID" ]]; then
                GAME_ID="$LAST_GAME_ID"
            else
                echo -e "\e[31mNo saved Game ID found. Please select option 2.\e[0m"
                sleep 2
                show_menu
            fi
            ;;
        2)
            echo ""
            read -p "Enter the new Roblox Game ID (e.g., 95878078212429): " GAME_ID
            if [[ -z "$GAME_ID" ]]; then
                echo -e "\e[31mGame ID cannot be empty.\e[0m"
                sleep 2
                show_menu
            else
                save_config
                echo -e "\e[32mGame ID saved successfully!\e[0m"
                sleep 1
            fi
            ;;
        3)
            echo -e "\e[36mExiting. Goodbye!\e[0m"
            exit 0
            ;;
        *)
            echo -e "\e[31mInvalid option selected.\e[0m"
            sleep 1
            show_menu
            ;;
    esac
}

# --- Main Control Flow ---

check_root
show_menu

clear
echo -e "\e[1;34m======================================\e[0m"
echo -e "\e[1;37m        Monitor is Running...         \e[0m"
echo -e "\e[1;34m======================================\e[0m"
echo -e "Game ID locked: \e[1;33m$GAME_ID\e[0m"
echo -e "Type \e[1;31mStop\e[0m at any time to pause."
echo ""
sleep 2

# Initial launch
launch_game

# Main Monitoring Loop
while true; do
    read -t 1 user_input
    
    if [[ "${user_input,,}" == "stop" ]]; then
        echo ""
        print_msg "\e[1;31mReconnector PAUSED. Roblox auto-reconnect is stopped.\e[0m"
        IS_PAUSED=1
        
        while [[ $IS_PAUSED -eq 1 ]]; do
            read -p "Type 'Resume' to continue or 'Exit' to quit: " pause_input
            if [[ "${pause_input,,}" == "resume" ]]; then
                print_msg "\e[33mResuming auto-reconnector...\e[0m"
                IS_PAUSED=0
                if is_roblox_running; then
                    print_msg "\e[36mRoblox is still running. Resuming tracking.\e[0m"
                else
                    launch_game
                fi
            elif [[ "${pause_input,,}" == "exit" ]]; then
                print_msg "\e[36mExiting Roblox Auto-Reconnector.\e[0m"
                exit 0
            fi
        done
    fi

    if [[ $IS_PAUSED -eq 0 ]]; then
        if is_roblox_running; then
            if [[ $IS_RUNNING -eq 0 ]]; then
                IS_RUNNING=1
                START_TIME=$(date +%s)
                print_msg "\e[32mSuccessfully connected to the game.\e[0m"
            fi
            update_logger
        else
            if [[ $IS_RUNNING -eq 1 ]]; then
                echo ""
                print_msg "\e[31mGame disconnected or closed. Reconnecting...\e[0m"
                IS_RUNNING=0
            fi
            launch_game
        fi
    fi
done
