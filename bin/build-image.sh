#!/bin/bash

set -euo pipefail

# Default values
ECR_REPO="bedrock-knowledge-bot"
PLATFORM="linux/amd64"

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Build and push Docker images to ECR"
    echo ""
    echo "Options:"
    echo "  -r, --repo REPO         ECR repository name (default: bedrock-knowledge-bot)"
    echo "  -p, --platform PLATFORM Platform to build for (default: linux/amd64)"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 -r my-repo"
    echo "  $0 --platform linux/amd64"
    echo "  $0 -p linux/arm64"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--repo)
            ECR_REPO="$2"
            shift 2
            ;;
        -p|--platform)
            PLATFORM="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            ;;
    esac
done

# Function to log messages with timestamps
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to handle errors
handle_error() {
    log "ERROR: $1"
    exit 1
}

# Check if docker is installed
if ! command -v docker &> /dev/null; then
    handle_error "Docker is required but not installed"
fi

# Set AWS variables
AWS_REGION=${AWS_REGION:-AWS_DEFAULT_REGION}
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Login to ECR
log "Logging into ECR"
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com || handle_error "Failed to login to ECR"

log "📦 Building and pushing image for platform: $PLATFORM"
docker build \
    --platform $PLATFORM \
    -t $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest \
    . || handle_error "Failed to build image for platform $PLATFORM"

docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest || handle_error "Failed to push image for platform $PLATFORM"

# Create and push manifest if we have built platforms
log "Build completed successfully!"
