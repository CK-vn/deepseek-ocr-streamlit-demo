# Application Load Balancer
resource "aws_lb" "deepseek_ocr" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false
  enable_http2               = true

  tags = {
    Name = "${var.project_name}-alb"
  }
}

# Target Group for API (Port 8000)
resource "aws_lb_target_group" "api" {
  name     = "${var.project_name}-api-tg"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health"
    port                = "8000"
    protocol            = "HTTP"
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = {
    Name = "${var.project_name}-api-tg"
  }
}

# Target Group for Frontend (Port 8501)
resource "aws_lb_target_group" "frontend" {
  name     = "${var.project_name}-frontend-tg"
  port     = 8501
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
    port                = "8501"
    protocol            = "HTTP"
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = {
    Name = "${var.project_name}-frontend-tg"
  }
}

# Listener for API (Port 8000)
resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.deepseek_ocr.arn
  port              = "8000"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  tags = {
    Name = "${var.project_name}-api-listener"
  }
}

# Listener for Frontend (Port 8501)
resource "aws_lb_listener" "frontend" {
  load_balancer_arn = aws_lb.deepseek_ocr.arn
  port              = "8501"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }

  tags = {
    Name = "${var.project_name}-frontend-listener"
  }
}

# Target Group Attachment for API
resource "aws_lb_target_group_attachment" "api" {
  target_group_arn = aws_lb_target_group.api.arn
  target_id        = aws_instance.deepseek_ocr.id
  port             = 8000
}

# Target Group Attachment for Frontend
resource "aws_lb_target_group_attachment" "frontend" {
  target_group_arn = aws_lb_target_group.frontend.arn
  target_id        = aws_instance.deepseek_ocr.id
  port             = 8501
}
