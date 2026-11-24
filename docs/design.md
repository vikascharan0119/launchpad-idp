# Launchpad IDP: Design Doc v1

Written: 13 November 2026
Status: design complete, build in progress. This document is updated when the design changes.

## Summary

Launchpad is a small internal developer platform (IDP) on AWS and Kubernetes. A developer adds one file, `service.yaml`, and the platform creates everything the service needs to run safely: an isolated namespace, permissions, a pipeline, a GitOps deployment, SLOs, dashboards and alerts.

Releases go out as canaries and roll back automatically when the SLO starts burning. An AI incident assistant with read-only access writes a first incident summary when an alert fires, and its accuracy is measured against failures injected on purpose.

**Why the name:** a launchpad provides fuel, power, tracking and an abort system, so the rocket team only brings the rocket. Here the developer brings code and the platform provides the rest.

## Goals and non-goals

**Goals**

1. Onboard a new service from one file in under 10 minutes, with no manual steps by a platform engineer.
2. Give every service the same guardrails by default: resource limits, network isolation, least-privilege access and policy checks.
3. Generate SLOs, dashboards and burn-rate alerts from the target written in the file.
4. Roll back a bad release automatically, based on the SLO, without a human.
5. Prove the platform under failure with at least five injected faults, runbooks and one written postmortem.
6. Measure the AI assistant honestly: publish how many injected faults it diagnosed correctly and where it was wrong.

**Non-goals**

- A developer portal UI such as Backstage. The file in Git is the interface.
- Multi-cluster or multi-region. One cluster is enough to show the design.
- An AI that takes actions. The assistant reads and reports; a human decides.
- Production traffic or real customer data. The demo services are deliberately simple.

## The developer experience

A developer opens a pull request that adds one file, `services/<name>/service.yaml`. When it merges, the service is onboarded.

```yaml
name: orders-api
owner: team-orders
image: ghcr.io/vikascharan0119/orders-api
port: 8080
slo:
  availability: 99.5      # percent of successful requests over 30 days
  latencyP95Ms: 300       # 95% of requests faster than this
resources:
  database: postgres-small
```

**What the platform creates from that file**

| Created | What it is | Why |
|---|---|---|
| Namespace | An isolated section of the shared cluster | Separation without a cluster per team |
| Resource quota and limits | A cap on CPU and memory | One service cannot starve the others |
| RBAC role binding | The owner team can view and debug only its own namespace | Least privilege |
| Network policy | Deny by default, allow only declared callers | Limits the damage of a compromise |
| Service account with an AWS IAM role | The app's own AWS identity | No stored AWS keys |
| Rollout and Service | The running app, released as a canary | Safe releases |
| SLO, dashboard, alerts | Generated from the `slo` block | Monitoring from day one |
| Database | Created by Crossplane from the `resources` block | Self-service infrastructure |

**How it works underneath**

1. An ArgoCD ApplicationSet watches `services/*/service.yaml` in Git.
2. For each file it creates one ArgoCD Application.
3. Each Application renders the same platform Helm chart, `service-template`, using the file as its values.
4. ArgoCD applies the result and keeps the cluster matching Git.

**Why this way:** it needs no custom code, and every service is built from one reviewed template.
**Alternative considered:** a custom Kubernetes operator with its own resource type. More flexible, but it takes weeks to write and maintain.

## Architecture

Every component is open source. Choices marked "confirm" get a final check against current docs when that part is built.

| Layer | Tool | What it does here | Why this one | Common alternative |
|---|---|---|---|---|
| Base infrastructure | Terraform | Builds the VPC, EKS cluster and IAM | The standard for base infrastructure | CloudFormation, Pulumi |
| Local cluster | kind | Runs the core platform on a laptop for free | Fast to create and delete | minikube, k3d |
| CI | GitHub Actions | Tests, builds, scans and pushes images | Lives next to the code; free for public repos | Jenkins, GitLab CI, Azure DevOps |
| CI to AWS access | GitHub OIDC | Short-lived AWS credentials for the pipeline | No long-lived keys stored in GitHub | Stored access keys |
| Delivery | ArgoCD + ApplicationSet | Deploys from Git and onboards services | GitOps: Git is the single source of truth | Flux |
| Releases | Argo Rollouts | Canary steps with automatic rollback | Checks Prometheus before each step | Flagger, plain rolling update |
| Self-service infra | Crossplane | Creates a database from the service file | Developers request infra through the same Git flow | Terraform module per team |
| Policy | Kyverno | Blocks unsafe workloads at admission | Policies are plain YAML | OPA Gatekeeper |
| Secrets | External Secrets + AWS Secrets Manager | Syncs secrets into the cluster | Nothing extra to run and patch | HashiCorp Vault |
| Pod AWS identity | IAM Roles for Service Accounts | Gives each app its own IAM role | No shared node credentials | EKS Pod Identity |
| Telemetry | OpenTelemetry | One standard for metrics, logs and traces | Vendor-neutral | Vendor agents |
| Metrics and alerts | Prometheus + Alertmanager | Stores metrics, fires burn-rate alerts | Widely used, well understood | Datadog, CloudWatch |
| Logs and traces | Loki and Tempo (confirm) | Stores logs and traces | Light, works with Grafana | ELK, Jaeger |
| Dashboards | Grafana | One generated dashboard per service | Works with all of the above | Vendor UIs |
| SLO rules | Pyrra or Sloth (confirm) | Turns an SLO target into burn-rate alert rules | Avoids hand-written alert maths | Hand-written rules |
| Failure testing | Chaos Mesh (confirm) | Injects pod, network and dependency faults | Runs as Kubernetes resources | LitmusChaos, AWS FIS |
| AI assistant | Python + MCP | Reads telemetry and drafts an incident summary | Standard, auditable tool access | Direct API calls from a script |

## The demo application

The platform is the product, so the demo app is deliberately small: Python (FastAPI) services that give the platform something realistic to run, measure and break. They live in a separate repository, [launchpad-demo-services](https://github.com/vikascharan0119/launchpad-demo-services).

| Service | What it does | Why it is in the demo |
|---|---|---|
| `orders-api` | Accepts and lists orders, stores them in Postgres, calls `payments-stub` | Has a database and a downstream dependency, like most real services |
| `payments-stub` | Pretends to authorise a payment; can be told to be slow or to fail | Gives failure tests a dependency to break |
| `loadgen` | Sends steady traffic to `orders-api` | SLOs and canary analysis need traffic to measure |

**Why two services:** a trace that crosses two services shows distributed tracing working, and a failing dependency is the most common real incident.

**What it is not:** it is not based on any employer's code or data. It is a generic sample written for this project.

## SLOs, alerting and automatic rollback

Each service gets two SLOs from its file: availability (share of requests that succeed) and latency (share of requests faster than the target).

**Error budget:** a 99.5% availability target over 30 days allows 0.5% of requests to fail. That allowance is the error budget.

**Burn-rate alerts:** an alert fires when the budget is being spent too fast, not on every error spike.

| Alert | Fires when | Action |
|---|---|---|
| Fast burn | The budget would be gone in about 2 days at the current rate | Page |
| Slow burn | The budget would be gone in about 10 days at the current rate | Ticket |

The exact windows and thresholds follow the multi-window method from the Google SRE Workbook and are set when observability is built.

**Automatic rollback**

1. A new version starts as a canary taking 10% of traffic.
2. Argo Rollouts queries Prometheus for the canary's error rate and latency.
3. If both are within the SLO, traffic moves to 50%, then 100%.
4. If either breaks the SLO, the rollout aborts and all traffic returns to the old version.

**Why this way:** the same SLO that pages a human also gates the release, so there is one definition of "healthy".
**Alternative considered:** a rolling update with readiness probes, which catches crashes but not a version that returns errors while staying up.

## AI incident assistant

When an alert fires, the assistant gathers evidence and writes a first incident summary as a GitHub issue. It never changes anything.

**Flow**

1. Alertmanager sends the alert to the assistant through a webhook.
2. The assistant queries metrics, logs, traces, recent deploys and pod events through MCP tools.
3. It writes a summary: what is failing, since when, the most likely cause, the evidence for it, and the matching runbook.
4. A human reads it and decides what to do.

**Guardrails**

| Guardrail | How it is enforced |
|---|---|
| Read-only | Its Kubernetes service account has only get, list and watch, and no access to secrets |
| No write tools | The MCP servers it can reach expose no create, update or delete tools |
| Audit trail | Every tool call and its result is logged |
| Bounded cost | A cap on tool calls and tokens per incident |
| Evidence required | The summary must cite the query behind each claim |

**How it is scored:** each injected fault from the failure tests is run three times. For each run we record whether the assistant's top cause matched the real fault. The README publishes the full table, including the misses.

**Why this way:** an assistant that can act is hard to trust in a regulated environment; a read-only one with a published accuracy number is easy to reason about.
**Alternative considered:** vendor AI SRE products, which do more but are closed and paid.

## Failure testing

Five faults are injected on purpose. Each has an expected result written down before the test runs.

| # | Fault injected | What should happen |
|---|---|---|
| 1 | Kill `orders-api` pods | Kubernetes replaces them; no SLO alert |
| 2 | Add 2 seconds of latency to `payments-stub` | Latency SLO burns; fast-burn alert fires |
| 3 | Deploy a version that returns errors | Canary analysis fails; automatic rollback |
| 4 | Make the database unreachable | Availability SLO burns; alert fires; runbook applies |
| 5 | Drain a node | Pods reschedule; no SLO alert |

**Deliverables:** one runbook per alert, and one blameless postmortem for the test with the most surprising result. Anything that did not behave as expected is reported as it happened.

## Repo layout

Two public repositories, split the way most companies split them: one owned by the platform team and one owned by the developers. See [ADR 0001](adr/0001-two-repositories.md).

| Repo | Owned by | Holds |
|---|---|---|
| `launchpad-idp` | Platform team | Infrastructure, platform add-ons, the service template, the list of onboarded services, failure tests, the AI assistant, docs |
| `launchpad-demo-services` | Developers | Source code and CI for `orders-api`, `payments-stub` and `loadgen` |

**How the two repos work together**

1. A developer merges code in `launchpad-demo-services`.
2. CI there tests the code, builds the image, scans it and pushes it to the registry.
3. CI then opens a pull request in `launchpad-idp` that changes one line: the image version in that service's `service.yaml`.
4. When that pull request merges, ArgoCD starts the canary release.

Developers never get write access to the cluster, and every change to what runs is a reviewed pull request in the platform repo.

```text
launchpad-idp/                 # platform repo
  README.md
  Makefile                     # one-command setup and teardown
  CODEOWNERS                   # who must review which folder
  docs/
    design.md                  # this document
    adr/                       # short decision records
    runbooks/
    postmortems/
  infra/terraform/             # VPC, EKS, IAM
  platform/
    bootstrap/                 # ArgoCD install and root app
    addons/                    # Kyverno, Crossplane, observability, Rollouts
    charts/service-template/   # the template every service is built from
  services/                    # one service.yaml per onboarded service
  assistant/                   # the AI incident assistant
  chaos/                       # failure experiments
  .github/workflows/           # checks on platform changes

launchpad-demo-services/       # developer repo
  README.md
  orders-api/
  payments-stub/
  loadgen/
  .github/workflows/           # test, build, scan, push, open PR to platform repo
```

**Working method:** every change goes through a branch and a pull request, so the history shows how the platform was built.

## Build order

The core platform is built on a free local cluster first and then moved to AWS. The heavier parts (the full observability stack and failure tooling) run on EKS only, because they do not fit on an 8 GB laptop alongside the rest.

| Phase | Build | Done when |
|---|---|---|
| 1 | Repo skeleton, local cluster, ArgoCD bootstrap | ArgoCD runs locally and manages itself from Git |
| 2 | Demo services, CI pipeline, `service-template` chart, ApplicationSet onboarding, Kyverno | Adding a `service.yaml` deploys a service with its guardrails |
| 3 | Terraform for VPC and EKS, pipeline access through OIDC, the platform running on EKS, Crossplane database | The same repo brings the platform up on AWS and tears it down |
| 4 | OpenTelemetry, Prometheus, logs, traces, generated SLOs and alerts, canary with automatic rollback | A bad version rolls back by itself |
| 5 | Failure tests, runbooks, postmortem, AI assistant first version | Five faults run; the assistant writes a summary for each |
| 6 | Assistant scoring, README, architecture diagram, demo recording, cost notes | A stranger can understand and run the project from the README |

**If time runs short, scope is cut in this order:** Crossplane first, then the AI assistant. The onboarding flow, SLOs, rollback and failure tests are never cut.

## Cost and teardown

The local phases cost nothing. AWS spending starts in phase 3.

| Item | Costs money? | How it is kept low |
|---|---|---|
| Local kind cluster | No | Runs on the laptop |
| GitHub repos and Actions | No | Free for public repositories |
| EKS control plane | Yes, about $0.10 per hour | Created per session, destroyed after |
| Worker nodes | Yes | Two small spot instances |
| NAT gateway | Yes | One only, destroyed with the cluster |
| Database through Crossplane | Yes | Smallest size, created only for the demo |
| LLM API | Yes, a few dollars in total | Capped tokens per incident |

**Rules**

1. A budget alert at $20 per month is set in AWS before the first resource is created.
2. Every AWS session ends with `make destroy`, then a check that no EKS cluster, NAT gateway, load balancer or database is left.
3. Nothing is left running overnight.
