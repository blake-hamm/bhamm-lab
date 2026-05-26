#####################################################################
#                            Build Stage                            #
#####################################################################
FROM docker.io/hugomods/hugo:nightly AS builder

WORKDIR /src
COPY . .

# Build site with minification
RUN hugo --minify

# Set the fallback 404 page if defaultContentLanguageInSubdir is enabled,
# please replace the `en` with your default language code.
# RUN cp ./public/en/404.html ./public/404.html

#####################################################################
#                            Final Stage                            #
#####################################################################
FROM docker.io/caddy:2.11.3-alpine

# Create non-root user
RUN adduser -D -H -s /sbin/nologin -u 1000 caddy

COPY --from=builder /src/public /usr/share/caddy

# Caddyfile: serve static files, port 8080, proper MIME types built-in
RUN cat > /etc/caddy/Caddyfile <<'EOF'
:8080 {
    root * /usr/share/caddy
    file_server
    log {
        output discard
    }
}
EOF

RUN chown -R caddy:caddy /usr/share/caddy /etc/caddy

USER caddy

EXPOSE 8080

ENTRYPOINT ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
