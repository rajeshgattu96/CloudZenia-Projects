resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "${var.name}-db-subnet-group"
  subnet_ids = var.private_subnets

  tags = {
    Name = "${var.name}-db-subnet-group"
  }
}

resource "aws_db_instance" "db_instance" {
  identifier              = var.identifier
  engine                  = var.engine
  engine_version          = var.engine_version
  instance_class          = var.instance_class
  allocated_storage       = var.allocated_storage
  db_name                 = var.database_name
  username                = var.username
  password                = var.password
  db_subnet_group_name    = aws_db_subnet_group.db_subnet_group.id
  vpc_security_group_ids  = [var.sg_id]
  skip_final_snapshot     = true
  publicly_accessible     = false
  backup_retention_period = var.backup_retention

  tags = {
    Name = var.name
  }
}
