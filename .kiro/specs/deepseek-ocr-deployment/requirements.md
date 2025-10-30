# Requirements Document

## Introduction

This document specifies the requirements for deploying DeepSeek-OCR, a vision-language model for optical character recognition tasks, on an AWS EC2 g6.xlarge instance. The system will provide both a Streamlit-based web interface for interactive use and an OpenAI-compatible API endpoint for programmatic access. The deployment will be automated using Terraform infrastructure-as-code.

## Glossary

- **DeepSeek-OCR System**: The complete deployment including the ML model, API server, and web interface
- **Streamlit Frontend**: The web-based user interface for interacting with the OCR model
- **OpenAI API Endpoint**: A REST API endpoint compatible with OpenAI's API specification for model inference
- **EC2 Instance**: The AWS g6.xlarge virtual machine hosting all components
- **Terraform Module**: The infrastructure-as-code configuration for AWS resource provisioning
- **SSM (Systems Manager)**: AWS service for secure remote access to EC2 instances
- **Model Inference**: The process of running the DeepSeek-OCR model on input images
- **ALB (Application Load Balancer)**: AWS load balancer providing a persistent public DNS endpoint for the EC2 instance

## Requirements

### Requirement 1

**User Story:** As a data scientist, I want to upload images through a web interface and select OCR task types, so that I can extract text and structured data from documents without writing code

#### Acceptance Criteria

1. WHEN a user accesses the Streamlit frontend, THE Streamlit Frontend SHALL display an image upload interface
2. WHEN a user uploads an image file, THE Streamlit Frontend SHALL accept PNG, JPG, and JPEG formats
3. THE Streamlit Frontend SHALL provide a dropdown selector with four task type options: Free OCR, Convert to Markdown, Parse Figure, and Locate Object by Reference
4. THE Streamlit Frontend SHALL provide a dropdown selector with five model size options: Tiny, Small, Base, Large, and Gundam
5. WHERE the user selects Locate Object by Reference task, THE Streamlit Frontend SHALL display a text input field for reference text
6. WHEN a user submits an image with selected parameters, THE Streamlit Frontend SHALL display the OCR results as text output
7. WHERE the model generates bounding boxes, THE Streamlit Frontend SHALL display the result image with visual annotations

### Requirement 2

**User Story:** As a developer, I want to access the DeepSeek-OCR model through an OpenAI-compatible API, so that I can integrate OCR capabilities into my applications programmatically

#### Acceptance Criteria

1. THE DeepSeek-OCR System SHALL expose an HTTP endpoint compatible with OpenAI API specification
2. WHEN a client sends a POST request to the API endpoint with an image, THE OpenAI API Endpoint SHALL process the image using the DeepSeek-OCR model
3. WHEN a client includes task type parameters in the request, THE OpenAI API Endpoint SHALL execute the specified OCR task
4. THE OpenAI API Endpoint SHALL return responses in JSON format matching OpenAI API response structure
5. WHEN the API receives invalid requests, THE OpenAI API Endpoint SHALL return appropriate HTTP error codes with descriptive messages

### Requirement 3

**User Story:** As a DevOps engineer, I want to deploy the entire infrastructure using Terraform, so that I can provision and manage AWS resources in a reproducible and version-controlled manner

#### Acceptance Criteria

1. THE Terraform Module SHALL provision a g6.xlarge EC2 instance in the us-west-2 region
2. THE Terraform Module SHALL provision an Application Load Balancer with target groups for ports 8501 and 8000
3. THE Terraform Module SHALL configure security groups allowing inbound HTTP traffic to the ALB on ports 80, 8501, and 8000
4. THE Terraform Module SHALL configure security groups allowing traffic from the ALB to the EC2 instance on ports 8501 and 8000
5. THE Terraform Module SHALL attach an IAM role enabling SSM access to the EC2 instance
6. THE Terraform Module SHALL provision the instance with sufficient EBS storage for the DeepSeek-OCR model weights
7. WHEN terraform apply is executed, THE Terraform Module SHALL output the ALB DNS name for accessing the services
8. THE Terraform Module SHALL configure user data scripts to install dependencies and start services on instance launch

### Requirement 4

**User Story:** As a system administrator, I want to remotely access the EC2 instance using AWS SSM, so that I can troubleshoot and manage the deployment without exposing SSH ports

#### Acceptance Criteria

1. THE EC2 Instance SHALL have the SSM agent installed and running
2. WHEN an administrator executes aws ssm start-session command, THE EC2 Instance SHALL establish a secure shell session
3. THE Terraform Module SHALL create IAM policies granting SSM session permissions
4. THE EC2 Instance SHALL register with AWS Systems Manager service upon startup

### Requirement 5

**User Story:** As an end user, I want both the web interface and API to be publicly accessible over the internet via a persistent DNS name, so that I can access the OCR service from any location without IP address changes

#### Acceptance Criteria

1. THE Streamlit Frontend SHALL be accessible via the ALB DNS name on port 8501 from any public IP address
2. THE OpenAI API Endpoint SHALL be accessible via the ALB DNS name on port 8000 from any public IP address
3. WHEN a user navigates to http://[alb-dns]:8501, THE Streamlit Frontend SHALL load successfully
4. WHEN a client sends requests to http://[alb-dns]:8000, THE OpenAI API Endpoint SHALL respond successfully
5. THE ALB SHALL maintain a persistent DNS name regardless of EC2 instance changes
6. THE ALB SHALL perform health checks on both service ports and route traffic only to healthy targets

### Requirement 6

**User Story:** As a developer, I want automated setup scripts to configure the environment, so that the deployment process is consistent and requires minimal manual intervention

#### Acceptance Criteria

1. THE DeepSeek-OCR System SHALL include a setup script that installs Python dependencies
2. THE DeepSeek-OCR System SHALL include a script that downloads and caches the DeepSeek-OCR model weights
3. THE DeepSeek-OCR System SHALL include systemd service files for automatic service startup
4. WHEN the EC2 instance boots, THE EC2 Instance SHALL automatically start both the Streamlit frontend and API server
5. THE DeepSeek-OCR System SHALL include health check scripts to verify service availability

### Requirement 7

**User Story:** As a project maintainer, I want a single comprehensive README file, so that users can understand the deployment process and usage without navigating multiple documentation files

#### Acceptance Criteria

1. THE DeepSeek-OCR System SHALL include a README.md file in the root directory
2. THE README.md SHALL document prerequisites including AWS credentials and Terraform installation
3. THE README.md SHALL provide step-by-step deployment instructions
4. THE README.md SHALL document how to access and test both the web interface and API endpoint
5. THE README.md SHALL include troubleshooting guidance for common issues
6. THE README.md SHALL document how to use SSM for remote access
