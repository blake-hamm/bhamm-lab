FROM python:3.10-slim AS builder

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

# Copy custom nginx configuration first
COPY nginx.conf /etc/nginx/nginx.conf
COPY default.conf /etc/nginx/conf.d/default.conf

# Copy built files from builder stage
COPY --from=builder /app/site /usr/share/nginx/html

# Remove default nginx config
RUN rm -f /etc/nginx/conf.d/default.conf.default

# Security hardening and set proper ownership
RUN addgroup -S nginx-group && \
    adduser -S -G nginx-group -s /sbin/nologin -H nginx-user && \
    mkdir -p /var/cache/nginx /var/run && \
    touch /var/run/nginx.pid && \
    chown -R nginx-user:nginx-group /var/cache/nginx /var/run/nginx.pid /usr/share/nginx/html /etc/nginx/conf.d /etc/nginx/nginx.conf && \
    chmod -R 755 /usr/share/nginx/html && \
    chmod -R 644 /etc/nginx/conf.d/* /etc/nginx/nginx.conf && \
    chmod 755 /etc/nginx/conf.d

# Create necessary directories with proper permissions
RUN mkdir -p /tmp/nginx/client-body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi && \
    chown -R nginx-user:nginx-group /tmp/nginx && \
    chmod 755 /tmp/nginx /tmp/nginx/client-body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi

# Switch to non-root user
USER nginx-user

EXPOSE 8080

# Use non-privileged port
CMD ["nginx", "-g", "daemon off;"]