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
FROM docker.io/busybox:1.37.0

# Create non-root user
RUN adduser -D -H -s /sbin/nologin -u 1000 staticuser

# Copy the generated files
COPY --from=builder /src/public /var/www

# Set proper ownership
RUN chown -R staticuser:staticuser /var/www

# Switch to non-root user
USER staticuser

# Expose port 8080 (non-root can't bind to 80)
EXPOSE 8080

# Start busybox httpd
# -f: run in foreground
# -p: port to listen on
# -h: home directory for files
ENTRYPOINT ["httpd", "-f", "-p", "8080", "-h", "/var/www"]
