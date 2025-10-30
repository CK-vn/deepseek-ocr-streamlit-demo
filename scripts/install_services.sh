#!/bin/bash
set -e

# This script installs the systemd service files and enables them to start on boot
# Must be run with sudo privileges

echo "Installing DeepSeek-OCR systemd services..."

# Copy service files to systemd directory
cp /opt/deepseek-ocr/scripts/deepseek-api.service /etc/systemd/system/
cp /opt/deepseek-ocr/scripts/deepseek-frontend.service /etc/systemd/system/

# Set correct permissions
chmod 644 /etc/systemd/system/deepseek-api.service
chmod 644 /etc/systemd/system/deepseek-frontend.service

# Reload systemd daemon
systemctl daemon-reload

# Enable services to start on boot
systemctl enable deepseek-api.service
systemctl enable deepseek-frontend.service

echo "Services installed and enabled successfully!"
echo ""
echo "To start the services now, run:"
echo "  sudo systemctl start deepseek-api"
echo "  sudo systemctl start deepseek-frontend"
echo ""
echo "To check service status, run:"
echo "  sudo systemctl status deepseek-api"
echo "  sudo systemctl status deepseek-frontend"
