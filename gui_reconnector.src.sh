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
    # We call update_logger to trigger the initial visual draw instead of relying on this static block
    # This prevents the static block from being drawn and then overwritten poorly.
    if [[ $IS_RUNNING -eq 1 ]]; then
        update_logger
    else
        show_header "S Y S T E M   A C T I V E"
        echo -e "Initializing Hardware Monitors...\n"
    fi
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
    show_header "L I C E N S E   A U T H E N T I C A T I O N"
    
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
        # HWID Binding Error messaging
        if echo "$RESPONSE" | grep -qi "hwid\|device\|already in use"; then
             echo -e "\e[31mThis key is already used on another device.\e[0m"
             echo -e "\e[33mReset the HWID of this key on our discord using the 'Reset Key' button in the #get-key section.\e[0m\n"
        else
             echo -e "\e[31mInvalid or expired key.\e[0m"
             echo -e "\e[33mGenerate a new key here: \e[1;32m$DISCORD_LINK\e[0m\n"
        fi
        
        KEY_EXPIRATION=""
        read -p "Enter your new Access Key : " PLATOBOOST_KEY
        verify_platoboost_key # Recurse until valid
    fi
}

print_msg() {
    # Print the line clearly and erase the remainder of the line
    echo -e "\r\033[K$1"
}

update_logger() {
    if [[ $IS_RUNNING -eq 1 && $START_TIME -gt 0 ]]; then
        local current_time=$(date +%s)
        local elapsed=$((current_time - START_TIME))
        local hours=$((elapsed / 3600))
        local minutes=$(((elapsed % 3600) / 60))
        local seconds=$((elapsed % 60))

        local time_str=""
        if [[ $hours -gt 0 ]]; then time_str="${hours}h "; fi
        if [[ $minutes -gt 0 || $hours -gt 0 ]]; then time_str="${time_str}${minutes}m "; fi
        time_str="${time_str}${seconds}s"
        # Safe Hardware polling (Pure Bash string splitting to avoid any C-binary stack corruption on emulators)
        
        # CPU Polling (Pure Bash parsing of /proc/stat)
        local cpu_raw="N/A"
        local cpu_v1=$(su -c "cat /proc/stat 2>/dev/null")
        local cpu_line1=""
        while IFS= read -r line; do if [[ "$line" == cpu\ * ]]; then cpu_line1="$line"; break; fi; done <<< "$cpu_v1"
        sleep 0.2
        local cpu_v2=$(su -c "cat /proc/stat 2>/dev/null")
        local cpu_line2=""
        while IFS= read -r line; do if [[ "$line" == cpu\ * ]]; then cpu_line2="$line"; break; fi; done <<< "$cpu_v2"
        
        if [[ -n "$cpu_line1" && -n "$cpu_line2" ]]; then
            read -r _ u1 n1 s1 i1 iow1 irq1 soft1 steal1 _ <<< "$cpu_line1"
            read -r _ u2 n2 s2 i2 iow2 irq2 soft2 steal2 _ <<< "$cpu_line2"
            
            if [[ "$u1" =~ ^[0-9]+$ && "$u2" =~ ^[0-9]+$ ]]; then
                local active1=$((u1 + n1 + s1))
                local active2=$((u2 + n2 + s2))
                local total1=$((active1 + i1 + iow1 + irq1 + soft1 + steal1))
                local total2=$((active2 + i2 + iow2 + irq2 + soft2 + steal2))
                
                local active_diff=$((active2 - active1))
                local total_diff=$((total2 - total1))
                
                if [[ $total_diff -gt 0 ]]; then
                    cpu_raw=$(( (active_diff * 100) / total_diff ))
                fi
            fi
        fi
        
        # RAM Polling (Pure Bash parsing of /proc/meminfo)
        local meminfo=$(su -c "cat /proc/meminfo 2>/dev/null")
        local mem_total_kb=0
        local mem_avail_kb=0
        local mem_free_kb=0
        local mem_cached_kb=0
        
        while IFS= read -r line; do
            if [[ "$line" == MemTotal:* ]]; then
                mem_total_kb="${line//[^0-9]/}"
            elif [[ "$line" == MemAvailable:* ]]; then
                mem_avail_kb="${line//[^0-9]/}"
            elif [[ "$line" == MemFree:* ]]; then
                mem_free_kb="${line//[^0-9]/}"
            elif [[ "$line" == Cached:* ]]; then
                mem_cached_kb="${line//[^0-9]/}"
            fi
        done <<< "$meminfo"
        
        if [[ -z "$mem_avail_kb" || "$mem_avail_kb" -eq 0 ]]; then
            mem_avail_kb=$((mem_free_kb + mem_cached_kb))
        fi
        
        local mem_total="N/A"
        local mem_used="N/A"
        if [[ "$mem_total_kb" =~ ^[0-9]+$ && "$mem_total_kb" -gt 0 ]]; then
            mem_total=$((mem_total_kb / 1024))
            local mem_used_kb=$((mem_total_kb - mem_avail_kb))
            mem_used=$((mem_used_kb / 1024))
        fi
        
        # Storage Polling (Using Android's native df via /system/bin/df and pure bash parsing)
        local storage_lines=$(su -c "/system/bin/df /data 2>/dev/null")
        local storage_info=""
        while IFS= read -r line; do
            if [[ -n "$line" && "$line" != *"Filesystem"* ]]; then
                storage_info="$line"
            fi
        done <<< "$storage_lines"
        
        local storage_total="N/A"
        local storage_used="N/A"
        if [[ -n "$storage_info" ]]; then
            read -r _ s_tot_kb s_used_kb _ <<< "$storage_info"
            
            local clean_tot="${s_tot_kb//[^0-9]/}"
            local clean_usd="${s_used_kb//[^0-9]/}"
            
            if [[ -n "$clean_tot" && "$clean_tot" == "$s_tot_kb" && -n "$clean_usd" && "$clean_usd" == "$s_used_kb" ]]; then
                local tot_gb=$((clean_tot / 1048576))
                local tot_dec=$(((clean_tot % 1048576) * 10 / 1048576))
                
                local usd_gb=$((clean_usd / 1048576))
                local usd_dec=$(((clean_usd % 1048576) * 10 / 1048576))
                
                storage_total="${tot_gb}.${tot_dec}G"
                storage_used="${usd_gb}.${usd_dec}G"
            else
                if [[ -n "$s_tot_kb" && -n "$s_used_kb" ]]; then
                    storage_total="$s_tot_kb"
                    storage_used="$s_used_kb"
                fi
            fi
        fi
        
        # Device details
        local dev_model=$(getprop ro.product.model 2>/dev/null || echo "Unknown Device")
        local dev_manu=$(getprop ro.product.manufacturer 2>/dev/null || echo "")
        
        # We need to overwrite a specific block of lines statically so the prompt doesn't jump
        # Move cursor up 11 lines to the start of the dynamic block, redraw, then move back down.
        # However, to avoid terminal clutter, it's safer to just redraw the whole monitor cleanly if it's the interval,
        # OR use specific ANSI absolute/relative drops. Since Termux handles `\033[<N>A` (cursor up) well:
        
        echo -ne "\033[s" # Save cursor position
        
        # Let's clear the screen slightly, but a full redraw is cleaner for Android Termux since sizing varies.
        # Actually, `tput cup` or ANSI absolute positioning is best. We'll redraw the whole screen smoothly if we must,
        # but to avoid flicker, let's just clear the screen entirely every few seconds.
        # For a truly smooth experience, we'll redraw only the data block.
        
        # For simplicity and robust display on Termux, let's just clear and redraw the whole screen cleanly.
        show_header "S Y S T E M   A C T I V E"
        
        echo -e "Device Name   : \e[1;36m${dev_manu} ${dev_model}\e[0m"
        echo -e "CPU Usage     : \e[1;33m${cpu_raw}%\e[0m"
        echo -e "Storage Usage : \e[1;33m${storage_used} of ${storage_total}\e[0m"
        echo -e "RAM Usage     : \e[1;33m${mem_used}MB of ${mem_total}MB\e[0m"
        echo ""
        echo -e "Connected to Game ID  : \e[1;32m${GAME_ID}\e[0m"
        echo -e "Time Lapsed Connected : \e[1;32m${time_str}\e[0m"
        echo ""
        echo -e "If you want to stop Write \e[1;31mStop\e[0m :"
        
        # Restore prompt placeholder at the bottom purely for the visual
        echo -ne "> " 
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
show_header() {
    local page_title="$1"
    clear
    echo -e "${GRAY}------------------ TERMUX RECONNECTOR - BY RiTiKM416 --------------------${NORMAL}\n"
    
    echo -e "${MAG}  ____  _____ _     _             ${NORMAL}"
    echo -e "${MAG} |  _ \| ____| |__ | | _____  __  ${NORMAL}"
    echo -e "${BLUE} | |_) |  _| | '_ \| |/ _ \ \/ /  ${NORMAL}"
    echo -e "${CYAN} |  _ <| |___| |_) | | (_) >  <   ${NORMAL}"
    echo -e "${CYAN} |_| \_\_____|_.__/|_|\___/_/\_\  ${NORMAL}\n"
    
    if [[ -n "$page_title" ]]; then
        # Calculate padding to center the title roughly (assuming 42 chars width for the divider)
        local title_len=${#page_title}
        local pad_len=$(( (42 - title_len) / 2 ))
        local padding=$(printf '%*s' "$pad_len" '')
        echo -e "${BOLD}${padding}${page_title}${NORMAL}"
        echo -e "${GRAY}==========================================${NORMAL}\n"
    fi
}

show_menu() {
    show_header "H O M E   P A G E"
    
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
            # 1. Start Reconnector (Quick Start)
            show_header "Q U I C K   S T A R T"
            
            echo -e "\e[33mScanning for installed Roblox packages...\e[0m\n"
            local available_pkgs=()
            local raw_pkgs=$(su -c "ls /data/data 2>/dev/null | grep -i 'roblox'" | tr -d '\r')
            
            if [[ -z "$raw_pkgs" ]]; then
                echo -e "\e[31mNo Roblox packages detected!\e[0m"
                sleep 2
                show_menu
                return
            fi
            
            local i=1
            for pkg in $raw_pkgs; do
                available_pkgs+=("$pkg")
                echo -e "  \e[1;36m${i}.\e[0m \e[1;33m$pkg\e[0m"
                ((i++))
            done
            
            echo ""
            echo -e "  \e[1;31m0.\e[0m \e[1;37mAfter selecting Packages Select 0 to proceed.\e[0m"
            echo ""
            
            TARGET_PACKAGES=()
            while true; do
                if [[ ${#TARGET_PACKAGES[@]} -gt 0 ]]; then
                    echo -e "\e[32mCurrently Selected:\e[0m ${TARGET_PACKAGES[@]}"
                fi
                read -p "Select Roblox packages : " pkg_selections
                
                local finish=0
                for sel in $pkg_selections; do
                    if [[ "$sel" == "0" ]]; then
                        finish=1
                        break
                    fi
                    local idx=$((sel - 1))
                    if [[ $idx -ge 0 && $idx -lt ${#available_pkgs[@]} ]]; then
                        local exists=0
                        for added in "${TARGET_PACKAGES[@]}"; do
                            if [[ "$added" == "${available_pkgs[$idx]}" ]]; then exists=1; fi
                        done
                        if [[ $exists -eq 0 ]]; then
                            TARGET_PACKAGES+=("${available_pkgs[$idx]}")
                        fi
                    fi
                done
                
                if [[ $finish -eq 1 ]]; then
                    break
                fi
                echo ""
            done
            
            if [[ ${#TARGET_PACKAGES[@]} -eq 0 ]]; then
                echo -e "\e[31mNo valid packages selected. Returning to menu.\e[0m"
                sleep 2
                show_menu
                return
            fi
            
            echo ""
            read -p "Enter Target Game ID (Ex: 9587807821): " GAME_ID
            
            echo ""
            read -p "Reconnect Timer ( eg 10m 30m 120m ) : " timer_input
            
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
            
            CURRENT_CONFIG="QUICK_START"
            return
            ;;
        2)
            # 2. Create a config
            show_header "C R E A T E   C O N F I G"
            
            # Step 1: Detect Packages
            echo -e "\e[33mScanning for installed Roblox packages...\e[0m\n"
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
                echo -e "  \e[1;36m${i}.\e[0m \e[1;33m$pkg\e[0m"
                ((i++))
            done
            
            echo ""
            echo -e "  \e[1;31m0.\e[0m \e[1;37mAfter selecting Packages Select 0 to proceed.\e[0m"
            echo ""
            
            TARGET_PACKAGES=()
            while true; do
                if [[ ${#TARGET_PACKAGES[@]} -gt 0 ]]; then
                    echo -e "\e[32mCurrently Selected:\e[0m ${TARGET_PACKAGES[@]}"
                fi
                read -p "Select Roblox packages : " pkg_selections
                
                local finish=0
                for sel in $pkg_selections; do
                    if [[ "$sel" == "0" ]]; then
                        finish=1
                        break
                    fi
                    local idx=$((sel - 1))
                    if [[ $idx -ge 0 && $idx -lt ${#available_pkgs[@]} ]]; then
                        local exists=0
                        for added in "${TARGET_PACKAGES[@]}"; do
                            if [[ "$added" == "${available_pkgs[$idx]}" ]]; then exists=1; fi
                        done
                        if [[ $exists -eq 0 ]]; then
                            TARGET_PACKAGES+=("${available_pkgs[$idx]}")
                        fi
                    fi
                done
                
                if [[ $finish -eq 1 ]]; then
                    break
                fi
                echo ""
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
            read -p "Reconnect Timer ( eg 10m 30m 120m ) : " timer_input
            
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
            show_header "L O A D   C O N F I G"
            
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
            # 4. Delete Config
            show_header "D E L E T E   C O N F I G"
            
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
                echo -e "\e[31mThere are no config available. Redirecting to Home Page.\e[0m"
                sleep 2
                show_menu
                return
            fi
            
            echo -e "  \e[1;31m[0]\e[0m Cancel & Go Back"
            echo ""
            read -p "Select The Config : " conf_choice
            
            if [[ "$conf_choice" == "0" ]]; then
                show_menu
                return
            fi
            
            local array_index=$((conf_choice - 1))
            if [[ $array_index -ge 0 && $array_index -lt ${#conf_files[@]} ]]; then
                local del_target="${conf_files[$array_index]}"
                local basename=$(basename "$del_target" .conf)
                echo ""
                echo -e "\e[41m\e[1;37m WARNING: Config '$basename' will be deleted permanently! \e[0m"
                read -p "Press [Enter] to delete or [Ctrl+C] to abort..."
                rm -f "$del_target"
                echo -e "\e[32mConfig deleted successfully!\e[0m"
                sleep 2
            else
                echo -e "\e[31mInvalid selection.\e[0m"
                sleep 2
            fi
            show_menu
            ;;
        5)
            # 5. Select all available Roblox
            show_header "G A M E   M A N A G E R"
            echo -e "\e[33mScanning for installed Roblox packages...\e[0m\n"
            local raw_pkgs=$(su -c "ls /data/data 2>/dev/null | grep -i 'roblox'" | tr -d '\r')
            if [[ -z "$raw_pkgs" ]]; then
                echo -e "\e[31mNo Roblox packages detected!\e[0m"
                sleep 2
                show_menu
                return
            fi
            
            TARGET_PACKAGES=()
            local i=0
            for pkg in $raw_pkgs; do
                TARGET_PACKAGES+=("$pkg")
                echo -e "  \e[1;32m[✓]\e[0m \e[1;33m$pkg\e[0m"
                ((i++))
            done
            echo -e "\n\e[32mAll $i packages selected.\e[0m\n"
            
            # Sub-menu Loop
            while true; do
                echo -e "\e[1;30m--------------------------------------\e[0m"
                echo -e "  \e[36m1.\e[0m Enter a Game ID"
                echo -e "  \e[36m2.\e[0m Launch Selected Roblox"
                echo -e "  \e[36m3.\e[0m Logout all Accounts"
                echo -e "  \e[36m4.\e[0m Clear Selected Roblox's Cache"
                echo -e "  \e[36m5.\e[0m Clear Selected Roblox's Data"
                echo -e "  \e[36m6.\e[0m Uninstall Selected Roblox"
                echo -e "  \e[36m7.\e[0m Go to Menu\n"
                
                read -p "Select an action: " rblx_action
                
                case $rblx_action in
                    1)
                        read -p "Enter Target Game ID: " GAME_ID
                        read -p "Reconnect Timer ( eg 10m 30m 120m ) : " timer_input
                        if [[ -z "$timer_input" || "${timer_input,,}" == "none" ]]; then
                            INTENTIONAL_CRASH_TIMER=0
                        else
                            local clean_num=$(echo "$timer_input" | tr -cd '0-9')
                            if [[ -n "$clean_num" && "$clean_num" -ge 10 ]]; then
                                INTENTIONAL_CRASH_TIMER=$clean_num
                            else
                                INTENTIONAL_CRASH_TIMER=0
                            fi
                        fi
                        echo -e "\e[32mSettings applied. Launching all packages sequentially...\e[0m"
                        CURRENT_CONFIG="QUICK_START"
                        return
                        ;;
                    2)
                        echo -e "\e[32mLaunching all selected packages...\e[0m"
                        GAME_ID="none"
                        INTENTIONAL_CRASH_TIMER=0
                        CURRENT_CONFIG="QUICK_START"
                        return
                        ;;
                    3)
                        echo -e "\e[33mLogging out all accounts in selected packages...\e[0m"
                        for pkg in "${TARGET_PACKAGES[@]}"; do
                            su -c "rm -rf /data/data/$pkg/shared_prefs/* 2>/dev/null"
                            echo -e "  \e[32m$pkg logged out.\e[0m"
                        done
                        ;;
                    4)
                        echo -e "\e[33mClearing cache for selected packages...\e[0m"
                        for pkg in "${TARGET_PACKAGES[@]}"; do
                            su -c "rm -rf /data/data/$pkg/cache/* /data/data/$pkg/code_cache/* 2>/dev/null"
                            echo -e "  \e[32m$pkg cache cleared.\e[0m"
                        done
                        ;;
                    5)
                        echo -e "\e[33mClearing application data for selected packages...\e[0m"
                        for pkg in "${TARGET_PACKAGES[@]}"; do
                            su -c "pm clear $pkg >/dev/null 2>&1"
                            echo -e "  \e[32m$pkg data cleared.\e[0m"
                        done
                        ;;
                    6)
                        echo -e "\n\e[41m\e[1;37m WARNING: This will uninstall all selected Roblox packages! \e[0m"
                        read -p "Are you sure? (yes/no): " confirm_un
                        if [[ "${confirm_un,,}" == "yes" ]]; then
                            for pkg in "${TARGET_PACKAGES[@]}"; do
                                echo -e "  \e[33m$pkg deleting....\e[0m"
                                su -c "pm uninstall $pkg >/dev/null 2>&1"
                                echo -e "  \e[32m$pkg deleted.\e[0m"
                            done
                            echo -e "\e[32mUninstallation complete.\e[0m"
                            sleep 2
                            show_menu
                            return
                        else
                            echo -e "\e[31mAborted.\e[0m"
                        fi
                        ;;
                    7)
                        show_menu
                        return
                        ;;
                    *)
                        echo -e "\e[31mInvalid action.\e[0m"
                        ;;
                esac
            done
            ;;
        6)
            # 6. Setup Discord Webhook
            show_header "D I S C O R D   W E B H O O K"
            
            # Check global env file for webhook
            local env_hook=$(grep "GLOBAL_WEBHOOK=" "$HOME/.roblox_reconnector.conf" 2>/dev/null | cut -d'"' -f2)
            local hook_active=$(grep "GLOBAL_WEBHOOK_ACTIVE=" "$HOME/.roblox_reconnector.conf" 2>/dev/null | cut -d'=' -f2)
            
            if [[ -n "$env_hook" ]]; then
                echo -e "Webhook URL is Present."
                if [[ "$hook_active" == "1" ]]; then
                    echo -e "Status: \e[32mActive\e[0m\n"
                    TARGET_WEBHOOK="$env_hook"
                else
                    echo -e "Status: \e[31mInactive\e[0m\n"
                    TARGET_WEBHOOK=""
                fi
            else
                echo -e "Webhook URL is \e[31mNot Set\e[0m.\n"
                TARGET_WEBHOOK=""
            fi
            
            while true; do
                echo -e "  \e[36m1.\e[0m Change Webhook URL"
                echo -e "  \e[36m2.\e[0m Turn on Webhook"
                echo -e "  \e[36m3.\e[0m Turn off webhook"
                echo -e "  \e[36m4.\e[0m Home\n"
                
                read -p "Select an option: " wh_action
                
                case $wh_action in
                    1)
                        read -p "Enter new Webhook URL: " new_hook
                        if [[ -n "$new_hook" ]]; then
                            # Update conf
                            sed -i '/GLOBAL_WEBHOOK=/d' "$HOME/.roblox_reconnector.conf" 2>/dev/null
                            echo "GLOBAL_WEBHOOK=\"$new_hook\"" >> "$HOME/.roblox_reconnector.conf"
                            env_hook="$new_hook"
                            
                            read -p "Do you want to turn on Webhook? (1. Yes / 2. No): " wh_on
                            sed -i '/GLOBAL_WEBHOOK_ACTIVE=/d' "$HOME/.roblox_reconnector.conf" 2>/dev/null
                            if [[ "$wh_on" == "1" || "${wh_on,,}" == "yes" ]]; then
                                echo "GLOBAL_WEBHOOK_ACTIVE=1" >> "$HOME/.roblox_reconnector.conf"
                                echo -e "\e[32mWebhook is turned on.\e[0m"
                            else
                                echo "GLOBAL_WEBHOOK_ACTIVE=0" >> "$HOME/.roblox_reconnector.conf"
                                echo -e "\e[31mWebhook is turned off.\e[0m"
                            fi
                            sleep 3
                            show_menu
                            return
                        fi
                        ;;
                    2)
                        if [[ -z "$env_hook" ]]; then
                            echo -e "\e[31mPlease add a URL first (Option 1).\e[0m"
                        elif [[ "$hook_active" == "1" ]]; then
                            echo -e "\e[33mWebhook is already turned on and its active.\e[0m"
                        else
                            sed -i '/GLOBAL_WEBHOOK_ACTIVE=/d' "$HOME/.roblox_reconnector.conf" 2>/dev/null
                            echo "GLOBAL_WEBHOOK_ACTIVE=1" >> "$HOME/.roblox_reconnector.conf"
                            hook_active="1"
                            echo -e "\e[32mWebhook is turned on.\e[0m"
                            sleep 3
                            show_menu
                            return
                        fi
                        ;;
                    3)
                        if [[ -z "$env_hook" ]]; then
                            echo -e "\e[31mPlease add a URL first (Option 1).\e[0m"
                        elif [[ "$hook_active" == "0" ]]; then
                            echo -e "\e[33mWebhook is already turned off and inactive.\e[0m"
                        else
                            sed -i '/GLOBAL_WEBHOOK_ACTIVE=/d' "$HOME/.roblox_reconnector.conf" 2>/dev/null
                            echo "GLOBAL_WEBHOOK_ACTIVE=0" >> "$HOME/.roblox_reconnector.conf"
                            hook_active="0"
                            echo -e "\e[31mWebhook is turned off.\e[0m"
                            sleep 3
                            show_menu
                            return
                        fi
                        ;;
                    4)
                        show_menu
                        return
                        ;;
                    *)
                        echo -e "\e[31mInvalid option.\e[0m"
                        ;;
                esac
            done
            ;;
        7)
            # 7. Logout Roblox
            show_header "L O G O U T   R O B L O X"
            echo -e "\e[33mScanning and logging out all installed Roblox accounts...\e[0m"
            local raw_pkgs=$(su -c "ls /data/data 2>/dev/null | grep -i 'roblox'" | tr -d '\r')
            for pkg in $raw_pkgs; do
                su -c "rm -rf /data/data/$pkg/shared_prefs/* 2>/dev/null"
                echo -e "  \e[32m$pkg logged out.\e[0m"
            done
            sleep 2
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
        # Redraw interval for dynamic stats
        if [[ $IS_RUNNING -eq 1 ]]; then
            if (( LOOP_COUNTER % 2 == 0 )); then
                update_logger
            fi
        fi
        
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
