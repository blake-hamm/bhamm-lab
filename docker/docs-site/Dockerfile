FROM harbor.bhamm-lab.com/dockerhub/python:3.12-alpine

WORKDIR /docs

COPY . .

RUN pip install --no-cache-dir mkdocs mkdocs-material \
  && chown 1000:1000 /docs/mkdocs.yml /docs/docs -R \
  && mkdocs build

EXPOSE 8000

CMD ["mkdocs", "serve", "--dev-addr", "0.0.0.0:8000"]