# Architecture

## The honest picture

You'll see "3-node cluster" in this repo. Be precise about what that means when you write
this up:

- The 3 nodes are **kind nodes** — each one is a Docker container, running on a single
  Docker host (your laptop). They are *not* 3 separate VMs.
- This is a deliberate simplification for local simulation. It's still a real, working
  multi-node Kubernetes cluster with real scheduling, real networking between nodes, and
  real distributed Ceph storage — it's just not physically distributed.
- If you later move this to 3 real VMs or 3 bare-metal boxes, almost nothing in `apps/`
  changes. You'd swap `kind/cluster-config.yaml` for a `kubeadm` bootstrap (or k3s), and
  the loop-device trick for real attached disks. Argo CD, Rook, Iceberg, and Trino configs
  stay the same. That portability is the point of doing this as GitOps from day one.

## Component by component

### 1. kind — the cluster itself

`kind/cluster-config.yaml` defines 1 control-plane + 2 workers. Each node gets an
`extraMounts` entry pointing at a loop-device-backed sparse file on the host, so Rook has
something that looks like a raw block device to claim as a Ceph OSD.

### 2. Rook-Ceph — distributed storage, running *inside* Kubernetes

Ceph doesn't know or care that its "disks" are loop devices — from its perspective it's
managing raw block storage across 3 nodes, same as it would on real hardware.

- `apps/rook-ceph-operator/` — the Rook operator (a Helm chart, deployed via Argo CD).
  It watches Ceph-related Custom Resources and translates them into running Ceph daemons.
- `apps/rook-ceph-cluster/` — the actual `CephCluster` and `CephObjectStore` custom
  resources. The `CephObjectStore` spins up RGW (RADOS Gateway), which is Ceph's
  **S3-compatible API**. This is the object storage endpoint Iceberg will write to.

Why Ceph instead of just using MinIO for S3-compatible storage? Because the brief is
specifically to prove out Ceph as the storage substrate — MinIO would be simpler but
wouldn't demonstrate the thing you're actually trying to learn/showcase.

### 3. Postgres — Iceberg catalog metadata store

Iceberg tables need a **catalog**: something that tracks "which files currently make up
table X". The catalog itself is small, transactional metadata — perfect fit for Postgres.
`apps/postgres/` is a minimal single-replica Postgres, not meant to be production-grade
(no HA, no backups configured yet — flagged in the runbook).

### 4. Iceberg REST Catalog

`apps/iceberg-rest/` runs Tabular's open-source `iceberg-rest-fixture` image, which speaks
the Iceberg REST Catalog protocol. Trino (and Spark, if you add it later) talk to this
service instead of talking to Postgres directly. It reads/writes catalog state to Postgres,
and points table data at Ceph RGW (via S3A-style config: endpoint, access key, secret key).

### 5. Trino — the query engine

`apps/trino/` is a coordinator + 1 worker. Its `iceberg` catalog properties file points at
the REST catalog service and at the Ceph RGW S3 endpoint. Once this is up, you query
Iceberg tables with plain SQL through Trino.

### 6. Argo CD — GitOps controller

`bootstrap/root-app.yaml` is the one manifest you apply by hand, ever. It's an
"app of apps" — an Argo CD `Application` whose only job is to watch the `apps/` directory
in this repo and create one child `Application` per subfolder. From then on:

```
git push  →  Argo CD detects drift  →  Argo CD reconciles cluster state to match Git
```

No more manual `kubectl apply`. If you want to change how many Trino workers you have, you
edit a YAML file in `apps/trino/`, commit, push, and Argo CD does the rest.

## Data flow, end to end

```
   Trino (SQL query)
        │
        ▼
  Iceberg REST Catalog ──── metadata ────▶ Postgres
        │
        ▼ (table data: parquet/avro files)
   Ceph RGW (S3 API)
        │
        ▼
   Ceph OSDs (loop devices on 3 kind nodes)
```

## Known limitations of this simulation (be upfront about these)

- Single Docker host = single point of failure for the whole "cluster." Real fault
  tolerance testing (killing a node and watching Ceph rebalance) needs real VMs or hosts.
- Loop-device OSDs are much slower than real disks and not persistent-storage-grade —
  fine for learning Ceph's *behavior*, not for benchmarking performance.
- Postgres and the REST catalog are single-replica here — no HA. Fine for a POC.
