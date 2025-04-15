#!/bin/bash

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# Check if AWS credentials are configured
if ! aws sts get-caller-identity &>/dev/null; then
    echo "Error: AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

# Get AWS account ID and region
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)

echo "🚀 Starting deployment process..."
echo "AWS Account: $AWS_ACCOUNT_ID"
echo "AWS Region: $AWS_REGION"

# Build and push Docker image
echo "📦 Building and pushing Docker image..."
"$SCRIPT_DIR/build-image.sh" -p linux/arm64

# Deploy CDK application
echo "🔄 Deploying CDK application..."
cd "$PROJECT_ROOT"

# Check if knowledge base ID is provided
# Get knowledge base ID from cdk.context.json
KNOWLEDGE_BASE_ID=$(jq -r '.knowledge_base_id' "$PROJECT_ROOT/cdk.context.json")
if [ -n "$KNOWLEDGE_BASE_ID" ] && [ "$KNOWLEDGE_BASE_ID" != "null" ]; then
    echo "📚 Using Knowledge Base ID from cdk.context.json: $KNOWLEDGE_BASE_ID"
    cdk deploy --context knowledge_base_id="$KNOWLEDGE_BASE_ID"
else
    echo "ℹ️ No Knowledge Base ID found in cdk.context.json. Deploying without knowledge base integration."
    cdk deploy
fi

echo "✅ Deployment completed successfully!"
