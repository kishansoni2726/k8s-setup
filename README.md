# Kubernetes Cluster Setup Guide

## Overview
This guide provides step-by-step instructions for setting up a Kubernetes cluster with one master node and multiple worker nodes.

## Prerequisites
- Ubuntu 18.04+ or similar Debian-based Linux distribution
- Minimum 2 GB RAM per node
- Network connectivity between all nodes
- Sudo privileges on all nodes

## Setup Process

### Step 1: Common Setup (Run on ALL nodes)

First, run the common setup script on **every node** (both master and worker nodes):

```bash
# Download and run the common setup script
chmod +x k8s-common-setup.sh
sudo ./k8s-common-setup.sh
```

This script will:
- Disable swap memory
- Configure kernel modules and network parameters
- Install and configure Docker
- Install Kubernetes tools (kubelet, kubeadm, kubectl)
- Pre-pull required container images

### Step 2: Master Node Setup

After the common setup is complete, run these commands **only on the master node**:

#### Initialize the Cluster
```bash
# Initialize Kubernetes Control Plane
# Creates etcd, API server, controller manager, and scheduler
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
```

#### Configure kubectl Access
```bash
# Set up kubectl authentication
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

#### Verify Cluster Initialization
```bash
# Check node status (will show "NotReady" until CNI is installed)
kubectl get nodes
```

#### Install Container Network Interface (CNI)
```bash
# Install Flannel CNI for pod networking
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

#### Final Verification
```bash
# Wait for components to start
sleep 30

# Check system pods
kubectl get pods -n kube-system

# Verify node is Ready
kubectl get nodes
```

#### Get Worker Join Command
```bash
# Generate join command for worker nodes
kubeadm token create --print-join-command
```

**⚠️ IMPORTANT:** Save the join command output - you'll need it for worker nodes!

### Step 3: Worker Node Setup

After completing the common setup on worker nodes, join them to the cluster:

#### Join the Cluster
```bash
# Use the join command from the master node
# Replace <MASTER-IP>, <TOKEN>, and <HASH> with actual values from your master node
sudo kubeadm join <MASTER-IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>
```

#### Verify from Master Node
```bash
# Run this on the master node to see all nodes
kubectl get nodes
```

## Node-Specific Commands Summary

### Master Node Only
| Command | Purpose |
|---------|---------|
| `kubeadm init --pod-network-cidr=10.244.0.0/16` | Initialize control plane |
| `mkdir -p $HOME/.kube && sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config && sudo chown $(id -u):$(id -g) $HOME/.kube/config` | Configure kubectl |
| `kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml` | Install CNI |
| `kubeadm token create --print-join-command` | Generate worker join command |

### Worker Nodes Only
| Command | Purpose |
|---------|---------|
| `kubeadm join <MASTER-IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>` | Join cluster |

### Verification Commands (Master Node)
| Command | Purpose |
|---------|---------|
| `kubectl get nodes` | List all cluster nodes |
| `kubectl get pods -n kube-system` | Check system components |
| `kubectl cluster-info` | Display cluster information |

## Optional Configurations

### Single-Node Cluster (Allow pods on master)
If you want to run workloads on the master node:
```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

### Regenerate Join Command
If you lose the worker join command:
```bash
# Run on master node
kubeadm token create --print-join-command
```
