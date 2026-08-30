variable "app_name" {
  type    = string
  default = "hello-spring-boot-eks"
}

# Kubernetes namespace the app (and its Fargate profile selector) live in.
variable "namespace" {
  type    = string
  default = "hello-spring-boot-eks"
}

variable "cluster_version" {
  type    = string
  default = "1.32"
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "db_name" {
  type    = string
  default = "hellodb"
}

variable "db_username" {
  type    = string
  default = "hellouser"
}

variable "aurora_engine_version" {
  type    = string
  default = "8.0.mysql_aurora.3.08.0"
}
