# Gerenciador de Bots Pro para Termux

Este é um gerenciador de bots profissional projetado para rodar 24h por dia no Termux, com suporte a Telegram, Discord e WhatsApp.

## Funcionalidades

- 🚀 Reinício automático com PM2.
- 📊 Monitoramento de recursos (CPU, RAM).
- 🤖 Assistente para criação de bots.
- 💾 Backup e restauração.
- 🔐 Ofuscação de tokens.
- 📝 Editor de código integrado.

## Como Instalar

1. Extraia o conteúdo do arquivo `.zip` no seu Termux.
2. Entre na pasta: `cd bot_manager_pro`
3. Dê permissão de execução: `chmod +x bot_manager_pro.sh`
4. Execute o gerenciador: `./bot_manager_pro.sh`

## Requisitos

- Node.js (para o PM2 e bots de WhatsApp)
- Python (para bots de Telegram e Discord)
- `jq` (para monitoramento avançado)
- `termux-api` (opcional, para notificações)

## Estrutura do Projeto

- `bot_manager_pro.sh`: Script principal.
- `templates/`: Pasta com modelos de bots.
- `bot_logs/`: Pasta onde os logs dos bots serão salvos.
- `bot_backups/`: Pasta para os backups criados.

Desenvolvido por Manus AI.
