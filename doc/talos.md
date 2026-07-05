# Running on Talos Linux

Talos is an immutable, minimal Kubernetes OS. It has no shell and a read-only
`/etc`, which breaks two assumptions the operator normally makes about the host.
This page explains what those constraints are and how the operator has been
adapted to work around them.

## Constraints on Talos

1. **No shell.** Udev rules that offload work to a helper script via
   `IMPORT{program}="...sh"` silently fail — the script never runs, so any name
   or variable it was expected to produce is empty.
2. **Read-only `/etc`.** The operator cannot write udev rules or helper scripts
   directly under the host's `/etc`. A writable location must be provided.

## What the operator does

### Configurable host paths

The operator no longer hard-codes host `/etc` and `/etc/udev`. Two environment
variables (surfaced as Helm values) let you point it at writable locations:

| Env var               | Helm value              | Default     |
|-----------------------|-------------------------|-------------|
| `SRIOV_HOST_ETC_PATH` | `operator.hostEtcPath`  | `/etc`      |
| `SRIOV_HOST_UDEV_PATH`| `operator.hostUdevPath` | `/etc/udev` |

On Talos these are set to a writable path (e.g. a location mounted under
`/var/etc`) so the operator can lay down its NetworkManager and PF-name udev
rules.

### Shell-free VF representor renaming

In switchdev mode the operator renames VF representors to `<pfName>_<vfID>`.
The original rule matched all VFs with a wildcard and called a shell helper
(`switchdev-vf-link-name.sh`) to extract the VF number at event time — which
does not work without a shell.

Instead, the operator now renders **fully materialized udev rules itself**: one
exact-match line per VF, with the VF number baked in, so udevd only needs static
string matching and no helper program:

```
SUBSYSTEM=="net", ACTION=="add|move", ATTRS{phys_switch_id}=="<id>", ATTR{phys_port_name}=="pf0vf0", NAME="ens9f0np0_0"
SUBSYSTEM=="net", ACTION=="add|move", ATTRS{phys_switch_id}=="<id>", ATTR{phys_port_name}=="pf0vf1", NAME="ens9f0np0_1"
... one line per VF
```

The rule file is fixed to `numVfs` at write time; the operator regenerates it
whenever it reconfigures the PF.

### Shell-free kernel module detection

Checking whether a kernel module is loaded previously shelled out to
`lsmod | grep ...`, which needs a shell. The check now stats
`/sys/module/<name>` (with `-` normalized to `_`) on the host instead, so it
works on Talos without a shell.

### Metrics exporter tolerations

The metrics-exporter DaemonSet now carries a blanket `operator: Exists`
toleration so it also schedules onto tainted nodes (e.g. Talos control-plane or
otherwise dedicated nodes) alongside the config daemon.

## Important limitation

The shell-free rendering fixes rule *generation*, but on Talos the operator
still cannot reliably *deliver* the switchdev representor rules: udevd does not
scan the operator's writable rules directory, and the operator container cannot
trigger a udev reload in the host mount namespace. On Talos the representor
rules must therefore be provided statically through the node's machine
configuration (`machine.udev.rules`), which Talos writes to
`/usr/lib/udev/rules.d/` where host udevd applies them on the representor `add`
event. These static rules use the same shell-free, one-line-per-VF form shown
above and are hardware-specific (regenerate if `numVfs` or the NIC changes).
