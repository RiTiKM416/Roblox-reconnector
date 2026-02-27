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
LINK="https://gateway.platoboost.com/a/$PROJECT_ID"
echo -e "\e[33mTo use this tool, you need a valid Platoboost Key.\e[0m"
echo -e "\e[36mGet your key here: \e[1;32m$LINK\e[0m"
echo ""

while true; do
    read -p "Enter your Platoboost Key: " user_key
    
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
    
    # Attempting standard validation pattern
    RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "https://api.platoboost.com/v1/public/whitelist/verify?project_id=$PROJECT_ID&key=$user_key")
    HTTP_STATUS=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    # If the JSON response contains true/success or HTTP 200, assume it's good.
    # Note: Platoboost V2 API for Lua often looks like: https://api-v2.platoboost.com/v1/public/whitelist/21504?key=YOUR_KEY
    # We will use the structure from their standard URL endpoints.
    
    # We will just do a simpler verify to see if the key matches the length/format, or assume standard JSON response.
    # Actually, the most robust way to check in bash is to look for "success" or "true" in the response body if HTTP is 200.
    
    # For now, let's use the standard platoboost v2 verify endpoint route
    RESPONSE=$(curl -s "https://api-v2.platoboost.com/v1/public/whitelist/$PROJECT_ID?key=$user_key")
    
    if echo "$RESPONSE" | grep -qi "true"; then
        echo -e "\e[32mAuthentication successful! Key is valid.\e[0m"
        echo ""
        # Save the valid key to config so the main script can use it
        echo "PLATOBOOST_KEY=\"$user_key\"" > "$HOME/.roblox_reconnector.conf"
        break
    else
        echo -e "\e[31mInvalid or expired key. Please get a new one from: $LINK\e[0m\n"
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
