#!/bin/bash

# =========================================================================
# COMPLETE KUBERNETES CLUSTER SETUP SCRIPT
# =========================================================================
# This script performs a complete Kubernetes cluster setup including:
# - System prerequisites and kernel modules
# - Docker installation and configuration
# - Kubernetes tools installation
# - Cluster initialization
# =========================================================================

# =========================================================================
# PHASE 1: SYSTEM PREREQUISITES
# =========================================================================

# ----------------------------------------
# Disable Swap Memory
# ----------------------------------------
# Kubernetes requires swap to be disabled for proper memory management
# kubelet will fail to start if swap is enabled
echo "Disabling swap..."
swapoff -a

# Permanently disable swap by commenting out swap entries in /etc/fstab
# This ensures swap stays disabled after reboot
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# ----------------------------------------
# Configure Kernel Modules for Networking
# ----------------------------------------
# Check if br_netfilter module is already loaded
echo "Checking bridge netfilter module..."
lsmod | grep br_netfilter 

# Load the br_netfilter module (required for Kubernetes networking)
# This module enables netfilter hooks in bridge networks
echo "Loading br_netfilter module..."
sudo modprobe br_netfilter

# ----------------------------------------
# Configure Kernel Network Parameters
# ----------------------------------------
# Set up sysctl parameters required for Kubernetes networking
# These settings allow iptables to see bridged traffic
echo "Configuring kernel networking parameters..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
# Enable netfilter on bridges for IPv6 traffic
net.bridge.bridge-nf-call-ip6tables = 1
# Enable netfilter on bridges for IPv4 traffic  
net.bridge.bridge-nf-call-iptables = 1
EOF

# Apply the sysctl parameters immediately
sudo sysctl --system

# =========================================================================
# PHASE 2: CONTAINER RUNTIME SETUP (DOCKER)
# =========================================================================

# ----------------------------------------
# Install Docker
# ----------------------------------------
echo "Installing Docker..."
apt-get update 
apt install docker.io -y

# Start Docker service
systemctl start docker

# ----------------------------------------
# Configure Docker for Kubernetes
# ----------------------------------------
# Configure Docker daemon with settings optimized for Kubernetes:
# - systemd cgroup driver: matches kubelet's cgroup driver
# - json-file log driver with size limits: prevents log files from growing too large
# - overlay2 storage driver: recommended for production use
echo "Configuring Docker daemon..."
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

# Reload systemd daemon to recognize Docker configuration changes
systemctl daemon-reload

# Enable Docker to start automatically on boot
systemctl enable docker

# Restart Docker with new configuration
systemctl restart docker

# =========================================================================
# PHASE 3: KUBERNETES TOOLS INSTALLATION
# =========================================================================

# ----------------------------------------
# Clean Up Old Kubernetes Repository
# ----------------------------------------
echo "Cleaning up old Kubernetes repository configuration..."

# Remove old repository configuration (if exists)
sudo rm -f /etc/apt/sources.list.d/kubernetes.list

# Remove deprecated apt-key (Google's old signing key)
sudo apt-key del 7F92E05B31093BEF5A3C2D38FEEA9169307EA071 2>/dev/null || true

# ----------------------------------------
# Set Up New Kubernetes Repository
# ----------------------------------------
echo "Setting up new Kubernetes repository..."

# Install required packages for secure repository access
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# Create directory for storing GPG keyrings (modern approach)
sudo mkdir -p -m 755 /etc/apt/keyrings

# Download and install Kubernetes signing key
# This key is used to verify the integrity of Kubernetes packages
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add Kubernetes repository to sources list
# This uses the new pkgs.k8s.io repository (replaces old apt.kubernetes.io)
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list

# ----------------------------------------
# Install Kubernetes Components
# ----------------------------------------
echo "Installing Kubernetes tools..."

# Update package list to include new Kubernetes repository
sudo apt-get update

# Install Kubernetes components:
# - kubelet: runs on every node, manages pods and containers
# - kubeadm: tool for bootstrapping clusters
# - kubectl: command-line tool for interacting with clusters
sudo apt-get install -y kubelet kubeadm kubectl

# Prevent automatic updates of Kubernetes packages
# This is important for cluster stability - you want to control when these update
sudo apt-mark hold kubelet kubeadm kubectl

# Enable kubelet service (it will fail until cluster is initialized - this is normal)
sudo systemctl enable --now kubelet

# ----------------------------------------
# Pre-pull Kubernetes Images
# ----------------------------------------
echo "Pre-pulling Kubernetes control plane images..."
# Download required container images in advance to speed up cluster initialization
# This downloads images for etcd, API server, controller manager, scheduler, etc.
kubeadm config images pull
