# Kubernetes backups

## k8up
k8up backups are used for pvc and tested with the `test` application. They require pvc to be labeled with `k8up.io/backup: "true"` and guarantee that data can be backed up on a schedule and restored. This can be configured in the `common` helm chart and more details can be found in the deployments/helm section of these docs. Specifically, you will need these values:
```yaml
k8up:
  backup:
    enabled: true
  restore:
    enabled: true
```

## Minio [Depreciated]
*Determined that this minio backups are functioning correctly.*
I have discovered that backing up and restoring the pvc of minio will not suffice.. I need to re-visit this, but ultimately, I plan to backup minio with k8up as a s3 to s3 backup. This will restore all data in minio (while not necessarily restoring the minio config). In the future, I need to better understand how to backup the config (like authelia settings). For now, in a DR, I will need to take some manual steps to recover minio fully.

## Velero [Depreciated]
Originally, I thought velero would work for backups, but this is not the case. Because I manage my manifests with gitops, I can easily guarantee that my cluster will bootstrap and restore state. However, what I cannot guaruntee is that the pv and pvc will be restored. They will be provisioned by argocd - no problem, but the underlying data will be new and historical data is lost.

This is a common problem and velero currently has no solution as outlined in this gh issue - https://github.com/vmware-tanzu/velero/issues/7345.
