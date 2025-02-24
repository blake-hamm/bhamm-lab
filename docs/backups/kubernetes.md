# Kubernetes backups


## k8up


## Velero (Decomissioned)
Originally, I thought velero would work for backups, but this is not the case. Because I manage my manifests with gitops, I can easily guarantee that my cluster will bootstrap and restore state. However, what I cannot guaruntee is that the pv and pvc will be restored. They will be provisioned by argocd - no problem, but the underlying data will be new and historical data is lost.

This is a common problem and velero currently has no solution as outlined in this gh issue - https://github.com/vmware-tanzu/velero/issues/7345.
