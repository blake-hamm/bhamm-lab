variable "environment" {
  description = "Environment name (dev/prod)"
  type        = string
}

variable "count_k3s_master" {
  description = "Number of master nodes"
  type        = number
}

variable "count_k3s_worker" {
  description = "Number of worker nodes"
  type        = number
}

variable "master_vm_id_start" {
  description = "Starting VM ID for masters"
  type        = number
}

variable "worker_vm_id_start" {
  description = "Starting VM ID for workers"
  type        = number
}

variable "master_ip_format" {
  description = "Format string for master IPs"
  type        = string
}

variable "worker_ip_format" {
  description = "Format string for worker IPs"
  type        = string
}

variable "cpu_cores_master" {
  type    = number
  default = 3
}

variable "cpu_cores_worker" {
  type    = number
  default = 2
}

variable "memory_dedicated_base" {
  type    = number
  default = 16384
}