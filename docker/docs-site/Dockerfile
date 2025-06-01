FROM python:3.10-slim AS builder

WORKDIR /app
COPY . .
RUN pip install -r requirements.txt
RUN mkdocs build

FROM nginx:alpine

COPY --from=builder /app/site /usr/share/nginx/html
COPY default.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]