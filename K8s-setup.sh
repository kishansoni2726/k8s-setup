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

# =========================================================================
# PHASE 4: CLUSTER INITIALIZATION
# =========================================================================

echo "========================================="
echo "CLUSTER INITIALIZATION"
echo "========================================="

# ----------------------------------------
# Initialize Kubernetes Control Plane
# ----------------------------------------
# Create the control plane components including:
# - etcd (cluster database)
# - kube-apiserver (API server)
# - kube-controller-manager (manages controllers)
# - kube-scheduler (schedules pods)
# The --pod-network-cidr flag reserves IP range for pod networking (required for Flannel CNI)
# This process may take 2-5 minutes
echo "Initializing Kubernetes cluster..."
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# ----------------------------------------
# Configure kubectl Authentication
# ----------------------------------------
echo "Configuring kubectl access..."

# These commands set up kubectl to authenticate with your new cluster
# The admin.conf file contains certificates and cluster connection details
# Without this, kubectl will try to connect to localhost:8080 and fail

# Create .kube directory in user's home directory
mkdir -p $HOME/.kube

# Copy the admin configuration file to user's kubectl config location
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config

# Change ownership of config file to current user (needed since we copied with sudo)
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# ----------------------------------------
# Verify Cluster Status
# ----------------------------------------
echo "Verifying cluster initialization..."
# This should now work and show your control plane node
# Initially the node will be "NotReady" until we install a CNI plugin
kubectl get nodes

# ----------------------------------------
# Install Container Network Interface (CNI)
# ----------------------------------------
echo "Installing Flannel CNI plugin..."
# Kubernetes requires a CNI plugin for pod-to-pod networking
# Without this, pods cannot communicate and the node stays "NotReady"
# Flannel is a simple overlay network - other options include Calico, Weave Net, etc.
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# ----------------------------------------
# Final Verification
# ----------------------------------------
echo "Waiting for system components to start..."
sleep 30

echo "Checking system pods status..."
kubectl get pods -n kube-system

echo "Checking final node status..."
kubectl get nodes

echo "========================================="
echo "SETUP COMPLETE!"
echo "========================================="
echo "Your Kubernetes cluster is now ready."
echo ""
echo "IMPORTANT: Save the 'kubeadm join' command that was displayed above!"
echo "You'll need it to add worker nodes to your cluster."
echo ""
echo "If you lost the join command, regenerate it with:"
echo "  kubeadm token create --print-join-command"
echo ""
echo "For a single-node cluster, remove the control-plane taint:"
echo "  kubectl taint nodes --all node-role.kubernetes.io/control-plane-"
