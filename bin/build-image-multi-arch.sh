#!/bin/bash

set -uo pipefail

BRANCH=${1:-main}

verify_command() {
  # shellcheck disable=SC2181
  if [[ "$?" -ne "0" ]]; then
    echo -e "[!] [MESSAGE]: ${1}"
    exit 1
  fi
}

# Exit if docker not installed
command -v docker >/dev/null 2>&1 || { echo "Docker required!  Aborting." >&2; exit 1; }

AWS_REGION=${AWS_REGION:-AWS_DEFAULT_REGION}
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO=kendra-bedrock-serverless

aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
verify_command "Failed to login to ECR"

# Check if docker buildx inspect default succeeds
$(command -v docker) buildx inspect default &>/dev/null
if [[ $? -eq 0 ]]; then
  DOCKER_BUILD_BIN="$(command -v docker) buildx build"
else
  DOCKER_BUILD_BIN="$(command -v docker) build"
fi

# Create manifest
# Remove manifest file if it exists
echo "[-] Removing manifest file if it exists"
docker manifest rm $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO >/dev/null 2>&1 || true
verify_command "Failed to remove manifest file"

echo "[-] Creating manifest file"
docker manifest create $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO

for arch in amd64 arm64; do
  echo "[-] Building image for '$arch'"
  $DOCKER_BUILD_BIN \
  --build-arg BRANCH=$BRANCH \
  --arch $arch \
  -t $ECR_REPO:latest-$arch .
  verify_command "Failed to build image for '$arch'"

  echo "[-] Tagging $ECR_REPO:$arch"
  docker tag $ECR_REPO:$arch $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest-$arch
  
  echo "[-] Pushing $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest-$arch"
  docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest-$arch

  echo "[-] Adding to manifest file"
  docker manifest add $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest-$arch
done

echo "[-] Verify ECS images"
aws ecr --region ${AWS_REGION} describe-images --repository-name $ECR_REPO

echo "[-] Pushing manifest file"
docker manifest push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO

echo "[-] Inspecting manifest file"
docker manifest inspect $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO

echo "[i] Done!"
