# 🐳 CI/CD Pipeline Documentation

## Структура пайплайна

| Этап | Job | Описание | Триггер |
|------|-----|----------|---------|
| **Build** | `build` | Сборка Docker образа | Push на main/develop |
| **Test** | `test` | Security scan + unit tests | После build |
| **Push** | `push` | Push в GHCR | Только main/tags |
| **Deploy Staging** | `deploy_staging` | Деплой на staging | Только develop |
| **Deploy Production** | `deploy_production` | Деплой на production | Только main/tags |

## Переменные окружения

| Переменная | Описание | Где настроить |
|------------|----------|---------------|
| `REGISTRY` | Container registry | В workflow (ghcr.io) |
| `IMAGE_NAME` | Имя образа | В workflow |
| `APP_VERSION` | Версия приложения | В workflow (git sha) |

## Secrets (настроить в GitHub Settings)

| Secret | Описание | Пример |
|--------|----------|--------|
| `STAGING_HOST` | IP staging сервера | `192.168.1.100` |
| `STAGING_USER` | SSH пользователь | `deploy` |
| `STAGING_SSH_KEY` | SSH приватный ключ | `-----BEGIN RSA PRIVATE KEY-----...` |
| `PRODUCTION_HOST` | IP production сервера | `192.168.1.200` |
| `PRODUCTION_USER` | SSH пользователь | `deploy` |
| `PRODUCTION_SSH_KEY` | SSH приватный ключ | `-----BEGIN RSA PRIVATE KEY-----...` |

## Ручной запуск

1. Перейти на вкладку **Actions**
2. Выбрать workflow **🐳 Docker Compose CI/CD**
3. Нажать **Run workflow**
4. Выбрать ветку и нажать **Run workflow**

## Статусы

- 🟢 **Success** — все этапы пройдены
- 🔴 **Failed** — ошибка на этапе
- 🟡 **Cancelled** — отменено пользователем
