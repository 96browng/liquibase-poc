output "database" {
  value       = aws_rds_cluster.postgresql.endpoint
  description = "The DNS address of the RDS instance"
}
