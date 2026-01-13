#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}


# Install AWS CLI automatically
install_aws_cli() {
    log_info "AWS CLI not found. Attempting to install..."
    
    # Detect the operating system
    local os_type=""
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        os_type="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        os_type="macos"
    else
        log_error "Unsupported operating system: $OSTYPE"
        log_info "Please install AWS CLI manually: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
    
    if [ "$os_type" == "linux" ]; then
        log_info "Detected Linux. Installing AWS CLI v2..."
        
        # Create temp directory
        local tmp_dir=$(mktemp -d)
        cd "$tmp_dir"
        
        # Download and install
        curl -sS "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        
        if ! command -v unzip &> /dev/null; then
            log_info "Installing unzip..."
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y unzip
            elif command -v yum &> /dev/null; then
                sudo yum install -y unzip
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y unzip
            else
                log_error "Could not install unzip. Please install it manually."
                exit 1
            fi
        fi
        
        unzip -q awscliv2.zip
        sudo ./aws/install
        
        # Cleanup
        cd - > /dev/null
        rm -rf "$tmp_dir"
        
    elif [ "$os_type" == "macos" ]; then
        log_info "Detected macOS. Installing AWS CLI..."
        
        if command -v brew &> /dev/null; then
            log_info "Installing via Homebrew..."
            brew install awscli
        else
            log_info "Installing via pkg installer..."
            local tmp_dir=$(mktemp -d)
            cd "$tmp_dir"
            
            curl -sS "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
            sudo installer -pkg AWSCLIV2.pkg -target /
            
            cd - > /dev/null
            rm -rf "$tmp_dir"
        fi
    fi
    
    # Verify installation
    if command -v aws &> /dev/null; then
        log_success "AWS CLI installed successfully: $(aws --version)"
    else
        log_error "AWS CLI installation failed. Please install manually."
        log_info "Visit: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
}

# Check if AWS CLI is installed, install if not
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        install_aws_cli
    else
        log_info "AWS CLI is installed: $(aws --version)"
    fi
}

# Check if AWS credentials are configured
check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured or invalid."
        log_info "Run 'aws configure' to set up your credentials."
        exit 1
    fi
    
    local identity=$(aws sts get-caller-identity --output json)
    local account_id=$(echo "$identity" | jq -r '.Account')
    local arn=$(echo "$identity" | jq -r '.Arn')
    
    log_info "AWS Account ID: $account_id"
    log_info "AWS Identity ARN: $arn"
}

# Verify the configured region
check_aws_region() {
    local region=$(aws configure get region)
    if [ -z "$region" ]; then
        log_warning "No default region configured. Using us-east-1"
        export AWS_DEFAULT_REGION="us-east-1"
    else
        log_info "AWS Region: $region"
    fi
}

# Full AWS environment check
check_aws_environment() {
    log_info "Checking AWS environment..."
    check_aws_cli
    check_aws_credentials
    check_aws_region
    log_success "AWS environment check passed!"
}

# Get the default VPC ID
get_default_vpc_id() {
    local vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=isDefault,Values=true" \
        --query 'Vpcs[0].VpcId' \
        --output text \
        --region "${AWS_REGION:-us-east-1}" 2>/dev/null)
    
    if [ "$vpc_id" == "None" ] || [ -z "$vpc_id" ]; then
        log_error "No default VPC found in region ${AWS_REGION:-us-east-1}"
        return 1
    fi
    
    echo "$vpc_id"
}

# Wait for EC2 instance to be in running state
wait_for_instance_running() {
    local instance_id="$1"
    local region="${2:-us-east-1}"
    
    log_info "Waiting for instance $instance_id to be running..."
    aws ec2 wait instance-running \
        --instance-ids "$instance_id" \
        --region "$region"
    
    if [ $? -eq 0 ]; then
        log_success "Instance $instance_id is now running"
        return 0
    else
        log_error "Timeout waiting for instance $instance_id"
        return 1
    fi
}

# Wait for EC2 instance to be terminated
wait_for_instance_terminated() {
    local instance_id="$1"
    local region="${2:-us-east-1}"
    
    log_info "Waiting for instance $instance_id to be terminated..."
    aws ec2 wait instance-terminated \
        --instance-ids "$instance_id" \
        --region "$region"
    
    if [ $? -eq 0 ]; then
        log_success "Instance $instance_id is terminated"
        return 0
    else
        log_error "Timeout waiting for instance $instance_id to terminate"
        return 1
    fi
}

# Get public IP of an EC2 instance
get_instance_public_ip() {
    local instance_id="$1"
    local region="${2:-us-east-1}"
    
    aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text \
        --region "$region"
}

# Check if a security group exists
security_group_exists() {
    local group_name="$1"
    local region="${2:-us-east-1}"
    
    local sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$group_name" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region "$region" 2>/dev/null)
    
    if [ "$sg_id" != "None" ] && [ -n "$sg_id" ]; then
        echo "$sg_id"
        return 0
    fi
    return 1
}

# Check if an S3 bucket exists
bucket_exists() {
    local bucket_name="$1"
    
    if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Check if a key pair exists
key_pair_exists() {
    local key_name="$1"
    local region="${2:-us-east-1}"
    
    if aws ec2 describe-key-pairs \
        --key-names "$key_name" \
        --region "$region" &>/dev/null; then
        return 0
    fi
    return 1
}

# Delete all objects in an S3 bucket (including versioned objects)
empty_s3_bucket() {
    local bucket_name="$1"
    
    log_info "Emptying bucket: $bucket_name"
    
    # Delete all object versions
    aws s3api list-object-versions \
        --bucket "$bucket_name" \
        --output json 2>/dev/null | \
    jq -r '.Versions[]? | "\(.Key) \(.VersionId)"' | \
    while read -r key version_id; do
        if [ -n "$key" ] && [ -n "$version_id" ]; then
            aws s3api delete-object \
                --bucket "$bucket_name" \
                --key "$key" \
                --version-id "$version_id" 2>/dev/null
        fi
    done
    
    # Delete all delete markers
    aws s3api list-object-versions \
        --bucket "$bucket_name" \
        --output json 2>/dev/null | \
    jq -r '.DeleteMarkers[]? | "\(.Key) \(.VersionId)"' | \
    while read -r key version_id; do
        if [ -n "$key" ] && [ -n "$version_id" ]; then
            aws s3api delete-object \
                --bucket "$bucket_name" \
                --key "$key" \
                --version-id "$version_id" 2>/dev/null
        fi
    done
    
    # Also try the simple delete for non-versioned objects
    aws s3 rm "s3://$bucket_name" --recursive 2>/dev/null
    
    log_success "Bucket $bucket_name emptied"
}

# Print a separator line
print_separator() {
    echo "============================================================"
}

# Print resource summary
print_resource_summary() {
    local resource_type="$1"
    local resource_id="$2"
    local resource_name="$3"
    
    print_separator
    echo -e "${GREEN}Resource Created Successfully${NC}"
    print_separator
    echo "Type: $resource_type"
    echo "ID: $resource_id"
    echo "Name: $resource_name"
    print_separator
}
