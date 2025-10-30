# Design Document

## Overview

The DeepSeek-OCR deployment consists of three main layers:

1. **Infrastructure Layer**: AWS resources provisioned via Terraform including EC2, ALB, VPC networking, security groups, and IAM roles
2. **Application Layer**: Two Python services running on the EC2 instance - a FastAPI server providing OpenAI-compatible API and a Streamlit web interface
3. **ML Model Layer**: DeepSeek-OCR model loaded into GPU memory, shared between both services

The architecture uses an Application Load Balancer to provide a persistent DNS endpoint, routing traffic to the EC2 instance on different ports for the API (8000) and frontend (8501).

## Architecture

### High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         Internet                             │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              Application Load Balancer (ALB)                 │
│  ┌──────────────────┐         ┌──────────────────┐         │
│  │  Listener :8501  │         │  Listener :8000  │         │
│  │  (Frontend)      │         │  (API)           │         │
│  └────────┬─────────┘         └────────┬─────────┘         │
└───────────┼──────────────────────────────┼──────────────────┘
            │                              │
            │         ┌────────────────────┘
            │         │
            ▼         ▼
┌─────────────────────────────────────────────────────────────┐
│              EC2 g6.xlarge Instance                          │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Streamlit Frontend :8501                 │  │
│  └────────────────────┬─────────────────────────────────┘  │
│                       │                                     │
│  ┌────────────────────┴─────────────────────────────────┐  │
│  │              FastAPI Server :8000                     │  │
│  └────────────────────┬─────────────────────────────────┘  │
│                       │                                     │
│  ┌────────────────────┴─────────────────────────────────┐  │
│  │         DeepSeek-OCR Model (GPU Memory)              │  │
│  │         - Model Weights: ~10GB                        │  │
│  │         - Flash Attention 2                           │  │
│  │         - BFloat16 Precision                          │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  GPU: NVIDIA L4 (24GB VRAM)                                │
└─────────────────────────────────────────────────────────────┘
```

### Network Architecture

- **VPC**: Dedicated VPC with public subnets in multiple availability zones for ALB
- **Security Groups**:
  - ALB Security Group: Allows inbound 8000, 8501 from 0.0.0.0/0
  - EC2 Security Group: Allows inbound 8000, 8501 from ALB security group only
- **IAM Roles**:
  - EC2 Instance Role: Permissions for SSM, CloudWatch Logs, S3 (for model caching)
  - SSM Managed Policy: AmazonSSMManagedInstanceCore

## Components and Interfaces

### 1. Terraform Infrastructure Module

**Location**: `terraform/`

**Components**:
- `main.tf`: Primary resource definitions
- `variables.tf`: Input variables (region, instance type, AMI)
- `outputs.tf`: ALB DNS name, instance ID
- `vpc.tf`: VPC, subnets, internet gateway, route tables
- `alb.tf`: Application Load Balancer, target groups, listeners
- `ec2.tf`: EC2 instance, security groups, IAM role
- `user_data.sh`: Bootstrap script for instance initialization

**Key Resources**:
```hcl
# Use latest Ubuntu 24.04 LTS AMI with GPU support
data "aws_ami" "ubuntu_gpu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical
  
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# EC2 Instance
resource "aws_instance" "deepseek_ocr" {
  instance_type = "g6.xlarge"
  ami           = data.aws_ami.ubuntu_gpu.id
  
  root_block_device {
    volume_size = 100  # GB for model weights + OS
    volume_type = "gp3"
  }
  
  iam_instance_profile = aws_iam_instance_profile.deepseek_ocr.name
  user_data            = file("user_data.sh")
}

# ALB with two target groups
resource "aws_lb" "deepseek_ocr" {
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "api" {
  port     = 8000
  protocol = "HTTP"
  
  health_check {
    path = "/health"
    port = 8000
  }
}

resource "aws_lb_target_group" "frontend" {
  port     = 8501
  protocol = "HTTP"
  
  health_check {
    path = "/"
    port = 8501
  }
}
```

### 2. FastAPI OpenAI-Compatible API Server

**Location**: `app/api_server.py`

**Endpoints**:
- `POST /v1/chat/completions`: OpenAI-compatible chat endpoint
- `POST /v1/completions`: OpenAI-compatible completion endpoint
- `GET /health`: Health check endpoint for ALB
- `GET /models`: List available models

**Request Format**:
```json
{
  "model": "deepseek-ocr",
  "messages": [
    {
      "role": "user",
      "content": [
        {"type": "text", "text": "Free OCR."},
        {"type": "image_url", "image_url": {"url": "data:image/png;base64,..."}}
      ]
    }
  ],
  "temperature": 0.0,
  "max_tokens": 4096,
  "extra_body": {
    "model_size": "Gundam",
    "task_type": "free_ocr"
  }
}
```

**Response Format**:
```json
{
  "id": "chatcmpl-123",
  "object": "chat.completion",
  "created": 1234567890,
  "model": "deepseek-ocr",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Extracted text content..."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 100,
    "completion_tokens": 50,
    "total_tokens": 150
  }
}
```

**Model Loading Strategy**:
```python
# Singleton pattern for model loading
class ModelManager:
    _instance = None
    _model = None
    _tokenizer = None
    
    @classmethod
    def get_model(cls):
        if cls._model is None:
            cls._tokenizer = AutoTokenizer.from_pretrained(
                "deepseek-ai/DeepSeek-OCR",
                trust_remote_code=True
            )
            cls._model = AutoModel.from_pretrained(
                "deepseek-ai/DeepSeek-OCR",
                _attn_implementation="flash_attention_2",
                trust_remote_code=True,
                torch_dtype=torch.bfloat16
            ).cuda().eval()
        return cls._model, cls._tokenizer
```

### 3. Streamlit Frontend Application

**Location**: `app/streamlit_app.py`

**UI Components**:
- Image upload widget (accepts PNG, JPG, JPEG)
- Model size dropdown (Tiny, Small, Base, Large, Gundam)
- Task type dropdown (Free OCR, Convert to Markdown, Parse Figure, Locate Object)
- Reference text input (conditional, visible only for Locate task)
- Submit button
- Text output area (for OCR results)
- Image output area (for annotated images with bounding boxes)

**Backend Integration**:
The Streamlit app will call the local FastAPI server via HTTP:
```python
import requests

def process_image(image, model_size, task_type, ref_text):
    # Convert image to base64
    buffered = BytesIO()
    image.save(buffered, format="PNG")
    img_str = base64.b64encode(buffered.getvalue()).decode()
    
    # Call local API
    response = requests.post(
        "http://localhost:8000/v1/chat/completions",
        json={
            "model": "deepseek-ocr",
            "messages": [...],
            "extra_body": {
                "model_size": model_size,
                "task_type": task_type,
                "ref_text": ref_text
            }
        }
    )
    return response.json()
```

### 4. Model Inference Engine

**Location**: Shared module `app/model_engine.py`

**Responsibilities**:
- Load and cache model weights from HuggingFace
- Handle different model size configurations
- Process images with appropriate preprocessing
- Execute inference with GPU acceleration
- Parse and format model outputs
- Extract bounding box coordinates and draw annotations

**Size Configurations**:
```python
SIZE_CONFIGS = {
    "Tiny": {"base_size": 512, "image_size": 512, "crop_mode": False},
    "Small": {"base_size": 640, "image_size": 640, "crop_mode": False},
    "Base": {"base_size": 1024, "image_size": 1024, "crop_mode": False},
    "Large": {"base_size": 1280, "image_size": 1280, "crop_mode": False},
    "Gundam": {"base_size": 1024, "image_size": 640, "crop_mode": True}
}
```

**Task Prompt Templates**:
```python
TASK_PROMPTS = {
    "free_ocr": "<image>\nFree OCR.",
    "markdown": "<image>\n<|grounding|>Convert the document to markdown.",
    "parse_figure": "<image>\nParse the figure.",
    "locate": "<image>\nLocate <|ref|>{ref_text}<|/ref|> in the image."
}
```

## Data Models

### Configuration Data

```python
from pydantic import BaseModel
from typing import Optional, Literal

class ModelConfig(BaseModel):
    model_size: Literal["Tiny", "Small", "Base", "Large", "Gundam"] = "Gundam"
    task_type: Literal["free_ocr", "markdown", "parse_figure", "locate"] = "free_ocr"
    ref_text: Optional[str] = None
    base_size: int
    image_size: int
    crop_mode: bool

class OCRRequest(BaseModel):
    model: str = "deepseek-ocr"
    messages: list
    temperature: float = 0.0
    max_tokens: int = 4096
    extra_body: Optional[dict] = None

class OCRResponse(BaseModel):
    id: str
    object: str
    created: int
    model: str
    choices: list
    usage: dict
```

### Inference Data Flow

```
User Input (Image + Params)
    ↓
Base64 Encoding / File Upload
    ↓
API Request Validation
    ↓
Model Configuration Selection
    ↓
Image Preprocessing
    ↓
GPU Inference (DeepSeek-OCR)
    ↓
Output Parsing (Text + Bounding Boxes)
    ↓
Response Formatting
    ↓
Return to Client
```

## Error Handling

### API Server Error Handling

```python
from fastapi import HTTPException

# Model loading errors
try:
    model, tokenizer = ModelManager.get_model()
except Exception as e:
    raise HTTPException(
        status_code=503,
        detail=f"Model loading failed: {str(e)}"
    )

# Invalid image format
if not image_data:
    raise HTTPException(
        status_code=400,
        detail="Invalid image data"
    )

# GPU out of memory
try:
    result = model.infer(...)
except torch.cuda.OutOfMemoryError:
    raise HTTPException(
        status_code=507,
        detail="GPU memory insufficient"
    )

# Inference timeout
@timeout(300)  # 5 minutes
def run_inference():
    return model.infer(...)
```

### Streamlit Error Handling

```python
import streamlit as st

try:
    result = process_image(image, model_size, task_type, ref_text)
    st.success("Processing complete!")
except requests.exceptions.ConnectionError:
    st.error("Cannot connect to API server. Please check if the service is running.")
except requests.exceptions.Timeout:
    st.error("Request timed out. The image may be too large or complex.")
except Exception as e:
    st.error(f"An error occurred: {str(e)}")
```

### Infrastructure Error Handling

- **ALB Health Checks**: Unhealthy targets removed from rotation after 2 consecutive failures
- **Auto-recovery**: EC2 instance configured with CloudWatch alarms for automatic recovery
- **Service Restart**: Systemd services configured with restart policies
```ini
[Service]
Restart=always
RestartSec=10
```

## Testing Strategy

### 1. Infrastructure Testing

**Pre-deployment Validation**:
```bash
# Terraform validation
terraform validate
terraform plan

# Check AWS credentials and permissions
aws sts get-caller-identity
aws ec2 describe-availability-zones --region us-west-2
```

**Post-deployment Verification**:
```bash
# Verify ALB is active
aws elbv2 describe-load-balancers --region us-west-2

# Verify target health
aws elbv2 describe-target-health --target-group-arn <arn>

# Test SSM connectivity
aws ssm start-session --target <instance-id>
```

### 2. API Endpoint Testing

**Health Check**:
```bash
curl http://<alb-dns>:8000/health
# Expected: {"status": "healthy", "model_loaded": true}
```

**Basic OCR Test**:
```bash
# Create test image
echo "iVBORw0KGgoAAAANS..." > test_image_b64.txt

# Test API
curl -X POST http://<alb-dns>:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-ocr",
    "messages": [
      {
        "role": "user",
        "content": [
          {"type": "text", "text": "Free OCR."},
          {"type": "image_url", "image_url": {"url": "data:image/png;base64,..."}}
        ]
      }
    ]
  }'
```

**Load Testing**:
```bash
# Use Apache Bench for basic load testing
ab -n 10 -c 2 -p request.json -T application/json http://<alb-dns>:8000/v1/chat/completions
```

### 3. Frontend Testing

**Manual Testing Checklist**:
- [ ] Navigate to http://<alb-dns>:8501
- [ ] Upload a test image (PNG/JPG)
- [ ] Select each model size and verify processing
- [ ] Test each task type:
  - [ ] Free OCR
  - [ ] Convert to Markdown
  - [ ] Parse Figure
  - [ ] Locate Object (with reference text)
- [ ] Verify text output displays correctly
- [ ] Verify annotated images display bounding boxes
- [ ] Test error handling with invalid inputs

**Browser Compatibility**:
- Chrome/Edge (latest)
- Firefox (latest)
- Safari (latest)

### 4. Integration Testing

**End-to-End Test Script**:
```python
import requests
import base64
from PIL import Image
import io

def test_e2e():
    # Create test image
    img = Image.new('RGB', (800, 600), color='white')
    # Add text to image...
    
    # Convert to base64
    buffered = io.BytesIO()
    img.save(buffered, format="PNG")
    img_b64 = base64.b64encode(buffered.getvalue()).decode()
    
    # Test API
    response = requests.post(
        f"http://{alb_dns}:8000/v1/chat/completions",
        json={
            "model": "deepseek-ocr",
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": "Free OCR."},
                        {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{img_b64}"}}
                    ]
                }
            ]
        },
        timeout=60
    )
    
    assert response.status_code == 200
    assert "choices" in response.json()
    print("✅ E2E test passed")

if __name__ == "__main__":
    test_e2e()
```

### 5. Performance Testing

**Metrics to Monitor**:
- Model loading time: < 60 seconds
- Inference time per image:
  - Tiny: < 2 seconds
  - Small: < 3 seconds
  - Base: < 5 seconds
  - Large: < 8 seconds
  - Gundam: < 5 seconds
- Memory usage: < 20GB GPU VRAM
- API response time: < 10 seconds (including network)

**Monitoring Commands**:
```bash
# GPU utilization
nvidia-smi -l 1

# Memory usage
free -h

# Service logs
journalctl -u deepseek-api -f
journalctl -u deepseek-frontend -f
```

## Deployment Process

### Phase 1: Infrastructure Provisioning
1. Initialize Terraform
2. Apply Terraform configuration
3. Wait for instance to be ready
4. Verify ALB health checks pass

### Phase 2: Service Verification
1. Connect via SSM
2. Check service status
3. Verify model weights downloaded
4. Test API endpoint
5. Test frontend access

### Phase 3: Validation
1. Run automated test suite
2. Perform manual smoke tests
3. Verify ALB routing
4. Document ALB DNS endpoint

## Security Considerations

- **No SSH Access**: All remote access via SSM only
- **Security Groups**: Principle of least privilege
- **IAM Roles**: Minimal permissions for EC2 instance
- **No API Authentication**: Consider adding API keys in production
- **HTTP Only**: Consider adding HTTPS with ACM certificate for production
- **Model Weights**: Cached locally, no external dependencies after initial download
