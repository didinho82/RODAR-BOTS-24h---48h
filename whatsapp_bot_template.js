const { makeWASocket, useMultiFileAuthState } = require("@whiskeysockets/baileys");

async function connectToWhatsApp() {
    const { state, saveCreds } = await useMultiFileAuthState("auth_info_baileys");
    const sock = makeWASocket({
        auth: state,
        printQRInTerminal: true
    });

    sock.ev.on("creds.update", saveCreds);

    sock.ev.on("connection.update", (update) => {
        const { connection, lastDisconnect } = update;
        if (connection === "close") {
            const shouldReconnect = lastDisconnect.error?.output?.statusCode !== 401;
            console.log("Conexão fechada. Reconectando...", shouldReconnect);
            if (shouldReconnect) {
                connectToWhatsApp();
            }
        } else if (connection === "open") {
            console.log("Conectado ao WhatsApp!");
        }
    });

    sock.ev.on("messages.upsert", async (m) => {
        const msg = m.messages[0];
        if (!msg.key.fromMe && m.type === "notify") {
            console.log("Mensagem recebida:", msg.message?.conversation);
            if (msg.message?.conversation === "!ping") {
                await sock.sendMessage(msg.key.remoteJid, { text: "Pong!" });
            }
        }
    });
}

connectToWhatsApp();
