resource "local_file" "kubeconfig" {
  content              = base64decode(linode_lke_cluster.demo_cluster.kubeconfig)
  filename             = "${path.module}/kubeconfig"
  file_permission      = "0777"
  directory_permission = "0777"
}

output "pg_host" {
  value = linode_database_postgresql_v2.pg_demo.host_primary
}

output "pg_port" {
  value = linode_database_postgresql_v2.pg_demo.port
}

output "pg_user" {
  value     = linode_database_postgresql_v2.pg_demo.root_username
  sensitive = true
}

output "pg_password" {
  value     = linode_database_postgresql_v2.pg_demo.root_password
  sensitive = true
}

output "pg_database" {
  value = var.pg_database
}

output "lke_cluster_id" {
  value = linode_lke_cluster.demo_cluster.id
}
