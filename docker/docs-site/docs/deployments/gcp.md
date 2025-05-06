# GCP
This manages my gcp resources.

```bash
tofu -chdir=tofu/gcp init
tofu -chdir=tofu/gcp plan
tofu -chdir=tofu/gcp apply -auto-approve
```