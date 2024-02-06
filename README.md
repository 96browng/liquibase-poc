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

## Liquibase

```
liquibase status --username=postgres --password=password --url=jdbc:postgresql://localhost:5432/postgres  --changelog-file=./db/changelog/changelog-root.sql
```


* Deploy to RDS
* Secrets Manager - password of DB
* Param Store - db location
* GitHub action pipeline
* CodeBuild - run liquibase
