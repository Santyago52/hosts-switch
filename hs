#!/bin/bash
#
# hs - переключатель локальных хостов
# Запуск: sudo hs
#
# Путь к сайтам
WEB_ROOT="/var/www/"
# Папки-исключения (не считать сайтами)
EXCLUDE=("logs" "backup" ".git" "cache" "tmp" "html")
# Файл hosts
HOSTS_FILE="/etc/hosts"
# Маркеры для управляемых записей
MARKER_START="# BEGIN hs managed entries"
MARKER_END="# END hs managed entries"
# IP для локальных доменов
LOCAL_IP="127.0.0.1"
# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Проверка на root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Ошибка: требуется sudo${NC}"
    echo "Запустите: sudo hs"
    exit 1
fi

# Проверка наличия fzf
if ! command -v fzf &> /dev/null; then
    echo -e "${RED}Ошибка: fzf не установлен${NC}"
    echo "Установите: sudo apt install fzf  или  brew install fzf"
    exit 1
fi

# Получение списка папок-сайтов (без www, только базовые имена)
get_sites() {
    local sites=()
    for dir in "$WEB_ROOT"*/; do
        if [ -d "$dir" ]; then
            local name
            name=$(basename "$dir")
            local skip=0
            for exc in "${EXCLUDE[@]}"; do
                if [ "$name" == "$exc" ]; then
                    skip=1
                    break
                fi
            done
            if [[ "$name" == *" "* ]]; then
                skip=1
            fi
            if [ $skip -eq 0 ]; then
                sites+=("$name")
            fi
        fi
    done
    echo "${sites[@]}"
}

# Проверка: есть ли домен в hosts (управляемой секции)
domain_exists_in_hosts() {
    local domain="$1"
    awk "/$MARKER_START/,/$MARKER_END/" "$HOSTS_FILE" | grep -q "\b$domain\b"
}

# Добавление доменов в hosts
add_domains() {
    local domains=("$@")
    local all_domains=""
    for name in "${domains[@]}"; do
        all_domains="$all_domains $name www.$name"
    done

    local temp_file
    temp_file=$(mktemp)
    sed "/$MARKER_START/,/$MARKER_END/d" "$HOSTS_FILE" > "$temp_file"

    echo "" >> "$temp_file"
    echo "$MARKER_START" >> "$temp_file"
    echo "$LOCAL_IP$all_domains" >> "$temp_file"
    echo "$MARKER_END" >> "$temp_file"

    mv "$temp_file" "$HOSTS_FILE"
    chmod 644 "$HOSTS_FILE"
}

# Удаление конкретных доменов из секции (остальные оставить)
remove_domains() {
    local to_remove=("$@")

    local current_line
    current_line=$(awk "/$MARKER_START/,/$MARKER_END/" "$HOSTS_FILE" | grep "^$LOCAL_IP")

    local current_domains
    current_domains=($(echo "$current_line" | sed "s/$LOCAL_IP//"))

    local keep_domains=()
    for domain in "${current_domains[@]}"; do
        local drop=0
        for rm_name in "${to_remove[@]}"; do
            if [ "$domain" == "$rm_name" ] || [ "$domain" == "www.$rm_name" ]; then
                drop=1
                break
            fi
        done
        if [ $drop -eq 0 ]; then
            keep_domains+=("$domain")
        fi
    done

    local temp_file
    temp_file=$(mktemp)
    sed "/$MARKER_START/,/$MARKER_END/d" "$HOSTS_FILE" > "$temp_file"

    if [ ${#keep_domains[@]} -gt 0 ]; then
        echo "" >> "$temp_file"
        echo "$MARKER_START" >> "$temp_file"
        echo "$LOCAL_IP ${keep_domains[*]}" >> "$temp_file"
        echo "$MARKER_END" >> "$temp_file"
    fi

    mv "$temp_file" "$HOSTS_FILE"
    chmod 644 "$HOSTS_FILE"
}

# ─── Основная логика ───────────────────────────────────────────────

echo -e "${YELLOW}Сканирование $WEB_ROOT...${NC}"

ALL_SITES=($(get_sites))

if [ ${#ALL_SITES[@]} -eq 0 ]; then
    echo -e "${RED}Сайты не найдены в $WEB_ROOT${NC}"
    exit 1
fi

# Определяем режим: смотрим есть ли наша секция в hosts
if awk "/$MARKER_START/,/$MARKER_END/" "$HOSTS_FILE" | grep -q "^$LOCAL_IP"; then
    MODE="remove"
else
    MODE="add"
fi

if [ "$MODE" == "add" ]; then

    SELECTED=$(printf '%s\n' "${ALL_SITES[@]}" | \
        fzf --multi \
            --bind 'load:select-all' \
            --bind 'space:toggle' \
            --prompt='> ' \
            --header=$'╔══════════════════════════╗\n║   ДОБАВИТЬ В /etc/hosts  ║\n╚══════════════════════════╝\nПробел: снять/поставить | Enter: применить' \
            --marker='✓' \
            --color='marker:green')

    if [ -z "$SELECTED" ]; then
        echo -e "${YELLOW}Ничего не выбрано. Выход.${NC}"
        exit 0
    fi

    mapfile -t CHOSEN <<< "$SELECTED"
    add_domains "${CHOSEN[@]}"

    echo -e "\n${GREEN}Добавлено доменов: ${#CHOSEN[@]} (+ www-версии)${NC}"
    for name in "${CHOSEN[@]}"; do
        echo -e "  ${GREEN}+${NC} $LOCAL_IP  $name  www.$name"
    done

else

    ACTIVE_SITES=()
    for name in "${ALL_SITES[@]}"; do
        if domain_exists_in_hosts "$name"; then
            ACTIVE_SITES+=("$name")
        fi
    done

    if [ ${#ACTIVE_SITES[@]} -eq 0 ]; then
        echo -e "${YELLOW}Нет активных доменов в /etc/hosts${NC}"
        exit 0
    fi

    SELECTED=$(printf '%s\n' "${ACTIVE_SITES[@]}" | \
        fzf --multi \
            --bind 'load:select-all' \
            --bind 'space:toggle' \
            --prompt='> ' \
            --header=$'╔══════════════════════════╗\n║  УДАЛИТЬ ИЗ /etc/hosts   ║\n╚══════════════════════════╝\nПробел: снять/поставить | Enter: применить' \
            --marker='✓' \
            --color='marker:red')

    if [ -z "$SELECTED" ]; then
        echo -e "${YELLOW}Ничего не выбрано. Выход.${NC}"
        exit 0
    fi

    mapfile -t CHOSEN <<< "$SELECTED"
    remove_domains "${CHOSEN[@]}"

    echo -e "\n${GREEN}Удалено доменов: ${#CHOSEN[@]} (+ www-версии)${NC}"
    for name in "${CHOSEN[@]}"; do
        echo -e "  ${RED}-${NC} $name  www.$name"
    done

fi

echo ""
echo "GitHub: https://github.com/santyago52/hosts-switch"