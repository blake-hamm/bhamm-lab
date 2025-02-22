```bash
# To encrypt sops file
sops -e secrets.decrypted.json > secrets.enc.json

# To decrypt sops file
sops -d secrets.enc.json > secrets.decrypted.json
```