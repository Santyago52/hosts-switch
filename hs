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

# Получение списка папок-сайтов (исключая исключения)
# Возвращает список: домен www.домен для каждого сайта
get_sites() {
    local sites=""
    for dir in "$WEB_ROOT"*/; do
        if [ -d "$dir" ]; then
            local name=$(basename "$dir")
            local skip=0
            # Пропускаем исключения
            for exc in "${EXCLUDE[@]}"; do
                if [ "$name" == "$exc" ]; then
                    skip=1
                    break
                fi
            done
            # Пропускаем папки с пробелами (не валидные домены)
            if [[ "$name" == *" "* ]]; then
                skip=1
            fi
            if [ $skip -eq 0 ]; then
                # Добавляем и домен, и www-версию
                sites="$sites $name www.$name"
            fi
        fi
    done
    echo $sites
}

# Проверка: все ли домены есть в hosts
all_domains_exist() {
    local domains="$1"
    for domain in $domains; do
        if ! grep -q "$domain" "$HOSTS_FILE"; then
            return 1
        fi
    done
    return 0
}

# Добавление доменов в hosts
add_domains() {
    local domains="$1"
    
    # Проверяем наличие маркеров
    if ! grep -q "$MARKER_START" "$HOSTS_FILE"; then
        echo "" >> "$HOSTS_FILE"
        echo "$MARKER_START" >> "$HOSTS_FILE"
        echo "$MARKER_END" >> "$HOSTS_FILE"
    fi
    
    # Удаляем старую секцию и добавляем новую
    local temp_file=$(mktemp)
    sed "/$MARKER_START/,/$MARKER_END/d" "$HOSTS_FILE" > "$temp_file"
    
    echo "" >> "$temp_file"
    echo "$MARKER_START" >> "$temp_file"
    echo "$LOCAL_IP $domains" >> "$temp_file"
    echo "$MARKER_END" >> "$temp_file"
    
    mv "$temp_file" "$HOSTS_FILE"
    chmod 644 "$HOSTS_FILE"
}

# Удаление доменов из hosts
remove_domains() {
    local temp_file=$(mktemp)
    sed "/$MARKER_START/,/$MARKER_END/d" "$HOSTS_FILE" > "$temp_file"
    mv "$temp_file" "$HOSTS_FILE"
    chmod 644 "$HOSTS_FILE"
}

# Основная логика
echo -e "${YELLOW}Сканирование $WEB_ROOT...${NC}"

SITES=$(get_sites)

if [ -z "$SITES" ]; then
    echo -e "${RED}Сайты не найдены в $WEB_ROOT${NC}"
    exit 1
fi

echo "Найдено сайтов:" $(echo $SITES | wc -w) "доменов (с www)"

if all_domains_exist "$SITES"; then
    echo -e "${YELLOW}Все домены уже есть в /etc/hosts - удаляю...${NC}"
    remove_domains
    echo -e "${GREEN}Готово! Удалено доменов:${NC}" $(echo $SITES | wc -w)
else
    echo -e "${YELLOW}Доменов нет в /etc/hosts - добавляю...${NC}"
    add_domains "$SITES"
    echo -e "${GREEN}Готово! Добавлено доменов:${NC}" $(echo $SITES | wc -w)
fi

echo ""
echo "GitHub: https://github.com/fixftp/hosts-switch"
