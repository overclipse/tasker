# ====== Конфигурация проекта ======
APP_NAME      := tasker
BIN_DIR       := bin
BIN           := $(BIN_DIR)/$(APP_NAME)
PKG           := ./...

# Где лежат миграции и SQL-запросы для sqlc
MIGRATIONS_DIR := db/migrations
QUERIES_DIR    := db/queries

# Команды (можно переопределить переменными окружения)
DOCKER_COMPOSE := docker-compose          # если у тебя новая Docker Desktop, можешь поставить docker compose
GOOSE          := goose                   # будет вызываться как go run github.com/pressly/goose/v3/cmd/goose@latest, если не установлен
SQLC           := sqlc

# ====== Dotenv: автоматически подхватываем .env ======
# Если есть .env — подключим все пары KEY=VALUE в окружение целей make
ifneq (,$(wildcard .env))
	include .env
	export
endif

# Адреса БД из .env (нужны для миграций и psql)
# В .env это DATABASE_URL=postgres://tasker:tasker@localhost:5432/tasker?sslmode=disable
DB_URL        ?= $(DATABASE_URL)

# ====== Красивый help по умолчанию ======
.DEFAULT_GOAL := help

# Хелпер для форматированного вывода
HELP_FORMAT = printf "%-22s %s\n"

.PHONY: help
help: ## Показать список команд
	@echo "Команды Makefile:"
	@$(call HELP_FORMAT,up,               "Поднять инфраструктуру (Postgres, Redis)")
	@$(call HELP_FORMAT,down,             "Остановить и удалить контейнеры и тома")
	@$(call HELP_FORMAT,restart,          "Перезапустить инфраструктуру")
	@$(call HELP_FORMAT,logs,             "Логи всех сервисов docker-compose")
	@$(call HELP_FORMAT,psql,             "Подключиться к Postgres (psql) внутри контейнера")
	@$(call HELP_FORMAT,redis-cli,        "Открыть redis-cli в контейнере")
	@$(call HELP_FORMAT,wait-db,          "Подождать готовности Postgres")
	@$(call HELP_FORMAT,migrate-new,      "Создать пару миграций up/down (NAME=...)")
	@$(call HELP_FORMAT,migrate-up,       "Применить все новые миграции")
	@$(call HELP_FORMAT,migrate-down,     "Откатить одну миграцию (или COUNT=N)")
	@$(call HELP_FORMAT,migrate-goto,     "Перейти к конкретной версии (VERSION=timestamp)")
	@$(call HELP_FORMAT,migrate-status,   "Показать статус миграций")
	@$(call HELP_FORMAT,sqlc-gen,         "Сгенерировать Go-код из SQL (sqlc)")
	@$(call HELP_FORMAT,run,              "Запустить приложение (go run ./cmd/api)")
	@$(call HELP_FORMAT,build,            "Собрать бинарник в ./bin")
	@$(call HELP_FORMAT,tidy,             "go mod tidy")
	@$(call HELP_FORMAT,fmt,              "go fmt всех пакетов")
	@$(call HELP_FORMAT,vet,              "go vet всех пакетов")
	@$(call HELP_FORMAT,lint,             "Запустить golangci-lint (если установлен)")
	@$(call HELP_FORMAT,test,             "Запустить тесты")
	@$(call HELP_FORMAT,cover,            "Тесты с генерацией покрытия coverage.out")

# ====== Инфраструктура (Docker) ======
.PHONY: up down logs restart
up: ## Поднять Postgres и Redis в фоне
	$(DOCKER_COMPOSE) up -d

down: ## Остановить и удалить контейнеры и тома
	$(DOCKER_COMPOSE) down -v

logs: ## Логи всех сервисов
	$(DOCKER_COMPOSE) logs -f

restart: down up ## Перезапустить инфру

# ====== Утилиты к БД (в контейнерах) ======
.PHONY: psql redis-cli wait-db
psql: ## Открыть psql к Postgres в контейнере
	$(DOCKER_COMPOSE) exec -e PGPASSWORD=tasker postgres psql -U tasker -d tasker

redis-cli: ## Открыть redis-cli к Redis в контейнере
	$(DOCKER_COMPOSE) exec redis redis-cli

wait-db: ## Ждать готовности Postgres (используется перед миграциями)
	@echo "Жду готовности Postgres..."
	@$(DOCKER_COMPOSE) exec -T postgres bash -lc 'for i in {1..30}; do pg_isready -U tasker -d tasker && exit 0; sleep 1; done; exit 1'
	@echo "Postgres готов."

# ====== Миграции (goose) ======
# Если goose не установлен, можно вызывать так:
#   go run github.com/pressly/goose/v3/cmd/goose@latest <driver> <dsn> <cmd>
# Но удобнее поставить один раз: `go install github.com/pressly/goose/v3/cmd/goose@latest`

.PHONY: migrate-new migrate-up migrate-down migrate-goto migrate-status
migrate-new: ## Создать новую пару миграций: make migrate-new NAME=create_users
ifeq ($(strip $(NAME)),)
	$(error Укажи NAME, пример: make migrate-new NAME=create_users_table)
endif
	$(GOOSE) -dir $(MIGRATIONS_DIR) create $(NAME) sql

migrate-up: wait-db ## Применить все новые миграции
	$(GOOSE) -dir $(MIGRATIONS_DIR) postgres "$(DB_URL)" up

migrate-down: wait-db ## Откатить N миграций: make migrate-down COUNT=1 (по умолчанию 1)
	$(GOOSE) -dir $(MIGRATIONS_DIR) postgres "$(DB_URL)" down $(or $(COUNT),1)

migrate-goto: wait-db ## Перейти к конкретной версии: make migrate-goto VERSION=20240810123456
ifeq ($(strip $(VERSION)),)
	$(error Укажи VERSION, пример: make migrate-goto VERSION=20250813101010)
endif
	$(GOOSE) -dir $(MIGRATIONS_DIR) postgres "$(DB_URL)" goto $(VERSION)

migrate-status: wait-db ## Показать статус миграций
	$(GOOSE) -dir $(MIGRATIONS_DIR) postgres "$(DB_URL)" status

# ====== Генерация кода sqlc ======
# Поставь один раз: `go install github.com/sqlc-dev/sqlc/cmd/sqlc@latest`
.PHONY: sqlc-gen
sqlc-gen: ## Сгенерировать код репозиториев из SQL
	$(SQLC) generate

# ====== Приложение ======
.PHONY: run build tidy fmt vet
run: ## Запустить приложение локально
	go run ./cmd/api

build: ## Собрать бинарник в ./bin
	mkdir -p $(BIN_DIR)
	go build -o $(BIN) ./cmd/api

tidy: ## Привести модули в порядок
	go mod tidy

fmt: ## Форматировать код
	go fmt $(PKG)

vet: ## Анализатор статический
	go vet $(PKG)

# ====== Качество кода и тесты ======
# golangci-lint: `go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest`
.PHONY: lint test cover
lint: ## Линтеры (golangci-lint)
	@golangci-lint version >/dev/null 2>&1 || (echo "Установи golangci-lint: go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest" && exit 1)
	golangci-lint run

test: ## Запустить тесты
	go test $(PKG)

cover: ## Тесты с покрытием и кратким отчётом
	go test -coverprofile=coverage.out $(PKG)
	go tool cover -func=coverage.out | tail -n 1
