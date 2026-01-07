# Stage 1: Build the Hugo site
FROM hugomods/hugo:base-non-root AS build

# Set the working directory
WORKDIR /src

# Copy the entire site content
COPY . .

# Build the site
RUN hugo --minify

# Stage 2: Serve the built site with Nginx
FROM nginx:alpine

# Copy the built site from the build stage
COPY --from=build /src/public /usr/share/nginx/html

# Expose port 80
EXPOSE 80
