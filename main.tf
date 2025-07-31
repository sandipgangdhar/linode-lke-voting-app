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

resource "null_resource" "create_voting_db" {
  depends_on = [
    linode_database_postgresql_v2.pg_demo
  ]

  provisioner "local-exec" {
    command = <<EOT
export PGPASSWORD="${linode_database_postgresql_v2.pg_demo.root_password}"
for i in {1..30}; do
  if nslookup "$DB_HOST" > /dev/null; then
    echo "DNS resolved for $DB_HOST"
    break
  fi
  echo "Waiting for DNS to resolve $DB_HOST..."
  sleep 5
done
if ! psql "host=${linode_database_postgresql_v2.pg_demo.host_primary} port=${linode_database_postgresql_v2.pg_demo.port} user=${linode_database_postgresql_v2.pg_demo.root_username} dbname=defaultdb sslmode=require" -tAc "SELECT 1 FROM pg_database WHERE datname='voting'" | grep -q 1; then
  psql "host=${linode_database_postgresql_v2.pg_demo.host_primary} port=${linode_database_postgresql_v2.pg_demo.port} user=${linode_database_postgresql_v2.pg_demo.root_username} dbname=defaultdb sslmode=require" -c "CREATE DATABASE voting;"
else
  echo "Database 'voting' already exists, skipping creation."
fi
EOT
  }

  triggers = {
    db_create_trigger = sha256("${linode_database_postgresql_v2.pg_demo.id}")
  }
}

resource "null_resource" "create_votes_table" {
  depends_on = [
    null_resource.create_voting_db
  ]

  provisioner "local-exec" {
    command = <<EOT
export PGPASSWORD="${linode_database_postgresql_v2.pg_demo.root_password}"
DB_HOST="${linode_database_postgresql_v2.pg_demo.host_primary}"
DB_PORT="${linode_database_postgresql_v2.pg_demo.port}"
DB_USER="${linode_database_postgresql_v2.pg_demo.root_username}"
DB_NAME="voting"

for i in {1..30}; do
  if getent hosts "$DB_HOST" > /dev/null; then
    echo "DNS resolved for $DB_HOST"
    break
  fi
  echo "Waiting for DNS to resolve $DB_HOST..."
  sleep 5
done

# Create the 'votes' table if it doesn't exist
psql "host=$DB_HOST port=$DB_PORT user=$DB_USER dbname=$DB_NAME sslmode=require" -c "CREATE TABLE IF NOT EXISTS votes (
  id SERIAL PRIMARY KEY,
  vote VARCHAR(255) NOT NULL
);"
EOT
  }

  triggers = {
    create_votes_table_trigger = sha256("${linode_database_postgresql_v2.pg_demo.id}")
  }
}

resource "null_resource" "install_metrics_server" {
  provisioner "local-exec" {
    command = <<EOT
      export KUBECONFIG=./kubeconfig
      kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    EOT
  }

  triggers = {
    version = "v0.7.0" # Or a hash
  }

  depends_on = [local_file.kubeconfig]
}

resource "null_resource" "inject_pg_secret" {
  depends_on = [
    linode_database_postgresql_v2.pg_demo,
    linode_lke_cluster.demo_cluster,
    null_resource.create_voting_db,
    null_resource.create_votes_table
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

resource "null_resource" "apply_voting_app_yaml" {
  depends_on = [
    linode_lke_cluster.demo_cluster,
    null_resource.inject_pg_secret,
    null_resource.install_metrics_server
  ]

  provisioner "local-exec" {
    command = <<EOT
export KUBECONFIG=./kubeconfig
kubectl apply -f terraform/voting-app/
EOT
  }
  triggers = {
    app_sha = join(",", [
      filesha256("${path.module}/terraform/voting-app/vote-deployment.yaml"),
      filesha256("${path.module}/terraform/voting-app/result-deployment.yaml"),
      filesha256("${path.module}/terraform/voting-app/worker-deployment.yaml"),
      filesha256("${path.module}/terraform/voting-app/redis-deployment.yaml"),
      filesha256("${path.module}/terraform/voting-app/services.yaml"),
      filesha256("${path.module}/terraform/voting-app/hpa.yaml"),
      filesha256("${path.module}/terraform/voting-app/traffic-generator-job.yaml"),
      filesha256("${path.module}/terraform/voting-app/vote-service.yaml"),
      filesha256("${path.module}/terraform/voting-app/result-service.yaml"),
    ])
  }
}
