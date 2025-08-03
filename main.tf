terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "linode" {
  token = var.linode_token
}

resource "linode_lke_cluster" "demo_cluster" {
  label       = var.cluster_label
  region      = var.region
  k8s_version = var.k8s_version

  pool {
    type  = "g6-standard-2"
    count = 3
  }
}

resource "linode_database_postgresql_v2" "pg_demo" {
  label        = "voting-db"
  engine_id    = "postgresql/15"
  region       = var.region
  type         = "g6-standard-1"
  cluster_size = 1
  allow_list   = ["0.0.0.0/0"]
}

resource "local_file" "kubeconfig" {
  content              = base64decode(linode_lke_cluster.demo_cluster.kubeconfig)
  filename             = "${path.module}/kubeconfig"
  file_permission      = "0777"
  directory_permission = "0777"
}

resource "null_resource" "install_rbac" {
  depends_on = [
    linode_lke_cluster.demo_cluster,
    local_file.kubeconfig
  ]

  provisioner "local-exec" {
    command = <<EOT
      export KUBECONFIG=./kubeconfig
      kubectl apply -f ${path.module}/voting-app/rbac.yaml
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    rbac_sha = filesha256("${path.module}/voting-app/rbac.yaml")
  }
}

resource "null_resource" "inject_pg_secret" {
  depends_on = [
    linode_database_postgresql_v2.pg_demo,
    linode_lke_cluster.demo_cluster,
    local_file.kubeconfig
  ]

  provisioner "local-exec" {
    command = <<EOT
      export KUBECONFIG=./kubeconfig
      kubectl create secret generic pg-credentials \
        --from-literal=PGHOST=${linode_database_postgresql_v2.pg_demo.host_primary} \
        --from-literal=PGUSER=${linode_database_postgresql_v2.pg_demo.root_username} \
        --from-literal=PGPASSWORD=${linode_database_postgresql_v2.pg_demo.root_password} \
        --from-literal=PGDATABASE=${var.pg_database} \
        --from-literal=PGPORT=${linode_database_postgresql_v2.pg_demo.port} \
        --from-literal=DATABASE_URL="postgresql://${linode_database_postgresql_v2.pg_demo.root_username}:${linode_database_postgresql_v2.pg_demo.root_password}@${linode_database_postgresql_v2.pg_demo.host_primary}:${linode_database_postgresql_v2.pg_demo.port}/${var.pg_database}" \
        --dry-run=client -o yaml | kubectl apply -f -
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    pg_sha = sha256("${linode_database_postgresql_v2.pg_demo.host_primary}${linode_database_postgresql_v2.pg_demo.root_username}${linode_database_postgresql_v2.pg_demo.root_password}${var.pg_database}")
  }
}

resource "null_resource" "run_db_init_job" {
  depends_on = [
    null_resource.inject_pg_secret
  ]

  provisioner "local-exec" {
    command = <<EOT
export KUBECONFIG=./kubeconfig
kubectl delete job db-init-job --ignore-not-found=true
kubectl apply -f voting-app/db-init-job.yaml
kubectl wait --for=condition=complete job/db-init-job --timeout=60s || kubectl logs job/db-init-job
EOT
  }

  triggers = {
    sha = filesha256("${path.module}/voting-app/db-init-job.yaml")
  }
}

resource "null_resource" "install_metrics_server" {
  depends_on = [
    linode_lke_cluster.demo_cluster,
    local_file.kubeconfig
  ]
  provisioner "local-exec" {
    command = <<EOT
      export KUBECONFIG=./kubeconfig
      kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    EOT
  }

  triggers = {
    version = "v0.7.0" # Or a hash
  }

}

resource "null_resource" "patch_metrics_server" {
  depends_on = [null_resource.install_metrics_server]
  provisioner "local-exec" {
    command = <<EOT
    export KUBECONFIG=./kubeconfig
kubectl -n kube-system patch deployment metrics-server --type=json -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/args/1", "value": "--secure-port=4443"},
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/ports/0/containerPort", "value": 4443},
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/httpGet/port", "value": 4443},
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/port", "value": 4443}
]'
kubectl -n kube-system rollout restart deployment metrics-server
EOT

  }

  triggers = {
    always_run = timestamp()
  }

}


resource "null_resource" "apply_voting_app_yaml" {
  depends_on = [
    null_resource.run_db_init_job,
    null_resource.patch_metrics_server
  ]

  provisioner "local-exec" {
    command = <<EOT
export KUBECONFIG=./kubeconfig
kubectl apply -f voting-app/
EOT
  }
  triggers = {
    app_sha = join(",", [
      filesha256("${path.module}/voting-app/vote-deployment.yaml"),
      filesha256("${path.module}/voting-app/result-deployment.yaml"),
      filesha256("${path.module}/voting-app/worker-deployment.yaml"),
      filesha256("${path.module}/voting-app/redis-deployment.yaml"),
      filesha256("${path.module}/voting-app/services.yaml"),
      filesha256("${path.module}/voting-app/hpa.yaml"),
      filesha256("${path.module}/voting-app/vote-service.yaml"),
      filesha256("${path.module}/voting-app/result-service.yaml"),
    ])
  }
}
