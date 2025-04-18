#!/bin/bash

set -euo pipefail

# Default values
BRANCH="main"
ECR_REPO="bedrock-knowledge-bot"
PLATFORMS="linux/amd64,linux/arm64"

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Build and push Docker images to ECR"
    echo ""
    echo "Options:"
    echo "  -b, --branch BRANCH     Git branch to build from (default: main)"
    echo "  -r, --repo REPO         ECR repository name (default: bedrock-knowledge-bot)"
    echo "  -p, --platform PLATFORMS Comma-separated list of platforms to build for"
    echo "                          Supported platforms: linux/amd64, linux/arm64"
    echo "                          (default: linux/amd64,linux/arm64)"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 -b main -r my-repo"
    echo "  $0 --platform linux/amd64"
    echo "  $0 -p linux/amd64,linux/arm64"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--branch)
            BRANCH="$2"
            shift 2
            ;;
        -r|--repo)
            ECR_REPO="$2"
            shift 2
            ;;
        -p|--platform)
            PLATFORMS="$2"
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

# If no platforms specified, use default list
if [ -z "$PLATFORMS" ]; then
    PLATFORMS="linux/amd64,linux/arm64"
fi

# Convert comma-separated platforms to array
IFS=',' read -ra PLATFORM_ARRAY <<< "$PLATFORMS"

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

# Build and push multi-platform images
BUILT_PLATFORMS=()
for platform in "${PLATFORM_ARRAY[@]}"; do
    # Replace forward slash with hyphen in platform name for tag
    platform_tag=$(echo $platform | tr '/' '-')
    log "📦 Building and pushing image for platform: $platform"
    docker build \
        --platform $platform \
        --build-arg BRANCH=$BRANCH \
        -t $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest-$platform_tag \
        . || handle_error "Failed to build image for platform $platform"
    
    docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest-$platform_tag || handle_error "Failed to push image for platform $platform"
    
    # Store the full image reference for manifest
    BUILT_PLATFORMS+=("$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest-$platform_tag")
done

# Create and push manifest if we have built platforms
if [ ${#BUILT_PLATFORMS[@]} -gt 0 ]; then
    log "Creating and pushing manifest"
    # Delete existing manifest if it exists
    log "Deleting existing manifest if it exists"
    docker manifest rm $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest || true

    # Create empty manifest
    docker manifest create $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest || handle_error "Failed to create manifest"

    # Add each platform to the manifest with proper annotations
    for platform in "${PLATFORM_ARRAY[@]}"; do
        platform_tag=$(echo $platform | tr '/' '-')
        log "Adding $platform to manifest"
        docker manifest add \
            $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest \
            $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest-$platform_tag || handle_error "Failed to add platform $platform to manifest"
    done

    docker manifest push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest || handle_error "Failed to push manifest"

    # Verify ECR images
    log "Verifying ECR images"
    aws ecr --region ${AWS_REGION} describe-images --repository-name $ECR_REPO 1>/dev/null || handle_error "Failed to verify ECR images"
else
    log "No platforms were built successfully. Skipping manifest creation."
fi

log "Build completed successfully!"
