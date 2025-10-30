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
