# Stage 1: Build MkDocs site with plugins
FROM python:3.11-alpine AS builder
WORKDIR /docs
RUN pip install --no-cache-dir mkdocs mkdocs-material
COPY . .
RUN mkdocs build --strict --clean

# Stage 2: Serve with Nginx (with security hardening)
FROM nginx:1.28-alpine

# 1) Replace the main nginx.conf so we can pull in mime.types globally
COPY nginx.conf /etc/nginx/nginx.conf

# 2) Remove default vhosts, then add ours
RUN rm -rf /etc/nginx/conf.d/*
COPY default.conf /etc/nginx/conf.d/default.conf

# 3) Copy the MkDocs-built site into the Nginx html directory
COPY --from=builder /docs/site /usr/share/nginx/html

# 4) Fix permissions on all configs and site files
RUN \
  chown root:nginx /etc/nginx/nginx.conf && \
  chmod 644       /etc/nginx/nginx.conf && \
  chown root:nginx /etc/nginx/conf.d/default.conf && \
  chmod 644       /etc/nginx/conf.d/default.conf && \
  chown -R nginx:nginx /usr/share/nginx/html && \
  chmod -R 755       /usr/share/nginx/html

USER nginx
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
