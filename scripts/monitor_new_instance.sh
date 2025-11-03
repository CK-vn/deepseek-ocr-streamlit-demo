#!/bin/bash
set -e

REGION="us-west-2"

# Get instance ID from Terraform output
INSTANCE_ID=$(terraform -chdir=terraform output -raw ec2_instance_id 2>/dev/null)

if [ -z "$INSTANCE_ID" ]; then
    echo "Error: No instance found in Terraform state"
    echo "Run: terraform -chdir=terraform apply"
    exit 1
fi

echo "=========================================="
echo "Monitoring Instance Initialization"
echo "=========================================="
echo "Instance ID: $INSTANCE_ID"
echo ""

for i in {1..30}; do
    echo "Check $i/30 - $(date)"
    
    COMMAND_ID=$(aws ssm send-command \
        --instance-ids ${INSTANCE_ID} \
        --region ${REGION} \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["tail -50 /var/log/user-data.log"]' \
        --output text \
        --query 'Command.CommandId' 2>&1)
    
    if [ $? -eq 0 ]; then
        sleep 5
        OUTPUT=$(aws ssm get-command-invocation \
            --command-id ${COMMAND_ID} \
            --instance-id ${INSTANCE_ID} \
            --region ${REGION} \
            --query 'StandardOutputContent' \
            --output text 2>&1)
        
        echo "$OUTPUT" | tail -20
        
        if echo "$OUTPUT" | grep -q "Initialization completed"; then
            echo ""
            echo "✅ Initialization complete!"
            
            # Check service status
            echo ""
            echo "Checking service status..."
            COMMAND_ID=$(aws ssm send-command \
                --instance-ids ${INSTANCE_ID} \
                --region ${REGION} \
                --document-name "AWS-RunShellScript" \
                --parameters 'commands=["systemctl status deepseek-api --no-pager", "systemctl status deepseek-frontend --no-pager"]' \
                --output text \
                --query 'Command.CommandId')
            
            sleep 5
            aws ssm get-command-invocation \
                --command-id ${COMMAND_ID} \
                --instance-id ${INSTANCE_ID} \
                --region ${REGION} \
                --query 'StandardOutputContent' \
                --output text
            
            exit 0
        fi
    fi
    
    echo ""
    sleep 20
done

echo "⚠️  Initialization still in progress after 10 minutes"
echo "Check logs manually with: aws ssm start-session --target ${INSTANCE_ID} --region ${REGION}"
