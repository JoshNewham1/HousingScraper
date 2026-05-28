#!/bin/bash

# Exit on any error
set -e

REGION="eu-west-2"
IMAGE_NAME="housing-scraper"

# Read a single key from an env file, stripping surrounding quotes and whitespace.
# Values containing '=' (e.g. URL query strings) are handled correctly by taking
# everything after the first '=' sign.
get_env() {
    local file=$1 key=$2
    grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2- \
        | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
        | sed 's/^"//;s/"$//'
}

echo "Step 0: Building terraform.tfvars from environment files..."

if [ ! -f .env.shared ]; then
    echo "Error: .env.shared not found."
    echo "Copy .env.shared.example to .env.shared and fill in your Mailjet credentials."
    exit 1
fi

# Collect instance env files: any .env.<name> that isn't a known non-instance file
shopt -s nullglob
instance_files=()
for f in .env.*; do
    name="${f#.env.}"
    case "$name" in
        shared|example|*example) continue ;;
    esac
    instance_files+=("$f")
done

if [ ${#instance_files[@]} -eq 0 ]; then
    echo "Error: No instance env files found."
    echo "Create at least one .env.<name> file (e.g. .env.my-search) from .env.instance.example."
    exit 1
fi

MJ_APIKEY_PUBLIC=$(get_env .env.shared MJ_APIKEY_PUBLIC)
MJ_APIKEY_PRIVATE=$(get_env .env.shared MJ_APIKEY_PRIVATE)
SENDER_EMAIL=$(get_env .env.shared SENDER_EMAIL)

{
    echo "mj_apikey_public  = \"$MJ_APIKEY_PUBLIC\""
    echo "mj_apikey_private = \"$MJ_APIKEY_PRIVATE\""
    echo "sender_email      = \"$SENDER_EMAIL\""
    echo ""
    echo "instances = {"

    for env_file in "${instance_files[@]}"; do
        instance_name="${env_file#.env.}"

        GUMTREE_LINK=$(get_env "$env_file" GUMTREE_LINK)
        RIGHTMOVE_LINK=$(get_env "$env_file" RIGHTMOVE_LINK)
        RECIPIENT_EMAIL=$(get_env "$env_file" RECIPIENT_EMAIL)
        START_DATE_FILTER=$(get_env "$env_file" START_DATE_FILTER)
        SCHEDULE=$(get_env "$env_file" SCHEDULE)
        [ -z "$SCHEDULE" ] && SCHEDULE="cron(0 9 * * ? *)"

        echo "  \"$instance_name\" = {"
        echo "    gumtree_link      = \"$GUMTREE_LINK\""
        echo "    rightmove_link    = \"$RIGHTMOVE_LINK\""
        echo "    recipient_email   = \"$RECIPIENT_EMAIL\""
        echo "    start_date_filter = \"$START_DATE_FILTER\""
        echo "    schedule          = \"$SCHEDULE\""
        echo "  }"
    done

    echo "}"
} > terraform.tfvars

echo "Generated terraform.tfvars with instances:"
grep -E '^\s+"' terraform.tfvars | sed 's/[" =]//g' | while read -r name; do echo "  - $name"; done

echo "Step 1: Fetching ECR Repository URL from Terraform..."
if ! command -v terraform &> /dev/null; then
    echo "Error: terraform is not installed."
    exit 1
fi

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
echo "Each scheduled task will use the 'latest' tag at its next run."
