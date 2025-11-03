#!/bin/bash
set -e

# Log all output to a file for debugging
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting DeepSeek-OCR instance initialization..."
echo "Timestamp: $(date)"
echo "AMI: Deep Learning Base AMI with Single CUDA (Ubuntu 22.04)"

# Verify CUDA is available (should be pre-installed)
echo "Verifying CUDA installation..."
nvidia-smi || echo "Warning: nvidia-smi not available yet"
nvcc --version || echo "Warning: nvcc not available yet"

# Configure environment variables
echo "Configuring environment variables..."
cat >> /etc/environment << 'EOF'
CUDA_HOME=/usr/local/cuda
PATH=/usr/local/cuda/bin:$PATH
LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
DEEPSEEK_OCR_HOME=/opt/deepseek-ocr
HF_HOME=/opt/deepseek-ocr/cache
TRANSFORMERS_CACHE=/opt/deepseek-ocr/cache
EOF

# Source environment
export CUDA_HOME=/usr/local/cuda
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

# Install python3-venv if not present
echo "Installing python3-venv..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y python3-venv python3-pip

# Create application directory structure
echo "Creating application directory structure..."
mkdir -p /opt/deepseek-ocr/{app,scripts,logs,cache,temp}

# Set up Python virtual environment (Ubuntu 22.04 has Python 3.10)
echo "Setting up Python virtual environment..."
python3 -m venv /opt/deepseek-ocr/venv

# Activate virtual environment
source /opt/deepseek-ocr/venv/bin/activate

# Upgrade pip and install build tools
echo "Upgrading pip and installing build tools..."
pip install --upgrade pip setuptools wheel
pip install ninja packaging

# Install PyTorch with CUDA support
echo "Installing PyTorch 2.6.0 with CUDA 12.6..."
pip install torch==2.6.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126

# Install transformers and tokenizers
echo "Installing transformers 4.46.3 and tokenizers 0.20.3..."
pip install transformers==4.46.3 tokenizers==0.20.3

# Install model dependencies
echo "Installing model dependencies..."
pip install einops timm easydict

# Install flash-attn (this will take 10-15 minutes to compile)
echo "Installing flash-attn 2.7.3 (this may take 10-15 minutes)..."
MAX_JOBS=4 pip install flash-attn==2.7.3 --no-build-isolation || {
    echo "Warning: flash-attn installation failed with MAX_JOBS, trying without..."
    pip install flash-attn==2.7.3 --no-build-isolation || echo "flash-attn installation failed"
}

# Download application files from S3
echo "Downloading application files from S3..."
cd /opt/deepseek-ocr

# Download requirements.txt
aws s3 cp s3://deepseek-ocr-deployment-assets/requirements.txt . || {
    echo "Warning: Could not download requirements.txt from S3"
}

# Download app files
mkdir -p app
aws s3 cp s3://deepseek-ocr-deployment-assets/app/api_server.py app/ || echo "Warning: Could not download api_server.py"
aws s3 cp s3://deepseek-ocr-deployment-assets/app/model_engine.py app/ || echo "Warning: Could not download model_engine.py"
aws s3 cp s3://deepseek-ocr-deployment-assets/app/streamlit_app.py app/ || echo "Warning: Could not download streamlit_app.py"

# Create __init__.py for app module
touch app/__init__.py

# Install application dependencies
if [ -f requirements.txt ]; then
    echo "Installing application dependencies..."
    pip install -r requirements.txt
fi

# Pre-download the model
echo "Pre-downloading DeepSeek-OCR model..."
python3 -c "from transformers import AutoTokenizer; AutoTokenizer.from_pretrained('deepseek-ai/DeepSeek-OCR', trust_remote_code=True); print('Model downloaded successfully')" || echo "Model pre-download failed"

# Set permissions
chown -R ubuntu:ubuntu /opt/deepseek-ocr

# Create systemd service for API
cat > /etc/systemd/system/deepseek-api.service << 'EOFSVC'
[Unit]
Description=DeepSeek-OCR API Server
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/deepseek-ocr
Environment="PATH=/opt/deepseek-ocr/venv/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="CUDA_HOME=/usr/local/cuda"
Environment="LD_LIBRARY_PATH=/usr/local/cuda/lib64"
Environment="DEEPSEEK_OCR_HOME=/opt/deepseek-ocr"
Environment="HF_HOME=/opt/deepseek-ocr/cache"
Environment="TRANSFORMERS_CACHE=/opt/deepseek-ocr/cache"
ExecStart=/opt/deepseek-ocr/venv/bin/python -m uvicorn app.api_server:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=10
StandardOutput=append:/opt/deepseek-ocr/logs/api.log
StandardError=append:/opt/deepseek-ocr/logs/api-error.log

[Install]
WantedBy=multi-user.target
EOFSVC

# Create systemd service for Frontend
cat > /etc/systemd/system/deepseek-frontend.service << 'EOFSVC'
[Unit]
Description=DeepSeek-OCR Streamlit Frontend
After=network.target deepseek-api.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/deepseek-ocr
Environment="PATH=/opt/deepseek-ocr/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="DEEPSEEK_OCR_HOME=/opt/deepseek-ocr"
ExecStart=/opt/deepseek-ocr/venv/bin/streamlit run app/streamlit_app.py --server.port 8501 --server.address 0.0.0.0
Restart=always
RestartSec=10
StandardOutput=append:/opt/deepseek-ocr/logs/frontend.log
StandardError=append:/opt/deepseek-ocr/logs/frontend-error.log

[Install]
WantedBy=multi-user.target
EOFSVC

# Reload systemd
systemctl daemon-reload

# Enable and start services
echo "Enabling and starting services..."
systemctl enable deepseek-api.service
systemctl enable deepseek-frontend.service
systemctl start deepseek-api.service
sleep 10
systemctl start deepseek-frontend.service

# Check service status
echo "Checking service status..."
systemctl status deepseek-api.service --no-pager || true
systemctl status deepseek-frontend.service --no-pager || true

echo "Initialization completed at $(date)"
echo "Instance is ready for application deployment"
