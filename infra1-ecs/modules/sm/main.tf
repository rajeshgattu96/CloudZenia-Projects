resource "aws_secretsmanager_secret" "db_credentials" {
  name = var.name
}

resource "aws_secretsmanager_secret_version" "db_credentials_version" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = var.username
    password = var.password
    host     = var.host
    port     = var.port
    dbname   = var.dbname
  })
}
