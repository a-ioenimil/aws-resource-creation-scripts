#!/bin/bash

# Source .env file if it exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"

if [ -f "$ENV_FILE" ]; then
    # Export all variables from .env file
    set -a
    source "$ENV_FILE"
    set +a
fi

export AWS_REGION="${AWS_REGION:-us-east-1}"

export PROJECT_TAG="AutomationLab"
export PROJECT_TAG_KEY="Project"
export ENVIRONMENT_TAG="${ENVIRONMENT_TAG:-dev}"

export KEY_PAIR_NAME="${KEY_PAIR_NAME:-automation-lab-keypair}"
export KEY_PAIR_FILE="${KEY_PAIR_FILE:-./automation-lab-keypair.pem}"

export INSTANCE_TYPE="${INSTANCE_TYPE:-t2.micro}"
export INSTANCE_NAME="${INSTANCE_NAME:-AutomationLab-Instance}"

get_ami_id() {
    local region="${1:-$AWS_REGION}"
    
    # If AMI_ID is set manually, use it
    if [ -n "$AMI_ID" ]; then
        echo "$AMI_ID"
        return 0
    fi
    
    # Query AWS for the latest Amazon Linux 2023 AMI (Free Tier eligible)
    local ami_id=$(aws ec2 describe-images \
        --region "$region" \
        --owners amazon \
        --filters "Name=name,Values=al2023-ami-2023*-kernel-*-x86_64" \
                  "Name=state,Values=available" \
                  "Name=architecture,Values=x86_64" \
                  "Name=virtualization-type,Values=hvm" \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
        --output text 2>/dev/null)
    
    if [ -n "$ami_id" ] && [ "$ami_id" != "None" ]; then
        echo "$ami_id"
        return 0
    fi
    
    # Fallback: Query for Amazon Linux 2 AMI
    ami_id=$(aws ec2 describe-images \
        --region "$region" \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
                  "Name=state,Values=available" \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
        --output text 2>/dev/null)
    
    if [ -n "$ami_id" ] && [ "$ami_id" != "None" ]; then
        echo "$ami_id"
        return 0
    fi
    
    # Final fallback: Use SSM Parameter Store (most reliable method)
    ami_id=$(aws ssm get-parameters \
        --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
        --region "$region" \
        --query 'Parameters[0].Value' \
        --output text 2>/dev/null)
    
    if [ -n "$ami_id" ] && [ "$ami_id" != "None" ]; then
        echo "$ami_id"
        return 0
    fi
    
    # If all methods fail, return error
    echo ""
    return 1
}

export SECURITY_GROUP_NAME="${SECURITY_GROUP_NAME:-devops-sg}"
export SECURITY_GROUP_DESC="${SECURITY_GROUP_DESC:-DevOps Security Group for AutomationLab}"

export SSH_CIDR="${SSH_CIDR:-0.0.0.0/0}"
export SSH_PORT="${SSH_PORT:-22}"

export HTTP_CIDR="${HTTP_CIDR:-0.0.0.0/0}"
export HTTP_PORT="${HTTP_PORT:-80}"

export S3_BUCKET_PREFIX="${S3_BUCKET_PREFIX:-automation-lab}"

# Generate unique bucket name
generate_bucket_name() {
    local prefix="${1:-$S3_BUCKET_PREFIX}"
    local timestamp=$(date +%Y%m%d%H%M%S)
    local random_suffix=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 6 | head -n 1)
    echo "${prefix}-${timestamp}-${random_suffix}"
}

# Sample file for S3 upload
export S3_SAMPLE_FILE="${S3_SAMPLE_FILE:-welcome.txt}"
export S3_SAMPLE_CONTENT="${S3_SAMPLE_CONTENT:-Welcome to AWS S3! This bucket was created by the AutomationLab scripts.}"


# File to store created resource IDs for cleanup (MY STATE MANAGEMENT)
export RESOURCE_TRACKING_FILE="${RESOURCE_TRACKING_FILE:-./created_resources.json}"

# Initialize or load resource tracking
init_resource_tracking() {
    if [ ! -f "$RESOURCE_TRACKING_FILE" ]; then
        echo '{"instances":[],"security_groups":[],"key_pairs":[],"s3_buckets":[]}' > "$RESOURCE_TRACKING_FILE"
        chmod 644 "$RESOURCE_TRACKING_FILE"
    else
        validate_tracking_file
    fi
}

# Validate tracking file integrity
validate_tracking_file() {
    if [ ! -f "$RESOURCE_TRACKING_FILE" ]; then
        return 0
    fi
    
    # Check if file is valid JSON
    if ! jq empty "$RESOURCE_TRACKING_FILE" 2>/dev/null; then
        log_error "Resource tracking file is corrupted!"
        
        # Try to restore from backup
        if [ -f "${RESOURCE_TRACKING_FILE}.backup" ]; then
            log_info "Restoring from backup..."
            cp "${RESOURCE_TRACKING_FILE}.backup" "$RESOURCE_TRACKING_FILE"
        else
            log_warning "No backup found. Reinitializing..."
            echo '{"instances":[],"security_groups":[],"key_pairs":[],"s3_buckets":[]}' > "$RESOURCE_TRACKING_FILE"
        fi
        return 1
    fi
    return 0
}

# Add a resource to tracking (with file locking)
track_resource() {
    local resource_type="$1"  # instances, security_groups, key_pairs, s3_buckets
    local resource_id="$2"
    
    init_resource_tracking
    
    local lock_file="${RESOURCE_TRACKING_FILE}.lock"
    local tmp_file=$(mktemp)
    
    # Create locking mechanism
    # Acquire exclusive lock (wait up to 10 seconds)
    exec 200>"$lock_file"
    if ! flock -w 10 200; then
        log_error "Failed to acquire lock on resource tracking file"
        rm -f "$tmp_file"
        return 1
    fi
    
    # Create backup before modification
    cp "$RESOURCE_TRACKING_FILE" "${RESOURCE_TRACKING_FILE}.backup"
    
    # Perform the update
    jq --arg type "$resource_type" --arg id "$resource_id" \
        '.[$type] += [$id] | .[$type] |= unique' \
        "$RESOURCE_TRACKING_FILE" > "$tmp_file"
    
    if [ $? -eq 0 ]; then
        # Atomic move to prevent corruption
        mv "$tmp_file" "$RESOURCE_TRACKING_FILE"
        chmod 644 "$RESOURCE_TRACKING_FILE"
    else
        log_error "Failed to update resource tracking file"
        rm -f "$tmp_file"
    fi
    
    # Release lock
    flock -u 200
    exec 200>&-
    rm -f "$lock_file"
}

# Get tracked resources (with read lock)
get_tracked_resources() {
    local resource_type="$1"
    local lock_file="${RESOURCE_TRACKING_FILE}.lock"
    
    if [ ! -f "$RESOURCE_TRACKING_FILE" ]; then
        return 0
    fi
    
    # Acquire shared lock for reading
    exec 201>"$lock_file"
    if ! flock -s -w 5 201; then
        # If lock fails, try to read anyway but warn 
        # (or return 1 if strict consistency is required)
        # log_warning "Failed to acquire read lock on resource tracking file"
        jq -r --arg type "$resource_type" '.[$type][]' "$RESOURCE_TRACKING_FILE" 2>/dev/null
    else
        jq -r --arg type "$resource_type" '.[$type][]' "$RESOURCE_TRACKING_FILE" 2>/dev/null
        # Release lock
        flock -u 201
    fi
    exec 201>&-
}
