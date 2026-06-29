from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

TOKEN = "SEU_TOKEN_AQUI"

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("Olá! Meu bot está funcionando.")

app = Application.builder().token(TOKEN).build()
app.add_handler(CommandHandler("start", start))

print("Bot do Telegram iniciado...")
app.run_polling()
