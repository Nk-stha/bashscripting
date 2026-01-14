#!/bin/bash
# Kubernetes Installation Script for EC2 (Ubuntu 20.04/22.04/24.04)
# Run this on ALL nodes (master and workers)
# Updated January 2026 - Production Ready

set -e

exec > >(tee /var/log/k8s-install.log)
exec 2>&1

echo "=== Kubernetes Installation Started at $(date) ==="

# Stop any running unattended upgrades
echo "=== Stopping unattended-upgrades if running ==="
systemctl stop unattended-upgrades 2>/dev/null || true
systemctl stop apt-daily.timer 2>/dev/null || true
systemctl stop apt-daily-upgrade.timer 2>/dev/null || true
killall -9 apt apt-get unattended-upgrade 2>/dev/null || true
sleep 3

# Remove any existing locks
rm -f /var/lib/dpkg/lock-frontend 2>/dev/null || true
rm -f /var/lib/dpkg/lock 2>/dev/null || true
rm -f /var/cache/apt/archives/lock 2>/dev/null || true
dpkg --configure -a 2>/dev/null || true

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
    OS_VERSION=$VERSION_ID
    echo "Detected OS: $OS_ID $OS_VERSION"
else
    echo "ERROR: Cannot detect OS"
    exit 1
fi

# Only support Ubuntu for this script
if [ "$OS_ID" != "ubuntu" ]; then
    echo "ERROR: This script only supports Ubuntu 20.04/22.04/24.04"
    echo "For Amazon Linux 2, use Amazon EKS or see documentation"
    exit 1
fi

# Verify minimum Ubuntu version
if [ "$OS_ID" = "ubuntu" ]; then
    MAJOR_VERSION=$(echo $VERSION_ID | cut -d. -f1)
    if [ "$MAJOR_VERSION" -lt 20 ]; then
        echo "ERROR: Ubuntu 20.04 or higher is required"
        exit 1
    fi
fi

# Disable swap (required by Kubernetes)
echo "=== Disabling swap ==="
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
echo "Swap disabled and fstab updated"

# Load required kernel modules
echo "=== Loading kernel modules ==="
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Verify modules are loaded
if ! lsmod | grep -q overlay; then
    echo "ERROR: overlay module failed to load"
    exit 1
fi

if ! lsmod | grep -q br_netfilter; then
    echo "ERROR: br_netfilter module failed to load"
    exit 1
fi

echo "Kernel modules loaded successfully"

# Set required sysctl parameters
echo "=== Setting sysctl parameters ==="
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system >/dev/null 2>&1
echo "Sysctl parameters configured"

# Install required packages and dependencies
echo "=== Installing required packages ==="
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    apt-transport-https \
    conntrack \
    socat \
    ebtables \
    ipset \
    ipvsadm \
    ethtool

echo "Required packages installed"

# Install container runtime (containerd)
echo "=== Installing containerd ==="

# Add Docker's official GPG key and repository for containerd
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y containerd.io

# Verify containerd is installed
if ! command -v containerd &> /dev/null; then
    echo "ERROR: containerd installation failed"
    exit 1
fi

# Configure containerd with systemd cgroup driver
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Enable systemd cgroup driver (required for Kubernetes)
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Restart and enable containerd
systemctl restart containerd
systemctl enable containerd

# Verify containerd is running
if ! systemctl is-active --quiet containerd; then
    echo "ERROR: containerd failed to start"
    systemctl status containerd
    exit 1
fi

echo "Containerd installed and running"

# Install Kubernetes components
echo "=== Installing Kubernetes components ==="

# Set Kubernetes version
K8S_VERSION="v1.31"

# Create keyrings directory
mkdir -p /etc/apt/keyrings

# Download Kubernetes GPG key
curl -fsSL https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key | \
    gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add Kubernetes apt repository
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" | \
    tee /etc/apt/sources.list.d/kubernetes.list

# Update apt cache
apt-get update

# Install Kubernetes packages
DEBIAN_FRONTEND=noninteractive apt-get install -y kubelet kubeadm kubectl

# Verify installations
if ! command -v kubelet &> /dev/null; then
    echo "ERROR: kubelet installation failed"
    exit 1
fi

if ! command -v kubeadm &> /dev/null; then
    echo "ERROR: kubeadm installation failed"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl installation failed"
    exit 1
fi

# Hold packages at current version
apt-mark hold kubelet kubeadm kubectl

# Enable kubelet service
systemctl enable kubelet

echo "=== Kubernetes components installed successfully ==="
echo "Containerd version: $(containerd --version)"
echo "kubelet version: $(kubelet --version)"
echo "kubeadm version: $(kubeadm version -o short)"
echo "kubectl version: $(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | head -1)"

# Create completion flag
touch /tmp/k8s-install-completed

# Display next steps
cat <<'EOF'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎉 KUBERNETES INSTALLATION COMPLETED SUCCESSFULLY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 NEXT STEPS FOR MASTER NODE:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1️⃣  Initialize the Kubernetes cluster:

    sudo kubeadm init --pod-network-cidr=10.244.0.0/16

2️⃣  Configure kubectl (run as regular user, NOT root):

    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

3️⃣  Install Flannel CNI network plugin:

    kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

4️⃣  Wait 30-60 seconds, then verify the cluster:

    kubectl get nodes
    kubectl get pods -A

5️⃣  Get the join command for worker nodes:

    kubeadm token create --print-join-command

6️⃣  (Optional) Allow pods on master node (single-node cluster):

    kubectl taint nodes --all node-role.kubernetes.io/control-plane-

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
👷 NEXT STEPS FOR WORKER NODES:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1️⃣  Run the join command from master initialization:

    sudo kubeadm join <MASTER-IP>:6443 --token <TOKEN> \
        --discovery-token-ca-cert-hash sha256:<HASH>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📝 IMPORTANT NOTES:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✓ Installation log saved to: /var/log/k8s-install.log
✓ Kubernetes version: v1.31
✓ Container runtime: containerd with systemd cgroup driver
✓ CNI not yet installed (required for nodes to be Ready)

⚠️  Before initializing:
    - Ensure security groups allow required ports
    - Master needs minimum 2 CPU, 2GB RAM (t3.small minimum)
    - Worker needs minimum 1 CPU, 1GB RAM (t2.micro minimum)

🔗 For troubleshooting, see: KUBERNETES_INSTALLATION_GUIDE.md

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

echo ""
echo "=== Installation completed at $(date) ==="
