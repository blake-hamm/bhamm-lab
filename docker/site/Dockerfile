#####################################################################
#                            Build Stage                            #
#####################################################################
FROM docker.io/hugomods/hugo:exts AS builder

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
FROM docker.io/caddy:2-alpine

# Create non-root user for running caddy
RUN adduser -D -H -s /sbin/nologin -u 1000 caddyuser

# Copy the generated files
COPY --from=builder /src/public /usr/share/caddy

# Set proper ownership for the non-root user
RUN chown -R caddyuser:caddyuser /usr/share/caddy

# Use non-root user
USER caddyuser

# Caddy defaults to port 80, but non-root users can't bind to it
# The caddy:alpine image is configured to handle this automatically
# or you can override with environment variable if needed
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:80/"]
