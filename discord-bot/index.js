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
            // Platoboost API V2 requires generating a link using the developer secret
            // If the user hasn't provided the secret yet, fallback to the generic gateway route
            let link = `https://gateway.platoboost.com/a/${PLATOBOOST_PROJECT}`;
            let messageStr = "Here is your Platoboost Link to get your 24-hour key:";

            if (PLATOBOOST_SECRET) {
                // If the developer has a Platoboost server-side secret, we should generate an API link 
                // that locks the generated key specifically to their unique Discord `userId`.
                // Example route (This depends on Platoboost's V2 REST endpoints, commonly POST to /v1/developers/...)
                // We're wrapping this in a try-catch in case the endpoint structure is slightly different for your tier

                // TODO: Replace with the exact Platoboost Server Link Generation endpoint if required 
                // (Usually developers just append ?id=DiscordID to the gateway link for basic tying)
                link = `https://gateway.platoboost.com/a/${PLATOBOOST_PROJECT}?id=${userId}`;
                messageStr = `Here is your unique Platoboost Link (Tied to Discord ID **${userId}**):`;
            }

            // Send link back to user privately
            await interaction.editReply({
                content: `${messageStr}\n\n👉 **${link}**\n\nOnce you complete the link, paste the generated string into the Termux Script!`,
                ephemeral: true
            });

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
