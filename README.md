# Launchpad IDP

A small internal developer platform on AWS and Kubernetes.

A developer adds one file, `services/<name>/service.yaml`, and the platform
creates what the service needs to run safely: a namespace, permissions, a
GitOps deployment, SLOs, dashboards and alerts. Releases go out as canaries and
roll back automatically when the SLO starts burning.

**Status: design complete, build in progress. Nothing is deployable yet.**
This README is updated as each part lands.

- Design: [docs/design.md](docs/design.md)
- Decisions: [docs/adr/](docs/adr/)
- Demo services (developer repo): https://github.com/vikascharan0119/launchpad-demo-services

## Layout

| Path | What it holds |
|---|---|
| `infra/terraform/` | VPC, EKS and IAM |
| `platform/bootstrap/` | ArgoCD install and root app |
| `platform/addons/` | Kyverno, Crossplane, observability, Argo Rollouts |
| `platform/charts/service-template/` | The Helm chart every service is built from |
| `services/` | One `service.yaml` per onboarded service |
| `assistant/` | Read-only AI incident assistant |
| `chaos/` | Failure experiments |
| `docs/` | Design doc, decision records, runbooks, postmortems |

## How changes are made

Every change goes through a branch and a pull request. Direct pushes to
`main` are blocked by a repository ruleset.
