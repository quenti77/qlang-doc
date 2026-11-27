# Deploy on a server (Raspberry Pi, Caddy in front)

Needs Docker with the compose plugin, and a reverse proxy that serves HTTPS (Caddy).

## 1. Files on the server

```sh
mkdir -p ~/qlang-doc && cd ~/qlang-doc
curl -fsSLO https://raw.githubusercontent.com/quenti77/qlang-doc/main/docker-compose.prod.yml
curl -fsSL https://raw.githubusercontent.com/quenti77/qlang-doc/main/deploy/env.example -o .env
chmod 600 .env
```

Fill `.env`: `DOC_DB_PASSWORD`, `DOC_SESSION_SECRET` and `DOC_ADMIN_PASSWORD` are required (`openssl rand -hex 32` makes a good secret), `DOC_BASE_URL` is the public address. Sign-up and package submissions stay closed until `DOC_SIGNUP` and `DOC_SUBMISSIONS` say otherwise.

## 2. The image

The package of a repository is private on ghcr.io until you change it. Either make it public (GitHub, the repository, *Packages*, `qlang-doc`, *Package settings*, *Change visibility*; the image holds no secret), or log in on the server with a token that has `read:packages`:

```sh
echo "$TOKEN" | docker login ghcr.io -u quenti77 --password-stdin
```

## 3. Start

```sh
docker compose -f docker-compose.prod.yml up -d
docker compose -f docker-compose.prod.yml ps        # site: healthy, setup: Exited (0)
curl -I http://127.0.0.1:8082/                      # 200
```

## 4. Caddy

```
doc.easyweb-quality.fr {
    reverse_proxy 127.0.0.1:8082
}
```

If Caddy runs in a container, `127.0.0.1` is the container itself: put it on the same Docker network as `site` and use `reverse_proxy site:8082`, or use the address of the host (`host.docker.internal` with `extra_hosts: ["host.docker.internal:host-gateway"]`).

## Update, logs, backup

```sh
docker compose -f docker-compose.prod.yml pull && docker compose -f docker-compose.prod.yml up -d
docker compose -f docker-compose.prod.yml logs -f site
docker compose -f docker-compose.prod.yml exec db pg_dump -U qlang_doc qlang_doc > backup-$(date +%F).sql
```

`DOC_TAG` in `.env` pins an image (`sha-1234567`) instead of `latest`, to go back to a version that worked.
