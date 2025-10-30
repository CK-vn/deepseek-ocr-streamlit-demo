#!/bin/bash
set -e

# Log all output to a file for debugging
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting DeepSeek-OCR instance initialization..."
echo "Timestamp: $(date)"

# Update system packages
echo "Updating system packages..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install NVIDIA drivers
echo "Installing NVIDIA drivers..."
apt-get install -y ubuntu-drivers-common
ubuntu-drivers autoinstall

# Install CUDA toolkit (use available version for Ubuntu 24.04)
echo "Installing CUDA toolkit..."
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
apt-get update

# Install CUDA toolkit - try cuda-toolkit without specific version
DEBIAN_FRONTEND=noninteractive apt-get install -y cuda-toolkit || {
    echo "Warning: Full CUDA toolkit installation failed, installing CUDA runtime only"
    DEBIAN_FRONTEND=noninteractive apt-get install -y cuda-runtime-12-6 || true
}

# Install Python 3.12 and pip
echo "Installing Python 3.12 and pip..."
apt-get install -y python3.12 python3.12-venv python3-pip python3.12-dev

# Install git and other utilities
echo "Installing git and utilities..."
apt-get install -y git curl wget unzip build-essential

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

# Create application directory structure
echo "Creating application directory structure..."
mkdir -p /opt/deepseek-ocr/{app,scripts,logs,cache,temp}
chown -R ubuntu:ubuntu /opt/deepseek-ocr

# Set up Python virtual environment
echo "Setting up Python virtual environment..."
su - ubuntu -c "python3.12 -m venv /opt/deepseek-ocr/venv"

# Create a flag file to indicate first boot completion
touch /var/log/user-data-first-boot-complete

echo "First boot initialization completed at $(date)"
echo "System will reboot to load NVIDIA drivers..."

# Schedule the second phase to run after reboot
cat > /var/lib/cloud/scripts/per-boot/setup-deepseek-ocr.sh << 'EOFSCRIPT'
#!/bin/bash
set -e

# Only run if first boot is complete and second phase hasn't run yet
if [ -f /var/log/user-data-first-boot-complete ] && [ ! -f /var/log/user-data-second-boot-complete ]; then
    exec > >(tee -a /var/log/user-data.log)
    exec 2>&1
    
    echo "Starting second phase initialization at $(date)"
    
    # Wait for system to stabilize
    sleep 30
    
    # Verify NVIDIA driver is loaded
    if nvidia-smi &> /dev/null; then
        echo "NVIDIA driver loaded successfully"
        nvidia-smi
    else
        echo "Warning: NVIDIA driver not loaded, but continuing..."
    fi
    

    
    # Clone the application repository
    echo "Cloning application repository..."
    cd /opt/deepseek-ocr
    su - ubuntu -c "cd /opt/deepseek-ocr && git clone https://github.com/CK-vn/deepseek-ocr-streamlit-demo.git repo"
    
    # Copy application files to the correct location
    echo "Setting up application files..."
    cp -r /opt/deepseek-ocr/repo/app /opt/deepseek-ocr/
    cp -r /opt/deepseek-ocr/repo/scripts /opt/deepseek-ocr/
    cp /opt/deepseek-ocr/repo/requirements.txt /opt/deepseek-ocr/
    cp -r /opt/deepseek-ocr/repo/.streamlit /opt/deepseek-ocr/ 2>/dev/null || true
    chown -R ubuntu:ubuntu /opt/deepseek-ocr
    
    # Install Python dependencies
    echo "Installing Python dependencies..."
    source /opt/deepseek-ocr/venv/bin/activate
    pip install --upgrade pip
    pip install -r /opt/deepseek-ocr/requirements.txt || {
        echo "Warning: Some packages failed to install, continuing..."
    }
    
    # Create systemd service files
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
    
    # Set permissions
    chown -R ubuntu:ubuntu /opt/deepseek-ocr
    chmod +x /opt/deepseek-ocr/venv/bin/*
    
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
    
    # Mark second phase as complete
    touch /var/log/user-data-second-boot-complete
    echo "Second phase initialization completed at $(date)"
    echo "Instance is ready for application deployment"
fi
EOFSCRIPT

chmod +x /var/lib/cloud/scripts/per-boot/setup-deepseek-ocr.sh

# Reboot to load NVIDIA drivers
echo "Rebooting to load NVIDIA drivers..."
reboot
