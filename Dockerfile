# The site, as one image for amd64 and arm64 (a Raspberry Pi): qlang, git (the package worker reads
# repositories), the packages of qlang.lock and the project. It does not hold a secret: everything
# comes from the environment (DOC_*).
ARG QLANG_VERSION=1.12.2
FROM ghcr.io/quenti77/qlang:${QLANG_VERSION} AS qlang

FROM alpine:3.22
RUN apk add --no-cache git ca-certificates \
    && adduser -D -u 65532 app \
    && mkdir /app && chown app /app
COPY --from=qlang /usr/local/bin/qlang /usr/local/bin/qlang
USER app
ENV HOME=/tmp
WORKDIR /app
# the packages first: this layer is rebuilt only when qlang.toml or qlang.lock change
COPY --chown=app qlang.toml qlang.lock ./
RUN qlang install
COPY --chown=app . .
EXPOSE 8082
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:8082/ || exit 1
CMD ["qlang", "serve", "main.q", "--bind", "0.0.0.0", "--port", "8082", "--static", "public"]
