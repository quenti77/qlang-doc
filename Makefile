# Development values only: nothing here is a secret that protects anything.
export DOC_DB_PORT ?= 5442
export DOC_DATABASE_URL ?= postgres://qlang_doc:qlang-doc-dev-only@127.0.0.1:$(DOC_DB_PORT)/qlang_doc
export DOC_TEST_DATABASE_URL ?= postgres://qlang_doc:qlang-doc-dev-only@127.0.0.1:$(DOC_DB_PORT)/qlang_doc_test
export DOC_SESSION_SECRET ?= dev-only-session-secret-of-32-characters
export DOC_ADMIN_LOGIN ?= admin
export DOC_ADMIN_PASSWORD ?= dev-only-admin-password
export DOC_BIND ?= 127.0.0.1
export DOC_PORT ?= 8082

.PHONY: db test-db migrate seed serve test down

db:
	docker compose up -d --wait db

migrate: db
	qlang run migrate.q

seed: migrate
	qlang run seed.q

serve: seed
	qlang serve main.q --bind $(DOC_BIND) --port $(DOC_PORT) --static public --dev --watch

test-db: db
	@docker compose exec -T db psql -U qlang_doc -d qlang_doc -tc "SELECT 1 FROM pg_database WHERE datname = 'qlang_doc_test'" | grep -q 1 || docker compose exec -T db createdb -U qlang_doc qlang_doc_test

test: test-db
	qlang test

down:
	docker compose down
