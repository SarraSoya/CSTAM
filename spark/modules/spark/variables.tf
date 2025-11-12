variable "vpc_id" {
  description = "ID du VPC"
  type        = string
}

variable "subnet_id" {
  description = "ID du subnet public"
  type        = string
}

variable "key_name" {
  description = "Nom de la paire de clés SSH"
  type        = string
}