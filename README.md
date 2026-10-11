```bash
docker compose run --rm --build ansible ansible-playbook -i /inventory/inventory.ini --private-key /root/.ssh/id_ed25519 -u ubuntu -b facts.yml
```


```bash
docker compose run --rm --build ansible ansible-playbook -i /inventory/inventory.ini --private-key /root/.ssh/id_ed25519 -u ubuntu -b cluster.yml
```

If, need update labels for nodes

```bash
docker compose run --rm --build ansible ansible-playbook -i /inventory/inventory.ini --private-key /root/.ssh/id_ed25519 -u ubuntu -b cluster.yml --tags node-label
```

## Useful Ansible tags

These tags come from the `kubernetes_sigs.kubespray` collection and apply to `cluster.yml`, `recover-control-plane.yml` and the collection's `upgrade_cluster` playbook (they all import the same roles under the hood).

| Tag | What it does | When to use it |
|---|---|---|
| `preinstall` | OS prep: sysctl, DNS, kernel modules | Rarely needed alone |
| `download` | Download binaries/images | Add `--skip-tags download` to speed up iteration once cached |
| `container-engine` | Configure containerd/docker | Rarely needed alone |
| `etcd` | Install/configure etcd, etcd certs | Replacing/repairing etcd members |
| `node` | kubelet setup on all nodes | kubelet-level issues |
| `control-plane` | Templates kubeadm-config and static manifests (apiserver/scheduler/controller-manager), kubectl | See note below — does **not** regenerate manifests on an already-joined node |
| `kubeadm` | `kubeadm init`/`join` phases, join tokens | Node join/token issues |
| `client` | kubeconfig on control-plane nodes | Restore `admin.conf` |
| `network` | CNI plugin (Calico, etc.) | Pod networking issues |
| `node-label` / `node-taint` | Node labels/taints | Quick metadata fixes |
| `apps`, `ingress-controller`, `policy-controller`, `external-provisioner`, `external-cloud-controller` | Addons | Rarely needed alone |

## Replacing a control-plane / etcd node

1. Add the new node to `inventory/inventory.ini` and join it:
   ```bash
   docker compose run --rm --build ansible ansible-playbook -i /inventory/inventory.ini --private-key /root/.ssh/id_ed25519 -u ubuntu -b cluster.yml --limit <new-node>,kube_control_plane
   ```
2. Remove **one** old node at a time (never remove more than one control-plane/etcd member at once — with 3 members, quorum needs 2 alive):
   ```bash
   docker compose run --rm --build ansible ansible-playbook -i /inventory/inventory.ini --private-key /root/.ssh/id_ed25519 -u ubuntu -b remove-node.yml -e node=<old-node>
   ```
3. Confirm the cluster is healthy (`kubectl get nodes`, `etcdctl endpoint health`) before touching the next node.

### Important: fix stale `--etcd-servers` after a node swap

`cluster.yml` and `remove-node.yml` do **not** update the `--etcd-servers` flag in `/etc/kubernetes/manifests/kube-apiserver.yaml` on nodes that are already joined — kubeadm only regenerates that flag during an actual `kubeadm upgrade apply`, which only runs from the collection's `upgrade_cluster` playbook (gated by its `upgrade_cluster_setup` variable). If you skip this step, the apiserver on surviving nodes can keep pointing at etcd members that no longer exist and crash-loop after any restart (which also breaks kube-vip leader election and the VIP).

Run this after every node swap to force kubeadm to resync the manifests with the current `[etcd]` group:

```bash
docker compose run --rm --build ansible ansible-playbook -i /inventory/inventory.ini --private-key /root/.ssh/id_ed25519 -u ubuntu -b kubernetes_sigs.kubespray.upgrade_cluster --limit kube_control_plane --tags control-plane
```

This is safe to run even without a Kubernetes version bump — `kubeadm upgrade apply` is idempotent and just rewrites the static manifests from the current inventory.

### Recovering a dead/unreachable node (`broken_etcd` / `broken_kube_control_plane`)

Only populate `[broken_etcd]` / `[broken_kube_control_plane]` in the inventory when a node is already dead and unreachable over SSH (so `remove-node.yml` can't run against it). List the dead node's name there, then run:

```bash
docker compose run --rm --build ansible ansible-playbook -i /inventory/inventory.ini --private-key /root/.ssh/id_ed25519 -u ubuntu -b recover-control-plane.yml --limit etcd,kube_control_plane -e etcd_snapshot=/path/to/snapshot.db
```

If etcd still has quorum, it just removes the broken member and its certs. If quorum is lost, it restores `etcd_snapshot` on the first `etcd` host and rebuilds the cluster from there. Once recovered, remove the node's name from `broken_etcd`/`broken_kube_control_plane` **and** from `[kube_control_plane]`/`[etcd:children]` so future runs don't try to "recover" it again.