# 🗳️ Linode LKE Voting App Demo

A complete Terraform-based demo showcasing a scalable Kubernetes Voting App deployed on **Linode Kubernetes Engine (LKE)** with:

- 🔄 Horizontal Pod Autoscaling (HPA)
- 🧠 Metrics Server Patch
- 🗳️ Voting app (Redis, Flask, Worker, PostgreSQL)
- ☁️ Linode Managed PostgreSQL
- 📦 Kubernetes-native init job for DB setup

---

## 🚀 Features

| Feature                  | Description                                                  |
|--------------------------|--------------------------------------------------------------|
| 🌐 LKE Cluster           | Linode Kubernetes Engine with 3 worker nodes                |
| 🗳️ Voting App           | Flask-based app with Redis + PostgreSQL                     |
| ⚙️ Terraform Automation | Full Infra & App lifecycle via Terraform                    |
| 📈 HPA Enabled           | CPU-based autoscaling of `vote`, `result`, `worker` pods    |
| 📊 Metrics Server Patch | Secure port + TLS fix for HPA                                |
| 🔐 Secrets Injection     | PostgreSQL credentials as Kubernetes Secret                 |
| 🧩 DB Init Job          | Kubernetes Job to bootstrap DB and tables                   |

---
## 🏗️ Architecture

This diagram shows how each component of the Voting App interacts:

![Architecture](https://github.com/kodekloudhub/example-voting-app/raw/master/architecture.png)

- **Vote UI**: Flask app that pushes votes to Redis.
- **Redis**: Queue that temporarily holds votes.
- **Worker**: Background process that pulls from Redis and writes to PostgreSQL.
- **Result UI**: Displays real-time vote counts from PostgreSQL.
- **PostgreSQL**: Linode Managed Database used as a persistent store.
- **HPA**: Automatically scales components based on CPU usage.

---

## 📁 Project Structure

```
linode-lke-voting-app/
├── main.tf
├── variables.tf
├── terraform.tfvars
├── outputs.tf
├── kubeconfig
├── terraform.tfstate*
├── README.md
└── voting-app/
    ├── vote-deployment.yaml
    ├── result-deployment.yaml
    ├── worker-deployment.yaml
    ├── redis-deployment.yaml
    ├── db-init-job.yaml
    ├── hpa.yaml
    ├── services.yaml
    ├── vote-service.yaml
    └── result-service.yaml
```

---

## 🧰 Prerequisites

- ✅ [Terraform](https://www.terraform.io/downloads.html) v1.3+
- ✅ [kubectl](https://kubernetes.io/docs/tasks/tools/) installed
- ✅ `linode-cli` configured with your access token
- ✅ Export `TF_VAR_linode_token` or set in `terraform.tfvars`

---

## 🚀 How to Deploy

### 1. Clone the Repository

```bash
git clone https://github.com/YOUR-USERNAME/linode-lke-voting-app.git
cd linode-lke-voting-app
```

### 2. Configure Variables

Edit `terraform.tfvars`:

```hcl
linode_token  = "your-linode-token"
region        = "ap-south"
cluster_label = "voting-cluster"
pg_database   = "voting"
```

### 3. Initialize & Deploy

```bash
terraform init
terraform apply -auto-approve
```

---

## 🌐 Access the App

Get the external IP of the vote service:

```bash
kubectl get svc vote -o wide
```

Then open:

```
http://<EXTERNAL-IP>
```

To access the result app:

```bash
kubectl get svc result -o wide
```

---

## 🔬 Test HPA (Autoscaling)

### Simulate Load:

```bash
seq 1 20 | xargs -n1 -P20 -I{} bash -c 'while true; do curl -s http://<EXTERNAL-IP> -d "vote=a" > /dev/null; done'
```

### Monitor Scaling:

```bash
kubectl get hpa -w
```

---

## 🧹 Cleanup

```bash
terraform destroy -auto-approve
```

---

## 🙌 Acknowledgements

Powered by:

- [Terraform](https://terraform.io)
- [Kubernetes](https://kubernetes.io)
- [Linode LKE](https://www.linode.com/products/kubernetes/)
- [Docker Voting App](https://github.com/dockersamples/example-voting-app)

> 💡 Maintained by [@sandipgangdhar](https://github.com/sandipgangdhar)
