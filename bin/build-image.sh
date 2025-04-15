#!/bin/bash

set -uo pipefail

command -v docker >/dev/null 2>&1 || { echo "Docker required!  Aborting." >&2; exit 1; }

AWS_REGION=${AWS_REGION:-AWS_DEFAULT_REGION}
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO=bedrock-knowledge-bot

# Create the ECR repository if it doesn't exist
aws ecr describe-repositories --repository-names $ECR_REPO > /dev/null 2>&1 || aws ecr create-repository --repository-name $ECR_REPO

aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

$(command -v docker) buildx inspect default &> /dev/null
if [[ $? -eq 0 ]]; then
  DOCKER_BUILD_BIN="$(command -v docker) buildx build"
else
  DOCKER_BUILD_BIN="$(command -v docker) build"
fi

$DOCKER_BUILD_BIN \
  --platform linux/amd64 \
  . -t $ECR_REPO:latest

docker tag $ECR_REPO:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest
