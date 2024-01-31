terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

provider "docker" {}

variable "database_password" {
  type        = string
  description = "The default password for the database."
  sensitive   = true
}

resource "docker_image" "postgres" {
  name         = "postgres:16-alpine"
  keep_locally = false
}

resource "docker_container" "postgres" {
  image   = docker_image.postgres.image_id
  name    = "liquibaseDb"
  restart = "always"
  env = [
    "POSTGRES_PASSWORD=var.database_password"
  ]
  ports {
    internal = 5432
    external = 5432
  }
}
