#!/data/data/com.termux/files/usr/bin/bash

# Termux Auto-Reconnector Bootstrapper
# This script is designed to be run via: curl | bash

# This script is designed to be downloaded and run locally.

# --- Utilities ---
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

# --- Device & Auth Init ---
AUTH_FILE="$HOME/.termux_reconnector_auth"
if [[ -f "$AUTH_FILE" ]]; then
    source "$AUTH_FILE"
fi

if [[ -z "$DEVICE_ID" ]]; then
    DEVICE_ID="DEV-$(cat /proc/sys/kernel/random/uuid | cut -c 1-8 | tr 'a-z' 'A-Z')"
fi

echo "======================================"
echo "                REblox                "
echo "                Setup                 "
echo "======================================"

# --- Platoboost Authentication ---
PROJECT_ID="21504"
DISCORD_LINK="https://discord.gg/ZFjE9yqUNy"

verify_key_silently() {
    local key_to_test="$1"
    local raw_response=$(curl -s "https://api.platoboost.net/public/whitelist/$PROJECT_ID?identifier=$DEVICE_ID&key=$key_to_test")
    
    if echo "$raw_response" | grep -qi "true"; then
        return 0 # Success
    else
        # Platoboost public API typically returns messages like "Invalid key" or "HWID mismatch" in JSON
        # If it's returning false but the key format is valid, it's usually an HWID binding error.
        return 1
    fi
}

echo -e "${YELLOW}To use this tool, you need a valid Access Key.${NORMAL}"
echo -e "${CYAN}Join our Discord to get your key: ${BOLD}${GREEN}$DISCORD_LINK${NORMAL}"
echo -e "${CYAN}( Go to the ${YELLOW}#get-key${CYAN} channel and get a Valid Access key. )${NORMAL}"
echo ""

# Attempt to fast-lane authenticate if they have a saved key!
needs_new_key=1
if [[ -n "$PLATOBOOST_KEY" ]]; then
    echo -e "${YELLOW}Checking cached key...${NORMAL}"
    if verify_key_silently "$PLATOBOOST_KEY"; then
        safe_key="${PLATOBOOST_KEY:0:15}*********"
        echo -e "${GREEN}[+] Authentication successful! Welcome back.${NORMAL}"
        echo -e "${CYAN}Active Key: $safe_key${NORMAL}\n"
        needs_new_key=0
    else
        echo -e "${RED}[-] Saved key is invalid or expired. Prompting for new key.${NORMAL}\n"
        PLATOBOOST_KEY=""
    fi
fi

while [[ $needs_new_key -eq 1 ]]; do
    read -p "Enter your Access Key : " user_key
    
    # Simple check for empty string
    if [[ -z "$user_key" ]]; then
        echo -e "${RED}Key cannot be empty.${NORMAL}\n"
        continue
    fi
    
    echo "Verifying key with Platoboost..."
    
    # Attempting standard validation pattern
    RESPONSE=$(curl -s "https://api.platoboost.net/public/whitelist/$PROJECT_ID?identifier=$DEVICE_ID&key=$user_key")
    
    if echo "$RESPONSE" | grep -qi "true"; then
        echo -e "${GREEN}Authentication successful! Key is permanently bound to this Device.${NORMAL}"
        
        # Backup Updater Payload (Silent Sync to Dashboard)
        if [[ -n "$WEBHOOK_URL" ]]; then
            curl -s "$WEBHOOK_URL/api/backup/update" \
                 -X POST -H "Content-Type: application/json" \
                 -d "{\"key\": \"$user_key\", \"device_id\": \"$DEVICE_ID\"}" > /dev/null &
        fi
        
        echo ""
        # Save the valid key and device ID to centralized config
        echo "PLATOBOOST_KEY=\"$user_key\"" > "$AUTH_FILE"
        echo "DEVICE_ID=\"$DEVICE_ID\"" >> "$AUTH_FILE"
        break
    else
        # HWID Binding Error messaging
        if echo "$RESPONSE" | grep -qi "hwid\|device\|already in use"; then
             echo -e "${RED}This key is already used on another device.${NORMAL}"
             echo -e "${YELLOW}Reset the HWID of this key on our discord using the 'Reset Key' button in the #get-key section.${NORMAL}\n"
        else
             echo -e "${RED}Invalid or expired key. Please generate a new one in our Discord.${NORMAL}\n"
        fi
    fi
done
# --- Dependency Installation ---
echo "Checking and installing essential Termux packages (tsu, procps, etc.)..."
echo "This might take a moment on the first run..."
pkg update -y
pkg install -y tsu procps coreutils ncurses-utils
echo "Essential packages successfully verified/installed."
echo ""

# --- Download Main Application ---
echo "Downloading core GUI script..."
curl -sL "https://raw.githubusercontent.com/RiTiKM416/Roblox-reconnector/main/gui_reconnector.sh" -o "$PREFIX/bin/roblox-reconnector" &
CURL_PID=$!

spin='-\|/'
i=0
while kill -0 $CURL_PID 2>/dev/null; do
    i=$(( (i+1) %4 ))
    printf "\r\e[36m[${spin:$i:1}] Downloading...\e[0m"
    sleep 0.1
done

printf "\r\e[32m[✓] Download complete!       \e[0m\n"
chmod +x "$PREFIX/bin/roblox-reconnector"

echo ""
echo "Installation complete!"
echo "Starting the application..."
echo ""

# Execute the downloaded GUI directly without the pipe constraint
exec "$PREFIX/bin/roblox-reconnector"
