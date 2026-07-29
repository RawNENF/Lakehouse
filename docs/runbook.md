# Runbook

## Adding the Rook toolbox (do this — you'll want it constantly)

Rook doesn't ship a `ceph` CLI pod by default in newer chart versions. Drop this in as
`apps/rook-ceph-cluster/manifests/toolbox.yaml` and let Argo CD pick it up:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rook-ceph-tools
  namespace: rook-ceph
spec:
  replicas: 1
  selector:
    matchLabels: { app: rook-ceph-tools }
  template:
    metadata:
      labels: { app: rook-ceph-tools }
    spec:
      containers:
        - name: rook-ceph-tools
          image: quay.io/ceph/ceph:v18.2.4
          command: ["/bin/bash", "-c", "sleep infinity"]
          env:
            - name: ROOK_CEPH_USERNAME
              valueFrom: { secretKeyRef: { name: rook-ceph-mon, key: ceph-username } }
            - name: ROOK_CEPH_SECRET
              valueFrom: { secretKeyRef: { name: rook-ceph-mon, key: ceph-secret } }
```

Then: `kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status`

## Health checks

| Check | Command |
|---|---|
| Argo CD app sync status | `kubectl get applications -n argocd` |
| All pods across cluster | `kubectl get pods -A` |
| Ceph cluster health | `kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status` |
| Ceph OSD tree (which disks are up) | `... -- ceph osd tree` |
| Bucket claim bound? | `kubectl -n lakehouse get obc iceberg-warehouse` |
| Trino coordinator logs | `kubectl -n lakehouse logs deploy/trino-coordinator` |
| Iceberg REST logs | `kubectl -n lakehouse logs deploy/iceberg-rest` |

## Common failures

**OSDs stuck in `Pending` / not showing up in `ceph osd tree`**
Almost always the loop devices. Check they're still attached: `losetup -a`. They don't
survive a host reboot — re-run `scripts/create-loop-devices.sh` and recreate the kind
cluster if you rebooted.

**`rook-ceph-cluster` Application stuck `OutOfSync` / CRDs not found**
The operator (which installs Ceph's CRDs) hasn't finished syncing yet. Wait for
`rook-ceph-operator` to be `Healthy` in Argo CD before `rook-ceph-cluster` can succeed —
Argo CD will keep retrying automatically, you don't need to intervene.

**`iceberg-rest` CrashLoopBackOff, complaining about Postgres connection**
Postgres pod isn't ready yet, or the PVC hasn't bound (check `ceph-rbd` StorageClass and
that `rook-csi-rbd-provisioner`/`rook-csi-rbd-node` secrets exist in `rook-ceph`
namespace — these are created by the Rook operator once Ceph is healthy, not before).

**`ObjectBucketClaim` never binds**
Check the `CephObjectStore` itself is healthy first:
`kubectl -n rook-ceph get cephobjectstore lakehouse-store -o yaml` — look at `.status`.
RGW pods (`rook-ceph-rgw-*`) need to be Running before a bucket can provision.

**Trino can't see the `iceberg` catalog**
Check `/etc/trino/catalog/iceberg.properties` actually mounted correctly:
`kubectl -n lakehouse exec deploy/trino-coordinator -- cat /etc/trino/catalog/iceberg.properties`

## Resource pressure (if you're on 16GB RAM)

Trim in this order, cheapest impact first:
1. Set `mon.count: 1` in `CephCluster` (loses quorum tolerance, fine for a solo POC)
2. Drop Trino worker replicas to 0 temporarily, query through the coordinator alone
   (`node-scheduler.include-coordinator=true` in the coordinator config if you do this)
3. Reduce JVM heap in `jvm.config` for Trino (`-Xmx512m`)

## Full teardown

```bash
kind delete cluster --name lakehouse
./scripts/teardown-loop-devices.sh
```

That's it — everything else (Argo CD, Rook, Postgres, etc.) lived inside the kind cluster
and goes with it.
