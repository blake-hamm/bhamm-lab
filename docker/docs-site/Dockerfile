FROM harbor.bhamm-lab.com/dockerhub/python:3.11-alpine

COPY . .

RUN pip install --no-cache-dir mkdocs mkdocs-material

RUN mkdocs build

EXPOSE 8000

CMD ["mkdocs", "serve", "--dev-addr", "0.0.0.0:8000"]