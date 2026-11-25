import "@std/web/migrate.q" as migrate

--" The schema, in order. An id that was applied is never run again: add a migration, never edit one. Times are
milliseconds since 1970 in a BIGINT (every driver reads those the same way). --"
fun all_migrations() -> array<migrate.Migration>
    [
        migrate.Migration {
            id: "001_users",
            up: [
                "CREATE TABLE users (
                    id BIGSERIAL PRIMARY KEY,
                    login VARCHAR(100) NOT NULL UNIQUE,
                    password_hash VARCHAR(255) NOT NULL,
                    role VARCHAR(20) NOT NULL DEFAULT 'editor',
                    created_at BIGINT NOT NULL
                )",
            ],
            down: ["DROP TABLE users"],
        },
        migrate.Migration {
            id: "002_documentation",
            up: [
                "CREATE TABLE folders (
                    id BIGSERIAL PRIMARY KEY,
                    parent_id BIGINT REFERENCES folders(id),
                    locale VARCHAR(5) NOT NULL,
                    slug VARCHAR(120) NOT NULL,
                    title VARCHAR(200) NOT NULL,
                    position INTEGER NOT NULL DEFAULT 0,
                    created_at BIGINT NOT NULL
                )",
                "CREATE UNIQUE INDEX folders_slug ON folders (locale, COALESCE(parent_id, 0), slug)",
                "CREATE TABLE pages (
                    id BIGSERIAL PRIMARY KEY,
                    folder_id BIGINT REFERENCES folders(id),
                    locale VARCHAR(5) NOT NULL,
                    slug VARCHAR(120) NOT NULL,
                    title VARCHAR(200) NOT NULL,
                    markdown TEXT NOT NULL,
                    html TEXT NOT NULL,
                    toc TEXT NOT NULL DEFAULT '[]',
                    position INTEGER NOT NULL DEFAULT 0,
                    revision INTEGER NOT NULL DEFAULT 1,
                    created_at BIGINT NOT NULL,
                    updated_at BIGINT NOT NULL,
                    updated_by BIGINT REFERENCES users(id)
                )",
                "CREATE UNIQUE INDEX pages_slug ON pages (locale, COALESCE(folder_id, 0), slug)",
                "CREATE TABLE page_revisions (
                    id BIGSERIAL PRIMARY KEY,
                    page_id BIGINT NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
                    number INTEGER NOT NULL,
                    title VARCHAR(200) NOT NULL,
                    markdown TEXT NOT NULL,
                    source VARCHAR(20) NOT NULL,
                    summary VARCHAR(300) NOT NULL DEFAULT '',
                    author_id BIGINT REFERENCES users(id),
                    created_at BIGINT NOT NULL,
                    UNIQUE (page_id, number)
                )",
            ],
            down: ["DROP TABLE page_revisions", "DROP TABLE pages", "DROP TABLE folders"],
        },
        migrate.Migration {
            id: "003_releases",
            up: [
                "CREATE TABLE releases (
                    id BIGSERIAL PRIMARY KEY,
                    label VARCHAR(50) NOT NULL UNIQUE,
                    qlang_version VARCHAR(50) NOT NULL,
                    note VARCHAR(500) NOT NULL DEFAULT '',
                    created_by BIGINT REFERENCES users(id),
                    created_at BIGINT NOT NULL
                )",
                "CREATE TABLE release_folders (
                    release_id BIGINT NOT NULL REFERENCES releases(id) ON DELETE CASCADE,
                    locale VARCHAR(5) NOT NULL,
                    path VARCHAR(500) NOT NULL,
                    title VARCHAR(200) NOT NULL,
                    position INTEGER NOT NULL,
                    PRIMARY KEY (release_id, locale, path)
                )",
                "CREATE TABLE release_pages (
                    release_id BIGINT NOT NULL REFERENCES releases(id) ON DELETE CASCADE,
                    locale VARCHAR(5) NOT NULL,
                    path VARCHAR(500) NOT NULL,
                    title VARCHAR(200) NOT NULL,
                    markdown TEXT NOT NULL,
                    html TEXT NOT NULL,
                    toc TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    PRIMARY KEY (release_id, locale, path)
                )",
                "CREATE TABLE settings (
                    name VARCHAR(100) PRIMARY KEY,
                    value VARCHAR(500) NOT NULL
                )",
            ],
            down: ["DROP TABLE settings", "DROP TABLE release_pages", "DROP TABLE release_folders", "DROP TABLE releases"],
        },
        migrate.Migration {
            id: "004_audit",
            up: [
                "CREATE TABLE audit_logs (
                    id BIGSERIAL PRIMARY KEY,
                    user_id BIGINT REFERENCES users(id),
                    action VARCHAR(60) NOT NULL,
                    entity_type VARCHAR(30) NOT NULL,
                    entity_id BIGINT,
                    summary VARCHAR(300) NOT NULL,
                    data TEXT NOT NULL DEFAULT '\{\}',
                    created_at BIGINT NOT NULL
                )",
                "CREATE INDEX audit_logs_created ON audit_logs (created_at DESC)",
                "CREATE INDEX audit_logs_entity ON audit_logs (entity_type, entity_id)",
            ],
            down: ["DROP TABLE audit_logs"],
        },
        migrate.Migration {
            id: "005_packages",
            up: [
                "CREATE TABLE packages (
                    id BIGSERIAL PRIMARY KEY,
                    name VARCHAR(100) NOT NULL UNIQUE,
                    git_url VARCHAR(500) NOT NULL,
                    description VARCHAR(500) NOT NULL DEFAULT '',
                    license VARCHAR(50) NOT NULL DEFAULT '',
                    keywords TEXT NOT NULL DEFAULT '[]',
                    readme_html TEXT NOT NULL DEFAULT '',
                    removed_reason VARCHAR(500),
                    owner_id BIGINT REFERENCES users(id),
                    synced_at BIGINT
                )",
                "CREATE TABLE package_versions (
                    id BIGSERIAL PRIMARY KEY,
                    package_id BIGINT NOT NULL REFERENCES packages(id) ON DELETE CASCADE,
                    version VARCHAR(50) NOT NULL,
                    commit_sha VARCHAR(64) NOT NULL,
                    yanked BOOLEAN NOT NULL DEFAULT false,
                    released_at BIGINT,
                    UNIQUE (package_id, version)
                )",
            ],
            down: ["DROP TABLE package_versions", "DROP TABLE packages"],
        },
        migrate.Migration {
            id: "006_registry_moderation",
            up: [
                "ALTER TABLE packages ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'listed'",
                "ALTER TABLE packages ADD COLUMN latest_version VARCHAR(50) NOT NULL DEFAULT ''",
                "ALTER TABLE packages ADD COLUMN sync_requested BOOLEAN NOT NULL DEFAULT false",
                "ALTER TABLE packages ADD COLUMN sync_error VARCHAR(500) NOT NULL DEFAULT ''",
                "ALTER TABLE packages ADD COLUMN created_at BIGINT NOT NULL DEFAULT 0",
                "ALTER TABLE package_versions ADD COLUMN qlang_req VARCHAR(50) NOT NULL DEFAULT ''",
                "ALTER TABLE package_versions ADD COLUMN first_seen BIGINT NOT NULL DEFAULT 0",
                "CREATE INDEX packages_status ON packages (status)",
            ],
            down: [
                "ALTER TABLE package_versions DROP COLUMN first_seen",
                "ALTER TABLE package_versions DROP COLUMN qlang_req",
                "ALTER TABLE packages DROP COLUMN created_at",
                "ALTER TABLE packages DROP COLUMN sync_error",
                "ALTER TABLE packages DROP COLUMN sync_requested",
                "ALTER TABLE packages DROP COLUMN latest_version",
                "ALTER TABLE packages DROP COLUMN status",
            ],
        },
    ]
end

export all_migrations
