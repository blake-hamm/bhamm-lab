# Stage 1: Build MkDocs site with plugins
FROM python:3.11-alpine as builder

WORKDIR /docs
RUN pip install --no-cache-dir mkdocs mkdocs-material

COPY . .
RUN mkdocs build --strict --clean

# Stage 2: Serve with Nginx (with security hardening)
FROM nginx:1.25-alpine

# Remove default configs and copy ours
RUN rm -rf /etc/nginx/conf.d/*
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Make sure nginx user can read it
RUN chown root:nginx /etc/nginx/conf.d/default.conf \
    && chmod 644 /etc/nginx/conf.d/default.conf

# Copy static site (from your builder stage)
COPY --from=builder /docs/site /usr/share/nginx/html

# Security: Run as non-root user
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html

USER nginx

EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]