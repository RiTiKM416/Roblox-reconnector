#!/data/data/com.termux/files/usr/bin/bash

# Termux Auto-Reconnector Bootstrapper
# This script is designed to be run via: curl | bash

# This script is designed to be downloaded and run locally.

echo "======================================"
echo "    Roblox Termux Auto-Reconnector    "
echo "                Setup                 "
echo "======================================"

# --- Platoboost Authentication ---
PROJECT_ID="21504"
DISCORD_LINK="https://discord.gg/ZFjE9yqUNy"
echo -e "\e[33mTo use this tool, you need a valid 24hr Access Key.\e[0m"
echo -e "\e[36mJoin our Discord to get your key: \e[1;32m$DISCORD_LINK\e[0m"
echo -e "\e[36m(Go to the #get-key channel and type \e[1;37m/getkey\e[36m)\e[0m"
echo ""

while true; do
    read -p "Enter your Auth Key: " user_key
    
    # Simple check for empty string
    if [[ -z "$user_key" ]]; then
        echo -e "\e[31mKey cannot be empty.\e[0m\n"
        continue
    fi
    
    echo "Verifying key with Platoboost..."
    
    # Call Platoboost API. Their public verify endpoint usually responds with a JSON success/error.
    # Platoboost driver for C# hits the public frontend API. Usually it's /api/public/boost/[projectId]/verify?key=[key] or similar, but generic Platoboost lua scripts use a post request.
    # We will use the standard public API endpoint for Platoboost: https://api.platoboost.com/v1/public/whitelist/verify
    # Query parameters are typically ?key=... &project=...
    
    # Generate a hardware ID for this device
    DEVICE_ID="DEV-$(cat /proc/sys/kernel/random/uuid | cut -c 1-8 | tr 'a-z' 'A-Z')"
    
    # Attempting standard validation pattern
    RESPONSE=$(curl -s "https://api.platoboost.net/public/whitelist/$PROJECT_ID?identifier=$DEVICE_ID&key=$user_key")
    
    if echo "$RESPONSE" | grep -qi "true"; then
        echo -e "\e[32mAuthentication successful! Key is permanently bound to this Device.\e[0m"
        
        # Backup Updater Payload (Silent Sync to Dashboard)
        if [[ -n "$WEBHOOK_URL" ]]; then
            curl -s "$WEBHOOK_URL/api/backup/update" \
                 -X POST -H "Content-Type: application/json" \
                 -d "{\"key\": \"$user_key\", \"device_id\": \"$DEVICE_ID\"}" > /dev/null &
        fi
        
        echo ""
        # Save the valid key and device ID to config so the main script can use it
        echo "PLATOBOOST_KEY=\"$user_key\"" > "$HOME/.roblox_reconnector.conf"
        echo "DEVICE_ID=\"$DEVICE_ID\"" >> "$HOME/.roblox_reconnector.conf"
        echo "WEBHOOK_URL=\"$WEBHOOK_URL\"" >> "$HOME/.roblox_reconnector.conf"
        break
    else
        echo -e "\e[31mInvalid or expired key. Please generate a new one in our Discord.\e[0m\n"
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
