# Kubernetes Installation Guide for AWS EC2 (Ubuntu)

**Last Updated:** January 14, 2026  
**Kubernetes Version:** v1.31  
**Supported OS:** Ubuntu 20.04, 22.04, 24.04  
**Container Runtime:** containerd

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [EC2 Instance Requirements](#ec2-instance-requirements)
3. [Security Group Configuration](#security-group-configuration)
4. [Installation Steps](#installation-steps)
5. [Cluster Initialization](#cluster-initialization)
6. [Adding Worker Nodes](#adding-worker-nodes)
7. [Verification](#verification)
8. [Common Problems and Solutions](#common-problems-and-solutions)
9. [Post-Installation Tasks](#post-installation-tasks)

---

## Prerequisites

### Required for All Nodes

- AWS EC2 instance running Ubuntu 20.04, 22.04, or 24.04
- Root or sudo access
- Internet connectivity
- Unique hostname, MAC address, and product_uuid for every node

### Not Supported

- Amazon Linux 2 (has dependency conflicts - use EKS instead)
- Ubuntu 18.04 or older
- Debian-based systems other than Ubuntu

---

## EC2 Instance Requirements

### Master Node (Control Plane)

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| vCPU | 2 | 4+ |
| RAM | 2 GB | 4+ GB |
| Disk | 20 GB | 50+ GB |
| Instance Type | t3.small | t3.medium or larger |

### Worker Node

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| vCPU | 1 | 2+ |
| RAM | 1 GB | 2+ GB |
| Disk | 20 GB | 50+ GB |
| Instance Type | t2.micro | t3.small or larger |

**Important:** Using undersized instances will cause:
- Pods failing to schedule
- OOM (Out of Memory) kills
- Slow or failed cluster initialization

---

## Security Group Configuration

### Master Node Security Group

**Inbound Rules:**

| Port/Protocol | Source | Purpose |
|---------------|--------|---------|
| 6443/TCP | Worker nodes, your IP | Kubernetes API server |
| 2379-2380/TCP | Master nodes only | etcd server client API |
| 10250/TCP | Master and Worker nodes | Kubelet API |
| 10259/TCP | Master nodes only | kube-scheduler |
| 10257/TCP | Master nodes only | kube-controller-manager |
| 22/TCP | Your IP | SSH access |

### Worker Node Security Group

**Inbound Rules:**

| Port/Protocol | Source | Purpose |
|---------------|--------|---------|
| 10250/TCP | Master nodes | Kubelet API |
| 30000-32767/TCP | External (if needed) | NodePort Services |
| 22/TCP | Your IP | SSH access |

### For Flannel CNI (All Nodes)

| Port/Protocol | Source | Purpose |
|---------------|--------|---------|
| 8472/UDP | All cluster nodes | VXLAN overlay network |
| 8285/UDP | All cluster nodes | Flannel UDP backend |

### For Calico CNI (All Nodes)

| Port/Protocol | Source | Purpose |
|---------------|--------|---------|
| 179/TCP | All cluster nodes | BGP |
| 4789/UDP | All cluster nodes | VXLAN (if using) |

**Outbound Rules:** Allow all traffic (default)

---

## Installation Steps

### Step 1: Download and Run Installation Script

On **ALL nodes** (master and workers):

```bash
# Download the installation script
wget https://your-repo/k8s-install.sh
# OR create it manually with the provided script

# Make it executable
chmod +x k8s-install.sh

# Run the script with sudo
sudo ./k8s-install.sh
```

### Step 2: Wait for Completion

The script will:
- Stop automatic updates (prevent lock conflicts)
- Disable swap
- Load kernel modules
- Install containerd
- Install Kubernetes components (kubelet, kubeadm, kubectl)

**Expected Duration:** 3-5 minutes

**Success Indicator:**
```
🎉 KUBERNETES INSTALLATION COMPLETED SUCCESSFULLY
```

**Installation Log Location:** `/var/log/k8s-install.log`

---

## Cluster Initialization

### On Master Node ONLY

#### Step 1: Initialize the Cluster

```bash
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
```

**Expected Output:**
```
Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

Then you can join any number of worker-nodes by running the following on each as root:

kubeadm join 172.31.32.169:6443 --token abc123.def456ghi789 \
    --discovery-token-ca-cert-hash sha256:1234567890abcdef...
```

**Duration:** 2-5 minutes

**IMPORTANT:** Save the `kubeadm join` command - you'll need it for worker nodes!

#### Step 2: Configure kubectl

Run these commands as your **regular user** (ubuntu), NOT as root:

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

**Verify kubectl works:**
```bash
kubectl get nodes
```

**Expected Output:**
```
NAME               STATUS     ROLES           AGE   VERSION
ip-172-31-32-169   NotReady   control-plane   30s   v1.31.14
```

**Status is "NotReady"** - this is normal! You need to install a CNI plugin.

#### Step 3: Install CNI Network Plugin

**Option A: Flannel (Recommended for beginners)**

```bash
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

**Option B: Calico (Better for production)**

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/custom-resources.yaml
```

**Wait 30-60 seconds**, then check:

```bash
kubectl get nodes
```

**Expected Output:**
```
NAME               STATUS   ROLES           AGE   VERSION
ip-172-31-32-169   Ready    control-plane   2m    v1.31.14
```

Node should now be **Ready**!

#### Step 4: Verify All Pods are Running

```bash
kubectl get pods -A
```

**Expected Output:**
```
NAMESPACE      NAME                                       READY   STATUS    RESTARTS   AGE
kube-flannel   kube-flannel-ds-xxxxx                      1/1     Running   0          1m
kube-system    coredns-xxxxxxxxxx-xxxxx                   1/1     Running   0          3m
kube-system    coredns-xxxxxxxxxx-xxxxx                   1/1     Running   0          3m
kube-system    etcd-ip-172-31-32-169                      1/1     Running   0          3m
kube-system    kube-apiserver-ip-172-31-32-169            1/1     Running   0          3m
kube-system    kube-controller-manager-ip-172-31-32-169   1/1     Running   0          3m
kube-system    kube-proxy-xxxxx                           1/1     Running   0          3m
kube-system    kube-scheduler-ip-172-31-32-169            1/1     Running   0          3m
```

All pods should be **Running** with **READY 1/1**.

#### Step 5 (Optional): Allow Pods on Master

By default, master nodes don't run application pods. For **single-node clusters**, run:

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

---

## Adding Worker Nodes

### Step 1: Get Join Command

On the **master node**, if you lost the join command:

```bash
kubeadm token create --print-join-command
```

**Output:**
```
kubeadm join 172.31.32.169:6443 --token abc123.def456ghi789 \
    --discovery-token-ca-cert-hash sha256:1234567890abcdef...
```

### Step 2: Run Join Command on Worker

On each **worker node**:

```bash
sudo kubeadm join 172.31.32.169:6443 --token abc123.def456ghi789 \
    --discovery-token-ca-cert-hash sha256:1234567890abcdef...
```

**Expected Output:**
```
[preflight] Running pre-flight checks
[preflight] Reading configuration from the cluster...
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[kubelet-start] Starting the kubelet
This node has joined the cluster:
* Certificate signing request was sent to apiserver and a response was received.
* The Kubelet was informed of the new secure connection details.

Run 'kubectl get nodes' on the control-plane to see this node join the cluster.
```

### Step 3: Verify on Master

On the **master node**:

```bash
kubectl get nodes
```

**Expected Output:**
```
NAME               STATUS   ROLES           AGE   VERSION
ip-172-31-32-169   Ready    control-plane   10m   v1.31.14
ip-172-31-45-78    Ready    <none>          1m    v1.31.14
```

Both nodes should be **Ready**.

---

## Verification

### Test Deployment

```bash
# Create a test deployment
kubectl create deployment nginx --image=nginx

# Check pods
kubectl get pods

# Expected output:
# NAME                     READY   STATUS    RESTARTS   AGE
# nginx-xxxxxxxxxx-xxxxx   1/1     Running   0          30s

# Expose as service
kubectl expose deployment nginx --port=80 --type=NodePort

# Get service details
kubectl get svc nginx

# Expected output:
# NAME    TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
# nginx   NodePort   10.96.123.456   <none>        80:31234/TCP   10s

# Test access (use node IP and NodePort)
curl http://<NODE-IP>:31234
```

### Clean Up Test

```bash
kubectl delete deployment nginx
kubectl delete service nginx
```

---

## Common Problems and Solutions

### Problem 1: "couldn't get current server API group list: connection refused"

**Error:**
```
The connection to the server localhost:8080 was refused
```

**Cause:** kubectl is not configured or cluster not initialized

**Solution:**

1. Check if cluster is initialized:
   ```bash
   sudo systemctl status kubelet
   ```

2. If not initialized, run:
   ```bash
   sudo kubeadm init --pod-network-cidr=10.244.0.0/16
   ```

3. Configure kubectl:
   ```bash
   mkdir -p $HOME/.kube
   sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
   sudo chown $(id -u):$(id -g) $HOME/.kube/config
   ```

---

### Problem 2: "[ERROR FileExisting-conntrack]: conntrack not found"

**Error during kubeadm init:**
```
[ERROR FileExisting-conntrack]: conntrack not found in system path
```

**Cause:** Missing conntrack package

**Solution:**
```bash
sudo apt-get update
sudo apt-get install -y conntrack
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
```

**Prevention:** Use the updated installation script which includes conntrack.

---

### Problem 3: Node Status "NotReady"

**Symptom:**
```bash
kubectl get nodes
# NAME         STATUS     ROLES           AGE   VERSION
# master       NotReady   control-plane   5m    v1.31.14
```

**Cause:** CNI plugin not installed

**Solution:**
```bash
# Install Flannel
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Wait 60 seconds
sleep 60

# Check again
kubectl get nodes
```

**Verification:**
```bash
kubectl get pods -n kube-flannel
# All pods should be Running
```

---

### Problem 4: "E: Could not get lock /var/lib/dpkg/lock-frontend"

**Error during installation:**
```
E: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process 1234 (unattended-upgr)
```

**Cause:** Ubuntu automatic updates running

**Solution:**
```bash
# Stop automatic updates
sudo systemctl stop unattended-upgrades
sudo killall apt apt-get unattended-upgrade

# Remove locks
sudo rm -f /var/lib/dpkg/lock-frontend
sudo rm -f /var/lib/dpkg/lock
sudo rm -f /var/cache/apt/archives/lock

# Fix any broken packages
sudo dpkg --configure -a

# Re-run installation script
sudo ./k8s-install.sh
```

**Prevention:** The updated script handles this automatically.

---

### Problem 5: Pods Stuck in "Pending" State

**Symptom:**
```bash
kubectl get pods
# NAME                     READY   STATUS    RESTARTS   AGE
# nginx-xxxxxxxxxx-xxxxx   0/1     Pending   0          2m
```

**Causes and Solutions:**

**A. Insufficient Resources**

Check node resources:
```bash
kubectl describe node <node-name> | grep -A 5 Allocated
```

Solution: Use larger EC2 instances or add more worker nodes.

**B. Master Node Taint (single-node cluster)**

```bash
# Allow pods on master
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

**C. CNI Not Working**

```bash
# Check CNI pods
kubectl get pods -n kube-flannel

# If not running, reinstall
kubectl delete -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

---

### Problem 6: "kubeadm join" Fails - Token Expired

**Error:**
```
error execution phase preflight: couldn't validate the identity of the API Server: token id "abc123" is invalid
```

**Cause:** Join tokens expire after 24 hours

**Solution:**

On master node, generate new token:
```bash
kubeadm token create --print-join-command
```

Use the new join command on worker nodes.

---

### Problem 7: CoreDNS Pods CrashLoopBackOff

**Symptom:**
```bash
kubectl get pods -n kube-system
# coredns-xxx   0/1   CrashLoopBackOff   5   3m
```

**Cause:** Loop in /etc/resolv.conf or SELinux issues

**Solution A: Check resolv.conf**

```bash
cat /etc/resolv.conf
# Should NOT have "nameserver 127.0.0.53" loop
```

Fix:
```bash
sudo rm /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
```

**Solution B: Edit CoreDNS ConfigMap**

```bash
kubectl edit configmap coredns -n kube-system

# Change:
# forward . /etc/resolv.conf
# To:
# forward . 8.8.8.8 8.8.4.4

# Restart CoreDNS
kubectl rollout restart deployment coredns -n kube-system
```

---

### Problem 8: "port 6443 already in use"

**Error during kubeadm init:**
```
error execution phase preflight: [preflight] Some fatal errors occurred:
[ERROR Port-6443]: Port 6443 is in use
```

**Cause:** Previous failed initialization

**Solution:**
```bash
# Reset kubeadm
sudo kubeadm reset -f

# Clean up
sudo rm -rf /etc/cni/net.d
sudo rm -rf $HOME/.kube/config

# Restart containerd
sudo systemctl restart containerd

# Wait 10 seconds
sleep 10

# Try init again
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
```

---

### Problem 9: Worker Node Not Joining

**Symptom:** Worker node runs join command but doesn't appear in `kubectl get nodes`

**Possible Causes:**

**A. Security Group Issues**

Verify worker can reach master on port 6443:
```bash
# On worker node
telnet <MASTER-IP> 6443
# OR
nc -zv <MASTER-IP> 6443
```

If connection fails, fix security groups.

**B. Firewall Rules**

```bash
# On master, check if firewall is blocking
sudo ufw status

# If active, allow Kubernetes ports
sudo ufw allow 6443/tcp
sudo ufw allow 2379:2380/tcp
sudo ufw allow 10250/tcp
sudo ufw allow 10259/tcp
sudo ufw allow 10257/tcp
```

**C. Different Pod Network CIDR**

Ensure worker joins with same pod CIDR as master initialization.

---

### Problem 10: Cannot Pull Images

**Symptom:**
```bash
kubectl describe pod <pod-name>
# Events:
#   Failed to pull image "nginx": rpc error: code = Unknown desc = failed to pull and unpack image
```

**Causes and Solutions:**

**A. No Internet Access**

Verify EC2 can reach internet:
```bash
ping -c 3 google.com
curl -I https://registry-1.docker.io
```

Fix: Check NAT gateway, internet gateway, route tables.

**B. Containerd Issues**

```bash
# Check containerd status
sudo systemctl status containerd

# Restart containerd
sudo systemctl restart containerd

# Check logs
sudo journalctl -u containerd -n 50
```

**C. Docker Hub Rate Limits**

Use authenticated pulls or mirror images.

---

## Post-Installation Tasks

### Set Up kubectl Autocomplete

```bash
# For current session
source <(kubectl completion bash)

# Permanently
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
source ~/.bashrc
```

### Install Kubernetes Dashboard (Optional)

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# Create admin user
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF

# Get token
kubectl -n kubernetes-dashboard create token admin-user

# Access dashboard
kubectl proxy
# Open: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

### Install Helm (Package Manager)

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

### Set Up Metrics Server (for resource monitoring)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Wait for deployment
kubectl get deployment metrics-server -n kube-system

# Test
kubectl top nodes
kubectl top pods -A
```

---

## Backup and Maintenance

### Backup etcd

```bash
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /backup/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db
```

### Upgrade Kubernetes

```bash
# Check current version
kubectl version --short

# Check available versions
apt-cache madison kubeadm

# Follow official upgrade guide:
# https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/
```

---

## Useful Commands

### Cluster Information
```bash
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get componentstatuses
```

### Troubleshooting
```bash
# Check logs
kubectl logs <pod-name>
kubectl logs <pod-name> -n <namespace>

# Describe resource
kubectl describe pod <pod-name>
kubectl describe node <node-name>

# Get events
kubectl get events -A --sort-by='.lastTimestamp'

# Shell into pod
kubectl exec -it <pod-name> -- /bin/bash

# Check kubelet logs
sudo journalctl -u kubelet -f
```

### Resource Management
```bash
# View resource usage
kubectl top nodes
kubectl top pods -A

# Scale deployment
kubectl scale deployment <name> --replicas=3

# Delete resources
kubectl delete pod <pod-name>
kubectl delete deployment <deployment-name>
```

---

## Additional Resources

- **Official Kubernetes Documentation:** https://kubernetes.io/docs/
- **kubeadm Documentation:** https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/
- **Flannel Documentation:** https://github.com/flannel-io/flannel
- **Calico Documentation:** https://docs.tigera.io/calico/latest/about/
- **Kubernetes Troubleshooting:** https://kubernetes.io/docs/tasks/debug/

---

## Summary Checklist

- [ ] EC2 instances meet minimum requirements
- [ ] Security groups configured correctly
- [ ] Installation script completed on all nodes
- [ ] Master node initialized with kubeadm init
- [ ] kubectl configured on master
- [ ] CNI plugin installed (Flannel/Calico)
- [ ] All nodes show "Ready" status
- [ ] All system pods are "Running"
- [ ] Worker nodes joined successfully
- [ ] Test deployment works
- [ ] kubectl autocomplete configured

---

**Document Version:** 1.0  
**Date:** January 14, 2026  
**Tested On:** Ubuntu 24.04 LTS, AWS EC2
