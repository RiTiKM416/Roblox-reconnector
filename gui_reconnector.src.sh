#!/data/data/com.termux/files/usr/bin/bash

# Roblox Auto-Reconnector (Termux) Core Logic [V2 GUI]
# This script runs locally on the device AFTER installation.

# --- Configuration & State Variables ---
CONFIG_FILE="$HOME/.roblox_reconnector.conf"
GAME_ID=""
PLATOBOOST_KEY=""
DEVICE_ID=""
PROJECT_ID="21504"
DISCORD_LINK="https://discord.gg/ZFjE9yqUNy"
IS_RUNNING=0
IS_PAUSED=0
START_TIME=0
LAST_LAUNCH_TIME=0
ROBLOX_PKG="com.roblox.client"

# --- Utility Functions ---

check_root() {
    if ! su -c 'echo "Root access granted"' >/dev/null 2>&1; then
        echo -e "\e[31mError: Root access is required to run this script. Please grant su permissions.\e[0m"
        sleep 2
        exit 1
    fi
}

verify_platoboost_key() {
    clear
    echo -e "\e[1;36mVerifying Auth Key...\e[0m"
    
    if [[ -z "$PLATOBOOST_KEY" ]]; then
        echo -e "\e[31mNo authentication key found in config.\e[0m"
        echo -e "\e[33mGet your daily key on our Discord: \e[1;32m$DISCORD_LINK\e[0m"
        echo -e "\e[36m(Go to #get-key channel and type \e[1;37m/getkey\e[36m)\e[0m"
        echo ""
        read -p "Enter your Auth Key: " PLATOBOOST_KEY
    fi
    
    # Platorelay V3 Verification Endpoint - Hidden HWID bind
    RESPONSE=$(curl -s "https://api.platoboost.net/public/whitelist/$PROJECT_ID?identifier=$DEVICE_ID&key=$PLATOBOOST_KEY")
    
    if echo "$RESPONSE" | grep -qi "true"; then
        echo -e "\e[32mKey is valid and attached specifically to your Device! Proceeding...\e[0m"
        # Save it back to ensure it's stored
        save_config
        sleep 1
    else
        echo -e "\e[31mInvalid or expired key.\e[0m"
        echo -e "\e[33mGenerate a new key here: \e[1;32m$DISCORD_LINK\e[0m"
        echo ""
        read -p "Enter your new Auth Key: " PLATOBOOST_KEY
        verify_platoboost_key # Recurse until valid
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

        printf "\r\e[32mTime we are connected to game [ %s ] | Current Game ID: \e[1;33m%s\e[0m" "$time_str" "$GAME_ID"
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

# Function to check if the Google Sign-in window has stolen focus
is_google_signin_focused() {
    # We check the currently focused window using dumpsys
    local focused_window=$(su -c "dumpsys window displays | grep -E 'mCurrentFocus|mFocusedApp'")
    
    # If the focused window belongs to Google Play Services (gms) or an account picker, return 0 (true)
    if echo "$focused_window" | grep -qiE "com.google.android.gms|accounts.AccountChecker|SignInActivity"; then
        return 0
    else
        return 1
    fi
}

# Function to check if Roblox dropped back to the Main Menu (Game crashed, but app is open)
is_roblox_in_main_menu() {
    local pid=$(su -c "pidof $ROBLOX_PKG" 2>/dev/null)
    if [[ -z "$pid" ]]; then
        return 1 # If it's closed entirely, the running check will catch it
    fi
    
    # Grace period: Wait 45 seconds after launch before assuming the game has crashed
    # Roblox takes a long time to process the deep-link and load the 3D surface
    local current_time=$(date +%s)
    if [[ $((current_time - LAST_LAUNCH_TIME)) -lt 45 ]]; then
        return 1 # Assume it's still loading safely
    fi
    
    # Check if the focused window is the React Main Menu instead of a 3D Game Surface
    local focused_window=$(su -c "dumpsys window displays | grep -E 'mCurrentFocus|mFocusedApp'")
    
    # If the focus is explicitly the Roblox React Home/Menu UI, it means we dropped out of the game
    if echo "$focused_window" | grep -qiE "com.roblox.client/(.*ActivityReact.*|.*MainActivity.*)"; then
        return 0 # True, we are stuck on the main menu
    else
        return 1 # False, we are presumably in-game
    fi
}

launch_game() {
    print_msg "\e[33mEnsuring Roblox is closed before launch...\e[0m"
    su -c "am force-stop $ROBLOX_PKG"
    sleep 3

    print_msg "\e[36mRoblox is opening...\e[0m"
    su -c "am start -a android.intent.action.VIEW -d \"roblox://placeId=${GAME_ID}\" >/dev/null 2>&1"
    
    sleep 4
    
    if is_roblox_running; then
        print_msg "\e[36mRoblox is opened.\e[0m"
        print_msg "\e[33mWaiting to enter the game (45s grace period)...\e[0m"
        sleep 3
        
        # Check if Google caught the intent and threw a sign-in wall
        if is_google_signin_focused; then
            echo ""
            print_msg "\e[35m[!] Google window has been detected.\e[0m"
            print_msg "\e[33mDismissing Google Sign-In prompt...\e[0m"
            # Simulate pressing the Android 'Back' button to close the popup
            su -c "input keyevent 4"
            sleep 2
        fi
        
        print_msg "\e[32mSuccessfully connected to the game.\e[0m"
        IS_RUNNING=1
        START_TIME=$(date +%s)
        LAST_LAUNCH_TIME=$(date +%s)
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
        if [[ -n "$GAME_ID" ]]; then
            echo -e "\e[32mLoaded saved Game ID: $GAME_ID\e[0m"
        fi
        if [[ -n "$PLATOBOOST_KEY" ]]; then
            echo -e "\e[32mLoaded saved Auth Key\e[0m"
        fi
    fi
    
    # Generate HWID if missing
    if [[ -z "$DEVICE_ID" ]]; then
        DEVICE_ID="DEV-$(cat /proc/sys/kernel/random/uuid | cut -c 1-8 | tr 'a-z' 'A-Z')"
        save_config
    fi
    echo -e "\e[32mDevice HWID: $DEVICE_ID\e[0m"
}

save_config() {
    echo "GAME_ID=\"$GAME_ID\"" > "$CONFIG_FILE"
    echo "PLATOBOOST_KEY=\"$PLATOBOOST_KEY\"" >> "$CONFIG_FILE"
    echo "DEVICE_ID=\"$DEVICE_ID\"" >> "$CONFIG_FILE"
}

# --- GUI Menu ---
show_menu() {
    clear
    echo -e "\e[1;34m==========================================\e[0m"
    echo -e "\e[1;37m      Roblox Termux Auto-Reconnector      \e[0m"
    echo -e "\e[1;34m==========================================\e[0m"
    echo -e "  \e[36mPremium Validation Active (Platoboost)\e[0m"
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
load_config
verify_platoboost_key
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
LOOP_COUNTER=0
while true; do
    read -t 1 user_input
    LOOP_COUNTER=$((LOOP_COUNTER + 1))
    
    if [[ "${user_input,,}" == "stop" ]]; then
        echo ""
        print_msg "\e[1;31mReconnector PAUSED. Roblox auto-reconnect is stopped.\e[0m"
        IS_PAUSED=1
        
        while [[ $IS_PAUSED -eq 1 ]]; do
            read -p "Type 'Resume' to continue, 'Menu' for main screen, or 'Exit' to quit: " pause_input
            if [[ "${pause_input,,}" == "resume" ]]; then
                print_msg "\e[33mResuming auto-reconnector...\e[0m"
                IS_PAUSED=0
                if is_roblox_running; then
                    print_msg "\e[36mRoblox is still running. Resuming tracking.\e[0m"
                else
                    launch_game
                fi
            elif [[ "${pause_input,,}" == "menu" ]]; then
                print_msg "\e[36mReturning to Main Menu...\e[0m"
                IS_PAUSED=0
                IS_RUNNING=0
                
                show_menu
                
                # Redraw the monitor UI after returning from the menu
                clear
                echo -e "\e[1;34m======================================\e[0m"
                echo -e "\e[1;37m        Monitor is Running...         \e[0m"
                echo -e "\e[1;34m======================================\e[0m"
                echo -e "Game ID locked: \e[1;33m$GAME_ID\e[0m"
                echo -e "Type \e[1;31mStop\e[0m at any time to pause."
                echo ""
                sleep 2
                
                launch_game
                break
            elif [[ "${pause_input,,}" == "exit" ]]; then
                print_msg "\e[36mExiting Roblox Auto-Reconnector.\e[0m"
                exit 0
            fi
        done
    fi

    if [[ $IS_PAUSED -eq 0 ]]; then
        # Update timer display every second
        update_logger
        
        # Every 5 seconds, poll process and root checks (prevents Termux crashing from overload)
        if (( LOOP_COUNTER % 5 == 0 )); then
            if is_roblox_running; then
                if [[ $IS_RUNNING -eq 0 ]]; then
                    IS_RUNNING=1
                    START_TIME=$(date +%s)
                    LAST_LAUNCH_TIME=$(date +%s)
                    print_msg "\e[32mSuccessfully connected to the game.\e[0m"
                fi
            else
                if [[ $IS_RUNNING -eq 1 ]]; then
                    echo ""
                    print_msg "\e[31mGame disconnected or closed. Reconnecting...\e[0m"
                    IS_RUNNING=0
                fi
                launch_game
                continue
            fi
            
            # Check if the game crashed but the Roblox app remained open (stuck on Main Menu)
            if [[ $IS_RUNNING -eq 1 ]]; then
                if is_roblox_in_main_menu; then
                    echo ""
                    print_msg "\e[31m[!] Roblox dropped to the Main Menu (Game Crash detected).\e[0m"
                    print_msg "\e[33mReconnecting to Game...\e[0m"
                    
                    IS_RUNNING=0
                    launch_game
                    continue
                fi
            fi
            
            # Continuous background check for Google Sign-in popups
            if [[ $IS_RUNNING -eq 1 ]]; then
                if is_google_signin_focused; then
                    echo ""
                    print_msg "\e[35m[!] Google window has been detected.\e[0m"
                    print_msg "\e[33mDismissing Google Sign-In prompt...\e[0m"
                    su -c "input keyevent 4"
                fi
            fi
            
        fi # End 5-second interval wrapper
    fi
done
