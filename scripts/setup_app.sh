#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/setup-app.log)
exec 2>&1

echo "Starting DeepSeek-OCR application setup..."

# Set environment variables
export DEEPSEEK_OCR_HOME=/opt/deepseek-ocr
export CUDA_HOME=/usr/local/cuda
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

cd $DEEPSEEK_OCR_HOME

# Copy application code (assumes code is already on the instance)
# In production, this would clone from a git repository or copy from S3
echo "Setting up application code..."
if [ ! -d "$DEEPSEEK_OCR_HOME/app" ]; then
    echo "ERROR: Application code not found at $DEEPSEEK_OCR_HOME/app"
    echo "Please copy the app/ directory to $DEEPSEEK_OCR_HOME/"
    exit 1
fi

# Activate virtual environment
source $DEEPSEEK_OCR_HOME/venv/bin/activate

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip

# Install Python dependencies from requirements.txt
echo "Installing Python dependencies..."
if [ -f "$DEEPSEEK_OCR_HOME/requirements.txt" ]; then
    pip install -r $DEEPSEEK_OCR_HOME/requirements.txt
else
    echo "ERROR: requirements.txt not found at $DEEPSEEK_OCR_HOME/"
    exit 1
fi

# Create necessary directories for temp files
echo "Creating necessary directories..."
mkdir -p $DEEPSEEK_OCR_HOME/temp
mkdir -p $DEEPSEEK_OCR_HOME/logs
mkdir -p $DEEPSEEK_OCR_HOME/cache

# Set permissions
chown -R ubuntu:ubuntu $DEEPSEEK_OCR_HOME

# Download and cache DeepSeek-OCR model weights
echo "Downloading and caching DeepSeek-OCR model weights..."
echo "This may take several minutes..."

# Run a Python script to download the model
python3 << 'PYTHON_SCRIPT'
import os
import torch
from transformers import AutoTokenizer, AutoModel

print("Downloading DeepSeek-OCR model...")
model_name = "deepseek-ai/DeepSeek-OCR"

# Set cache directory
cache_dir = os.path.join(os.environ.get("DEEPSEEK_OCR_HOME", "/opt/deepseek-ocr"), "cache")
os.environ["HF_HOME"] = cache_dir
os.environ["TRANSFORMERS_CACHE"] = cache_dir

try:
    # Download tokenizer
    print("Downloading tokenizer...")
    tokenizer = AutoTokenizer.from_pretrained(
        model_name,
        trust_remote_code=True,
        cache_dir=cache_dir
    )
    print("Tokenizer downloaded successfully")
    
    # Download model (this will take time)
    print("Downloading model weights (this may take 10-15 minutes)...")
    model = AutoModel.from_pretrained(
        model_name,
        trust_remote_code=True,
        torch_dtype=torch.bfloat16,
        cache_dir=cache_dir
    )
    print("Model downloaded successfully")
    
    # Clean up to free memory
    del model
    del tokenizer
    torch.cuda.empty_cache()
    
    print("Model caching completed successfully!")
except Exception as e:
    print(f"ERROR: Failed to download model: {e}")
    exit(1)
PYTHON_SCRIPT

echo "Application setup completed successfully!"
echo "You can now start the services using systemd."
