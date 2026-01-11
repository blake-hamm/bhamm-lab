# Stage 1: Build the Hugo site
FROM hugomods/hugo:base-non-root AS builder

# Set the working directory
WORKDIR /src

# Switch to the non-root user
USER hugo

# Copy the entire site content
COPY --chown=hugo:hugo . .

# Build the site
RUN hugo --minify

# Stage 2: Serve the built site with Nginx
FROM hugomods/hugo:nginx

# Copy the built site from the build stage
COPY --from=builder /src/public /site

# Expose port 80
EXPOSE 80
