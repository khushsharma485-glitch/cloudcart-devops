variable "identifier" {
  description = "RDS instance identifier and name prefix."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Database subnets (at least two AZs)."
  type        = list(string)
}

variable "allowed_security_groups" {
  description = "Security groups allowed to connect on 5432, keyed by a static name, e.g. { eks = sg-123 }."
  type        = map(string)
}

variable "engine_major_version" {
  description = "PostgreSQL major version. Kept in step with the Testcontainers image used in CI."
  type        = string
  default     = "16"
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "database_name" {
  type    = string
  default = "cloudcart"
}

variable "master_username" {
  type    = string
  default = "cloudcart_admin"
}

variable "allocated_storage_gb" {
  type    = number
  default = 20
}

variable "max_allocated_storage_gb" {
  description = "Upper bound for storage autoscaling."
  type        = number
  default     = 100
}

variable "multi_az" {
  description = "Synchronous standby in a second AZ with automatic failover."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "skip_final_snapshot" {
  type    = bool
  default = false
}

variable "performance_insights_enabled" {
  type    = bool
  default = true
}

variable "enhanced_monitoring_interval" {
  description = "Seconds between OS metrics samples (0 disables, 1/5/10/15/30/60)."
  type        = number
  default     = 0
}

variable "slow_query_log_ms" {
  description = "Statements slower than this are logged to CloudWatch."
  type        = number
  default     = 500
}

variable "apply_immediately" {
  type    = bool
  default = false
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic for CloudWatch alarm notifications."
  type        = string
  default     = null
}

variable "free_storage_alarm_bytes" {
  type    = number
  default = 2 * 1024 * 1024 * 1024
}

variable "max_connections_alarm" {
  type    = number
  default = 80
}
