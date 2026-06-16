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

- **`helm/go-web-app-chart/`** — the chart actually used for deploys. `values.yaml` holds shared defaults (`replicaCount`, `image.repository`, `image.pullPolicy`); `values-dev.yaml` and `values-prod.yaml` are per-environment overlays holding `env` and `image.tag`, applied with `-f values.yaml -f values-<env>.yaml`. CI auto-updates the `image.tag` field in the matching overlay file on every push (see below) — don't hand-edit `image.tag` in those overlays, it gets overwritten by the pipeline.
- **`fresh-helm-config/`** — a separate, unrelated scaffold chart (still has placeholder `nginx` image, gateway-api `httpRoute`, etc.). Not wired into CI. Treat as a template/reference, not the deployed chart.
- **`k8s/manifests/`** — raw Kubernetes YAML (Deployment/Service/Ingress), pinned to a fixed `v1` image tag. Separate from the Helm-based flow; not updated by CI.

### Branch → environment → image tag

- `dev` branch → `env=dev`, image tag `dev-<7-char-commit-sha>`, updates `helm/go-web-app-chart/values-dev.yaml`.
- `main` branch → `env=prod`, image tag `prod-<7-char-commit-sha>`, updates `helm/go-web-app-chart/values-prod.yaml`.
- The tag embeds the commit SHA (not a run ID) specifically so a deployed image can be traced back to the exact commit via `git show <sha>` or `git log --all --grep`.

### `.github/workflows/ci.yaml` pipeline (triggers on push to `main` or `dev`, ignores changes under `helm/**`, `k8s/**`, `README.md`)

1. `setup` — derives `environment` (`dev`/`prod`), `image_tag` (`<env>-<short-sha>`), and `values_file` (`values-<env>.yaml`) from `github.ref_name`; exposed as job outputs for downstream jobs.
2. `build` — `go build` + `go test ./...`
3. `code-quality` — `golangci-lint`
4. `push` (needs setup + build + code-quality) — builds the Docker image and pushes to Docker Hub as `<DOCKERHUB_USERNAME>/go-web-app:<env>-<short-sha>`
5. `update-newtag-in-helm-chart` (needs setup + push) — `sed`-replaces the `tag:` line in the environment's overlay (`values-dev.yaml` or `values-prod.yaml`) with the new image tag and commits/pushes that change back to the same branch using the `TOKEN` secret

This means: every app code push triggers a second, automated commit updating that environment's Helm overlay. Because the workflow ignores `helm/**` paths in its trigger, that auto-commit does not retrigger the pipeline (avoids an infinite loop).
