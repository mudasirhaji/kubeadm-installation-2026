#!/bin/bash
set -euo pipefail

# ---- Versions (change here; keep identical to master-node-setup.sh) ----
K8S_VERSION="v1.36"

echo "===== Kubernetes WORKER Setup (${K8S_VERSION}) ====="

# Generate unique hostname based on IP
IP=$(hostname -I | awk '{print $1}')
HOSTNAME="worker-$(echo "$IP" | tr '.' '-')"

echo "Setting hostname to $HOSTNAME"
sudo hostnamectl set-hostname "$HOSTNAME"
echo "preserve_hostname: true" | sudo tee /etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg >/dev/null

# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Kernel modules
cat <<EOT | sudo tee /etc/modules-load.d/k8s.conf >/dev/null
overlay
br_netfilter
EOT

sudo modprobe overlay
sudo modprobe br_netfilter

# Sysctl
cat <<EOT | sudo tee /etc/sysctl.d/k8s.conf >/dev/null
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOT

sudo sysctl --system >/dev/null

# Install containerd from Docker's apt repo.
# Kubernetes 1.36+ requires containerd 2.x; Ubuntu 22.04's own package is 1.7.x.
sudo apt-get update
sudo apt-get install -y ca-certificates curl gpg apt-transport-https
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOT
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOT

sudo apt-get update
sudo apt-get install -y containerd.io

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null

# Enable systemd cgroup
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd
containerd --version

# Add Kubernetes repo
sudo mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key" \
  | sudo tee /etc/apt/keyrings/kubernetes-apt-keyring.asc >/dev/null

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.asc] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

# Install Kubernetes tools
sudo apt-get update
sudo apt-get install -y kubelet kubeadm
sudo apt-mark hold kubelet kubeadm

echo ""
echo "===== WORKER SETUP COMPLETE ====="
echo "Hostname: $HOSTNAME"
echo ""
echo "NEXT STEP: run the join command printed by the MASTER, like:"
echo ""
echo "sudo kubeadm join <MASTER-IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH> --v=5"
echo ""
echo "After joining, verify on MASTER:  kubectl get nodes"

