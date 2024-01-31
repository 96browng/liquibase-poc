# liquibase-poc

## Docker

Terraform has been created to create the necessary docker containers for testing. Running terraform will create the necessary database container for this poc.

```
terraform apply
```

### Colima on Mac

Colima uses docker profiles which some applications, such as the Terraform docker provider, are not aware. Set the `docker.socket` location created by Colima as below.

```
export DOCKER_HOST="unix://${HOME}/.colima/docker.sock"
```
