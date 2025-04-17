#!/bin/bash

set -euo pipefail

# Default values
ECR_REPO="bedrock-knowledge-bot"
AWS_REGION="us-east-1"
KEEP_LAST_N_IMAGES=5

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Clean up Docker resources and ECR images"
    echo ""
    echo "Options:"
    echo "  -e, --repo REPO         ECR repository name (default: bedrock-knowledge-bot)"
    echo "  -r, --region REGION     AWS region (default: us-east-1)"
    echo "  -k, --keep COUNT        Number of recent images to keep (default: 5)"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 -e my-repo"
    echo "  $0 --region eu-west-1"
    echo "  $0 -k 10"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--repo)
            ECR_REPO="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -k|--keep)
            KEEP_LAST_N_IMAGES="$2"
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

echo "Starting cleanup process..."
echo "Using configuration:"
echo "ECR Repository: $ECR_REPO"
echo "AWS Region: $AWS_REGION"
echo "Keeping last $KEEP_LAST_N_IMAGES images"

# Function to get ECR repository URI
get_ecr_repo_uri() {
    aws ecr describe-repositories --repository-names $ECR_REPO --region $AWS_REGION --query 'repositories[0].repositoryUri' --output text
}

# Function to get list of image tags in ECR
get_ecr_image_tags() {
    aws ecr describe-images --repository-name $ECR_REPO --region $AWS_REGION --query 'imageDetails[*].imageTags[0]' --output text
}

# Function to delete old ECR images
cleanup_ecr_images() {
    echo "Cleaning up ECR images..."
    local repo_uri=$(get_ecr_repo_uri)
    local image_tags=($(get_ecr_image_tags))
    
    # Sort tags by date (assuming tags are timestamps or version numbers)
    IFS=$'\n' sorted_tags=($(sort -r <<<"${image_tags[*]}"))
    unset IFS
    
    # Keep only the most recent N images
    for ((i=$KEEP_LAST_N_IMAGES; i<${#sorted_tags[@]}; i++)); do
        local tag=${sorted_tags[$i]}
        echo "Deleting image: $tag"
        aws ecr batch-delete-image \
            --repository-name $ECR_REPO \
            --region $AWS_REGION \
            --image-ids imageTag=$tag
    done
}

# Clean up local Docker resources
cleanup_local_docker() {
    echo "Cleaning up local Docker resources..."
    
    # Remove all stopped containers
    echo "Removing stopped containers..."
    docker container prune -f
   
    # Remove all dangling images
    echo "Removing dangling images..."
    docker image prune -af
    
}

# Main execution
echo "Starting cleanup process..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo "Docker is not running. Please start Docker first."
    exit 1
fi

# Execute cleanup functions
cleanup_ecr_images
cleanup_local_docker

echo "Cleanup completed successfully!" 
