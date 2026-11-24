# ADR 0001: Two repositories, platform and services

Date: 2026-11-17
Status: Accepted

## Context

The platform config (what runs in the cluster) and the application code
(what developers write) change for different reasons and are owned by
different people in most companies.

## Decision

Use two public repositories:

- `launchpad-idp`: infrastructure, platform add-ons, the service template,
  and one `service.yaml` per onboarded service.
- `launchpad-demo-services`: source code and CI for the demo services.

CI in the services repo builds and pushes an image, then opens a pull
request in the platform repo that changes one line: the image version in
that service's `service.yaml`. ArgoCD deploys after that pull request merges.

## Consequences

- Developers never need write access to the cluster. Every change to what
  runs is a reviewed pull request in the platform repo.
- The services pipeline needs a narrowly scoped credential that can open
  pull requests in the platform repo.
- Two repos are harder to read than one.

## Alternative considered

One repository for everything. Simpler, but it hides the separation between
who can change code and who can change what runs.
