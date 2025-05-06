FROM python:3.11-slim AS builder

WORKDIR /app

# Install required dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy mkdocs files
COPY . .

# Build static site
RUN mkdocs build

# Use nginx to serve static files
FROM nginx:1.28-alpine

# Security hardening
RUN apk add --no-cache shadow && \
    groupadd -r nginx-group && \
    useradd -r -g nginx-group -s /sbin/nologin -c "Nginx user" nginx-user && \
    touch /var/run/nginx.pid && \
    chown -R nginx-user:nginx-group /var/cache/nginx /var/run/nginx.pid

# Copy custom nginx configuration
COPY default.conf /etc/nginx/conf.d/default.conf

# Copy built files from builder stage
COPY --from=builder /app/site /usr/share/nginx/html

# Remove default nginx config and use custom one
RUN rm -f /etc/nginx/conf.d/default.conf.default

# Security headers and configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Set proper ownership
RUN chown -R nginx-user:nginx-group /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html

# Switch to non-root user
USER nginx-user

EXPOSE 8080

# Use non-privileged port
CMD ["nginx", "-g", "daemon off;"]