# Setup Guide

Do these in order. Each step assumes the previous one succeeded — don't skip ahead.

## 0. Prerequisites

Install on your laptop (host, not inside any VM):

- Docker (kind runs nodes as Docker containers)
- `kind` — https://kind.sigs.k8s.io/docs/user/quick-start/#installation
- `kubectl`
- `helm` (only needed if you want to inspect/template charts locally; Argo CD handles the actual install)
- `git`, and a GitHub account with a new empty repo created (e.g. `lakehouse`)

Sanity check:
```bash
docker version
kind version
kubectl version --client
```

## 1. Push this repo to GitHub

```bash
cd lakehouse
git init
git add .
git commit -m "Initial lakehouse scaffold"
git branch -M main
git remote add origin https://github.com/YOUR-GITHUB-USERNAME/lakehouse.git
git push -u origin main
```

Then **go edit every file that has `YOUR-GITHUB-USERNAME` in it** (search with
`grep -rl YOUR-GITHUB-USERNAME .`) and replace it with your actual repo URL. Commit and
push that fix before continuing — Argo CD needs the real URL to find this repo.

## 2. Create the simulated disks

```bash
chmod +x scripts/*.sh bootstrap/*.sh
./scripts/create-loop-devices.sh
```

This creates 3 sparse files under `/var/lib/lakehouse-disks/`, attaches each as a loop device,
and regenerates `kind/cluster-config.yaml` from the template with the real `/dev/loopN`
paths. You'll need `sudo` for `losetup`.

## 3. Create the kind cluster

```bash
kind create cluster --config kind/cluster-config.yaml
kubectl get nodes   # should show 3 nodes: lakehouse-control-plane, lakehouse-worker, lakehouse-worker2
```

## 4. Install Argo CD (the only manual kubectl step, ever)

```bash
./bootstrap/install-argocd.sh
```

Follow the printed instructions to port-forward and log into the UI if you want to watch
things sync visually (recommended for your first run — seeing Rook/Ceph come up live is
genuinely useful for understanding what's happening).

## 5. Hand the rest of the cluster over to GitOps

```bash
kubectl apply -f bootstrap/root-app.yaml
```

From this point on, Argo CD will:
1. See the `root` Application, which watches `apps/`
2. Discover 5 child Applications (rook-ceph-operator, rook-ceph-cluster, postgres,
   iceberg-rest, trino)
3. Sync each one in dependency order roughly as follows — **note that Argo CD does not
   automatically sequence dependencies for you**, so expect `rook-ceph-cluster`,
   `postgres`, `iceberg-rest`, and `trino` to all attempt to sync immediately and some to
   fail/retry until their dependencies are ready. This is normal. Argo CD's `selfHeal` will
   keep retrying. Watch it settle over 5-10 minutes.

Watch progress:
```bash
kubectl get applications -n argocd
watch kubectl get pods -A
```

## 6. Verify Ceph is healthy

```bash
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
```
(If `rook-ceph-tools` isn't there yet, you may need to add the Rook toolbox — see the
runbook for a quick manifest to drop in under `apps/rook-ceph-cluster/manifests/`.)

You want to see `HEALTH_OK` and 3 OSDs up/in.

## 7. Verify the object store and bucket

```bash
kubectl -n lakehouse get secret iceberg-warehouse -o yaml
kubectl -n lakehouse get configmap iceberg-warehouse -o yaml
```
You should see `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` in the secret and bucket
host/port info in the configmap. If these don't exist, the `ObjectBucketClaim` hasn't
bound yet — check `kubectl -n lakehouse describe obc iceberg-warehouse`.

## 8. Query through Trino

```bash
kubectl -n lakehouse port-forward svc/trino-coordinator 8080:8080
```
Then, in another terminal (using the Trino CLI, or any SQL client that speaks the Trino
protocol):
```sql
SHOW CATALOGS;
CREATE SCHEMA iceberg.demo;
CREATE TABLE iceberg.demo.hello (id INT, msg VARCHAR);
INSERT INTO iceberg.demo.hello VALUES (1, 'lakehouse is alive');
SELECT * FROM iceberg.demo.hello;
```

If that select comes back with a row, the entire chain — Trino → Iceberg REST Catalog →
Postgres (metadata) + Ceph RGW (data) → Ceph OSDs — is working end to end.

## From here on: the GitOps workflow

Want to change anything? Don't `kubectl edit`. Instead:
1. Edit the relevant YAML under `apps/`
2. `git commit && git push`
3. Argo CD notices within its poll interval (default 3 min, or force it in the UI/CLI)
   and reconciles the live cluster to match

This is the habit worth building now, because it's the actual point of the exercise.
