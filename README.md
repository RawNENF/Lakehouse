# Lakehouse-on-Kind

A simulated 3-node on-premises data lakehouse, built as a learning/POC project:

**kind (Kubernetes-in-Docker) → Rook-Ceph (S3-compatible object storage) → Iceberg REST Catalog → Trino (query engine)**,
fully GitOps'd with **Argo CD**.

> Note on "3 nodes": this uses `kind`, so the 3 nodes are Docker containers on a single host
> (your laptop), not 3 separate VMs. This is intentional — it's a lighter, faster way to
> simulate a multi-node cluster locally. See `docs/architecture.md` for the honest breakdown.

## What's in here

```
lakehouse/
├── docs/                  # Architecture + step-by-step setup guide + runbook
├── kind/                  # kind cluster definition (3 nodes + device mounts for Ceph)
├── scripts/               # Helper scripts (loop devices, bootstrap)
├── bootstrap/             # One-time Argo CD install + the "app of apps" root
├── apps/                  # Every component Argo CD manages, one folder each
│   ├── rook-ceph-operator/
│   ├── rook-ceph-cluster/
│   ├── postgres/
│   ├── iceberg-rest/
│   └── trino/
└── .github/workflows/     # CI: validates every manifest before Argo CD touches it
```

## Quickstart

Full instructions are in [`docs/setup-guide.md`](docs/setup-guide.md). Short version:

```bash
./scripts/create-loop-devices.sh        # 1. simulate raw disks for Ceph
kind create cluster --config kind/cluster-config.yaml   # 2. spin up the 3-node cluster
./bootstrap/install-argocd.sh           # 3. install Argo CD
kubectl apply -f bootstrap/root-app.yaml # 4. tell Argo CD to sync everything in apps/
```

From here on, **you don't run kubectl apply for your workloads again.** You edit YAML in
`apps/`, commit, push — Argo CD notices the drift and reconciles the cluster to match Git.
That's the whole point of GitOps.

## Read next

- [`docs/architecture.md`](docs/architecture.md) — what each piece is and why it's there
- [`docs/setup-guide.md`](docs/setup-guide.md) — the full walkthrough, in order
- [`docs/runbook.md`](docs/runbook.md) — how to check health, common failures, how to tear down
