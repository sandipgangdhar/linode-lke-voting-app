variable "linode_token" {
  description = "Linode API token"
  type        = string
  sensitive   = true
}

variable "node_type" {
  type    = string
  default = "g6-standard-2"
}

variable "cluster_label" {
  description = "Label for the LKE cluster"
  type        = string
}

variable "region" {
  description = "Linode region"
  type        = string
}

variable "k8s_version" {
  description = "LKE Kubernetes version"
  type        = string
}

variable "node_count" {
  type    = number
  default = 3
}

variable "pg_database" {
  type        = string
  description = "PostgreSQL database name"
  default = "voting"
}
