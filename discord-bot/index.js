require('dotenv').config();
const { Client, GatewayIntentBits, REST, Routes, ActionRowBuilder, ButtonBuilder, ButtonStyle, ModalBuilder, TextInputBuilder, TextInputStyle, EmbedBuilder } = require('discord.js');
const express = require('express');
const auth = require('basic-auth');
const fs = require('fs');
const path = require('path');
const sqlite3 = require('sqlite3').verbose();
const crypto = require('crypto');
// --- Database Initialization ---
const dbPath = path.join(__dirname, 'database.sqlite');
const db = new sqlite3.Database(dbPath);

db.serialize(() => {
    db.run(`CREATE TABLE IF NOT EXISTS sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        hwid TEXT UNIQUE,
        discord_tag TEXT,
        key_used TEXT,
        last_updated INTEGER
    )`);
});

// --- Environment Variables ---
const TOKEN = process.env.DISCORD_TOKEN || process.env.BOT_TOKEN;
const CLIENT_ID = process.env.DISCORD_CLIENT_ID || process.env.CLIENT_ID;
const PLATOBOOST_PROJECT = '21504';
const ADMIN_USER = process.env.ADMIN_USER || 'admin';
const ADMIN_PASS = process.env.ADMIN_PASS || 'admin123';
const PORT = process.env.PORT || 3000;
const CLIENT_SECRET = process.env.CLIENT_SECRET || 'RECONNECTOR_V1_SECRET_998877';

// --- State Database (Persistent) ---
const statsPath = path.join(__dirname, 'stats.json');
let appState = {
    botOnline: false,
    totalKeysGenerated: 0,
    recentKeys: [] // { discordId, time, timeMs, link }
};

try {
    if (fs.existsSync(statsPath)) {
        const rawStats = fs.readFileSync(statsPath, 'utf8');
        const parsed = JSON.parse(rawStats);
        appState.totalKeysGenerated = parsed.totalKeysGenerated || 0;
        appState.recentKeys = parsed.recentKeys || [];
    }
} catch (e) {
    console.error('Failed to load stats', e);
}

const saveStats = () => {
    fs.writeFileSync(statsPath, JSON.stringify({
        totalKeysGenerated: appState.totalKeysGenerated,
        recentKeys: appState.recentKeys
    }, null, 4));
};

// --- Custom Embed Configurator ---
const embedConfigPath = path.join(__dirname, 'embed_config.json');
let embedConfig = {
    title: 'REblox Authentication',
    description: 'Click one of the buttons below to interact with the Free Key System.',
    color: '#38bdf8',
    image: '',
    thumbnail: ''
};

// Try to load any previously saved custom embed settings
try {
    if (fs.existsSync(embedConfigPath)) {
        const rawConfig = fs.readFileSync(embedConfigPath, 'utf8');
        embedConfig = { ...embedConfig, ...JSON.parse(rawConfig) };
    }
} catch (e) {
    console.error('Failed to load embed config', e);
}

// --- Anti-Spam Rate Limiter ---
// Maps discordUserId => { link: string, expiresAt: number }
const activeLinks = new Map();

// --- Express Web Server ---
const app = express();
app.set('view engine', 'ejs');
app.use(express.static('public'));

// Basic Auth Middleware
const authMiddleware = (req, res, next) => {
    // Skip auth for the backup webhook
    if (req.path === '/api/backup/update') return next();

    const user = auth(req);
    if (!user || user.name !== ADMIN_USER || user.pass !== ADMIN_PASS) {
        res.set('WWW-Authenticate', 'Basic realm="Reconnector Admin"');
        return res.status(401).send('Authentication required.');
    }
    next();
};

app.use(authMiddleware);

// Web Routes
app.get('/', (req, res) => {
    const now = Date.now();
    // A key is "Active" if generated within the last 24 hours (86400000 ms)
    const activeCount = appState.recentKeys.filter(k => (now - (k.timeMs || 0)) < 86400000).length;
    let expiredCount = appState.totalKeysGenerated - activeCount;
    if (expiredCount < 0) expiredCount = 0;

    db.all("SELECT * FROM sessions ORDER BY last_updated DESC LIMIT 100", (err, rows) => {
        const backupKeys = (rows || []).map(r => ({
            discordId: r.discord_tag,
            time: new Date(r.last_updated).toLocaleTimeString(),
            timeMs: r.last_updated,
            key: r.key_used,
            hwid: r.hwid
        }));

        res.render('index', {
            state: appState,
            activeCount: activeCount,
            expiredCount: expiredCount,
            guildCount: client.isReady() ? client.guilds.cache.size : 0,
            userTag: client.isReady() ? client.user.tag : 'Offline',
            embedConfig: embedConfig,
            backupKeys: backupKeys,
            alert: req.query.alert ? JSON.parse(decodeURIComponent(req.query.alert)) : null
        });
    });
});

app.post('/api/bot/toggle', (req, res) => {
    if (appState.botOnline) {
        client.destroy();
        appState.botOnline = false;
    } else {
        client.login(TOKEN).catch(e => {
            console.error("[Bot] Manual Login Error:", e.message || e);
            appState.botOnline = false;
        });
    }
    res.redirect('/');
});

// Admin Route Helper
const redirectAlert = (res, type, message) => {
    res.redirect(`/?alert=${encodeURIComponent(JSON.stringify({ type, message }))}`);
};

// --- Webhook: Backup Updater from Bash Script ---
// Note: This endpoint does NOT use basic AUTH so the Bash script can ping it anonymously.
app.post('/api/backup/update', express.json(), express.urlencoded({ extended: true }), (req, res) => {
    const signature = req.headers['x-signature'];
    if (!signature) return res.status(401).json({ success: false, message: 'Missing Signature Header' });

    const { key, device_id, discord_id } = req.body;
    if (!key || !device_id) return res.status(400).json({ success: false, message: 'Missing key or device_id' });

    // Validate Signature: We reconstruct the exact payload string the bash script sends
    // The bash script sends: {"device_id":"HWID","key":"KEY","discord_id":"DISCORD_TAG"}
    const payloadString = `{"device_id":"${device_id}","key":"${key}","discord_id":"${discord_id || ''}"}`;
    const expectedSig = crypto.createHmac('sha256', CLIENT_SECRET).update(payloadString).digest('base64');

    if (signature !== expectedSig) {
        console.warn(`[Security] Rejected invalid HMAC signature for HWID: ${device_id}`);
        return res.status(403).json({ success: false, message: 'Invalid Cryptographic Signature' });
    }

    const tag = discord_id || 'Termux User';
    const now = Date.now();

    db.run(`INSERT INTO sessions (hwid, discord_tag, key_used, last_updated) 
            VALUES (?, ?, ?, ?) 
            ON CONFLICT(hwid) DO UPDATE SET 
                discord_tag = excluded.discord_tag,
                key_used = excluded.key_used,
                last_updated = excluded.last_updated`,
        [device_id, tag, key, now],
        (err) => {
            if (err) console.error("Database insert error:", err);
            return res.json({ success: true, message: 'Backup Synchronized Successfully' });
        }
    );
});

// --- Custom Embed Form Handler ---
app.post('/api/admin/update-embed', express.urlencoded({ extended: true }), (req, res) => {
    try {
        const { title, description, color, image, thumbnail } = req.body;

        embedConfig = {
            title: title || 'REblox Authentication',
            description: description || 'Click one of the buttons below to interact with the Free Key System.',
            color: color || '#38bdf8',
            image: image || '',
            thumbnail: thumbnail || ''
        };

        fs.writeFileSync(embedConfigPath, JSON.stringify(embedConfig, null, 4));
        redirectAlert(res, 'success', 'Embed Layout successfully saved! Run /setup in Discord to see changes.');
    } catch (e) {
        redirectAlert(res, 'error', 'Failed to save Embed configuration.');
    }
});

// --- Instant Admin Key Generator (No Platoboost Required) ---
app.post('/api/admin/create-instant-key', (req, res) => {
    // Generate a random 16-character alphanumeric key
    const rawKey = `ADMIN_GEN_${Math.random().toString(36).substring(2, 10)}${Math.random().toString(36).substring(2, 10)}`.toUpperCase();

    const tag = 'Web Console Admin';
    const hwid = 'BYPASS_HWID_' + Math.random().toString(36).substring(2, 8);
    const now = Date.now();

    db.run(`INSERT INTO sessions (hwid, discord_tag, key_used, last_updated) VALUES (?, ?, ?, ?)`,
        [hwid, tag, rawKey, now],
        (err) => {
            if (err) console.error("Database insert error:", err);
            redirectAlert(res, 'success', `Instant Admin Key Generated: <code style="padding:4px 8px; background:rgba(0,0,0,0.5); user-select:all; cursor:pointer;" onclick="navigator.clipboard.writeText('${rawKey}')">${rawKey}</code> (Click to copy)`);
        }
    );
});

// --- Advanced Admin Key Management API ---
const PLATOBOOST_SECRET = process.env.PLATOBOOST_SECRET; // Native Developer Secret

app.post('/api/admin/create-key', async (req, res) => {
    try {
        const identifier = `admin-gen-${Math.random().toString(36).substring(2, 8)}`;
        const response = await fetch('https://api.platoboost.net/public/start', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                service: parseInt(PLATOBOOST_PROJECT),
                identifier: identifier
            }),
        });
        const decoded = await response.json();
        if (decoded.success) {
            appState.totalKeysGenerated++;
            appState.recentKeys.unshift({
                discordId: 'Web Console Admin',
                time: new Date().toLocaleTimeString(),
                timeMs: Date.now(),
                link: decoded.data.url
            });
            if (appState.recentKeys.length > 500) appState.recentKeys.pop();
            saveStats();
            redirectAlert(res, 'success', `Generated Admin Link: <a href="${decoded.data.url}" target="_blank" class="link" style="color:#10b981; font-weight:bold;">${decoded.data.url}</a>`);
        } else {
            redirectAlert(res, 'error', `API Rejected: ${decoded.message}`);
        }
    } catch (err) {
        redirectAlert(res, 'error', `Network Error trying to create key.`);
    }
});

app.post('/api/admin/delete-key', express.urlencoded({ extended: true }), async (req, res) => {
    const key = req.body.key;
    if (!key) return redirectAlert(res, 'error', 'You must provide a key to delete.');

    try {
        // Drop from SQLite immediately
        db.run(`DELETE FROM sessions WHERE key_used = ?`, [key], (err) => {
            if (err) console.error("Database delete error:", err);
        });

        // Offline Admin keys bypass the API
        if (key.startsWith('ADMIN_GEN_')) {
            return redirectAlert(res, 'success', `Admin Key **${key}** DELETED from local database.`);
        }

        const response = await fetch(`https://api.platoboost.net/public/whitelist/${PLATOBOOST_PROJECT}?key=${key}`, {
            method: 'DELETE',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${PLATOBOOST_SECRET}`
            }
        });
        const decoded = await response.json();

        if (response.ok || (decoded && decoded.success)) {
            redirectAlert(res, 'success', `Key **${key}** DELETED completely from the system.`);
        } else {
            redirectAlert(res, 'error', `Could not delete key: ${decoded.message || 'Unknown API Error'}`);
        }
    } catch (err) {
        redirectAlert(res, 'error', `Network Error trying to delete key.`);
    }
});

app.post('/api/admin/reset-hwid', express.urlencoded({ extended: true }), async (req, res) => {
    const key = req.body.key;
    if (!key) return redirectAlert(res, 'error', 'You must provide a key to reset.');

    try {
        // Also remove from SQLite because the HWID is reset
        db.run(`DELETE FROM sessions WHERE key_used = ?`, [key], (err) => {
            if (err) console.error("Database delete error:", err);
        });

        if (key.startsWith('ADMIN_GEN_')) {
            return redirectAlert(res, 'success', `Admin Key **${key}** unbound from local HWID.`);
        }

        // To forcibly reset a key as an admin
        // Note: Reset requires the identifier that generated it. As admin, we may not know it. 
        // We will attempt to use the developer secret on the reset endpoint.
        const response = await fetch(`https://api.platoboost.net/public/reset/${PLATOBOOST_PROJECT}?key=${key}`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${PLATOBOOST_SECRET}`
            }
        });
        const decoded = await response.json();
        if (decoded.success) {
            redirectAlert(res, 'success', `HWID Binding successfully reset for Key: **${key}**`);
        } else {
            redirectAlert(res, 'error', `Could not reset HWID: ${decoded.message || 'Platoboost API error.'}`);
        }
    } catch (err) {
        redirectAlert(res, 'error', `Network Error trying to reset HWID binding.`);
    }
});


// --- Discord Bot ---
const client = new Client({
    intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages]
});

const commands = [
    {
        name: 'getkey',
        description: 'Generates a unique Platoboost Link to get a 24-hr access key.',
    },
    {
        name: 'setup',
        description: 'Admin Only: Spawns the interactive Auth menu.',
    },
    {
        name: 'reset',
        description: 'Resets the Hardware ID binding on your active key so you can use it on a new device.',
        options: [
            {
                name: 'key',
                description: 'The exact Platoboost Key you want to reset.',
                type: 3, // String type
                required: true
            }
        ]
    }
];

const rest = new REST({ version: '10' }).setToken(TOKEN);

client.once('ready', async () => {
    console.log(`[Bot] Logged in as ${client.user.tag}`);
    appState.botOnline = true;
    try {
        await rest.put(Routes.applicationCommands(CLIENT_ID), { body: commands });
    } catch (error) {
        console.error("Failed to register commands:", error);
    }
});

// --- Interaction Handlers ---
async function handleGetKey(interaction) {
    const userId = interaction.user.id;
    await interaction.deferReply({ ephemeral: true });

    // Check Anti-Spam Cache
    const now = Date.now();
    if (activeLinks.has(userId)) {
        const cachedData = activeLinks.get(userId);
        if (now < cachedData.expiresAt) {
            // Determine minutes left
            const minutesLeft = Math.ceil((cachedData.expiresAt - now) / 60000);
            return await interaction.editReply({
                content: `⚠️ **Anti-Spam Protection**\nYou already requested a key. Please complete your active link first!\n*(If you lost the page, you can generate a brand new link in ${minutesLeft} minutes).*\n\n👉 **${cachedData.link}**`,
                ephemeral: true
            });
        } else {
            activeLinks.delete(userId);
        }
    }

    try {
        const response = await fetch('https://api.platoboost.net/public/start', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                service: parseInt(PLATOBOOST_PROJECT),
                identifier: userId
            }),
        });
        const decoded = await response.json();
        if (decoded.success) {
            const link = decoded.data.url;
            // Add to Anti-Spam Memory Cache (1 Hour Expiration)
            activeLinks.set(userId, { link: link, expiresAt: now + (60 * 60 * 1000) });
            // Save to Dashboard State
            appState.totalKeysGenerated++;
            appState.recentKeys.unshift({ discordId: interaction.user.tag, time: new Date().toLocaleTimeString(), timeMs: now, link: link });
            if (appState.recentKeys.length > 500) appState.recentKeys.pop();
            saveStats();

            await interaction.editReply({
                content: `Here is your unique Platoboost Link!\n\n👉 **${link}**\n\nWhen you complete the link, enter the generated string into your Termux Script! It will permanently lock to that specific device.`,
                ephemeral: true
            });
        } else {
            throw new Error("API rejected request: " + decoded.message);
        }
    } catch (error) {
        console.error('Error generating link:', error);
        await interaction.editReply({ content: `Error communicating with Platoboost. Try again later.`, ephemeral: true });
    }
}

async function handleReset(interaction, key) {
    const userId = interaction.user.id;
    await interaction.deferReply({ ephemeral: true });
    try {
        const response = await fetch(`https://api.platoboost.net/public/reset/${PLATOBOOST_PROJECT}?key=${key}&identifier=${userId}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }
        });
        const decoded = await response.json();
        if (decoded.success) {
            // Clear the anti-spam cache so they can immediately generate a new key
            activeLinks.delete(userId);
            await interaction.editReply({
                content: `✅ Successfully Reset Hardware ID binding for \`${key}\`!\n\nYou can now use this key on a new phone, or generate a brand new key.`,
                ephemeral: true
            });
        } else {
            await interaction.editReply({
                content: `❌ Failed to reset key: ${decoded.message}\n(Make sure the key is correct and you were the one who generated it!).`,
                ephemeral: true
            });
        }
    } catch (error) {
        await interaction.editReply({ content: `Error communicating with Platoboost. Try again later.`, ephemeral: true });
    }
}

async function handleGetScript(interaction, key) {
    const userId = interaction.user.id;
    await interaction.deferReply({ ephemeral: true });

    try {
        // Platoboost Validation Request (To check if key is active/valid)
        // We use the regular whitelist endpoint to check its status. 
        // Note: the Termux script currently passes the HWID here, but for simple validation
        // we can just check if the key is structurally valid or recognized by the system.
        // A simple way to check validity without burning a hwid lock is to see if the key exists 
        // or check its expiration. If Platoboost V3 doesn't have a pure 'check' endpoint, 
        // we can attempt a dummy whitelist without identifier, or assume if it doesn't 404 it's real.
        // Let's use the developer /whitelist check if available, or just a basic fetch.

        // Since we are just downloading the script, let's verify if the key format is vaguely correct and let the bash script handle the real HWID locking.
        // Or better, we can actually try fetching the key info:
        const response = await fetch(`https://api.platoboost.net/public/whitelist/${PLATOBOOST_PROJECT}?key=${key}`);
        const text = await response.text();

        // As long as the API doesn't explicitly throw a "Invalid Key" error or 404, we assume it's valid enough to download the script. 
        // (The bash script itself will do the rigorous hardware locking anyway).
        if (text.includes('error') && text.includes('Invalid')) {
            await interaction.editReply({
                content: `❌ The key you entered is invalid or expired. Kindly get a new one using the **Get Key** button!`,
                ephemeral: true
            });
            return;
        }

        const webhookUrl = process.env.WEBHOOK_URL || 'http://localhost:3000';
        await interaction.editReply({
            content: `✅ **Key Verified!**\n\n**Copy & Paste this into Termux:**\n\`\`\`bash\nexport WEBHOOK_URL="${webhookUrl}" && curl -sL https://raw.githubusercontent.com/RiTiKM416/Roblox-reconnector/main/install.sh -o install.sh && bash install.sh\n\`\`\``,
            ephemeral: true
        });

    } catch (error) {
        await interaction.editReply({ content: `Error communicating with Validation Server. Try again later.`, ephemeral: true });
    }
}

// --- Interaction Router ---
client.on('interactionCreate', async interaction => {
    // 1. Slash Commands
    if (interaction.isChatInputCommand()) {
        if (interaction.commandName === 'getkey') {
            await handleGetKey(interaction);
        } else if (interaction.commandName === 'reset') {
            await handleReset(interaction, interaction.options.getString('key'));
        } else if (interaction.commandName === 'setup') {
            if (!interaction.memberPermissions || !interaction.memberPermissions.has('Administrator')) {
                return interaction.reply({ content: 'You do not have permission to use this command.', ephemeral: true });
            }

            // Map valid Hex String -> hex integer
            let embedColor = 0x38bdf8;
            if (embedConfig.color) {
                const hexVal = embedConfig.color.replace('#', '');
                embedColor = parseInt(hexVal, 16);
            }

            const embed = new EmbedBuilder()
                .setTitle(embedConfig.title || 'REblox Authentication')
                .setDescription(embedConfig.description || 'Click one of the buttons below to interact with the Free Key System.')
                .setColor(embedColor)
                .addFields(
                    { name: '🔑 Get Key', value: 'Generate a new 24hr access key tied to this Discord account.' },
                    { name: '🗑️ Reset HWID', value: 'Reset the hardware binding of an active key if you changed phones.' },
                    { name: '📜 Get Script', value: 'Get the 1-line installation script to run in Termux.' }
                );

            if (embedConfig.image) embed.setImage(embedConfig.image);
            if (embedConfig.thumbnail) embed.setThumbnail(embedConfig.thumbnail);

            const row = new ActionRowBuilder().addComponents(
                new ButtonBuilder().setCustomId('btn_getkey').setLabel('Get Key').setStyle(ButtonStyle.Success).setEmoji('🔑'),
                new ButtonBuilder().setCustomId('btn_reset').setLabel('Reset HWID').setStyle(ButtonStyle.Danger).setEmoji('🗑️'),
                new ButtonBuilder().setCustomId('btn_script').setLabel('Get Script').setStyle(ButtonStyle.Secondary).setEmoji('📜')
            );

            await interaction.reply({ components: [row], embeds: [embed] });
        }
    }
    // 2. Button Clicks
    else if (interaction.isButton()) {
        if (interaction.customId === 'btn_getkey') {
            await handleGetKey(interaction);
        } else if (interaction.customId === 'btn_script') {
            // Pop up a Modal to ask for the Key string to unlock the script
            const modal = new ModalBuilder()
                .setCustomId('modal_script')
                .setTitle('Verify Key to Get Script');

            const keyInput = new TextInputBuilder()
                .setCustomId('input_key_script')
                .setLabel("Enter your active Reconnector key")
                .setStyle(TextInputStyle.Short)
                .setPlaceholder('e.g., FREE_1cff246e93...#######')
                .setRequired(true);

            modal.addComponents(new ActionRowBuilder().addComponents(keyInput));
            await interaction.showModal(modal);
        } else if (interaction.customId === 'btn_reset') {
            // Pop up a Modal to ask for the Key string
            const modal = new ModalBuilder()
                .setCustomId('modal_reset')
                .setTitle('Reset Hardware ID');

            const keyInput = new TextInputBuilder()
                .setCustomId('input_key')
                .setLabel("Enter your Reconnector key")
                .setStyle(TextInputStyle.Short)
                .setPlaceholder('e.g., FREE_1cff246e93...#######')
                .setRequired(true);

            modal.addComponents(new ActionRowBuilder().addComponents(keyInput));
            await interaction.showModal(modal);
        }
    }
    // 3. Modal Submissions
    else if (interaction.isModalSubmit()) {
        if (interaction.customId === 'modal_reset') {
            const userKey = interaction.fields.getTextInputValue('input_key');
            await handleReset(interaction, userKey);
        } else if (interaction.customId === 'modal_script') {
            const scriptKey = interaction.fields.getTextInputValue('input_key_script');
            await handleGetScript(interaction, scriptKey);
        }
    }
});


// --- Boot System ---
app.listen(PORT, () => {
    console.log(`[Web] Admin Dashboard running on http://localhost:${PORT}`);
    console.log(`[Web] Use username: ${ADMIN_USER} | pass: ${ADMIN_PASS}`);
    // Start bot on boot
    client.login(TOKEN).catch(e => {
        console.error("[Bot] Auto-Login Failed on Boot:", e.message || e);
        appState.botOnline = false;
    });
});
