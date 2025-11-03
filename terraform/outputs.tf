output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.deepseek_ocr.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.deepseek_ocr.zone_id
}

output "ec2_instance_id" {
  description = "ID of the EC2 instance for SSM access"
  value       = aws_instance.deepseek_ocr.id
}

output "ec2_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.deepseek_ocr.private_ip
}

output "alb_security_group_id" {
  description = "Security group ID for the ALB"
  value       = aws_security_group.alb.id
}

output "ec2_security_group_id" {
  description = "Security group ID for the EC2 instance"
  value       = aws_security_group.ec2.id
}

output "api_endpoint" {
  description = "API endpoint URL"
  value       = "http://${aws_lb.deepseek_ocr.dns_name}:8000"
}

output "frontend_endpoint" {
  description = "Frontend endpoint URL"
  value       = "http://${aws_lb.deepseek_ocr.dns_name}:8501"
}

output "ssm_connect_command" {
  description = "Command to connect to the instance via SSM"
  value       = "aws ssm start-session --target ${aws_instance.deepseek_ocr.id} --region ${var.aws_region}"
}

output "lambda_function_name" {
  description = "Name of the Lambda function for instance scheduling"
  value       = var.enable_scheduling ? aws_lambda_function.instance_scheduler[0].function_name : "Scheduling disabled"
}

output "stop_schedule" {
  description = "Schedule for stopping the instance"
  value       = var.enable_scheduling ? "Weekdays at ${var.stop_time_utc}:00 UTC (9:00 PM UTC+7), Weekends: Friday ${var.stop_time_utc}:00 UTC until Monday ${var.start_time_utc}:00 UTC" : "Scheduling disabled"
}

output "start_schedule" {
  description = "Schedule for starting the instance"
  value       = var.enable_scheduling ? "Weekdays at ${var.start_time_utc}:00 UTC (9:00 AM UTC+7), Weekends: Off Saturday-Sunday" : "Scheduling disabled"
}
