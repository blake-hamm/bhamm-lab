# Docs
This directory contains the mkdocs markdown files. This collection of .md files is then served with nginx at `docs.bhamm-lab.com`.

*Ultimately, this will be the only publicly exposed site - more to come...*

### Local deployment
```nix-shell
mkdocs build
mkdocs serve
```

### CD deployment
Deployment is handled by the github action `mkdocs.yaml`. This action will rebuild the docs and copy them to the kubernetes pod serving them.
