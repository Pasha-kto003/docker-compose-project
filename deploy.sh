#!/bin/bash

# ==========================================
#  Docker Compose Deployment Script
# ==========================================
# Назначение: Автоматический деплой приложения
# Вызов: ./deploy.sh [environment]
# Примеры:
#   ./deploy.sh staging    - деплой на staging
#   ./deploy.sh production - деплой на production
#   ./deploy.sh            - деплой по умолчанию (production)

set -e  # Выход при ошибке

# ==========================================
# 📋 КОНФИГУРАЦИЯ
# ==========================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Переменные окружения
ENVIRONMENT=${1:-production}
PROJECT_NAME="myapp"
COMPOSE_FILE="docker-compose.yml"
REGISTRY="ghcr.io"
IMAGE_NAME="nosferatu/docker-compose-project"
IMAGE_TAG="latest"

# Выбор файла docker-compose в зависимости от окружения

# ==========================================
# 📋 ВЫБОР КОНФИГУРАЦИИ ПО ОКРУЖЕНИЮ
# ==========================================

case $ENVIRONMENT in
    dev|development)
        COMPOSE_FILE="docker-compose.dev.yml"
        ENV_FILE=".env.dev"
        PROJECT_NAME="myapp-dev"
        ;;
    staging)
        COMPOSE_FILE="docker-compose.staging.yml"
        ENV_FILE=".env.staging"
        PROJECT_NAME="myapp-staging"
        ;;
    prod|production)
        COMPOSE_FILE="docker-compose.prod.yml"
        ENV_FILE=".env.prod"
        PROJECT_NAME="myapp-prod"
        ;;
    *)
        COMPOSE_FILE="docker-compose.yml"
        ENV_FILE=".env"
        PROJECT_NAME="myapp"
        ;;
esac

export COMPOSE_PROJECT_NAME=$PROJECT_NAME

# Загружаем переменные окружения из .env файла
if [ -f "$ENV_FILE" ]; then
    log "Загрузка переменных из $ENV_FILE"
    set -a
    source "$ENV_FILE"
    set +a
    success "Переменные загружены"
else
    warning "Файл $ENV_FILE не найден, используем значения по умолчанию"
fi

# Таймауты
STARTUP_TIMEOUT=60
HEALTHCHECK_RETRIES=5
HEALTHCHECK_INTERVAL=10

# Логирование
LOG_FILE="deploy-$(date +%Y%m%d-%H%M%S).log"

# ==========================================
# 📝 ФУНКЦИИ
# ==========================================

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1" >> "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ $1" >> "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1" >> "$LOG_FILE"
    exit 1
}

# ==========================================
# 🔍 ПРЕ-ПРОВЕРКИ
# ==========================================

pre_checks() {
    log "=== 🔍 Пре-проверки ==="
    
    # Проверка Docker
    if ! command -v docker &> /dev/null; then
        error "Docker не установлен!"
    fi
    success "Docker установлен: $(docker --version)"
    
    # Проверка Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        error "Docker Compose не установлен!"
    fi
    success "Docker Compose установлен"
    
    # Проверка файла docker-compose.yml
    if [ ! -f "$COMPOSE_FILE" ]; then
        error "Файл $COMPOSE_FILE не найден!"
    fi
    success "Файл $COMPOSE_FILE найден"
    
    # Проверка окружения
    log "Окружение: $ENVIRONMENT"
    log "Проект: $PROJECT_NAME"
    log "Лог файл: $LOG_FILE"
}

# ==========================================
# 📥 ШАГ 1: PULL ОБРАЗОВ
# ==========================================

pull_images() {
    log "=== 📥 Шаг 1: Загрузка образов из реестра ==="
    
    # Логин в реестр (если нужны учётные данные)
    if [ -n "$REGISTRY_USER" ] && [ -n "$REGISTRY_PASSWORD" ]; then
        log "Авторизация в реестре $REGISTRY..."
        echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY" -u "$REGISTRY_USER" --password-stdin
        success "Авторизация успешна"
    fi
    
    # Pull образов
    log "Загрузка последних версий образов..."
    
    if docker compose pull; then
        success "Образы загружены успешно"
    else
        warning "Не удалось загрузить образы (возможно локальные)"
    fi
    
    # Показать версии образов
    log "Версии образов:"
    docker images | grep -E "$IMAGE_NAME|postgres|redis" || true
}

# ==========================================
# 🛑 ШАГ 2: ОСТАНОВКА СТАРЫХ КОНТЕЙНЕРОВ
# ==========================================

stop_containers() {
    log "=== 🛑 Шаг 2: Остановка старых контейнеров ==="
    
    # Проверка запущенных контейнеров
    RUNNING=$(docker compose ps -q 2>/dev/null | wc -l)
    log "Найдено запущенных контейнеров: $RUNNING"
    
    if [ "$RUNNING" -gt 0 ]; then
        log "Остановка контейнеров..."
        
        # Graceful shutdown
        docker compose down --timeout 30
        
        success "Контейнеры остановлены"
    else
        warning "Нет запущенных контейнеров"
    fi
    
    # Очистка старых образов (опционально)
    log "Очистка неиспользуемых образов..."
    docker image prune -f --filter "until=24h" || true
    success "Очистка завершена"
}

# ==========================================
# 🚀 ШАГ 3: ЗАПУСК НОВЫХ КОНТЕЙНЕРОВ
# ==========================================

start_containers() {
    log "=== 🚀 Шаг 3: Запуск новых контейнеров ==="
    
    # Запуск в detached режиме
    docker compose up -d --remove-orphans
    
    success "Контейнеры запущены"
    
    # Пауза для старта сервисов
    log "Ожидание запуска сервисов (${STARTUP_TIMEOUT}с)..."
    sleep 10
}

# ==========================================
# ❤️ ШАГ 4: ПРОВЕРКА ЗДОРОВЬЯ
# ==========================================

health_check() {
    log "=== ❤️ Шаг 4: Проверка здоровья сервисов ==="
    
    # Проверка статуса контейнеров
    log "Статус контейнеров:"
    docker compose ps
    
    # Проверка здоровья каждого сервиса
    SERVICES=$(docker compose ps --services 2>/dev/null)
    
    for SERVICE in $SERVICES; do
        log "Проверка сервиса: $SERVICE"
        
        RETRY=0
        while [ $RETRY -lt $HEALTHCHECK_RETRIES ]; do
            STATUS=$(docker compose ps -q "$SERVICE" 2>/dev/null | xargs docker inspect --format='{{.State.Status}}' 2>/dev/null || echo "not_found")
            
            if [ "$STATUS" = "running" ]; then
                success "Сервис $SERVICE: running"
                break
            else
                RETRY=$((RETRY + 1))
                warning "Сервис $SERVICE: $STATUS (попытка $RETRY/$HEALTHCHECK_RETRIES)"
                sleep $HEALTHCHECK_INTERVAL
            fi
        done
        
        if [ "$STATUS" != "running" ]; then
            error "Сервис $SERVICE не запустился!"
        fi
    done
    
    # Проверка HTTP endpoint (если есть)
    if command -v curl &> /dev/null; then
        log "Проверка HTTP endpoint..."
        
        if curl -f --max-time 10 http://localhost:3000/api/health > /dev/null 2>&1; then
            success "HTTP healthcheck пройден"
        else
            warning "HTTP healthcheck не пройден (сервис может быть ещё не готов)"
        fi
    fi
}

# ==========================================
# 📊 ШАГ 5: ФИНАЛЬНЫЙ ОТЧЁТ
# ==========================================

final_report() {
    log "=== 📊 Финальный отчёт ==="
    
    echo ""
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║           🎉 DEPLOYMENT COMPLETED SUCCESSFULLY         ║"
    echo "╠════════════════════════════════════════════════════════╣"
    echo "║  Environment:  $ENVIRONMENT"
    echo "║  Project:      $PROJECT_NAME"
    echo "║  Log file:     $LOG_FILE"
    echo "╚════════════════════════════════════════════════════════╝"
    echo ""
    
    # Статус сервисов
    echo "📋 Статус сервисов:"
    docker compose ps
    
    echo ""
    echo "📦 Версии образов:"
    docker images | grep -E "$IMAGE_NAME|postgres|redis" | head -5
    
    echo ""
    echo "📝 Логи последних событий:"
    docker compose logs --tail=5 --no-color
    
    success "Деплой завершён успешно!"
}

# ==========================================
# 🧹 ОБРАБОТКА ОШИБОК
# ==========================================

cleanup() {
    if [ $? -ne 0 ]; then
        error "Деплой не удался! Проверьте лог: $LOG_FILE"
        log "Возможные действия:"
        log "  1. Проверить логи: docker compose logs"
        log "  2. Откатить версию: git revert"
        log "  3. Перезапустить: ./deploy.sh"
    fi
}

trap cleanup EXIT

# ==========================================
# 🎯 ОСНОВНАЯ ЛОГИКА
# ==========================================

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║              🚀 DOCKER DEPLOYMENT SCRIPT               ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo ""
    
    pre_checks
    pull_images
    stop_containers
    start_containers
    health_check
    final_report
}

# Запуск
main "$@"
