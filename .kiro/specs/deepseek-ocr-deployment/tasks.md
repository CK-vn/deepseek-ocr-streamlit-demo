# Implementation Plan

- [x] 1. Set up project structure and core Python application files
  - Create directory structure: `app/`, `terraform/`, `scripts/`
  - Create `app/model_engine.py` for shared model inference logic
  - Create `app/api_server.py` for FastAPI OpenAI-compatible API
  - Create `app/streamlit_app.py` for Streamlit frontend
  - Create `requirements.txt` with all Python dependencies
  - _Requirements: 1.1, 1.2, 2.1, 6.1_

- [x] 2. Implement model inference engine
  - [x] 2.1 Create ModelManager singleton class for model loading and caching
    - Implement lazy loading pattern to load model only once
    - Configure model with Flash Attention 2 and bfloat16 precision
    - Add error handling for model loading failures
    - _Requirements: 2.1, 6.2_
  
  - [x] 2.2 Implement task prompt generation and configuration mapping
    - Create SIZE_CONFIGS dictionary mapping model sizes to parameters
    - Create TASK_PROMPTS dictionary for different OCR task types
    - Implement function to build prompts based on task type and reference text
    - _Requirements: 1.3, 1.4, 1.5_
  
  - [x] 2.3 Implement image preprocessing and inference execution
    - Add image format validation (PNG, JPG, JPEG)
    - Implement inference function with GPU memory management
    - Add timeout handling for long-running inference
    - Parse model output to extract text and bounding box coordinates
    - _Requirements: 1.2, 2.2, 2.3_
  
  - [x] 2.4 Implement bounding box extraction and image annotation
    - Parse detection coordinates from model output using regex
    - Scale normalized coordinates to actual image dimensions
    - Draw bounding boxes on images using PIL
    - Return both text results and annotated images
    - _Requirements: 1.7_

- [x] 3. Implement FastAPI OpenAI-compatible API server
  - [x] 3.1 Create API data models and request/response schemas
    - Define Pydantic models for OCRRequest and OCRResponse
    - Implement OpenAI-compatible message format parsing
    - Add validation for required fields and image data
    - _Requirements: 2.1, 2.4_
  
  - [x] 3.2 Implement chat completions endpoint
    - Create POST `/v1/chat/completions` endpoint
    - Parse image data from base64 or URL
    - Extract task parameters from extra_body field
    - Call model inference engine and format response
    - _Requirements: 2.2, 2.3_
  
  - [x] 3.3 Implement health check and utility endpoints
    - Create GET `/health` endpoint returning service status and model loaded state
    - Create GET `/models` endpoint listing available models
    - Add error handling middleware for all endpoints
    - _Requirements: 2.5, 5.6_
  
  - [x] 3.4 Configure FastAPI server with CORS and startup events
    - Enable CORS for all origins
    - Add startup event to pre-load model
    - Configure uvicorn server to listen on 0.0.0.0:8000
    - Add graceful shutdown handling
    - _Requirements: 2.1, 5.2, 5.4_

- [x] 4. Implement Streamlit frontend application
  - [x] 4.1 Create UI layout with input components
    - Add image upload widget accepting PNG, JPG, JPEG
    - Create model size dropdown with 5 options
    - Create task type dropdown with 4 options
    - Add conditional reference text input for Locate task
    - Add submit button
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_
  
  - [x] 4.2 Implement image processing and API integration
    - Convert uploaded image to base64 encoding
    - Build API request payload with selected parameters
    - Send POST request to local FastAPI server at localhost:8000
    - Parse API response and extract results
    - _Requirements: 1.6, 2.2_
  
  - [x] 4.3 Implement result display and error handling
    - Display text output in text area with copy button
    - Display annotated image with bounding boxes
    - Add error handling for API connection failures
    - Add loading spinner during processing
    - Show user-friendly error messages
    - _Requirements: 1.6, 1.7_
  
  - [x] 4.4 Configure Streamlit app settings
    - Set page title and icon
    - Configure server to listen on 0.0.0.0:8501
    - Disable file watcher for production
    - Add app description and usage instructions
    - _Requirements: 5.1, 5.3_

- [x] 5. Create Terraform infrastructure configuration
  - [x] 5.1 Set up Terraform project structure and provider configuration
    - Create `terraform/main.tf` with AWS provider for us-west-2
    - Create `terraform/variables.tf` with input variables
    - Create `terraform/outputs.tf` for ALB DNS and instance ID
    - Configure Terraform backend for state management
    - _Requirements: 3.1, 3.7_
  
  - [x] 5.2 Implement VPC and networking resources
    - Create VPC with CIDR block
    - Create public subnets in 2 availability zones
    - Create internet gateway and route tables
    - Associate subnets with route tables
    - _Requirements: 3.2, 3.3_
  
  - [x] 5.3 Implement security groups for ALB and EC2
    - Create ALB security group allowing inbound 8000, 8501 from 0.0.0.0/0
    - Create EC2 security group allowing inbound 8000, 8501 from ALB security group
    - Add egress rules for outbound traffic
    - _Requirements: 3.2, 3.4, 5.1, 5.2_
  
  - [x] 5.4 Implement Application Load Balancer resources
    - Create ALB in public subnets
    - Create target group for API on port 8000 with health check at /health
    - Create target group for frontend on port 8501 with health check at /
    - Create listeners for ports 8000 and 8501
    - Register EC2 instance with both target groups
    - _Requirements: 3.2, 5.5, 5.6_
  
  - [x] 5.5 Implement IAM roles and instance profile
    - Create IAM role for EC2 instance
    - Attach AmazonSSMManagedInstanceCore policy
    - Add policies for CloudWatch Logs and S3 access
    - Create instance profile
    - _Requirements: 3.5, 4.3_
  
  - [x] 5.6 Implement EC2 instance resource with user data
    - Query latest Ubuntu 24.04 LTS AMI with GPU support
    - Create EC2 instance with g6.xlarge instance type
    - Configure 100GB gp3 root volume
    - Attach IAM instance profile
    - Reference user data script for initialization
    - _Requirements: 3.1, 3.6, 4.1_
  
  - [x] 5.7 Configure Terraform outputs
    - Output ALB DNS name for accessing services
    - Output EC2 instance ID for SSM access
    - Output security group IDs for reference
    - _Requirements: 3.7, 5.3, 5.4_

- [x] 6. Create deployment and initialization scripts
  - [x] 6.1 Create user data bootstrap script
    - Write `terraform/user_data.sh` to install system dependencies
    - Install NVIDIA drivers and CUDA toolkit
    - Install Python 3.12 and pip
    - Install git and other utilities
    - Configure environment variables
    - _Requirements: 3.8, 6.1_
  
  - [x] 6.2 Create application setup script
    - Write `scripts/setup_app.sh` to clone/copy application code
    - Install Python dependencies from requirements.txt
    - Download and cache DeepSeek-OCR model weights
    - Create necessary directories for temp files
    - _Requirements: 6.1, 6.2_
  
  - [x] 6.3 Create systemd service files
    - Write `scripts/deepseek-api.service` for FastAPI server
    - Write `scripts/deepseek-frontend.service` for Streamlit app
    - Configure services to start on boot
    - Add restart policies and dependencies
    - Copy service files to /etc/systemd/system/
    - _Requirements: 6.3, 6.4_
  
  - [x] 6.4 Create health check and monitoring script
    - Write `scripts/health_check.sh` to verify service availability
    - Check if API responds on port 8000
    - Check if frontend responds on port 8501
    - Verify model is loaded successfully
    - Output status report
    - _Requirements: 6.5_

- [x] 7. Create comprehensive README documentation
  - [x] 7.1 Document prerequisites and setup requirements
    - List required tools: Terraform, AWS CLI, Python
    - Document AWS credentials configuration
    - Specify required IAM permissions
    - List system requirements
    - _Requirements: 7.2_
  
  - [x] 7.2 Document deployment instructions
    - Provide step-by-step Terraform deployment commands
    - Explain how to initialize and apply Terraform
    - Document expected deployment time
    - Show how to retrieve ALB DNS from outputs
    - _Requirements: 7.3_
  
  - [x] 7.3 Document usage and testing instructions
    - Explain how to access frontend at http://[alb-dns]:8501
    - Provide curl examples for API testing
    - Document all API endpoints and parameters
    - Include example requests and responses
    - _Requirements: 7.4_
  
  - [x] 7.4 Document SSM access and troubleshooting
    - Show how to connect via aws ssm start-session
    - Document how to check service logs
    - Provide common troubleshooting steps
    - List monitoring commands for GPU and memory
    - _Requirements: 7.5, 7.6_

- [-] 8. Deploy infrastructure and verify deployment
  - [x] 8.1 Initialize and apply Terraform configuration
    - Run terraform init in terraform directory
    - Run terraform plan and review changes
    - Run terraform apply and confirm
    - Wait for deployment to complete
    - Capture ALB DNS and instance ID from outputs
    - _Requirements: 3.1, 3.7_
  
  - [x] 8.2 Verify instance initialization via SSM
    - Connect to instance using aws ssm start-session
    - Check user data script execution logs
    - Verify NVIDIA drivers installed with nvidia-smi
    - Verify Python and dependencies installed
    - Check systemd service status
    - _Requirements: 4.1, 4.2, 6.4_
  
  - [ ] 8.3 Test API endpoint accessibility
    - Test health endpoint: curl http://[alb-dns]:8000/health
    - Verify response shows model loaded
    - Test models endpoint: curl http://[alb-dns]:8000/models
    - Perform sample OCR request with test image
    - Verify response format matches OpenAI spec
    - _Requirements: 2.1, 2.4, 5.2, 5.4_
  
  - [ ] 8.4 Test frontend accessibility and functionality
    - Navigate to http://[alb-dns]:8501 in browser
    - Verify Streamlit interface loads correctly
    - Upload a test image
    - Test each model size option
    - Test each task type option
    - Verify results display correctly
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 5.1, 5.3_
  
  - [ ] 8.5 Verify ALB health checks and routing
    - Check target health in AWS console
    - Verify both target groups show healthy status
    - Test that ALB routes requests correctly to both ports
    - Verify persistent DNS name works
    - _Requirements: 5.5, 5.6_
