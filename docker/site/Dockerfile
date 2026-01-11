# Stage 1: Build the Hugo site
FROM hugomods/hugo:exts AS builder

# Copy the entire site content
COPY . /src

# Build the site
RUN hugo --minify

# Stage 2: Serve the built site with Nginx
FROM hugomods/hugo:nginx

# Copy the built site from the build stage
COPY --from=builder /src/public /site
