# Fix Traefik EndpointSlice Support for Ceph RGW Ingress

## Status
**Workaround applied** — `rgw-endpoints-all.yaml` reverted from `EndpointSlice` to legacy `Endpoints` API to restore ingress access immediately.

## Background
Traefik proxy **v3.0.4** (shipped with Helm chart v29.0.0) does **not** support `EndpointSlice` discovery. It only reads the deprecated `v1/Endpoints` API. After migrating `external-rgw` from `Endpoints` to `EndpointSlice` (to avoid K8s 1.33+ deprecation warnings), Traefik could no longer resolve backend IPs, causing:

```
error="endpoints not found for ceph/external-rgw"
```

This resulted in **404 Not Found** on `https://rgw.bhamm-lab.com` and broken restic / AWS CLI access through the ingress.

Direct RGW access (`10.0.20.11:7480`) remained healthy, confirming the issue was purely Traefik service discovery.

## Long-Term Solutions

### Option A: Upgrade Traefik Helm Chart (Recommended)
Upgrade to **Traefik Helm chart v31.1.1** (or newer). This chart defaults to Traefik proxy **v3.1.x/v3.2.x**, which natively supports `EndpointSlice` discovery and automatically generates the correct `discovery.k8s.io/endpointslices` RBAC.

**Why v31.1.1?**
- First stable line with full EndpointSlice support
- Avoids breaking changes in v33+ (entrypoint port `9000` → `8080`, `redirectTo` syntax refactor)
- Safe upgrade path from v29.0.0

**Migration steps:**
1. **Pre-flight CRD update** (Helm does not auto-upgrade CRDs):
   ```bash
   kubectl apply --server-side --force-conflicts \
     -k https://github.com/traefik/traefik-helm-chart/traefik/crds?ref=v31.1.1
   ```
2. **Update ArgoCD Application** (`kubernetes/manifests/base/traefik/helm-all.yaml`):
   ```yaml
   targetRevision: v31.1.1
   ```
3. **Sync and validate** on the inactive cluster (green/blue) first:
   ```bash
   # Verify proxy version
   kubectl get deployment traefik -n traefik -o jsonpath='{.spec.template.spec.containers[0].image}'

   # Verify EndpointSlice RBAC exists
   kubectl get clusterrole traefik-traefik -o yaml | grep -A5 endpointslices

   # Verify no "endpoints not found" errors
   kubectl logs -n traefik -l app.kubernetes.io/name=traefik --tail=100 | grep external-rgw

   # Test ingress
   curl -I https://rgw.bhamm-lab.com
   ```
4. **Revert the workaround** — switch `rgw-endpoints-all.yaml` back to `EndpointSlice`.
5. **Promote to the active cluster** after a reasonable soak period.

### Option B: Minimal Image Override (Lowest Risk)
Stay on chart `v29.0.0` but override the proxy image tag:

```yaml
# kubernetes/manifests/base/traefik/helm-all.yaml
image:
  tag: v3.1.7
```

The v29 chart detects `>= v3.1.0` and automatically swaps `endpoints` RBAC for `endpointslices` RBAC. You still must apply the v3.1 CRDs manually.

**Tradeoff:** Zero chart-breaking changes, but misses ~1.5 years of chart bug fixes and improvements.

## Post-Fix Cleanup
After upgrading Traefik, revert `kubernetes/manifests/base/ceph/rgw-endpoints-all.yaml` from `Endpoints` back to `EndpointSlice`:

```yaml
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: external-rgw
  namespace: ceph
  labels:
    kubernetes.io/service-name: external-rgw
  annotations:
    argocd.argoproj.io/sync-wave: "7"
addressType: IPv4
endpoints:
  - addresses:
      - 10.0.20.11
    conditions: {}
  - addresses:
      - 10.0.20.12
    conditions: {}
  - addresses:
      - 10.0.20.15
    conditions: {}
ports:
  - name: s3
    port: 7480
    protocol: TCP
```

## References
- Traefik EndpointSlice PR: [#10664](https://github.com/traefik/traefik/pull/10664)
- Traefik v3.0 → v3.1 migration: [doc.traefik.io/traefik/migration/v3/#v30-to-v31](https://doc.traefik.io/traefik/migration/v3/#v30-to-v31)
- Helm chart v29.0.0 conditional RBAC: [traefik/traefik-helm-chart#1099](https://github.com/traefik/traefik-helm-chart/pull/1099)
- Helm chart releases: [GitHub — traefik/traefik-helm-chart](https://github.com/traefik/traefik-helm-chart/releases)
