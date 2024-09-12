# Vault


### `kuberenetes/core/vault/cr-raft.yaml`
This file defines the config that vault operator applies to our vault instance.

There is one vault AppRole that has access to `read_secrets`. This AppRole will retire a token id that needs to be (manually) updated in gitea action secrets `VAULT_SECRET_ID`. In the future, this could be automated by building a base/default gitea action runner container. To generate vault approle secret_id, run:
```bash
vault write -f auth/approle/role/default/secret-id
```
