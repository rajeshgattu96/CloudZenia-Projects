output "endpoint" {
  value = aws_db_instance.db_instance.address
}

output "db_port" {
  value = aws_db_instance.db_instance.port
}
