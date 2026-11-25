# Kubernetes Cluster Setup on AWS EC2 (kubeadm, 1 Master + N Workers)

Create a Kubernetes cluster with **kubeadm** on AWS EC2. Optimized for learning, demos and DevOps projects.

## Repository contents

| File | Purpose |
|------|---------|
| `docker-install.sh` | Installs Docker and prepares the container runtime (run on **every** node) |
| `master-node-setup.sh` | Sets up the control plane, initializes the cluster, installs Calico |
| `worker-node-setup.sh` | Prepares a worker node so it can join the cluster |

## Architecture

- 1 Master node (control plane)
- N Worker nodes

## AWS EC2 configuration

| Role | Instance type | vCPU | RAM | Storage | OS |
|------|---------------|------|-----|---------|----|
| Master | `t3.small` | 2 | 2 GB | 30 GB gp3 | Ubuntu 22.04 |
| Worker | `t3.micro` | 2 | 1 GB | 20 GB gp3 | Ubuntu 22.04 |

> **Note:** kubeadm officially recommends at least 2 GB RAM per node. `t3.micro` workers (1 GB) work for light demos but can be unstable. Use `t3.small` for workers if you see OOM issues.

## Security group

### Master node (control plane)

| Protocol | Port(s) | Source | Purpose |
|----------|---------|--------|---------|
| TCP | 22 | Your IP (recommended) | SSH |
| TCP | 6443 | Worker nodes / your IP | Kubernetes API server |
| TCP | 2379-2380 | Master nodes | etcd |
| TCP | 10250 | Master & worker nodes | Kubelet API |
| TCP | 10259 | Master nodes | kube-scheduler |
| TCP | 10257 | Master nodes | kube-controller-manager |

### Worker nodes

| Protocol | Port(s) | Source | Purpose |
|----------|---------|--------|---------|
| TCP | 22 | Your IP (recommended) | SSH |
| TCP | 10250 | Master node | Kubelet API |
| TCP | 30000-32767 | 0.0.0.0/0 | NodePort services |

### Simplest setup for labs

Use a single security group for all nodes:

```
- All traffic          Source: the same Security Group (self-reference)
- SSH, port 22         Source: your IP
- Custom TCP 6443      Source: your IP (to run kubectl remotely, optional)
- Custom TCP 30000-32767  Source: 0.0.0.0/0 (NodePort access)
```

Allowing all traffic inside the group also covers Calico's networking needs (BGP 179, IP-in-IP, VXLAN).

---

## Master setup

### 1. Clone the repo

```bash
git clone https://github.com/mudasirhaji/kubeadm-installation-2026.git
cd kubeadm-installation-2026
```

### 2. Install Docker / runtime dependencies (every node)

```bash
chmod +x *.sh
./docker-install.sh
```

### 3. Run the master script

```bash
./master-node-setup.sh
```

The script:

- Sets the hostname to `master`
- Disables swap
- Configures kernel networking
- Installs containerd and enables `SystemdCgroup`
- Installs kubeadm, kubelet, kubectl
- Initializes the cluster
- Configures kubectl
- Installs the Calico network plugin

At the end it prints a join command:

```
kubeadm join <MASTER-IP>:6443 --token ... --discovery-token-ca-cert-hash sha256:...
```

Copy it for the workers.

---

## Worker setup

### 1. Clone the repo

```bash
git clone https://github.com/mudasirhaji/kubeadm-installation-2026.git
cd kubeadm-installation-2026
```

### 2. Install Docker and run the worker script

```bash
chmod +x *.sh
./docker-install.sh
./worker-node-setup.sh
```

### 3. Join the cluster

```bash
sudo kubeadm join <MASTER-IP>:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --v=5
```

---

## Verify the cluster

Run on the master:

```bash
kubectl get nodes
kubectl get pods -A
```

Expected: every node `Ready` and every pod `Running`.

```
master            Ready
worker-172-31-x   Ready
worker-172-31-x   Ready
```

## Command reference

| Command | Description |
|---------|-------------|
| `kubeadm init` | Initializes the control plane |
| `kubeadm join` | Joins a worker to the cluster |
| `kubectl get nodes` | Lists cluster nodes |
| `kubectl get pods -A` | Lists pods in all namespaces |

## Important notes

- Always disable swap.
- All nodes must be in the same VPC.
- Nodes need internet access.
- Wait 1-2 minutes after setup before verifying.

## Troubleshooting

- **Lost or expired join command:** tokens expire after 24 hours. Generate a new one on the master:
  ```bash
  kubeadm token create --print-join-command
  ```
- **Nodes stuck in `NotReady`:** usually no CNI plugin is running yet. Check with `kubectl get pods -n kube-system` and `kubectl describe node <node>`.
- **Upgrades:** don't skip minor versions. Upgrade one minor version at a time following the official kubeadm steps.

## Final result

- 1 master node
- N worker nodes
- A working Kubernetes cluster

## Official documentation

- [Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
- [Creating a cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
- [Upgrading kubeadm clusters](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)
