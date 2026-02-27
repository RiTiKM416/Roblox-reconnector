require('dotenv').config();
const { Client, GatewayIntentBits, REST, Routes } = require('discord.js');
const axios = require('axios');

// Environment variables
const TOKEN = process.env.DISCORD_TOKEN;
const CLIENT_ID = process.env.DISCORD_CLIENT_ID;
const PLATOBOOST_PROJECT = '21504';
const PLATOBOOST_SECRET = process.env.PLATOBOOST_SECRET;

// Create Discord Client
const client = new Client({
    intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages]
});

// Define Slash Commands
const commands = [
    {
        name: 'getkey',
        description: 'Generates a unique Platoboost link for your Discord account to get a 24hr access key.',
    }
];

// Register Slash Commands on startup
const rest = new REST({ version: '10' }).setToken(TOKEN);

client.once('ready', async () => {
    console.log(`[Bot] Logged in as ${client.user.tag}`);
    try {
        console.log('Started refreshing application (/) commands.');
        await rest.put(Routes.applicationCommands(CLIENT_ID), { body: commands });
        console.log('Successfully reloaded application (/) commands.');
    } catch (error) {
        console.error(error);
    }
});

// Handle Interactions
client.on('interactionCreate', async interaction => {
    if (!interaction.isChatInputCommand()) return;

    if (interaction.commandName === 'getkey') {
        const userId = interaction.user.id;

        // Defer reply because Platoboost API might take a second
        await interaction.deferReply({ ephemeral: true });

        try {
            // Platoboost V3 (Platorelay) Link Generation
            // We request a unique authenticated URL for this specific Discord User ID.
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
                const messageStr = `Here is your unique Platoboost Link (Securely tied to your Discord ID **${userId}**):`;

                // Send link back to user privately
                await interaction.editReply({
                    content: `${messageStr}\n\n👉 **${link}**\n\n1. Complete the link to get your access Key.\n2. In the Termux Script, enter your Discord ID (**${userId}**) and the Key!`,
                    ephemeral: true
                });
            } else {
                throw new Error("Platoboost API rejected the start request: " + decoded.message);
            }
        } catch (error) {
            console.error('Error generating Platoboost link:', error);
            await interaction.editReply({
                content: `Sorry, there was an error communicating with Platoboost. Please try again later.`,
                ephemeral: true
            });
        }
    }
});

// Log In
client.login(TOKEN);
