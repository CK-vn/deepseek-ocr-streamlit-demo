variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
  default     = "dev"
}

variable "instance_type" {
  description = "EC2 instance type with GPU support"
  type        = string
  default     = "g6.xlarge"
}

variable "root_volume_size" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 100
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "deepseek-ocr"
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_scheduling" {
  description = "Enable automatic start/stop scheduling for the EC2 instance"
  type        = bool
  default     = true
}

variable "stop_time_utc" {
  description = "Time to stop the instance in UTC (24-hour format, e.g., '14' for 2 PM UTC)"
  type        = string
  default     = "14" # 2 PM UTC = 9 PM UTC+7
}

variable "start_time_utc" {
  description = "Time to start the instance in UTC (24-hour format, e.g., '02' for 2 AM UTC)"
  type        = string
  default     = "02" # 2 AM UTC = 9 AM UTC+7
}
