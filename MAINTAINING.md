# Maintaining this fork

This is a long-maintained kube-nfv fork of
[k8snetworkplumbingwg/sriov-network-operator](https://github.com/k8snetworkplumbingwg/sriov-network-operator).
It carries a small, topical set of fixes to run the operator on shell-less,
immutable **Talos Linux** nodes — see [doc/talos.md](doc/talos.md).

The goal is to keep the fork **close to upstream**: a thin patch set on top of
`master`, easy to rebase/merge and easy to audit.

## Branch model

- `master` is the fork's integration branch and tracks `origin/master`.
- All fork-specific changes are carried as a small, topically-grouped set of
  commits on top of upstream (currently the Talos fixes). Keep them grouped so
  upstream-sync conflicts stay localized.
- Everything lands on `master` via PR.

## CI / CD (already automated)

| Trigger | Workflow | Result |
|---|---|---|
| push to `master` | `image-push-master.yml` | Builds + pushes `operator`, `config-daemon`, `webhook` images (multi-arch) to `ghcr.io/kube-nfv/…` as `:latest` and `:<sha>` |
| push tag `v*` | `image-push-release.yml` | Same images tagged with the release version |
| push tag `v*` | `chart-push-release.yml` | Packages the Helm chart (`make chart-prepare-release` → `chart-push-release`) and OCI-pushes it to ghcr |
| weekly / manual | `upstream-sync.yml` | Opens a PR merging upstream `master` (see below) |

Images build on **every commit** to master. The Helm chart is published **only
on tags** (semver); between releases, consume images by `:latest` or `:<sha>`.

## Versioning

The fork does **not** reuse upstream's exact versions — a fork `v1.6.0` would be
a different artifact than upstream's `v1.6.0`. Fork tags derive from the upstream
base they are built on:

```
v<upstream-base>-kubenfv.<N>
```

| Tag | Meaning |
|---|---|
| `v1.6.0-kubenfv.1` | first fork release on top of upstream `v1.6.0` |
| `v1.6.0-kubenfv.2` | fork-only fix, same upstream base |
| `v1.7.0-kubenfv.1` | after syncing upstream `v1.7.0` |

This keeps the upstream base traceable and lets fork-only fixes ship
independently. `-kubenfv.N` is a SemVer2 pre-release, so it is valid for both
image tags and the Helm chart version. Note: as a pre-release it sorts *below*
the plain base version, so `helm install` needs `--devel` or an exact version
pin (a non-issue for kube-nfv deployments, which pin exact versions).

**Tagging is manual and deliberate** — you decide when a synced tree is
release-worthy and whether it's a new upstream base or a fork-only bump. A
tag pushed by CI would not trigger the release workflows anyway (GitHub's
anti-recursion rule), so there is no full auto-release. Use the helper to
compute the next tag so you don't have to track `N` by hand:

```sh
make next-fork-version BASE=v1.6.0   # -> v1.6.0-kubenfv.1
```

## Cutting a release

```sh
TAG=$(make -s next-fork-version BASE=v1.6.0)   # e.g. v1.6.0-kubenfv.1
git tag "$TAG"
git push origin "$TAG"
```

This triggers both the release image build and the chart publish. The chart's
`chart-update.sh`:

- sets the operator/config-daemon/webhook images to
  `ghcr.io/kube-nfv/…:<tag>` (fork-aware via `GITHUB_REPO_OWNER`);
- pins the bundled CNI images (sriov-cni, ovs-cni, rdma-cni, device-plugin,
  metrics-exporter, …) to **upstream's latest tag at release time**.

> ⚠️ The CNI image tags are resolved dynamically from upstream, so two releases
> cut at different times may bundle different CNI versions. If you need
> reproducible releases, pin those tags explicitly in `hack/release/chart-update.sh`.

## Syncing from upstream

Automated: `upstream-sync.yml` runs weekly (and on manual dispatch). It fetches
`k8snetworkplumbingwg/sriov-network-operator` `master`, merges it into a
`sync/upstream-<date>` branch, and opens a PR. Review the delta, confirm the
fork's Talos fixes are still intact, then merge.

- **Clean merge** → normal PR.
- **Conflicts** → the conflicted tree is committed and the PR is opened as a
  **draft** titled `… (CONFLICTS — resolve manually)`. Check out the branch,
  resolve the markers, and push.

> CI note: PRs opened by the default `GITHUB_TOKEN` do **not** trigger the
> `pull_request` test workflow. To run tests automatically on sync PRs, add a
> repo secret `UPSTREAM_SYNC_TOKEN` (PAT with `contents: write` +
> `pull-requests: write`); the workflow uses it when present.

### Doing it manually

```sh
git remote add upstream https://github.com/k8snetworkplumbingwg/sriov-network-operator.git
git fetch upstream master
git checkout -b sync/upstream-manual origin/master
git merge upstream/master     # resolve conflicts if any
git push origin sync/upstream-manual
# open a PR into master
```

We use **merge** (not rebase) on the published `master` to avoid force-pushing a
branch that CI and consumers track.

## Fork hygiene

- Keep the Talos delta documented in [doc/talos.md](doc/talos.md).
- When resolving sync conflicts, preserve the fork behavior — the Talos fixes
  touch: `pkg/consts/constants.go`, `pkg/host/internal/udev/`,
  `pkg/host/internal/kernel/kernel.go`, `bindata/manifests/daemon/daemonset.yaml`,
  `bindata/scripts/udev-find-sriov-pf.sh`,
  `controllers/sriovoperatorconfig_controller.go`,
  `bindata/manifests/metrics-exporter/metrics-daemonset.yaml`, and the Helm chart.
