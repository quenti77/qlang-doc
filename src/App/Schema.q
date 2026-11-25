import "@std/web/migrate.q" as migrate

--" The schema, in order. An id that was applied is never run again: add a migration, never edit one. --"
fun all_migrations() -> array<migrate.Migration>
    [
        migrate.Migration {
            id: "001_users",
            up: [
                "CREATE TABLE users (
                    id BIGSERIAL PRIMARY KEY,
                    login VARCHAR(100) NOT NULL UNIQUE,
                    password_hash VARCHAR(255) NOT NULL,
                    role VARCHAR(20) NOT NULL DEFAULT 'member',
                    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
                )",
            ],
            down: ["DROP TABLE users"],
        },
        migrate.Migration {
            id: "002_pages",
            up: [
                "CREATE TABLE pages (
                    id BIGSERIAL PRIMARY KEY,
                    locale VARCHAR(5) NOT NULL,
                    slug VARCHAR(200) NOT NULL,
                    parent_id BIGINT REFERENCES pages(id) ON DELETE SET NULL,
                    position INTEGER NOT NULL DEFAULT 0,
                    title VARCHAR(200) NOT NULL,
                    markdown TEXT NOT NULL,
                    html TEXT NOT NULL,
                    published BOOLEAN NOT NULL DEFAULT false,
                    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                    UNIQUE (locale, slug)
                )",
            ],
            down: ["DROP TABLE pages"],
        },
        migrate.Migration {
            id: "003_packages",
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
                    owner_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
                    synced_at TIMESTAMPTZ
                )",
                "CREATE TABLE package_versions (
                    id BIGSERIAL PRIMARY KEY,
                    package_id BIGINT NOT NULL REFERENCES packages(id) ON DELETE CASCADE,
                    version VARCHAR(50) NOT NULL,
                    commit_sha VARCHAR(64) NOT NULL,
                    yanked BOOLEAN NOT NULL DEFAULT false,
                    released_at TIMESTAMPTZ,
                    UNIQUE (package_id, version)
                )",
            ],
            down: ["DROP TABLE package_versions", "DROP TABLE packages"],
        },
    ]
end

export all_migrations
