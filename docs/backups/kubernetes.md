# Kubernetes backups

## k8up
k8up backups are used for pvc and tested with the 'example' application. They require pvc to be labeled with `k8up.io/backup: "true"` and guarantee that data can be backed up on a schedule and restored. This can be configured in the 'common' helm chart and more details can be found in the deployments/helm section of these docs.

## Cloudnative pg
For postgres, backups are orchestrated with the cloudnative pg operator. This can be configured with the common helm chart. One thing to note: *these backups require a volumesnapshot.* I still need to ensure a 'new' cluster is able to restore a cloudnative pg. Theoritically, these are the steps:
- Create new cluster w/ ceph storage class and csi
- Restore volume snapshot resource from ceph directly (w/ manifest)
- Deploy cloudnative pg with recovery config

## Velero (Decomissioned)
Originally, I thought velero would work for backups, but this is not the case. Because I manage my manifests with gitops, I can easily guarantee that my cluster will bootstrap and restore state. However, what I cannot guaruntee is that the pv and pvc will be restored. They will be provisioned by argocd - no problem, but the underlying data will be new and historical data is lost.

This is a common problem and velero currently has no solution as outlined in this gh issue - https://github.com/vmware-tanzu/velero/issues/7345.
