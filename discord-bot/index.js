require('dotenv').config();
const { Client, GatewayIntentBits, REST, Routes } = require('discord.js');
const express = require('express');
const auth = require('basic-auth');

// --- Environment Variables ---
const TOKEN = process.env.DISCORD_TOKEN;
const CLIENT_ID = process.env.DISCORD_CLIENT_ID;
const PLATOBOOST_PROJECT = '21504';
const ADMIN_USER = process.env.ADMIN_USER || 'admin';
const ADMIN_PASS = process.env.ADMIN_PASS || 'admin123';
const PORT = process.env.PORT || 3000;

// --- State Database (In-Memory) ---
const appState = {
    botOnline: false,
    totalKeysGenerated: 0,
    recentKeys: [] // { discordId, time, link }
};

// --- Anti-Spam Rate Limiter ---
// Maps discordUserId => { link: string, expiresAt: number }
const activeLinks = new Map();

// --- Express Web Server ---
const app = express();
app.set('view engine', 'ejs');
app.use(express.static('public'));

// Basic Auth Middleware
const authMiddleware = (req, res, next) => {
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
    res.render('index', {
        state: appState,
        guildCount: client.isReady() ? client.guilds.cache.size : 0,
        userTag: client.isReady() ? client.user.tag : 'Offline',
        alert: req.query.alert ? JSON.parse(decodeURIComponent(req.query.alert)) : null
    });
});

app.post('/api/bot/toggle', (req, res) => {
    if (appState.botOnline) {
        client.destroy();
        appState.botOnline = false;
    } else {
        client.login(TOKEN);
    }
    res.redirect('/');
});

// Admin Route Helper
const redirectAlert = (res, type, message) => {
    res.redirect(`/?alert=${encodeURIComponent(JSON.stringify({ type, message }))}`);
};

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

client.on('interactionCreate', async interaction => {
    if (!interaction.isChatInputCommand()) return;

    if (interaction.commandName === 'getkey') {
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
                // Link is expired in cache, remove it so they can generate a new one.
                activeLinks.delete(userId);
            }
        }

        try {
            // Platoboost V3 (Platorelay) Link Generation
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
                activeLinks.set(userId, {
                    link: link,
                    expiresAt: now + (60 * 60 * 1000) // 60 minutes
                });

                // Save to Dashboard State
                appState.totalKeysGenerated++;
                appState.recentKeys.unshift({
                    discordId: interaction.user.tag,
                    time: new Date().toLocaleTimeString(),
                    link: link
                });
                if (appState.recentKeys.length > 20) appState.recentKeys.pop();

                const messageStr = `Here is your unique Platoboost Link!`;
                await interaction.editReply({
                    content: `${messageStr}\n\n👉 **${link}**\n\nWhen you complete the link, enter the generated string into your Termux Script! It will permanently lock to that specific device.`,
                    ephemeral: true
                });
            } else {
                throw new Error("API rejected request: " + decoded.message);
            }
        } catch (error) {
            console.error('Error generating link:', error);
            await interaction.editReply({
                content: `Error communicating with Platoboost. Try again later.`,
                ephemeral: true
            });
        }
    } else if (interaction.commandName === 'reset') {
        const key = interaction.options.getString('key');
        const userId = interaction.user.id;
        await interaction.deferReply({ ephemeral: true });

        try {
            // Platoboost V3 Reset endpoint for Developers
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
            await interaction.editReply({
                content: `Error communicating with Platoboost. Try again later.`,
                ephemeral: true
            });
        }
    }
});


// --- Boot System ---
app.listen(PORT, () => {
    console.log(`[Web] Admin Dashboard running on http://localhost:${PORT}`);
    console.log(`[Web] Use username: ${ADMIN_USER} | pass: ${ADMIN_PASS}`);
    // Start bot on boot
    client.login(TOKEN);
});
