#!/bin/bash

# Bootstrap Pipeline Deployment Script
# Deploy the self-updating pipeline once, then everything is automated

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_message() {
    echo -e "${2}${1}${NC}"
}

# Configuration
PIPELINE_STACK_NAME="resume-website-pipeline"
TEMPLATE_FILE="infra/bootstrap-pipeline.yaml"
PARAMETERS_FILE="infra/parameters.json"
REGION="us-east-1"

print_message "🚀 Bootstrap Pipeline Deployment" $BLUE
print_message "========================================" $BLUE

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    print_message "AWS CLI not installed!" $RED
    exit 1
fi

# Get AWS profile
echo ""
if [ -f ~/.aws/credentials ]; then
    print_message "Available AWS profiles:" $BLUE
    grep '\[' ~/.aws/credentials | sed 's/\[//g' | sed 's/\]//g' | sed 's/^/  - /'
fi
echo ""
read -p "Enter AWS profile name (or press Enter for default): " AWS_PROFILE

if [ ! -z "$AWS_PROFILE" ]; then
    export AWS_PROFILE="$AWS_PROFILE"
    AWS_CMD="aws --profile $AWS_PROFILE"
    print_message "Using AWS profile: $AWS_PROFILE" $YELLOW
else
    AWS_CMD="aws"
    print_message "Using default AWS profile" $YELLOW
fi

# Check authentication
if ! $AWS_CMD sts get-caller-identity &> /dev/null; then
    print_message "Authentication failed!" $RED
    exit 1
fi

CURRENT_USER=$($AWS_CMD sts get-caller-identity --query 'Arn' --output text)
print_message "Authenticated as: $CURRENT_USER" $GREEN

# Check SSM parameter
print_message "\nChecking GitHub token in SSM..." $BLUE
if ! $AWS_CMD ssm get-parameter --name "/github/pat/pipeline" --region $REGION &> /dev/null; then
    print_message "GitHub token not found in SSM!" $RED
    print_message "Create it with:" $YELLOW
    print_message "  aws ssm put-parameter --name \"/github/pat/pipeline\" --value \"your-token\" --type \"String\"" $YELLOW
    exit 1
fi
print_message "✓ GitHub token found" $GREEN

# Check parameters file
if [ ! -f "$PARAMETERS_FILE" ]; then
    print_message "Parameters file not found!" $RED
    exit 1
fi

if grep -q "YOUR_GITHUB_USERNAME" "$PARAMETERS_FILE"; then
    print_message "Please update $PARAMETERS_FILE with your GitHub username!" $RED
    exit 1
fi

# Display deployment info
AWS_ACCOUNT=$($AWS_CMD sts get-caller-identity --query Account --output text)
print_message "\n📋 Deployment Details:" $BLUE
print_message "AWS Account: $AWS_ACCOUNT" $YELLOW
print_message "Region: $REGION" $YELLOW
print_message "Pipeline Stack: $PIPELINE_STACK_NAME" $YELLOW

echo ""
read -p "Deploy bootstrap pipeline? (y/n): " confirm
if [[ $confirm != "y" && $confirm != "Y" ]]; then
    print_message "Cancelled" $YELLOW
    exit 0
fi

# Deploy pipeline stack
print_message "\n🚀 Deploying bootstrap pipeline..." $BLUE

if $AWS_CMD cloudformation describe-stacks --stack-name $PIPELINE_STACK_NAME --region $REGION &> /dev/null; then
    print_message "Stack exists. Updating..." $YELLOW
    $AWS_CMD cloudformation update-stack \
        --stack-name $PIPELINE_STACK_NAME \
        --template-body file://$TEMPLATE_FILE \
        --parameters file://$PARAMETERS_FILE \
        --capabilities CAPABILITY_NAMED_IAM \
        --region $REGION
    
    print_message "Waiting for update..." $YELLOW
    $AWS_CMD cloudformation wait stack-update-complete --stack-name $PIPELINE_STACK_NAME --region $REGION
else
    print_message "Creating new stack..." $YELLOW
    $AWS_CMD cloudformation create-stack \
        --stack-name $PIPELINE_STACK_NAME \
        --template-body file://$TEMPLATE_FILE \
        --parameters file://$PARAMETERS_FILE \
        --capabilities CAPABILITY_NAMED_IAM \
        --region $REGION
    
    print_message "Waiting for creation..." $YELLOW
    $AWS_CMD cloudformation wait stack-create-complete --stack-name $PIPELINE_STACK_NAME --region $REGION
fi

# Get outputs
PIPELINE_URL=$($AWS_CMD cloudformation describe-stacks \
    --stack-name $PIPELINE_STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`PipelineURL`].OutputValue' \
    --output text)

print_message "\n✅ Bootstrap Pipeline Deployed Successfully!" $GREEN
print_message "==========================================" $GREEN
print_message "Pipeline Console: $PIPELINE_URL" $CYAN
print_message "\n📝 Next Steps:" $BLUE
print_message "1. Pipeline is now monitoring your GitHub repository" $BLUE
print_message "2. Push changes to trigger automatic deployment" $BLUE
print_message "3. Pipeline will deploy infrastructure and website" $BLUE
print_message "4. Pipeline can self-update if you modify bootstrap-pipeline.yaml" $BLUE
print_message "\n🎯 Push to GitHub to trigger first deployment!" $GREEN
