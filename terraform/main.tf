terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 3.1.0"
    }
  }
}

provider "linode" {
  token = var.linode_token
}

resource "linode_lke_cluster" "demo_cluster" {
  label       = "lke-voting-demo"
  k8s_version = "1.33"
  region      = var.region

  pool {
    type  = var.node_type
    count = var.node_count
  }

  control_plane {
    high_availability = false
  }

  tags = ["marketing", "voting-demo"]
}

resource "linode_database_postgresql_v2" "pg_demo" {
  label        = "voting-db"
  engine_id    = "postgresql/15"
  region       = var.region
  type         = "g6-standard-1"
  cluster_size = 1
  allow_list   = ["0.0.0.0/0"]
}

resource "null_resource" "inject_pg_secret" {
  depends_on = [linode_database_postgresql_v2.pg_demo, local_file.kubeconfig]

  provisioner "local-exec" {
    command = <<EOT
export KUBECONFIG=${local_file.kubeconfig.filename}
kubectl create secret generic pg-secret \
  --from-literal=host=${linode_database_postgresql_v2.pg_demo.host_primary} \
  --from-literal=password=${linode_database_postgresql_v2.pg_demo.root_password} \
  --dry-run=client -o yaml | kubectl apply -f -
EOT
  }
}

resource "null_resource" "deploy_voting_app" {
  depends_on = [null_resource.inject_pg_secret]

  provisioner "local-exec" {
    command = <<EOT
export KUBECONFIG=${local_file.kubeconfig.filename}
kubectl apply -f ${path.module}/voting-app/
EOT
  }
}
