require('dotenv').config();
const dns = require('dns');
dns.setDefaultResultOrder('ipv4first'); // Bypasses IPv6 blackholes
const { Client, GatewayIntentBits, REST, Routes, ActionRowBuilder, ButtonBuilder, ButtonStyle, ModalBuilder, TextInputBuilder, TextInputStyle, EmbedBuilder, WebhookClient } = require('discord.js');
const fs = require('fs');
const path = require('path');

// --- Environment Variables ---
const TOKEN = process.env.DISCORD_TOKEN || process.env.BOT_TOKEN;
const CLIENT_ID = process.env.DISCORD_CLIENT_ID || process.env.CLIENT_ID;
const PLATOBOOST_PROJECT = '21504';
const DISCORD_WEBHOOK_URL = process.env.DISCORD_WEBHOOK_URL || process.env.WEBHOOK_URL;

let systemWebhook = null;
if (DISCORD_WEBHOOK_URL) {
    try {
        systemWebhook = new WebhookClient({ url: DISCORD_WEBHOOK_URL });
    } catch (e) {
        console.error("Invalid Webhook URL provided.");
    }
}

// --- Custom Embed Configurator ---
const embedConfigPath = path.join(__dirname, 'embed_config.json');
let embedConfig = {
    title: 'REblox Authentication',
    description: 'Click one of the buttons below to interact with the Free Key System.',
    color: '#38bdf8',
    image: '',
    thumbnail: ''
};

try {
    if (fs.existsSync(embedConfigPath)) {
        const rawConfig = fs.readFileSync(embedConfigPath, 'utf8');
        embedConfig = { ...embedConfig, ...JSON.parse(rawConfig) };
    }
} catch (e) { }

// --- Anti-Spam Rate Limiter ---
// Maps discordUserId => { link: string, expiresAt: number }
const activeLinks = new Map();

// --- Discord Bot ---
const client = new Client({
    intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages],
    ws: { properties: { browser: 'Discord iOS' } },
    rest: { timeout: 20000, retries: 3 }
});
client.on('error', console.error);

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
    try {
        await rest.put(Routes.applicationCommands(CLIENT_ID), { body: commands });
        console.log("[Bot] Slash commands synced.");
    } catch (error) {
        console.error("Failed to register commands:", error);
    }
});

// --- System Logger ---
async function logToSystem(title, userTag, actionDetails, colorHex) {
    if (!systemWebhook) return;
    try {
        const embed = new EmbedBuilder()
            .setTitle(title)
            .setColor(colorHex)
            .addFields(
                { name: 'User', value: userTag, inline: true },
                { name: 'Details', value: actionDetails, inline: false }
            )
            .setTimestamp();
        await systemWebhook.send({ embeds: [embed] });
    } catch (e) {
        console.error("Failed to send webhook log:", e.message);
    }
}

// --- Interaction Handlers ---
async function handleGetKey(interaction) {
    const userId = interaction.user.id;
    await interaction.deferReply({ ephemeral: true });

    const now = Date.now();
    if (activeLinks.has(userId)) {
        const cachedData = activeLinks.get(userId);
        if (now < cachedData.expiresAt) {
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
            activeLinks.set(userId, { link: link, expiresAt: now + (60 * 60 * 1000) });

            // Log to System Webhook
            logToSystem('🔑 New Key Generated', interaction.user.tag, `Generated Link: ${link}`, 0x10b981);

            await interaction.editReply({
                content: `Here is your unique Platoboost Link!\n\n👉 **${link}**\n\nWhen you complete the link, enter the generated string into your Termux Script!`,
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
            activeLinks.delete(userId);
            logToSystem('🗑️ HWID Reset', interaction.user.tag, `Reset Key: \`${key}\``, 0xef4444);

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
        const response = await fetch(`https://api.platoboost.net/public/whitelist/${PLATOBOOST_PROJECT}?key=${key}`);
        const text = await response.text();

        if (text.includes('error') && text.includes('Invalid')) {
            await interaction.editReply({
                content: `❌ The key you entered is invalid or expired. Kindly get a new one using the **Get Key** button!`,
                ephemeral: true
            });
            return;
        }

        const webhookOverride = DISCORD_WEBHOOK_URL || '';
        await interaction.editReply({
            content: `✅ **Key Verified!**\n\n**Copy & Paste this into Termux:**\n\`\`\`bash\nexport WEBHOOK_URL="${webhookOverride}" && curl -sL https://raw.githubusercontent.com/RiTiKM416/Roblox-reconnector/main/install.sh -o install.sh && bash install.sh\n\`\`\``,
            ephemeral: true
        });

    } catch (error) {
        await interaction.editReply({ content: `Error communicating with Validation Server. Try again later.`, ephemeral: true });
    }
}

// --- Interaction Router ---
client.on('interactionCreate', async interaction => {
    if (interaction.isChatInputCommand()) {
        if (interaction.commandName === 'getkey') {
            await handleGetKey(interaction);
        } else if (interaction.commandName === 'reset') {
            await handleReset(interaction, interaction.options.getString('key'));
        } else if (interaction.commandName === 'setup') {
            if (!interaction.memberPermissions || !interaction.memberPermissions.has('Administrator')) {
                return interaction.reply({ content: 'You do not have permission to use this command.', ephemeral: true });
            }

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
    else if (interaction.isButton()) {
        if (interaction.customId === 'btn_getkey') {
            await handleGetKey(interaction);
        } else if (interaction.customId === 'btn_script') {
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

console.log(`[Bot] Attempting to log in to Discord gateway...`);
client.login(TOKEN).catch(e => {
    console.error("[Bot] Auto-Login Failed on Boot:", e.message || e);
});
