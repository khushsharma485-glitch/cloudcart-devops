# PostgreSQL on RDS.
#
# - Lives in the database subnets (no Internet route) and only accepts
#   connections from the security groups passed in (the EKS nodes).
# - The master password is generated and stored by RDS in AWS Secrets
#   Manager (manage_master_user_password). It never appears in Terraform
#   code, state, CI logs or Git. Pods receive it via External Secrets.
# - TLS is enforced (rds.force_ssl), storage is encrypted, and logs plus
#   key metrics go to CloudWatch.

resource "aws_db_subnet_group" "this" {
  name       = var.identifier
  subnet_ids = var.subnet_ids
  tags       = { Name = var.identifier }
}

resource "aws_security_group" "this" {
  name        = "${var.identifier}-rds"
  description = "PostgreSQL access for ${var.identifier}"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.identifier}-rds" }
}

# Keys are static names so for_each works even though the security group
# IDs are only known after apply.
resource "aws_vpc_security_group_ingress_rule" "postgres" {
  for_each = var.allowed_security_groups

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from ${each.key}"
}

resource "aws_db_parameter_group" "this" {
  name   = "${var.identifier}-pg${var.engine_major_version}"
  family = "postgres${var.engine_major_version}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = tostring(var.slow_query_log_ms)
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "monitoring" {
  count = var.enhanced_monitoring_interval > 0 ? 1 : 0
  name  = "${var.identifier}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count      = var.enhanced_monitoring_interval > 0 ? 1 : 0
  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "this" {
  identifier = var.identifier

  engine                     = "postgres"
  engine_version             = var.engine_major_version
  auto_minor_version_upgrade = true
  instance_class             = var.instance_class

  db_name                     = var.database_name
  username                    = var.master_username
  manage_master_user_password = true

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period  = var.backup_retention_days
  backup_window            = "02:00-03:00"
  maintenance_window       = "sun:03:30-sun:04:30"
  copy_tags_to_snapshot    = true
  delete_automated_backups = false

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.identifier}-final"

  performance_insights_enabled    = var.performance_insights_enabled
  monitoring_interval             = var.enhanced_monitoring_interval
  monitoring_role_arn             = var.enhanced_monitoring_interval > 0 ? aws_iam_role.monitoring[0].arn : null
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  apply_immediately = var.apply_immediately

  depends_on = [aws_iam_role_policy_attachment.monitoring]
}

# --- CloudWatch alarms -----------------------------------------------------

locals {
  alarm_actions = var.alarm_sns_topic_arn == null ? [] : [var.alarm_sns_topic_arn]

  alarms = {
    cpu-high = {
      metric      = "CPUUtilization"
      operator    = "GreaterThanThreshold"
      threshold   = 80
      description = "RDS CPU above 80% for 10 minutes"
    }
    free-storage-low = {
      metric      = "FreeStorageSpace"
      operator    = "LessThanThreshold"
      threshold   = var.free_storage_alarm_bytes
      description = "RDS free storage below threshold"
    }
    freeable-memory-low = {
      metric      = "FreeableMemory"
      operator    = "LessThanThreshold"
      threshold   = 128 * 1024 * 1024
      description = "RDS freeable memory below 128 MiB"
    }
    connections-high = {
      metric      = "DatabaseConnections"
      operator    = "GreaterThanThreshold"
      threshold   = var.max_connections_alarm
      description = "RDS connection count unusually high (pool leak?)"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name          = "${var.identifier}-${each.key}"
  alarm_description   = each.value.description
  namespace           = "AWS/RDS"
  metric_name         = each.value.metric
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = each.value.operator
  threshold           = each.value.threshold
  treat_missing_data  = "breaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this.identifier
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}
