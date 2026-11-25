#!/bin/bash
set -euo pipefail

# ---- Versions (change here) ----
K8S_VERSION="v1.36"                     # Kubernetes minor version (needs containerd 2.x)
POD_CIDR="192.168.0.0/16"               # must match Calico's default and not overlap your VPC
CALICO_URL="https://docs.tigera.io/calico/latest/manifests/calico.yaml"

echo "===== Kubernetes MASTER Setup (${K8S_VERSION}) ====="

# Set hostname (and keep it across reboots on EC2/cloud-init)
sudo hostnamectl set-hostname master
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

# Sysctl settings
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
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key" \
  | sudo tee /etc/apt/keyrings/kubernetes-apt-keyring.asc >/dev/null

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.asc] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

# Install Kubernetes tools
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Initialize cluster
sudo kubeadm init --pod-network-cidr="${POD_CIDR}"

# Configure kubectl
mkdir -p "$HOME/.kube"
sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

# Install Calico network plugin
kubectl apply -f "${CALICO_URL}"

echo "Waiting for the master node to become Ready (up to 5 min)..."
kubectl wait --for=condition=Ready node/master --timeout=300s || true

echo ""
echo "===== MASTER SETUP COMPLETE ====="
echo "Run the below command on worker nodes:"
sudo kubeadm token create --print-join-command

