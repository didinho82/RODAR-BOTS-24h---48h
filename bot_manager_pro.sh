#!/bin/bash

# bot_manager_pro.sh - Gerenciador de Bots Avançado para Termux
# Desenvolvido por Manus AI

# Cores para a interface
GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; BLUE="\033[0;34m"; CYAN="\033[0;36m"; MAGENTA="\033[0;35m"; WHITE="\033[1;37m"; NC="\033[0m"

# Diretórios e arquivos de configuração
BASE_DIR="$(dirname "$0")"
BOTS_FILE="$BASE_DIR/.bot_manager_pro_bots.conf"
LOG_DIR="$BASE_DIR/bot_logs"
PM2_HOME="$BASE_DIR/.pm2"
TEMPLATES_DIR="$BASE_DIR/templates"

# Variáveis para dependências
JQ_INSTALLED=false
if command -v jq &> /dev/null; then
    JQ_INSTALLED=true
fi
BACKUP_DIR="$BASE_DIR/bot_backups"

mkdir -p "$LOG_DIR"
mkdir -p "$PM2_HOME"
mkdir -p "$BACKUP_DIR"
mkdir -p "$TEMPLATES_DIR"

# Variáveis para notificações (Termux-API)
TERMUX_API_INSTALLED=false
if command -v termux-notification &> /dev/null; then
    TERMUX_API_INSTALLED=true
fi

# Função para exibir animação de carregamento
loading_animation() {
    local duration=$1
    local message=$2
    local pid=$!
    local i=0
    local chars=("-" "\\" "|" "/")
    echo -ne "${CYAN}${message} ${NC}"
    while kill -0 $pid 2>/dev/null; do
        echo -ne "\\r${CYAN}${message} ${chars[i++ % ${#chars[@]}]} ${NC}"
        sleep 0.1
    done
    echo -ne "\\r${CYAN}${message} ${GREEN}[OK]${NC}\\n"
}

# Função para enviar notificação (Termux-API)
send_notification() {
    local title=$1
    local message=$2
    if $TERMUX_API_INSTALLED; then
        termux-notification --title "$title" --content "$message"
    else
        echo -e "${YELLOW}AVISO: Termux-API não instalado. Não foi possível enviar notificação: $title - $message${NC}"
    fi
}

# Função para verificar e instalar PM2
install_pm2() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${WHITE}  INSTALAR PM2 (GERENCIADOR DE PROCESSOS)${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    # Verifica e instala jq primeiro, pois é necessário para o PM2 jlist
    if ! $JQ_INSTALLED; then
        echo -e "\n${YELLOW}jq não encontrado. Instalando jq para monitoramento avançado...${NC}"
        pkg install -y jq
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}jq instalado com sucesso!${NC}"
            JQ_INSTALLED=true
        else
            echo -e "${RED}Falha ao instalar jq. O monitoramento avançado pode não funcionar.${NC}"
            echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
            return # Sai da função se jq não puder ser instalado
        fi
    fi

    if command -v pm2 &> /dev/null; then
        echo -e "${GREEN}PM2 já está instalado.${NC}"
    else
        echo -e "${YELLOW}PM2 não encontrado. Iniciando instalação...${NC}"
        echo -e "${CYAN}Certifique-se de ter Node.js e npm instalados no Termux.${NC}"
        echo -e "${CYAN}Comandos para instalar Node.js: pkg install nodejs-lts${NC}"
        echo -e "${CYAN}Pressione ENTER para continuar com a instalação do PM2...${NC}"; read -r
        npm install -g pm2 --prefix /data/data/com.termux/files/usr
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}PM2 instalado com sucesso!${NC}"
            echo -e "${CYAN}Para iniciar bots automaticamente no boot do Termux, execute:${NC}"
            echo -e "${WHITE}pm2 startup termux${NC}"
            echo -e "${CYAN}e siga as instruções. Isso criará um script de inicialização no seu perfil do Termux.${NC}"
        else
            echo -e "${RED}Falha ao instalar PM2. Verifique sua conexão e instalação do Node.js/npm.${NC}"
        fi
    fi
    echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
}

# Função para adicionar um novo bot
add_bot() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${WHITE}  ADICIONAR NOVO BOT${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -ne "${WHITE}Nome do Bot (ex: TelegramBot): ${NC}"; read -r bot_name

    echo -e "${WHITE}Selecione a Plataforma do Bot:${NC}"
    echo -e "  1) WhatsApp"
    echo -e "  2) Discord"
    echo -e "  3) Telegram"
    echo -ne "${WHITE}Opção (1-3): ${NC}"; read -r platform_choice

    local platform="Desconhecida"
    case $platform_choice in
        1) platform="WhatsApp" ;;
        2) platform="Discord" ;;
        3) platform="Telegram" ;;
        *) echo -e "${RED}Opção de plataforma inválida. Usando \'Desconhecida\'.${NC}" ;;
    esac

    echo -ne "${WHITE}Comando para iniciar o Bot (ex: python bot.py): ${NC}"; read -r bot_command

    if [ -z "$bot_name" ] || [ -z "$bot_command" ]; then
        echo -e "${RED}Nome e comando do bot não podem ser vazios!${NC}"
    else
        # Armazena: Nome;Plataforma;Comando;Reinicios (PM2 gerencia PID)
        echo "$bot_name;$platform;$bot_command;0" >> "$BOTS_FILE"
        echo -e "${GREEN}Bot \'$bot_name\' ($platform) adicionado com sucesso!${NC}"
    fi
    echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
}

# Função para listar bots
list_bots() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${WHITE}  LISTA DE BOTS CADASTRADOS${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    if [ ! -f "$BOTS_FILE" ] || [ ! -s "$BOTS_FILE" ]; then
        echo -e "${YELLOW}Nenhum bot cadastrado ainda.${NC}"
    else
        echo -e "${WHITE}ID | Nome do Bot      | Plataforma | Status   | PID      | CPU% | RAM    | Uptime     | Reinícios | Comando${NC}"
        echo -e "${BLUE}-----------------------------------------------------------------------------------------------------------------${NC}"
        local id=1
        while IFS=";" read -r name platform command restarts;
        do
            local status="${RED}PARADO${NC}"
            local pm2_pid="N/A"
            local pm2_cpu="N/A"
            local pm2_mem="N/A"
            local pm2_uptime="N/A"
            local pm2_restarts_count="N/A"

            if command -v pm2 &> /dev/null && $JQ_INSTALLED; then
                pm2_info=$(pm2 jlist 2>/dev/null | jq -r ".[] | select(.name == \"$name\")")
                if [ -n "$pm2_info" ]; then
                    local pm2_status_raw=$(echo "$pm2_info" | jq -r ".pm2_env.status")
                    pm2_restarts_count=$(echo "$pm2_info" | jq -r ".pm2_env.restart_time")
                    pm2_pid=$(echo "$pm2_info" | jq -r ".pid")
                    pm2_cpu=$(echo "$pm2_info" | jq -r ".monit.cpu")
                    pm2_mem_bytes=$(echo "$pm2_info" | jq -r ".monit.memory")
                    pm2_mem=$(echo "scale=2; $pm2_mem_bytes / 1024 / 1024" | bc) # Convert bytes to MB
                    local started_at_timestamp=$(echo "$pm2_info" | jq -r ".pm2_env.pm_uptime")
                    local current_timestamp=$(date +%s%3N) # Current time in milliseconds
                    local uptime_seconds=$(( (current_timestamp - started_at_timestamp) / 1000 ))
                    pm2_uptime=$(printf ":%02d:%02d" $((uptime_seconds/3600)) $(( (uptime_seconds%3600)/60 )) $((uptime_seconds%60)))

                    if [ "$pm2_status_raw" == "online" ]; then
                        status="${GREEN}RODANDO${NC}"
                    elif [ "$pm2_status_raw" == "stopped" ]; then
                        status="${YELLOW}PARADO${NC}"
                    else
                        status="${RED}ERRO${NC}"
                    fi
                fi
            fi
            printf "${WHITE}%-2s | %-17s | %-10s | %-10s | %-8s | %-4s | %-6s | %-10s | %-9s | %s${NC}\n" "$id" "$name" "$platform" "$status" "$pm2_pid" "$pm2_cpu" "${pm2_mem}MB" "$pm2_uptime" "$pm2_restarts_count" "$command"
            id=$((id+1))
        done < "$BOTS_FILE"
    fi
    echo -e "${BLUE}================================================================================================================-${NC}"
    echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
}

# Função auxiliar para listar bots sem pausa para seleção
list_bots_selection() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${WHITE}  LISTA DE BOTS CADASTRADOS${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    if [ ! -f "$BOTS_FILE" ] || [ ! -s "$BOTS_FILE" ]; then
        echo -e "${YELLOW}Nenhum bot cadastrado ainda.${NC}"
    else
        echo -e "${WHITE}ID | Nome do Bot      | Plataforma | Status   | Comando${NC}"
        echo -e "${BLUE}-----------------------------------------------------------------${NC}"
        local id=1
        while IFS=";" read -r name platform command restarts;
        do
            local status="${RED}PARADO${NC}"
            if command -v pm2 &> /dev/null; then
                if pm2 list 2>/dev/null | grep -q " $name "; then
                    status="${GREEN}RODANDO (PM2)${NC}"
                fi
            fi
            printf "${WHITE}%-2s | %-17s | %-10s | %-10s | %s${NC}\n" "$id" "$name" "$platform" "$status" "$command"
            id=$((id+1))
        done < "$BOTS_FILE"
    fi
    echo -e "${BLUE}=====================================================${NC}"
}

# Função para iniciar um bot usando PM2
start_bot() {
    clear
    list_bots_selection
    if [ ! -f "$BOTS_FILE" ] || [ ! -s "$BOTS_FILE" ]; then
        echo -e "${RED}Nenhum bot para iniciar.${NC}"
        echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
        return
    fi
    echo -ne "${WHITE}Digite o ID do bot para iniciar: ${NC}"; read -r bot_id

    local line=$(sed -n "${bot_id}p" "$BOTS_FILE")
    if [ -z "$line" ]; then
        echo -e "${RED}ID de bot inválido!${NC}"
    else
        IFS=";" read -r name platform command restarts <<< "$line"
        if command -v pm2 &> /dev/null; then
            if pm2 list 2>/dev/null | grep -q " $name "; then
                echo -e "${YELLOW}Bot \'$name\' já está rodando com PM2.${NC}"
            else
                echo -e "${CYAN}Iniciando bot \'$name\' com PM2...${NC}"
                local wrapper_script="$LOG_DIR/${name}_wrapper.sh"
                echo "#!/bin/bash" > "$wrapper_script"
                echo "cd \"$(dirname \"$command\")\" || true" >> "$wrapper_script" # Tenta mudar para o diretório do script, ignora erro se não for um path
                echo "exec $command" >> "$wrapper_script"
                chmod +x "$wrapper_script"

                pm2 start "$wrapper_script" --name "$name" --output "$LOG_DIR/${name}_pm2.log" --error "$LOG_DIR/${name}_pm2_err.log" --time --restart-delay 5000 --max-restarts 1000
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}Bot \'$name\' iniciado com PM2. Logs em \'$LOG_DIR/${name}_pm2.log\' e \'$LOG_DIR/${name}_pm2_err.log\'.${NC}"
                    send_notification "Bot Iniciado" "O bot \'$name\' ($platform) foi iniciado com sucesso!"
                else
                    echo -e "${RED}Falha ao iniciar bot \'$name\' com PM2.${NC}"
                    send_notification "Erro ao Iniciar Bot" "Falha ao iniciar o bot \'$name\' ($platform). Verifique os logs."
                fi
            fi
        else
            echo -e "${RED}PM2 não está instalado. Por favor, instale-o primeiro (Opção 7 no menu).${NC}"
            echo -e "${YELLOW}Não é possível garantir operação 24h sem PM2.${NC}"
        fi
    fi
    echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
}

# Função para parar um bot usando PM2
stop_bot() {
    clear
    list_bots_selection
    if [ ! -f "$BOTS_FILE" ] || [ ! -s "$BOTS_FILE" ]; then
        echo -e "${RED}Nenhum bot para parar.${NC}"
        echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
        return
    fi
    echo -ne "${WHITE}Digite o ID do bot para parar: ${NC}"; read -r bot_id

    local line=$(sed -n "${bot_id}p" "$BOTS_FILE")
    if [ -z "$line" ]; then
        echo -e "${RED}ID de bot inválido!${NC}"
    else
        IFS=";" read -r name platform command restarts <<< "$line"
        if command -v pm2 &> /dev/null; then
            if pm2 list 2>/dev/null | grep -q " $name "; then
                echo -e "${CYAN}Parando bot \'$name\' com PM2...${NC}"
                pm2 stop "$name"
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}Bot \'$name\' parado com PM2 com sucesso!${NC}"
                    send_notification "Bot Parado" "O bot \'$name\' ($platform) foi parado."
                else
                    echo -e "${YELLOW}Bot \'$name\' não estava rodando com PM2 ou falha ao parar.${NC}"
                fi
            else
                echo -e "${YELLOW}Bot \'$name\' não está rodando com PM2.${NC}"
            fi
        else
            echo -e "${RED}PM2 não está instalado. Não é possível parar bots gerenciados por PM2.${NC}"
        fi
    fi
    echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
}

# Função para reiniciar um bot usando PM2
restart_bot() {
    clear
    list_bots_selection
    if [ ! -f "$BOTS_FILE" ] || [ ! -s "$BOTS_FILE" ]; then
        echo -e "${RED}Nenhum bot para reiniciar.${NC}"
        echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
        return
    fi
    echo -ne "${WHITE}Digite o ID do bot para reiniciar: ${NC}"; read -r bot_id

    local line=$(sed -n "${bot_id}p" "$BOTS_FILE")
    if [ -z "$line" ]; then
        echo -e "${RED}ID de bot inválido!${NC}"
    else
        IFS=";" read -r name platform command restarts <<< "$line"
        if command -v pm2 &> /dev/null; then
            echo -e "${CYAN}Reiniciando bot \'$name\' com PM2...${NC}"
            pm2 restart "$name"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Bot \'$name\' reiniciado com PM2 com sucesso!${NC}"
                send_notification "Bot Reiniciado" "O bot \'$name\' ($platform) foi reiniciado."
            else
                echo -e "${RED}Falha ao reiniciar bot \'$name\' com PM2. Verifique se ele foi iniciado com PM2.${NC}"
            fi
        else
            echo -e "${RED}PM2 não está instalado. Não é possível reiniciar bots gerenciados por PM2.${NC}"
        fi
    fi
    echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
}

# Função para remover um bot
remove_bot() {
    clear
    list_bots_selection
    if [ ! -f "$BOTS_FILE" ] || [ ! -s "$BOTS_FILE" ]; then
        echo -e "${RED}Nenhum bot para remover.${NC}"
        echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
        return
    fi
    echo -ne "${WHITE}Digite o ID do bot para remover: ${NC}"; read -r bot_id

    local line=$(sed -n "${bot_id}p" "$BOTS_FILE")
    if [ -z "$line" ]; then
        echo -e "${RED}ID de bot inválido!${NC}"
    else
        IFS=";" read -r name platform command restarts <<< "$line"
        if command -v pm2 &> /dev/null; then
            if pm2 list 2>/dev/null | grep -q " $name "; then
                echo -e "${CYAN}Parando e removendo bot \'$name\' do PM2...${NC}"
                pm2 delete "$name"
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}Bot \'$name\' parado e removido do PM2 com sucesso!${NC}"
                    send_notification "Bot Removido" "O bot \'$name\' ($platform) foi parado e removido."
                else
                    echo -e "${YELLOW}Falha ao remover bot \'$name\' do PM2. Pode não estar rodando.${NC}"
                fi
            else
                echo -e "${YELLOW}Bot \'$name\' não está rodando com PM2, removendo apenas do registro.${NC}"
            fi
        fi
        # Remove o bot do arquivo de configuração
        sed -i "${bot_id}d" "$BOTS_FILE"
        echo -e "${GREEN}Bot \'$name\' removido do gerenciador.${NC}"
    fi
    echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
}

# Função para editar um bot
edit_bot() {
    clear
    list_bots_selection
    if [ ! -f "$BOTS_FILE" ] || [ ! -s "$BOTS_FILE" ]; then
        echo -e "${RED}Nenhum bot para editar.${NC}"
        echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
        return
    fi
    echo -ne "${WHITE}Digite o ID do bot para editar: ${NC}"; read -r bot_id

    local line=$(sed -n "${bot_id}p" "$BOTS_FILE")
    if [ -z "$line" ]; then
        echo -e "${RED}ID de bot inválido!${NC}"
    else
        IFS=";" read -r old_name old_platform old_command old_restarts <<< "$line"
        echo -e "${BLUE}=====================================================${NC}"
        echo -e "${WHITE}  EDITAR BOT: \'$old_name\'${NC}"
        echo -e "${BLUE}=====================================================${NC}"
        echo -ne "${WHITE}Novo Nome do Bot (atual: \'$old_name\', deixe em branco para manter): ${NC}"; read -r new_name
        new_name=${new_name:-$old_name}

        echo -e "${WHITE}Nova Plataforma do Bot (atual: \'$old_platform\', deixe em branco para manter): ${NC}"
        echo -e "  1) WhatsApp"
        echo -e "  2) Discord"
        echo -e "  3) Telegram"
        echo -ne "${WHITE}Opção (1-3, ou vazio para manter): ${NC}"; read -r new_platform_choice

        local new_platform="$old_platform"
        case $new_platform_choice in
            1) new_platform="WhatsApp" ;;
            2) new_platform="Discord" ;;
            3) new_platform="Telegram" ;;
            "") new_platform="$old_platform" ;;
            *) echo -e "${RED}Opção de plataforma inválida. Mantendo \'$old_platform\'.${NC}" ;;
        esac

        echo -ne "${WHITE}Novo Comando para iniciar o Bot (atual: \'$old_command\', deixe em branco para manter): ${NC}"; read -r new_command
        new_command=${new_command:-$old_command}

        # Atualiza o arquivo de configuração
        sed -i "${bot_id}s|${old_name};${old_platform};${old_command};${old_restarts}|${new_name};${new_platform};${new_command};${old_restarts}|" "$BOTS_FILE"

        # Se o nome do bot mudou, atualiza no PM2 também
        if [ "$old_name" != "$new_name" ] && command -v pm2 &> /dev/null; then
            if pm2 list 2>/dev/null | grep -q " $old_name "; then
                pm2 reload "$old_name" --name "$new_name"
                echo -e "${GREEN}Bot \'$old_name\' renomeado para \'$new_name\' no PM2.${NC}"
            fi
        fi

        echo -e "${GREEN}Bot \'$new_name\' editado com sucesso!${NC}"
    fi
    echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
}

# Função para o assistente de criação de bots
create_bot_assistant() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${WHITE}  ASSISTENTE DE CRIAÇÃO DE BOTS${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${WHITE}Este assistente irá ajudá-lo a criar um script básico para seu bot.${NC}"
    echo -e "${WHITE}Selecione a plataforma para a qual deseja criar o bot:${NC}"
    echo -e "  1) Telegram (Python)"
    echo -e "  2) Discord (Python)"
    echo -e "  3) WhatsApp (Node.js - com Baileys)"
    echo -ne "${WHITE}Opção (1-3): ${NC}"; read -r assistant_choice

    local bot_filename
    local bot_template_file
    local install_cmd

    case $assistant_choice in
        1)
            bot_filename="telegram_bot.py"
            bot_template_file="$TEMPLATES_DIR/telegram_bot_template.py"
            install_cmd="pip install python-telegram-bot"
            ;;
        2)
            bot_filename="discord_bot.py"
            bot_template_file="$TEMPLATES_DIR/discord_bot_template.py"
            install_cmd="pip install discord.py"
            ;;
        3)
            bot_filename="whatsapp_bot.js"
            bot_template_file="$TEMPLATES_DIR/whatsapp_bot_template.js"
            install_cmd="npm install @whiskeysockets/baileys"
            ;;
        *)
            echo -e "${RED}Opção inválida.${NC}"
            echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
            return
            ;;
    esac

    echo -ne "${WHITE}Nome para o arquivo do bot (sugestão: $bot_filename): ${NC}"; read -r custom_filename
    custom_filename=${custom_filename:-$bot_filename}

    if [ ! -f "$bot_template_file" ]; then
        echo -e "${RED}Erro: Arquivo de template não encontrado para a plataforma selecionada: $bot_template_file${NC}"
        echo -e "${YELLOW}Certifique-se de que os arquivos de template estão na pasta \'$TEMPLATES_DIR\'.${NC}"
        echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
        return
    fi

    cp "$bot_template_file" "$custom_filename"

    echo -e "${GREEN}Arquivo \'$custom_filename\' criado com sucesso!${NC}"
    echo -e "${CYAN}Sugestão de comando de instalação de dependências: ${WHITE}$install_cmd${NC}"
    echo -e "${CYAN}Lembre-se de editar o arquivo \'$custom_filename\' para inserir seu TOKEN e personalizar o bot.${NC}"
    echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
}

# Função para editar o código de um bot
edit_bot_code() {
    clear
    list_bots_selection
    if [ ! -f "$BOTS_FILE" ] || [ ! -s "$BOTS_FILE" ]; then
        echo -e "${RED}Nenhum bot cadastrado para editar o código.${NC}"
        echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
        return
    fi
    echo -ne "${WHITE}Digite o ID do bot cujo código você deseja editar: ${NC}"; read -r bot_id

    local line=$(sed -n "${bot_id}p" "$BOTS_FILE")
    if [ -z "$line" ]; then
        echo -e "${RED}ID de bot inválido!${NC}"
    else
        IFS=";" read -r name platform command restarts <<< "$line"
        local bot_script_path=$(echo "$command" | awk 
' { print $NF } ')
        
        if [ -f "$bot_script_path" ]; then
            echo -e "${CYAN}Abrindo \'$bot_script_path\' no nano...${NC}"
            nano "$bot_script_path"
            echo -e "${GREEN}Edição concluída. Lembre-se de reiniciar o bot se fez alterações importantes.${NC}"
        else
            echo -e "${RED}Arquivo de script do bot não encontrado: \'$bot_script_path\'.${NC}"
            echo -e "${YELLOW}Verifique o comando do bot cadastrado.${NC}"
        fi
    fi
    echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
}

# Função para instalar dependências
install_dependencies() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${WHITE}  INSTALAR DEPENDÊNCIAS${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${WHITE}Este menu ajuda a instalar dependências para seus bots.${NC}"
    echo -e "${WHITE}Selecione o tipo de dependência ou o bot para instalar:${NC}"
    echo -e "  1) Python (requirements.txt)"
    echo -e "  2) Node.js (package.json)"
    echo -e "  3) Instalar dependências para um bot específico (via comando)"
    echo -ne "${WHITE}Opção (1-3): ${NC}"; read -r dep_choice

    case $dep_choice in
        1)
            echo -ne "${WHITE}Caminho para o arquivo requirements.txt (ex: ./meu_bot/requirements.txt): ${NC}"; read -r req_path
            if [ -f "$req_path" ]; then
                echo -e "${CYAN}Instalando dependências Python de \'$req_path\'...${NC}"
                pip install -r "$req_path"
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}Dependências Python instaladas com sucesso!${NC}"
                else
                    echo -e "${RED}Falha ao instalar dependências Python.${NC}"
                fi
            else
                echo -e "${RED}Arquivo requirements.txt não encontrado em \'$req_path\'.${NC}"
            fi
            ;;
        2)
            echo -ne "${WHITE}Caminho para o diretório com package.json (ex: ./meu_bot/): ${NC}"; read -r pkg_dir
            if [ -f "$pkg_dir/package.json" ]; then
                echo -e "${CYAN}Instalando dependências Node.js em \'$pkg_dir\'...${NC}"
                (cd "$pkg_dir" && npm install)
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}Dependências Node.js instaladas com sucesso!${NC}"
                else
                    echo -e "${RED}Falha ao instalar dependências Node.js.${NC}"
                fi
            else
                echo -e "${RED}Arquivo package.json não encontrado em \'$pkg_dir\'.${NC}"
            fi
            ;;
        3)
            list_bots_selection
            if [ ! -f "$BOTS_FILE" ] || [ ! -s "$BOTS_FILE" ]; then
                echo -e "${RED}Nenhum bot cadastrado para instalar dependências.${NC}"
                echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
                return
            fi
            echo -ne "${WHITE}Digite o ID do bot para instalar dependências: ${NC}"; read -r bot_id

            local line=$(sed -n "${bot_id}p" "$BOTS_FILE")
            if [ -z "$line" ]; then
                echo -e "${RED}ID de bot inválido!${NC}"
            else
                IFS=";" read -r name platform command restarts <<< "$line"
                echo -ne "${WHITE}Comando de instalação de dependências para \'$name\' (ex: pip install -r requirements.txt): ${NC}"; read -r install_command
                if [ -n "$install_command" ]; then
                    echo -e "${CYAN}Executando comando: \'$install_command\' para o bot \'$name\'...${NC}"
                    eval "$install_command"
                    if [ $? -eq 0 ]; then
                        echo -e "${GREEN}Dependências instaladas com sucesso para \'$name\'!${NC}"
                    else
                        echo -e "${RED}Falha ao instalar dependências para \'$name\'.${NC}"
                    fi
                else
                    echo -e "${YELLOW}Nenhum comando de instalação fornecido.${NC}"
                fi
            fi
            ;;
        *)
            echo -e "${RED}Opção inválida.${NC}"
            ;;
    esac
    echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
}

# Função para backup dos bots
backup_bots() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${WHITE}  BACKUP DOS BOTS${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/bots_backup_${timestamp}.tar.gz"

    echo -e "${CYAN}Criando backup dos bots e configurações...${NC}"
    tar -czf "$backup_file" -C "$BASE_DIR" .bot_manager_pro_bots.conf bot_logs templates
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Backup criado com sucesso em: \'$backup_file\'.${NC}"
    else
        echo -e "${RED}Falha ao criar backup.${NC}"
    fi
    echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
}

# Função para restaurar bots de um backup
restore_bots() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${WHITE}  RESTAURAR BOTS${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${WHITE}Backups disponíveis em \'$BACKUP_DIR\':${NC}"
    ls -lh "$BACKUP_DIR" 2>/dev/null || echo -e "${YELLOW}Nenhum backup encontrado.${NC}"

    if [ "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        echo -ne "${WHITE}Digite o nome completo do arquivo de backup para restaurar (ex: bots_backup_20231027_123456.tar.gz): ${NC}"; read -r backup_file_name
        local full_backup_path="$BACKUP_DIR/$backup_file_name"

        if [ -f "$full_backup_path" ]; then
            echo -e "${YELLOW}ATENÇÃO: A restauração irá sobrescrever os arquivos de configuração e logs atuais.${NC}"
            echo -ne "${YELLOW}Deseja continuar? (s/N): ${NC}"; read -r confirm
            if [[ "$confirm" =~ ^[Ss]$ ]]; then
                echo -e "${CYAN}Restaurando de \'$full_backup_path\'...${NC}"
                tar -xzf "$full_backup_path" -C "$BASE_DIR"
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}Restauração concluída com sucesso!${NC}"
                    echo -e "${YELLOW}Pode ser necessário reiniciar os bots via PM2 após a restauração.${NC}"
                else
                    echo -e "${RED}Falha ao restaurar backup.${NC}"
                fi
            else
                echo -e "${YELLOW}Restauração cancelada.${NC}"
            fi
        else
            echo -e "${RED}Arquivo de backup não encontrado: \'$full_backup_path\'.${NC}"
        fi
    fi
    echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
}

# Função para ofuscar/desofuscar tokens (Base64 simples)
obfuscate_token() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${WHITE}  OFUSCAR/DESOFUSCAR TOKEN${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${WHITE}Esta função usa Base64 para ofuscar ou desofuscar tokens. Não é criptografia forte!${NC}"
    echo -e "  1) Ofuscar Token"
    echo -e "  2) Desofuscar Token"
    echo -ne "${WHITE}Opção (1-2): ${NC}"; read -r token_choice

    case $token_choice in
        1)
            echo -ne "${WHITE}Digite o token para ofuscar: ${NC}"; read -r raw_token
            if [ -n "$raw_token" ]; then
                encoded_token=$(echo -n "$raw_token" | base64)
                echo -e "${GREEN}Token Ofuscado: ${WHITE}$encoded_token${NC}"
            else
                echo -e "${RED}Token não pode ser vazio.${NC}"
            fi
            ;;
        2)
            echo -ne "${WHITE}Digite o token ofuscado (Base64) para desofuscar: ${NC}"; read -r encoded_token
            if [ -n "$encoded_token" ]; then
                decoded_token=$(echo -n "$encoded_token" | base64 -d 2>/dev/null)
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}Token Desofuscado: ${WHITE}$decoded_token${NC}"
                else
                    echo -e "${RED}Token inválido ou não está em formato Base64.${NC}"
                fi
            else
                echo -e "${RED}Token ofuscado não pode ser vazio.${NC}"
            fi
            ;;
        *)
            echo -e "${RED}Opção inválida.${NC}"
            ;;
    esac
    echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
}

# Função para verificar atualizações do gerenciador (simulado)
update_manager() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${WHITE}  ATUALIZAR GERENCIADOR${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${YELLOW}Esta função é um placeholder. Em uma versão real, ela buscaria atualizações do GitHub.${NC}"
    echo -e "${WHITE}Para atualizar manualmente, você pode baixar a versão mais recente do repositório e substituir este arquivo.${NC}"
    echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r
}

# Função para o menu principal
main_menu() {
    while true; do
        clear
        echo -e "${BLUE}=====================================================${NC}"
        echo -e "${WHITE}  GERENCIADOR DE BOTS PRO (Termux)  ${NC}"
        echo -e "${BLUE}=====================================================${NC}"
        echo -e "${GREEN}  1) Adicionar Novo Bot${NC}"
        echo -e "${GREEN}  2) Listar Bots${NC}"
        echo -e "${GREEN}  3) Iniciar Bot${NC}"
        echo -e "${GREEN}  4) Parar Bot${NC}"
        echo -e "${GREEN}  5) Reiniciar Bot${NC}"
        echo -e "${GREEN}  6) Remover Bot${NC}"
        echo -e "${GREEN}  7) Instalar/Verificar PM2${NC}"
        echo -e "${GREEN}  8) Visualizar Logs de Bot${NC}"
        echo -e "${GREEN}  9) Editar Bot (Nome, Plataforma, Comando)${NC}"
        echo -e "${GREEN} 10) Assistente de Criação de Bots${NC}"
        echo -e "${GREEN} 11) Editar Código de Bot${NC}"
        echo -e "${GREEN} 12) Instalar Dependências${NC}"
        echo -e "${GREEN} 13) Backup dos Bots${NC}"
        echo -e "${GREEN} 14) Restaurar Bots${NC}"
        echo -e "${GREEN} 15) Ofuscar/Desofuscar Token${NC}"
        echo -e "${GREEN} 16) Atualizar Gerenciador${NC}"
        echo -e "${RED}  0) Sair${NC}"
        echo -e "${BLUE}=====================================================${NC}"
        echo -ne "${WHITE}Escolha uma opção: ${NC}"; read -r option

        case $option in
            1) add_bot ;;
            2) list_bots ;;
            3) start_bot ;;
            4) stop_bot ;;
            5) restart_bot ;;
            6) remove_bot ;;
            7) install_pm2 ;;
            8) view_logs ;;
            9) edit_bot ;;
           10) create_bot_assistant ;;
           11) edit_bot_code ;;
           12) install_dependencies ;;
           13) backup_bots ;;
           14) restore_bots ;;
           15) obfuscate_token ;;
           16) update_manager ;;
            0) echo -e "${GREEN}Saindo do Gerenciador de Bots. Até mais!${NC}"; exit 0 ;;
            *) echo -e "${RED}Opção inválida. Tente novamente.${NC}"; echo -e "\n${BLUE}Pressione ENTER para continuar...${NC}"; read -r ;;
        esac
    done
}

# Iniciar o menu principal
main_menu
