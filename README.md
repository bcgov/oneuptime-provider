# oneuptime-pathfinder

Installation repo for deploying [OneUptime](https://oneuptime.com) to AWS
on **Amazon ECS/Fargate** — no Kubernetes, all Terraform.

## What's in here

| Path                                | What it does |
|--------------------------------------|--------------|
| `terraform/`                         | Terraform for the full ECS/Fargate stack: cluster, internal ALB, Aurora PostgreSQL, ElastiCache Redis, self-hosted ClickHouse (Fargate + EFS), and the OneUptime ECS services (`nginx`, `app`, `home`, `worker`, `probe`, `runner`). |
| `docs/deploy-aws.md`                 | Step-by-step deployment runbook — **you run every command yourself**. |
| `docs/deploy-aws-fargate-plan.md`    | Design plan/rationale for the ECS architecture (superseded once fully implemented — kept for context). |
| `docs/aws-resources.md`              | Inventory of every AWS resource this repo creates, plus a cost estimate. |

## Quick start

See [`docs/deploy-aws.md`](docs/deploy-aws.md) for full instructions,
prerequisites, and known limitations. In short:

```console
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: acm_certificate_arn, oneuptime_public_host, ...
terraform init
terraform apply
```

## Assumptions made

This repo was generated based on the following choices (see
`docs/deploy-aws-fargate-plan.md` for the full rationale):

- **ECS on Fargate**, not EKS — no EC2 nodes to patch/manage.
- A **simplified/dev-sized** deployment: the minimum OneUptime service set
  (`nginx`, `app`, `home`, `worker`, `probe`, `runner`), single task per
  service, no autoscaling yet.
- **Managed data stores**: Amazon Aurora PostgreSQL (Serverless v2) and
  Amazon ElastiCache for Redis, since Fargate has no persistent block
  storage for self-hosted databases. **ClickHouse** has no AWS-managed
  equivalent, so it's self-hosted on its own Fargate task backed by EFS
  (single instance, no HA — see `docs/deploy-aws.md`'s "Known limitations").
- **LZA Pattern B**: a Terraform-managed internal ALB tagged
  `Public=True`/`PublicHost=<label>` for the platform's perimeter
  automation — same public-exposure model as before, just without the
  Kubernetes AWS Load Balancer Controller in between.
- **Tagged for expense tracking** — every AWS resource this repo creates is
  tagged `Project=oneuptime` / `CostTracking=oneuptime` (see
  `docs/aws-resources.md`).
