#####################################################################
#                            Build Stage                            #
#####################################################################
FROM docker.io/hugomods/hugo:0.163.1 AS builder

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
FROM docker.io/caddy:2.11.4-alpine@sha256:77c07d5ebfa5be9fd6c820d2094ae662c9e7eeb9bf98346b7f639900263ee2a2

# Create non-root user
RUN adduser -D -H -s /sbin/nologin -u 1000 caddy

COPY --from=builder /src/public /usr/share/caddy

# Caddyfile: serve static files, port 8080, proper MIME types built-in
RUN printf ':8080 {\n\troot * /usr/share/caddy\n\tfile_server\n\tlog {\n\t\toutput discard\n\t}\n}\n' > /etc/caddy/Caddyfile

RUN chown -R caddy:caddy /usr/share/caddy /etc/caddy

USER caddy

EXPOSE 8080

ENTRYPOINT ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
