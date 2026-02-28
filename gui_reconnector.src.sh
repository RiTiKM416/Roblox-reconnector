#!/data/data/com.termux/files/usr/bin/bash

# Roblox Auto-Reconnector (Termux) Core Logic [V2 GUI]
# This script runs locally on the device AFTER installation.

# --- Configuration & State Variables ---
CONFIG_DIR="$HOME/.termux_reconnector/configs"
CURRENT_CONFIG=""
GAME_ID=""
PLATOBOOST_KEY=""
DEVICE_ID=""
PROJECT_ID="21504"
DISCORD_LINK="https://discord.gg/ZFjE9yqUNy"
IS_RUNNING=0
IS_PAUSED=0
START_TIME=0
LAST_LAUNCH_TIME=0
# Arrays and specific tracking variables
TARGET_PACKAGES=()
TARGET_WEBHOOK=""
INTENTIONAL_CRASH_TIMER=0
LAST_INTENTIONAL_CRASH=0
LAST_WEBHOOK_TIME=0
TOTAL_CRASHES=0
TOTAL_GOOGLE_POPUPS=0

mkdir -p "$CONFIG_DIR"

# --- Utility Functions ---

# Colors using tput if available, fall back to ANSI
if command -v tput >/dev/null 2>&1; then
  BOLD=$(tput bold)
  NORMAL=$(tput sgr0)
  RED=$(tput setaf 1)
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  BLUE=$(tput setaf 4)
  MAG=$(tput setaf 5)
  CYAN=$(tput setaf 6)
  GRAY=$(tput setaf 7)
else
  BOLD='\e[1m'
  NORMAL='\e[0m'
  RED='\e[31m'
  GREEN='\e[32m'
  YELLOW='\e[33m'
  BLUE='\e[34m'
  MAG='\e[35m'
  CYAN='\e[36m'
  GRAY='\e[37m'
fi

box() {
  local s="${1}" w=${2:-60}
  printf "%s\n" "${MAG}┌$(printf '─%.0s' $(seq 1 $((w-2))))┐${NORMAL}"
  printf "%s\n" "${MAG}│${NORMAL} $(printf '%-'$((w-4))'s' "$s") ${MAG}│${NORMAL}"
  printf "%s\n" "${MAG}└$(printf '─%.0s' $(seq 1 $((w-2))))┘${NORMAL}"
}

show_active_monitor() {
  clear
  echo -e "${GRAY}------------------ TERMUX RECONNECTOR - SYSTEM ACTIVE -------------------${NORMAL}\n"
  
  echo -e "${MAG}  ____       _     _             ${NORMAL}"
  echo -e "${MAG} |  _ \ ___ | |__ | | _____  __  ${NORMAL}"
  echo -e "${BLUE} | |_) / _ \| '_ \| |/ _ \ \/ /  ${NORMAL}"
  echo -e "${CYAN} |  _ < (_) | |_) | | (_) >  <   ${NORMAL}"
  echo -e "${CYAN} |_| \_\___/|_.__/|_|\___/_/\_\  ${NORMAL}\n"
  
  echo -e "${BOLD}      S Y S T E M   A C T I V E ${NORMAL}"
  echo -e "${GRAY}==========================================${NORMAL}\n"
  
  echo -e "Game ID locked: ${CYAN}${GAME_ID:-none}${NORMAL}\n"
  echo -e "Type '${RED}Stop${NORMAL}' at any time to pause the monitor.\n"
  echo -e "${GRAY}$(date) — Press Ctrl+C to quit monitor.${NORMAL}\n"
  echo -e "${GRAY}==========================================${NORMAL}\n"
}

show_progress() {
    local message="$1"
    local steps=25
    local delay=0.1
    
    echo -en "\e[1;36m$message\e[0m  "
    echo -en "\e[1;30m[\e[0m"
    for ((i=1; i<=steps; i++)); do
        echo -en "\e[1;32m#\e[0m"
        sleep "$delay"
    done
    echo -e "\e[1;30m]\e[0m \e[1;32mOK\e[0m"
}

check_root() {
    if ! su -c 'echo "Root access granted"' >/dev/null 2>&1; then
        echo -e "\e[31mError: Root access is required to run this script. Please grant su permissions.\e[0m"
        sleep 2
        exit 1
    fi
}

verify_platoboost_key() {
    clear
    box "TERMUX RECONNECTOR KEY AUTH" 76
    
    local needs_new_key=0

    if [[ -n "$PLATOBOOST_KEY" ]]; then
        if [[ "$KEY_EXPIRATION" == "LIFETIME" ]]; then
            echo -e "\e[32m[+] Cached Lifetime Admin Key found.\e[0m"
        elif [[ -n "$KEY_EXPIRATION" ]]; then
            local current_time=$(date +%s)
            local remaining=$((KEY_EXPIRATION - current_time))
            
            if [[ $remaining -le 0 ]]; then
                echo -e "\e[31m[-] Saved key has expired (00h 00m remaining).\e[0m"
                needs_new_key=1
                PLATOBOOST_KEY=""
            else
                local rem_d=$((remaining / 86400))
                local rem_h=$(((remaining % 86400) / 3600))
                local rem_m=$(((remaining % 3600) / 60))
                
                if [[ $rem_d -gt 0 ]]; then
                    printf "\e[32m[+] Cached Premium Key found! Time remaining: \e[1;33m%02dd %02dh %02dm\e[0m\n" $rem_d $rem_h $rem_m
                else
                    printf "\e[32m[+] Cached Daily Key found! Time remaining: \e[1;33m%02dh %02dm\e[0m\n" $rem_h $rem_m
                fi
            fi
        else
            needs_new_key=1
        fi
    else
        needs_new_key=1
    fi

    if [[ $needs_new_key -eq 1 ]]; then
        echo -e "\e[31mNo valid authentication key found.\e[0m"
        echo -e "\e[33mGet your daily key on our Discord: \e[1;32m$DISCORD_LINK\e[0m"
        echo -e "\e[36m( Go to the \e[33m#get-key\e[36m channel and get a Valid Access key. )\e[0m"
        echo ""
        read -p "Enter your Access Key : " PLATOBOOST_KEY
    fi
    
    show_progress "Authenticating Device HWID..."
    
    # Check for direct Instant Admin Key bypass
    if [[ "$PLATOBOOST_KEY" == ADMIN_GEN_* ]]; then
        echo -e "\e[32mInstant Admin Key Provider recognized! Bypassing link generation...\e[0m"
        RESPONSE="true"
    else
        # Platorelay V3 Verification Endpoint - Hidden HWID bind
        RESPONSE=$(curl -s "https://api.platoboost.net/public/whitelist/$PROJECT_ID?identifier=$DEVICE_ID&key=$PLATOBOOST_KEY")
    fi
    
    if echo "$RESPONSE" | grep -qi "true"; then
        echo -e "\e[32mKey is valid and attached specifically to your Device! Proceeding...\e[0m"
        
        # Determine and set Expiration if it is a new valid key that doesn't have an expiration yet
        if [[ "$PLATOBOOST_KEY" == ADMIN_GEN_* ]]; then
            KEY_EXPIRATION="LIFETIME"
        elif [[ "$PLATOBOOST_KEY" == PREMIUM_KEY_* && -z "$KEY_EXPIRATION" ]]; then
            # 30 Days (2,592,000 Seconds)
            KEY_EXPIRATION=$(( $(date +%s) + 2592000 ))
        elif [[ -z "$KEY_EXPIRATION" || $needs_new_key -eq 1 ]]; then
            # 24 Hours (86,400 Seconds)
            KEY_EXPIRATION=$(( $(date +%s) + 86400 ))
        fi
        
        save_hwid
        
        # Backup Updater Sync
        if [[ -n "$WEBHOOK_URL" ]]; then
            local secret="RECONNECTOR_V1_SECRET_998877"
            local payload="{\"device_id\":\"$DEVICE_ID\",\"key\":\"$PLATOBOOST_KEY\",\"discord_id\":\"$DISCORD_ID\"}"
            local signature=$(echo -n "$payload" | openssl dgst -sha256 -hmac "$secret" -binary | base64)
            
            curl -s "$WEBHOOK_URL/api/backup/update" \
                 -X POST -H "Content-Type: application/json" \
                 -H "X-Signature: $signature" \
                 -d "$payload" > /dev/null &
        fi
        
        # If CURRENT_CONFIG is already populated, resave it. Otherwise, it will save when they reach the menu.
        if [[ -n "$CURRENT_CONFIG" ]]; then save_config; fi
        sleep 1
    else
        echo -e "\e[31mInvalid or expired key.\e[0m"
        echo -e "\e[33mGenerate a new key here: \e[1;32m$DISCORD_LINK\e[0m"
        echo ""
        KEY_EXPIRATION=""
        read -p "Enter your new Access Key : " PLATOBOOST_KEY
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
    # Check if ANY of the target packages are running
    for pkg in "${TARGET_PACKAGES[@]}"; do
        local pid=$(su -c "pidof $pkg" 2>/dev/null)
        if [[ -n "$pid" ]]; then
            return 0 # True, at least one is running
        fi
    done
    return 1 # False, none are running
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
    # Check each package individually
    for pkg in "${TARGET_PACKAGES[@]}"; do
        local pid=$(su -c "pidof $pkg" 2>/dev/null)
        if [[ -z "$pid" ]]; then
            continue # If this specific one is completely closed, skip to next package
        fi
        
        # Grace period: Wait 45 seconds after launch before assuming the game has crashed
        local current_time=$(date +%s)
        if [[ $((current_time - LAST_LAUNCH_TIME)) -lt 45 ]]; then
            return 1 # Assume it's still loading safely
        fi
        
        # Check if the focused window is the React Main Menu instead of a 3D Game Surface
        local focused_window=$(su -c "dumpsys window displays | grep -E 'mCurrentFocus|mFocusedApp'")
        
        # If the focus is explicitly the Roblox React Home/Menu UI, it means we dropped out of the game
        if echo "$focused_window" | grep -qiE "$pkg/(.*ActivityReact.*|.*MainActivity.*)"; then
            return 0 # True, we are stuck on the main menu
        fi
    done
    
    return 1 # False, none are stuck on the menu
}

launch_game() {
    print_msg "\e[33mEnsuring Roblox packages are closed before launch...\e[0m"
    for pkg in "${TARGET_PACKAGES[@]}"; do
        su -c "am force-stop $pkg"
    done
    sleep 3

    for pkg in "${TARGET_PACKAGES[@]}"; do
        su -c "am start -a android.intent.action.VIEW -d \"roblox://placeId=${GAME_ID}\" $pkg >/dev/null 2>&1"
    done
    
    show_progress "Injecting Roblox Memory Space..."
    sleep 1
    
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
        RETRY_COUNT=0
        START_TIME=$(date +%s)
        LAST_LAUNCH_TIME=$(date +%s)
    else
        IS_RUNNING=0
        if [[ -z "$RETRY_COUNT" ]]; then RETRY_COUNT=0; fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        
        if [[ $RETRY_COUNT -ge 6 ]]; then
            echo ""
            print_msg "\e[31m[CRITICAL FAILURE] Roblox failed to launch 6 times consecutively.\e[0m"
            print_msg "\e[33mPausing auto-reconnector to prevent CPU thermal overload.\e[0m"
            print_msg "\e[36mType 'resume' if you want to force try again.\e[0m"
            IS_PAUSED=1
        else
            local backoff=$(( (2 ** RETRY_COUNT) * 5 ))
            print_msg "\e[31mProcess drop detected. Thermal Backoff: Retrying ($RETRY_COUNT/6) in $backoff seconds...\e[0m"
            sleep $backoff
        fi
    fi
}

# --- Device HWID Management ---
load_hwid() {
    # We store the global HWID and Platoboost key centrally since they apply to the whole device, not specific game configs.
    local auth_file="$HOME/.termux_reconnector_auth"
    if [[ -f "$auth_file" ]]; then
        source "$auth_file"
    fi
    
    if [[ -z "$DEVICE_ID" ]]; then
        DEVICE_ID="DEV-$(cat /proc/sys/kernel/random/uuid | cut -c 1-8 | tr 'a-z' 'A-Z')"
        echo "DEVICE_ID=\"$DEVICE_ID\"" > "$auth_file"
    fi
    echo -e "\e[32mDevice HWID: $DEVICE_ID\e[0m"
}

save_hwid() {
    local auth_file="$HOME/.termux_reconnector_auth"
    echo "DEVICE_ID=\"$DEVICE_ID\"" > "$auth_file"
    echo "PLATOBOOST_KEY=\"$PLATOBOOST_KEY\"" >> "$auth_file"
    echo "KEY_EXPIRATION=\"$KEY_EXPIRATION\"" >> "$auth_file"
}

load_config() {
    if [[ -f "$CURRENT_CONFIG" ]]; then
        source "$CURRENT_CONFIG"
        # TARGET_PACKAGES is loaded as an array string, we must evaluate it or load line by line.
        # It's safer to source it if written properly in save_config
    fi
}

save_config() {
    # Generate array string representation securely
    local pkg_str="("
    for pkg in "${TARGET_PACKAGES[@]}"; do
        pkg_str+="\"$pkg\" "
    done
    pkg_str+=")"
    
    echo "GAME_ID=\"$GAME_ID\"" > "$CURRENT_CONFIG"
    echo "TARGET_WEBHOOK=\"$TARGET_WEBHOOK\"" >> "$CURRENT_CONFIG"
    echo "INTENTIONAL_CRASH_TIMER=\"$INTENTIONAL_CRASH_TIMER\"" >> "$CURRENT_CONFIG"
    echo "TARGET_PACKAGES=$pkg_str" >> "$CURRENT_CONFIG"
}

# --- Webhook Logger ---
trigger_webhook() {
    if [[ -z "$TARGET_WEBHOOK" ]]; then return; fi
    
    local img_path="/sdcard/termux_monitor_snap.png"
    # Take screenshot as root and save to accessible SD card location
    su -c "screencap -p $img_path"
    
    # Gather Metrics
    local mem_total=$(su -c "free -m | grep Mem | awk '{print \$2}'" | tr -d '\r')
    local mem_used=$(su -c "free -m | grep Mem | awk '{print \$3}'" | tr -d '\r')
    
    local uptime_seconds=$(awk '{print int($1)}' /proc/uptime)
    local uptime_hours=$((uptime_seconds / 3600))
    local uptime_mins=$(((uptime_seconds % 3600) / 60))
    local device_uptime="${uptime_hours}h ${uptime_mins}m"
    
    local current_time=$(date +%s)
    local script_elapsed=$((current_time - START_TIME))
    local script_mins=$(((script_elapsed % 3600) / 60))
    local script_hours=$((script_elapsed / 3600))
    
    # We use jq to build the JSON safely if available, but for raw bash we format carefully.
    local json_payload=$(cat <<EOF
{
  "embeds": [
    {
      "title": "Status Report: active",
      "color": 3922152,
      "fields": [
        { "name": "💻 HWID", "value": "\`$DEVICE_ID\`", "inline": true },
        { "name": "⏱ Script Uptime", "value": "\`${script_hours}h ${script_mins}m\`", "inline": true },
        { "name": "🔋 Device Uptime", "value": "\`${device_uptime}\`", "inline": true },
        { "name": "💥 Crashes Recovered", "value": "\`$TOTAL_CRASHES\`", "inline": true },
        { "name": "🧩 Google Sign-Ins", "value": "\`$TOTAL_GOOGLE_POPUPS\`", "inline": true },
        { "name": "📊 Device RAM", "value": "\`${mem_used}MB / ${mem_total}MB\`", "inline": true }
      ],
      "footer": { "text": "Termux Reconnector Analytics" }
    }
  ]
}
EOF
)
    
    # Post JSON Embed, then Post Screenshot (Standard Discord webhook format requires multipart if sending image together, 
    # but the easiest Bash way is sending two fast payloads: The Embed, then the Raw File).
    curl -s -H "Content-Type: application/json" -X POST -d "$json_payload" "$TARGET_WEBHOOK" >/dev/null
    
    # Send image
    curl -s -F "file=@$img_path" "$TARGET_WEBHOOK" >/dev/null
    
    # Cleanup image
    su -c "rm -f $img_path"
}

# --- GUI Menu ---
show_menu() {
    clear
    echo -e "${GRAY}------------------ TERMUX RECONNECTOR - BY RiTiKM416 --------------------${NORMAL}\n"
    
    echo -e "${MAG}  ____  _____ _     _             ${NORMAL}"
    echo -e "${MAG} |  _ \| ____| |__ | | _____  __  ${NORMAL}"
    echo -e "${BLUE} | |_) |  _| | '_ \| |/ _ \ \/ /  ${NORMAL}"
    echo -e "${CYAN} |  _ <| |___| |_) | | (_) >  <   ${NORMAL}"
    echo -e "${CYAN} |_| \_\_____|_.__/|_|\___/_/\_\  ${NORMAL}\n"
    
    echo -e "${BOLD}            H O M E   P A G E     ${NORMAL}"
    echo -e "${GRAY}==========================================${NORMAL}\n"
    
    echo -e "  ${CYAN}[1]${NORMAL} Start Reconnector"    
    echo -e "  ${CYAN}[2]${NORMAL} Create a config"
    echo -e "  ${CYAN}[3]${NORMAL} Load existing Config"    
    echo -e "  ${CYAN}[4]${NORMAL} Edit or Delete Config"
    echo -e "  ${CYAN}[5]${NORMAL} Select all available Roblox"
    echo -e "  ${CYAN}[6]${NORMAL} Setup Discord Webhook"
    echo -e "  ${CYAN}[7]${NORMAL} Logout Roblox"
    echo -e "  ${CYAN}[8]${NORMAL} Exit Application\n"
    
    echo -e "${GRAY}==========================================${NORMAL}\n"
    
    read -p "to Select an option : " menu_choice
    
    case $menu_choice in
        1)
            # 1. Start Reconnector
            echo -e "\e[32mStarting Reconnector...\e[0m"
            sleep 1
            break
            ;;
        2)
            # 2. Create a config
            clear
            echo -e "\e[1;36mCreating New Configuration...\e[0m"
            echo -e "\e[1;30m--------------------------------------\e[0m"
            
            # Step 1: Detect Packages
            echo -e "\e[33mScanning for installed Roblox packages...\e[0m"
            local available_pkgs=()
            
            local raw_pkgs=$(su -c "ls /data/data 2>/dev/null | grep -i 'roblox'" | tr -d '\r')
            
            if [[ -z "$raw_pkgs" ]]; then
                echo -e "\e[31mNo Roblox packages detected on this device!\e[0m"
                sleep 2
                show_menu
                return
            fi
            
            local i=1
            for pkg in $raw_pkgs; do
                available_pkgs+=("$pkg")
                echo -e "  \e[1;32m[$i]\e[0m \e[1;33m$pkg\e[0m"
                ((i++))
            done
            
            echo ""
            echo -e "\e[36mEnter the numbers of the packages you want to monitor.\e[0m"
            echo -e "\e[36mSeparate with spaces (e.g. '1 2 4'):\e[0m"
            read -p "> " pkg_selections
            
            TARGET_PACKAGES=()
            for sel in $pkg_selections; do
                local idx=$((sel - 1))
                if [[ $idx -ge 0 && $idx -lt ${#available_pkgs[@]} ]]; then
                    TARGET_PACKAGES+=("${available_pkgs[$idx]}")
                fi
            done
            
            if [[ ${#TARGET_PACKAGES[@]} -eq 0 ]]; then
                echo -e "\e[31mNo valid packages selected. Aborting config creation.\e[0m"
                sleep 2
                show_menu
                return
            fi
            
            # Step 2: Game ID
            echo ""
            read -p "Enter Target Game ID (Ex: 9587807821): " GAME_ID
            
            # Step 3: Intentional Crash Timer
            echo ""
            echo -e "\e[36mEnter Intentional Crash/Relaunch Timer in Minutes (e.g. 30).\e[0m"
            echo -e "\e[36mLeave blank or type 'none' to disable.\e[0m"
            read -p "> " timer_input
            
            if [[ -z "$timer_input" || "${timer_input,,}" == "none" ]]; then
                INTENTIONAL_CRASH_TIMER=0
            else
                local clean_num=$(echo "$timer_input" | tr -cd '0-9')
                if [[ -n "$clean_num" && "$clean_num" -ge 10 ]]; then
                    INTENTIONAL_CRASH_TIMER=$clean_num
                else
                    echo -e "\e[33mInvalid or too short. Disabling intentional crash.\e[0m"
                    INTENTIONAL_CRASH_TIMER=0
                fi
            fi
            
            # Step 4: Webhook
            echo ""
            echo -e "\e[36mEnter Discord Webhook URL for Analytics (Leave blank to disable):\e[0m"
            read -p "> " TARGET_WEBHOOK
            
            # Step 5: Save Name
            echo ""
            read -p "Enter a name for this Config (e.g., Farm_1): " conf_name
            if [[ -z "$conf_name" ]]; then conf_name="Default_Config"; fi
            
            conf_name=${conf_name// /_}
            CURRENT_CONFIG="$CONFIG_DIR/$conf_name.conf"
            
            save_config
            echo -e "\e[32mConfig '$conf_name' successfully saved and loaded!\e[0m"
            sleep 2
            show_menu
            ;;
        3)
            # 3. Load existing Config
            clear
            echo -e "\e[1;36mSaved Configurations:\e[0m"
            echo -e "\e[1;30m--------------------------------------\e[0m"
            
            local conf_files=()
            local i=1
            for f in "$CONFIG_DIR"/*.conf; do
                if [[ -f "$f" ]]; then
                    conf_files+=("$f")
                    local basename=$(basename "$f" .conf)
                    echo -e "  \e[1;33m[$i]\e[0m $basename"
                    ((i++))
                fi
            done
            
            if [[ ${#conf_files[@]} -eq 0 ]]; then
                echo -e "\e[31mNo configurations found.\e[0m"
                sleep 2
                show_menu
                return
            fi
            
            echo -e "  \e[1;31m[0]\e[0m Back"
            echo ""
            read -p "Select a config to load by number: " conf_choice
            
            if [[ "$conf_choice" == "0" ]]; then
                show_menu
                return
            fi
            
            local array_index=$((conf_choice - 1))
            if [[ $array_index -ge 0 && $array_index -lt ${#conf_files[@]} ]]; then
                CURRENT_CONFIG="${conf_files[$array_index]}"
                load_config
                echo -e "\e[32mSuccessfully loaded config!\e[0m"
                sleep 1
            else
                echo -e "\e[31mInvalid selection.\e[0m"
                sleep 2
            fi
            show_menu
            ;;
        4)
            # 4. Edit or Delete Config
            echo -e "\e[33m[Feature Scaffold] Edit or Delete Config\e[0m"
            sleep 1
            show_menu
            ;;
        5)
            # 5. Select all available Roblox
            echo -e "\e[33m[Feature Scaffold] Select all available Roblox\e[0m"
            sleep 1
            show_menu
            ;;
        6)
            # 6. Setup Discord Webhook
            echo -e "\e[33m[Feature Scaffold] Setup Discord Webhook\e[0m"
            sleep 1
            show_menu
            ;;
        7)
            # 7. Logout Roblox
            echo -e "\e[33m[Feature Scaffold] Logout Roblox\e[0m"
            sleep 1
            show_menu
            ;;
        8)
            # 8. Exit Application
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
load_hwid
verify_platoboost_key
# The Platoboost function might recurse if key is invalid, so once returned we save
save_hwid

# Loop until a config is loaded
while [[ -z "$CURRENT_CONFIG" ]]; do
    show_menu
done

show_active_monitor
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
                show_active_monitor
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
                    LAST_WEBHOOK_TIME=$(date +%s)
                    LAST_INTENTIONAL_CRASH=$(date +%s)
                    print_msg "\e[32mSuccessfully connected to the games.\e[0m"
                fi
            else
                if [[ $IS_RUNNING -eq 1 ]]; then
                    echo ""
                    print_msg "\e[31mGame disconnected or closed. Reconnecting...\e[0m"
                    IS_RUNNING=0
                    TOTAL_CRASHES=$((TOTAL_CRASHES + 1))
                fi
                launch_game
                continue
            fi
            
            # Continuous webhook firing log check
            if [[ $IS_RUNNING -eq 1 && -n "$TARGET_WEBHOOK" ]]; then
                local w_timestamp=$(date +%s)
                # 600 Seconds = 10 Minutes
                if [[ $((w_timestamp - LAST_WEBHOOK_TIME)) -ge 600 ]]; then
                    print_msg "\e[36m[Logger] Taking 10-Minute Snapshot and posting to Discord...\e[0m"
                    trigger_webhook & # Executed asynchronously so UI doesn't hang
                    LAST_WEBHOOK_TIME=$w_timestamp
                fi
            fi
            
            # Intentional Crash Manager Loop 
            if [[ $IS_RUNNING -eq 1 && $INTENTIONAL_CRASH_TIMER -gt 0 ]]; then
                local c_timestamp=$(date +%s)
                # Parse config intentional timer mapping (Timer is in MINUTES, converting to seconds)
                local required_seconds=$((INTENTIONAL_CRASH_TIMER * 60))
                
                if [[ $((c_timestamp - LAST_INTENTIONAL_CRASH)) -ge $required_seconds ]]; then
                    echo ""
                    print_msg "\e[35m[System] Intentional Restart Timer Reached ($INTENTIONAL_CRASH_TIMER mins)!\e[0m"
                    print_msg "\e[33mForce clearing servers cleanly...\e[0m"
                    
                    IS_RUNNING=0
                    launch_game
                    continue
                fi
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
                    TOTAL_GOOGLE_POPUPS=$((TOTAL_GOOGLE_POPUPS + 1))
                fi
            fi
            
        fi # End 5-second interval wrapper
    fi
done
