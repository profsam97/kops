# 🚀 Complete Installation & Replication Guide

This guide walks you through setting up the entire production-ready FastAPI service infrastructure from scratch.

## 📋 **Prerequisites**

- **AWS Account** with admin permissions
- **Domain name** (e.g., yourdomain.com)
- **Ubuntu/Debian VM** (minimum 4GB RAM, 2 vCPUs)
- **GitHub account** with repository access

---

## 🖥️ **Step 1: VM Setup & Basic Tools**

### **1.1 Update System**
```bash
sudo apt update && sudo apt upgrade -y

# Install essential tools
sudo apt install -y curl wget unzip git vim htop
```

### **1.2 Install Docker**
```bash
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Verify installation
docker --version
```

### **1.3 Install kubectl**
```bash
# Download kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# Install kubectl
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Verify installation
kubectl version --client
```

### **1.4 Install Helm**
```bash
# Download and install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installation
helm version
```

---

## ☁️ **Step 2: AWS CLI & Configuration**

### **2.1 Install AWS CLI**
```bash
# Download AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

# Install AWS CLI
unzip awscliv2.zip
sudo ./aws/install

# Verify installation
aws --version
```

### **2.2 Configure AWS CLI**
```bash
# Configure AWS credentials, go to aws and search for iam, create a profile, then on the access tab, create a new access key, give
# it neccessary permissions like s3, ec2, elb. 
aws configure
# Enter your:
# - AWS Access Key ID
# - AWS Secret Access Key



### **2.3 Create S3 Bucket for kops State**
```bash
# Replace with your unique bucket name
export KOPS_STATE_STORE=s3://kops-state-your-unique-name
export KOPS_CLUSTER_NAME=k8s.yourdomain.com

# Create S3 bucket
aws s3 mb $KOPS_STATE_STORE --region us-east-1
# Enable versioning
aws s3api put-bucket-versioning --bucket kops-state-your-unique-name --versioning-configuration Status=Enabled
```

---

## 🔧 **Step 3: Install kops**

### **3.1 Download and Install kops**
```bash
# Download kops
curl -Lo kops https://github.com/kubernetes/kops/releases/download/$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4)/kops-linux-amd64

# Make executable and move to PATH
chmod +x kops
sudo mv kops /usr/local/bin/kops

# Verify installation
kops version
```

### **3.2 Create Kubernetes Cluster**
```bash
export KOPS_STATE_STORE=s3://kops-state-your-unique-name
export KOPS_CLUSTER_NAME=k8s.yourdomain.com

# Create cluster configuration
kops create cluster \
  --node-count=2 \
  --node-size=t3.medium \
  --master-size=t3.medium \
  --master-count=1 \
  --zones=us-east-1a \
  --name=$KOPS_CLUSTER_NAME \
  --dns-zone=yourdomain.com \
  --yes

# Wait for cluster to be ready (10-15 minutes)
kops validate cluster --wait 10m

# Verify cluster
kubectl get nodes
```

---

## 🌐 **Step 4: Install Nginx Ingress Controller**

```bash
# Install nginx ingress controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/aws/deploy.yaml

# Wait for ingress controller to be ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# Get ingress controller external IP
kubectl get service ingress-nginx-controller -n ingress-nginx
```

---

## 🔒 **Step 5: Install cert-manager**

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s

# Verify installation
kubectl get pods -n cert-manager
```

---

## 📊 **Step 6: Install Prometheus & Grafana**

```bash
# Add Prometheus community Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create monitoring namespace
kubectl create namespace monitoring

# Install Prometheus + Grafana stack
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword=admin123 \
  --set grafana.service.type=NodePort \
  --set prometheus.service.type=NodePort

# Wait for pods to be ready
kubectl get pods -n monitoring -w
```

---

## 🐙 **Step 7: GitHub & Docker Hub Setup**

### **7.1 Create Docker Hub Account**
1. Go to [hub.docker.com](https://hub.docker.com)
2. Create account
3. Create Access Token:
   - Settings → Security → New Access Token
   - Copy the token

### **7.2 Fork/Clone Repository**
```bash
# Clone  repository
git clone https://github.com/profsam97/kops.git
cd kops
```

### **7.3 Update Configuration Files**

**Update Docker Hub username in:**
- `k8s/deployment.yaml`
- `.github/workflows/ci.yml`
- `.github/workflows/cd.yml`

```bash
# Replace placeholder with your Docker Hub username
find  -name "*.yaml" -o -name "*.yml" | xargs sed -i 's/your-dockerhub-username/YOUR_ACTUAL_USERNAME/g'
```

**Update domain names in:**
- `k8s/ingress.yaml`
- `.github/workflows/cd.yml`
- `k8s/cert-manager.yaml`

```bash
# Replace with your actual domain
sed -i 's/kops.agroconnect.ng/api.yourdomain.com/g' k8s/ingress.yaml
sed -i 's/staging.kops.agroconnect.ng/api-staging.yourdomain.com/g' .github/workflows/cd.yml
sed -i 's/devops@agroconnect.ng/admin@yourdomain.com/g' k8s/cert-manager.yaml
```

---

## 🔑 **Step 8: GitHub Secrets Configuration**

### **8.1 Export Kubeconfig**
```bash
# Get kubeconfig content
cat ~/.kube/config | base64 -w 0
# Copy this entire base64 string
```

### **8.2 Add GitHub Secrets**
Go to your GitHub repository → Settings → Secrets and variables → Actions

Add these secrets:
- `DOCKERHUB_USERNAME`: Your Docker Hub username
- `DOCKERHUB_TOKEN`: Your Docker Hub access token
- `KUBECONFIG`: Base64-encoded kubeconfig from step 8.1

---

## 🌍 **Step 9: DNS Configuration**

### **9.1 Get Ingress External IP**
```bash
# Get the external IP of your ingress controller
kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### **9.2 Configure DNS Records**
In your domain registrar (Cloudflare, Route53, etc.), create:
- **A Record**: `api.yourdomain.com` → `INGRESS_EXTERNAL_IP`
- **A Record**: `api-staging.yourdomain.com` → `INGRESS_EXTERNAL_IP`

---

## 🚀 **Step 10: Deploy Application**

### **10.1 Apply cert-manager Issuers**
```bash
kubectl apply -f k8s/cert-manager.yaml
```

### **10.2 Deploy Application**
```bash
# Create namespaces and deploy
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/ -n fastapi-production

# Check deployment
kubectl get pods -n fastapi-production
kubectl get certificates -n fastapi-production
```

### **10.3 Push to GitHub (Trigger CI/CD)**
```bash
git add .
git commit -m "Initial production deployment"
git push origin main
```

---

## ✅ **Step 11: Verification**

### **11.1 Test HTTPS**
```bash
# Test production
curl -I https://api.yourdomain.com/health

# Test staging (after CI/CD completes)
curl -I https://api-staging.yourdomain.com/health
```



### **11.2 Access Monitoring**
```bash
# Get Grafana NodePort
kubectl get service -n monitoring monitoring-grafana -o jsonpath='{.spec.ports[0].nodePort}'

# Access Grafana
# http://YOUR_NODE_IP:GRAFANA_PORT
# Login: admin/admin123

##make sure you update your node worker security group to allow inbound traffic on the grafana port
```



---

## 🛠️ **Troubleshooting**

### **Common Issues**

#### Certificates not issued
```bash
# Check certificate status
kubectl describe certificate -n fastapi-production

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=50
```

#### Pods not starting
```bash
# Check pod events
kubectl describe pod POD_NAME -n fastapi-production

# Check resource limits
kubectl top pods -n fastapi-production
```

#### DNS not resolving
```bash
# Check ingress
kubectl get ingress -n fastapi-production

# Check DNS propagation
nslookup api.yourdomain.com
```

---

## 📚 **Quick Commands Reference**

```bash
# Export environment variables (add to ~/.bashrc)
export KOPS_STATE_STORE=s3://kops-state-your-unique-name
export KOPS_CLUSTER_NAME=k8s.yourdomain.com

# Check cluster status
kops validate cluster

# Scale application
kubectl scale deployment fastapi-deployment --replicas=5 -n fastapi-production

# View logs
kubectl logs -f deployment/fastapi-deployment -n fastapi-production

# Port forward for testing
kubectl port-forward service/fastapi-service 8080:80 -n fastapi-production
```

---

## 🎯 **Expected Results**

After completing this guide, you should have:

- ✅ **Kubernetes cluster** running on AWS with kops
- ✅ **FastAPI application** with auto-scaling (2-10 replicas)
- ✅ **HTTPS certificates** automatically managed by Let's Encrypt
- ✅ **CI/CD pipeline** with GitHub Actions and Docker Hub
- ✅ **Monitoring** with Prometheus and Grafana
- ✅ **Production-ready** security and best practices

**Total setup time**: ~2-3 hours (mostly waiting for cluster creation)

---

## 💡 **Tips for Success**

## for secret management we can use vault, its a better option.

