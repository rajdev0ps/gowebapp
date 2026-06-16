# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A minimal Go web server (`net/http`, no framework) that serves static HTML pages, packaged with a multi-stage Dockerfile and deployed to Kubernetes via Helm. The app itself is intentionally tiny — most of the complexity in this repo is in the CI/CD and deployment plumbing around it.

## Commands

```bash
go run main.go              # run the server locally (listens on 0.0.0.0:8080)
go build -o go-web-app       # build binary (matches CI build step)
go test ./...                # run all tests (matches CI test step)
go test -run TestMain -v     # run the single existing test
```

There is no separate lint command locally configured beyond `golangci-lint` (run via GitHub Action `golangci-lint-action`).

Routes: `/home`, `/courses`, `/about`, `/contact` — each maps directly to a file in `static/` via `http.ServeFile`. There is no `/` root route registered.

## Architecture

- `main.go` — all HTTP handlers and route registration live in one file. Each handler just serves a static HTML file from `static/`. Adding a page means: add the HTML file to `static/`, add a handler function, register it with `http.HandleFunc` in `main()`.
- `main_test.go` — uses `httptest` to test handlers directly (no live server needed).
- `Dockerfile` — multi-stage build: compiles in `golang:1.22.5`, then copies only the binary + `static/` into a `gcr.io/distroless/base` final image. Any new top-level asset directory the app reads at runtime must be added to the final stage's `COPY --from=base` lines or it won't exist in the container.

## Deployment / CI-CD (important — multiple Helm/k8s dirs, easy to confuse)

- **`helm/go-web-app-chart/`** — the chart actually used in production deploys. Its `values.yaml` `image.tag` is auto-updated by CI on every push to `main` (see below). Don't hand-edit the `tag` field; it gets overwritten by the pipeline.
- **`fresh-helm-config/`** — a separate, unrelated scaffold chart (still has placeholder `nginx` image, gateway-api `httpRoute`, etc.). Not wired into CI. Treat as a template/reference, not the deployed chart.
- **`k8s/manifests/`** — raw Kubernetes YAML (Deployment/Service/Ingress), pinned to a fixed `v1` image tag. Separate from the Helm-based flow; not updated by CI.

### `.github/workflows/ci.yaml` pipeline (triggers on push to `main`, ignores changes under `helm/**`, `k8s/**`, `README.md`)

1. `build` — `go build` + `go test ./...`
2. `code-quality` — `golangci-lint`
3. `push` (needs build + code-quality) — builds the Docker image and pushes to Docker Hub as `<DOCKERHUB_USERNAME>/go-web-app:<github.run_id>`
4. `update-newtag-in-helm-chart` (needs push) — `sed`-replaces the `tag:` line in `helm/go-web-app-chart/values.yaml` with the new run ID and commits/pushes that change back to `main` using the `TOKEN` secret

This means: every app code push triggers a second, automated commit updating the Helm chart's image tag. Because the workflow ignores `helm/**` paths in its trigger, that auto-commit does not retrigger the pipeline (avoids an infinite loop).
