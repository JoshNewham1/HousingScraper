#!/bin/bash

# Exit on any error
set -e

# Configuration - should match aws.tf
REGION="eu-west-2"
IMAGE_NAME="housing-scraper"

echo "Step 0: Synchronising .env to Terraform variables..."
if [ ! -f .env ]; then
    echo "Error: .env file not found. Please create it from .env.example."
    exit 1
fi

# Create a terraform.tfvars file from .env
# This maps ENV_VAR=value to env_var="value" for Terraform
cat .env | grep -v '^#' | grep '=' | sed -E 's/^([^=]+)=(.*)/lower(\1) = "\2"/' | sed 's/mj_/mj_/g' > terraform.tfvars.tmp

# Specifically handle the mapping for our terraform variable names
# (Terraform vars are lowercase in our aws.tf)
echo "" > terraform.tfvars
while IFS='=' read -r key value || [ -n "$key" ]; do
    [[ $key =~ ^#.* ]] && continue
    [[ -z $key ]] && continue
    
    # Remove quotes if they exist in .env to avoid double-quoting
    value=$(echo "$value" | sed 's/^"//;s/"$//')
    
    case "$key" in
        GUMTREE_LINK) echo "gumtree_link = \"$value\"" >> terraform.tfvars ;;
        RIGHTMOVE_LINK) echo "rightmove_link = \"$value\"" >> terraform.tfvars ;;
        MJ_APIKEY_PUBLIC) echo "mj_apikey_public = \"$value\"" >> terraform.tfvars ;;
        MJ_APIKEY_PRIVATE) echo "mj_apikey_private = \"$value\"" >> terraform.tfvars ;;
        SENDER_EMAIL) echo "sender_email = \"$value\"" >> terraform.tfvars ;;
        RECIPIENT_EMAIL) echo "recipient_email = \"$value\"" >> terraform.tfvars ;;
        START_DATE_FILTER) echo "start_date_filter = \"$value\"" >> terraform.tfvars ;;
    esac
done < .env

rm -f terraform.tfvars.tmp

echo "Step 1: Fetching ECR Repository URL from Terraform..."
# Ensure terraform has been initialised and applied
if ! command -v terraform &> /dev/null; then
    echo "Error: terraform is not installed."
    exit 1
fi

# Apply terraform first to ensure variables are in sync and ECR exists
echo "Applying Terraform changes..."
terraform apply -auto-approve

ECR_URL=$(terraform output -raw ecr_repository_url)

if [ -z "$ECR_URL" ] || [ "$ECR_URL" == "null" ]; then
    echo "Error: Could not find ecr_repository_url in terraform output."
    echo "Make sure you have run 'terraform apply' first."
    exit 1
fi

echo "ECR URL found: $ECR_URL"

echo "Step 2: Authenticating Docker with ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_URL

echo "Step 3: Building Docker image..."
docker build -t $IMAGE_NAME .

echo "Step 4: Tagging image..."
docker tag $IMAGE_NAME:latest $ECR_URL:latest

echo "Step 5: Pushing image to ECR..."
docker push $ECR_URL:latest

echo "Deployment complete! Your image is now in ECR."
echo "The scheduled task will use the 'latest' tag at its next run."
