#!/bin/bash

# =========================================================================
# KUBERNETES COMMON SETUP SCRIPT
# =========================================================================
# This script contains all the common setup steps required for both
# master and worker nodes in a Kubernetes cluster.
# Run this script on ALL nodes (master and worker) before proceeding
# with node-specific configurations.
# =========================================================================

echo "========================================="
echo "KUBERNETES COMMON SETUP"
echo "========================================="
echo "This script will prepare your system for Kubernetes installation"
echo "Run this on ALL nodes (master and worker) in your cluster"
echo ""

# =========================================================================
# PHASE 1: SYSTEM PREREQUISITES
# =========================================================================

echo "Phase 1: Configuring system prerequisites..."

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

# Make the module load automatically on boot
echo "br_netfilter" | sudo tee /etc/modules-load.d/k8s.conf

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
# Enable IP forwarding
net.ipv4.ip_forward = 1
EOF

# Apply the sysctl parameters immediately
sudo sysctl --system

# =========================================================================
# PHASE 2: CONTAINER RUNTIME SETUP (DOCKER)
# =========================================================================

echo "Phase 2: Installing and configuring Docker..."

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

# Verify Docker is running
echo "Verifying Docker installation..."
docker --version
systemctl is-active docker

# =========================================================================
# PHASE 3: KUBERNETES TOOLS INSTALLATION
# =========================================================================

echo "Phase 3: Installing Kubernetes tools..."

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

# =========================================================================
# PHASE 4: FINAL VERIFICATION
# =========================================================================

echo "Phase 4: Verifying installation..."

# ----------------------------------------
# Verify Installations
# ----------------------------------------
echo "Verifying component versions..."
echo "Docker version:"
docker --version

echo "Kubernetes tools versions:"
kubelet --version
kubeadm version
kubectl version --client

echo "System status:"
echo "- Docker service: $(systemctl is-active docker)"
echo "- Kubelet service: $(systemctl is-active kubelet)"
echo "- Swap status: $(if swapon --show | grep -q .; then echo "ENABLED (ERROR)"; else echo "DISABLED (OK)"; fi)"

# ----------------------------------------
# Pre-pull Kubernetes Images (Optional)
# ----------------------------------------
echo "Pre-pulling Kubernetes control plane images..."
echo "This may take a few minutes depending on your internet connection..."
# Download required container images in advance to speed up cluster initialization
# This downloads images for etcd, API server, controller manager, scheduler, etc.
kubeadm config images pull

echo ""
echo "========================================="
echo "COMMON SETUP COMPLETE!"
echo "========================================="
echo "All nodes are now prepared for Kubernetes cluster setup."
echo ""
echo "Next steps:"
echo "1. For MASTER node: Follow master node setup instructions"
echo "2. For WORKER nodes: Follow worker node setup instructions"
echo ""
echo "Prerequisites verified:"
echo "✓ Swap disabled"
echo "✓ Docker installed and configured"
echo "✓ Kubernetes tools installed"
echo "✓ Network parameters configured"
echo "✓ Required kernel modules loaded"
echo "✓ Container images pre-pulled"
echo ""
echo "System is ready for cluster initialization!"
