# Development values only: nothing here is a secret that protects anything.
export DOC_DB_PORT ?= 5442
export DOC_DATABASE_URL ?= postgres://qlang_doc:qlang-doc-dev-only@127.0.0.1:$(DOC_DB_PORT)/qlang_doc
export DOC_SESSION_SECRET ?= dev-only-session-secret-of-32-characters
export DOC_BIND ?= 127.0.0.1
export DOC_PORT ?= 8082

.PHONY: db migrate serve test down

db:
	docker compose up -d --wait db

migrate: db
	qlang run migrate.q

serve: migrate
	qlang serve main.q --bind $(DOC_BIND) --port $(DOC_PORT) --static public --dev --watch

test:
	qlang test

down:
	docker compose down
