# oneuptime-pathfinder

Installation repo for deploying [OneUptime](https://oneuptime.com) to AWS
using its official [Helm chart](https://artifacthub.io/packages/helm/oneuptime/oneuptime),
on a newly-provisioned Amazon EKS cluster.

## What's in here

| Path                        | What it does |
|------------------------------|--------------|
| `terraform/`                 | Terraform to create the VPC + EKS cluster (with the EBS CSI driver add-on) that OneUptime runs on. |
| `helm/values.yaml`           | Helm values file configuring OneUptime for a small/dev-sized deployment (built-in standalone Postgres/Redis/ClickHouse, single replicas, plain HTTP). |
| `helm/gp3-storageclass.yaml` | gp3 `StorageClass` manifest, set as the cluster default for database PVCs. |
| `docs/deploy-aws.md`         | Step-by-step instructions: provision the cluster, install the chart, and go to production. |

## Quick start

See [`docs/deploy-aws.md`](docs/deploy-aws.md) for full instructions. In short:

```console
cd terraform && terraform init && terraform apply
aws eks update-kubeconfig --region <region> --name <cluster-name>
kubectl apply -f ../helm/gp3-storageclass.yaml

helm repo add oneuptime https://helm-chart.oneuptime.com/
helm install my-oneuptime oneuptime/oneuptime -f ../helm/values.yaml --timeout 15m
```

## Assumptions made

This repo was generated based on the following choices (see
`docs/deploy-aws.md` "Next steps" for how to change them later):

- A **new** EKS cluster is provisioned via Terraform (rather than reusing an
  existing cluster).
- A **small/dev-sized** deployment: built-in standalone PostgreSQL, Redis and
  ClickHouse, single replicas — not the HA operator-backed production setup.
- **No custom domain yet** — OneUptime is served over plain HTTP via an
  internal ALB's hostname. Add a domain + TLS once you have one (see
  `docs/deploy-aws.md`).
- **Tagged for expense tracking** — every AWS resource created or used by
  OneUptime (VPC/EKS via Terraform, EBS volumes, and the ALB) is
  tagged `Project=oneuptime` / `CostTracking=oneuptime`, so its spend rolls up
  cleanly in Cost Explorer (see `docs/deploy-aws.md` "Tagging").
