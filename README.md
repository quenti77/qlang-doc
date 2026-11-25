# qlang-doc

The documentation site and the package registry of [qlang](https://github.com/quenti77/qlang), written in qlang.

- **Documentation**: pages in sections and folders, two locales, revisions with a diff, an audit log, a Markdown editor with a live preview, and a playground.
- **Registry**: packages read from public git repositories (tags, manifest, README), a submission queue, and the index in the format of `qlang search`.
- **Accounts**: a first administrator from the environment, public sign-up for members.

It needs qlang 1.12 or later, Docker (for Postgres) and `make`.

## Run it

```sh
make serve     # starts Postgres, migrates, seeds the administrator, serves on http://127.0.0.1:8082
make test      # runs the tests against a separate test database
make down      # stops Postgres
```

The development values are in the `Makefile` (they protect nothing). The administrator is `admin` with the password `DOC_ADMIN_PASSWORD`.

## Configuration

| Variable | Meaning | Default |
|---|---|---|
| `DOC_DATABASE_URL` | Postgres URL (required) | |
| `DOC_SESSION_SECRET` | secret of the session cookie, 32 characters at least (required) | |
| `DOC_ADMIN_LOGIN`, `DOC_ADMIN_PASSWORD` | first administrator, used by `seed.q` (password: 12 characters at least) | `admin` |
| `DOC_SECURE_COOKIES` | `1` behind HTTPS | off |
| `DOC_SUBMISSIONS` | `open` lets visitors submit packages | closed |
| `DOC_SIGNUP` | `closed` stops public sign-up | open |
| `DOC_GIT_HOSTS` | hosts accepted for packages | `github.com,gitlab.com,codeberg.org` |
| `DOC_HOOK_SECRET` | secret of the webhook that asks for a package to be read | empty |
| `DOC_BASE_URL` | public address of the site | `http://127.0.0.1:8082` |
| `DOC_VIEWS_DIR` | folder of the HTML views | `views` |
| `DOC_TEST_DATABASE_URL` | database of the tests | |

## Layout

| Path | Content |
|---|---|
| `main.q` | the web application (`qlang serve main.q --static public`) |
| `migrate.q`, `seed.q` | tables and first administrator, safe to run again |
| `src/Docs` | pages, sections, revisions, diff, audit log |
| `src/Registry` | packages, versions, submissions, git reading |
| `src/Markup` | Markdown rendering and syntax highlighting |
| `src/Web`, `src/App` | pages, routes, configuration, schema |
| `views`, `public` | HTML templates, CSS and JS, the playground |
| `tools` | imports and the package worker |

## Tools

All of them are safe to run again.

```sh
qlang run tools/import-tree.q -- fr ../qlang-learn/content/fr   # a folder of Markdown files
qlang run tools/import-index.q -- ../qlang/packages.json        # the packages of an index file
qlang run tools/split-generated.q                               # spread imported pages over the sections
qlang run --allow-process tools/sync-packages.q                 # read the git repositories (cron / systemd timer)
```

`sync-packages.q` is the only part that runs `git`, so that the web server never does. Run it every few minutes.

## Checks

```sh
qlang fmt --check
qlang lint .
qlang test --allow-process
```
