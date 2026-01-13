#!/bin/bash

set -e
set -o pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source utility functions and configuration
source "$PROJECT_ROOT/lib/utils.sh"
source "$PROJECT_ROOT/config/config.sh"

BUCKET_PREFIX="$S3_BUCKET_PREFIX"
REGION="$AWS_REGION"
UPLOAD_FILE=""

show_help() {
    head -30 "$0" | grep -E "^#" | sed 's/^# //' | sed 's/^#//'
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                BUCKET_PREFIX="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -f|--file)
                UPLOAD_FILE="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

generate_unique_bucket_name() {
    local prefix="$1"
    local timestamp=$(date +%Y%m%d%H%M%S)
    local random_suffix=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 6 | head -n 1)
    echo "${prefix}-${timestamp}-${random_suffix}"
}

create_s3_bucket() {
    local bucket_name="$1"
    
    log_info "Creating S3 bucket: $bucket_name"
    
    # Check if bucket already exists
    if bucket_exists "$bucket_name"; then
        log_warning "Bucket '$bucket_name' already exists"
        return 0
    fi
    
    # Create bucket - Note: us-east-1 doesn't use LocationConstraint
    if [ "$REGION" == "us-east-1" ]; then
        aws s3api create-bucket \
            --bucket "$bucket_name" \
            --region "$REGION"
    else
        aws s3api create-bucket \
            --bucket "$bucket_name" \
            --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION"
    fi
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create S3 bucket"
        exit 1
    fi
    
    log_success "S3 bucket created: $bucket_name"
    
    # Wait for bucket to exist
    log_info "Waiting for bucket to be available..."
    aws s3api wait bucket-exists --bucket "$bucket_name"
    
    # Track for cleanup
    track_resource "s3_buckets" "$bucket_name"
}

enable_bucket_versioning() {
    local bucket_name="$1"
    
    log_info "Enabling versioning on bucket: $bucket_name"
    
    aws s3api put-bucket-versioning \
        --bucket "$bucket_name" \
        --versioning-configuration Status=Enabled
    
    if [ $? -eq 0 ]; then
        log_success "Versioning enabled"
    else
        log_error "Failed to enable versioning"
        exit 1
    fi
}

set_bucket_tags() {
    local bucket_name="$1"
    
    log_info "Setting bucket tags..."
    
    aws s3api put-bucket-tagging \
        --bucket "$bucket_name" \
        --tagging "TagSet=[{Key=$PROJECT_TAG_KEY,Value=$PROJECT_TAG},{Key=Environment,Value=$ENVIRONMENT_TAG},{Key=Name,Value=$bucket_name}]"
    
    if [ $? -eq 0 ]; then
        log_success "Bucket tags applied"
    else
        log_warning "Failed to set bucket tags"
    fi
}

set_bucket_policy() {
    local bucket_name="$1"
    
    log_info "Setting bucket policy..."
    
    # Get the current AWS account ID
    local account_id=$(aws sts get-caller-identity --query 'Account' --output text)
    
    # Create a simple bucket policy that allows the account to access the bucket
    local policy=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowAccountAccess",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${account_id}:root"
            },
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${bucket_name}",
                "arn:aws:s3:::${bucket_name}/*"
            ]
        }
    ]
}
EOF
)
    
    echo "$policy" | aws s3api put-bucket-policy \
        --bucket "$bucket_name" \
        --policy file:///dev/stdin
    
    if [ $? -eq 0 ]; then
        log_success "Bucket policy applied"
    else
        log_warning "Failed to set bucket policy (may require additional permissions)"
    fi
}

create_sample_file() {
    local file_path="$PROJECT_ROOT/files/$S3_SAMPLE_FILE"
    
    # Create files directory if it doesn't exist
    mkdir -p "$PROJECT_ROOT/files"
    
    # Create sample file if it doesn't exist
    if [ ! -f "$file_path" ]; then
        log_info "Creating sample file: $file_path"
        
        cat > "$file_path" <<EOF
====================================================
   Welcome to AWS S3!
====================================================

This bucket was created by the AutomationLab scripts.

Creation Details:
  - Date: $(date '+%Y-%m-%d %H:%M:%S %Z')
  - Project: $PROJECT_TAG
  - Environment: $ENVIRONMENT_TAG
  - Region: $REGION

This is a sample file to demonstrate S3 object upload
capabilities using the AWS CLI automation scripts.

For more information, visit:
https://docs.aws.amazon.com/s3/

====================================================
EOF
        log_success "Sample file created: $file_path"
    fi
    
    echo "$file_path"
}

upload_file_to_bucket() {
    local bucket_name="$1"
    local file_path="$2"
    
    log_info "Uploading file to bucket..."
    
    local file_name=$(basename "$file_path")
    
    aws s3 cp "$file_path" "s3://$bucket_name/$file_name"
    
    if [ $? -eq 0 ]; then
        log_success "File uploaded: s3://$bucket_name/$file_name"
    else
        log_error "Failed to upload file"
        exit 1
    fi
}

display_bucket_info() {
    local bucket_name="$1"
    
    print_separator
    echo -e "${GREEN}S3 Bucket Created Successfully${NC}"
    print_separator
    
    echo ""
    echo "Bucket Details:"
    echo "  Name:     $bucket_name"
    echo "  Region:   $REGION"
    echo "  ARN:      arn:aws:s3:::$bucket_name"
    echo ""
    
    # Get versioning status
    local versioning=$(aws s3api get-bucket-versioning \
        --bucket "$bucket_name" \
        --query 'Status' \
        --output text 2>/dev/null || echo "N/A")
    echo "  Versioning: $versioning"
    echo ""
    
    # List objects in bucket
    echo "Objects in bucket:"
    aws s3 ls "s3://$bucket_name/" 2>/dev/null | while read -r line; do
        echo "  - $line"
    done
    echo ""
    
    # Get bucket tags
    echo "Tags:"
    aws s3api get-bucket-tagging \
        --bucket "$bucket_name" \
        --query 'TagSet[]' \
        --output text 2>/dev/null | while read -r key value; do
        echo "  - $key: $value"
    done || echo "  (no tags)"
    echo ""
    
    echo "Access URLs:"
    echo "  S3 URI:    s3://$bucket_name"
    echo "  HTTP URL:  https://$bucket_name.s3.amazonaws.com"
    echo "  Console:   https://s3.console.aws.amazon.com/s3/buckets/$bucket_name"
    
    print_separator
}

# =============================================================================
# Main Script
# =============================================================================

main() {
    parse_args "$@"
    
    log_info "=========================================="
    log_info "AWS S3 Bucket Creation Script"
    log_info "=========================================="
    
    # Check AWS environment
    check_aws_environment
    
    # Override region if set
    export AWS_DEFAULT_REGION="$REGION"
    
    # Generate unique bucket name
    BUCKET_NAME=$(generate_unique_bucket_name "$BUCKET_PREFIX")
    
    log_info "Configuration:"
    log_info "  Bucket Name: $BUCKET_NAME"
    log_info "  Region: $REGION"
    
    # Create S3 bucket
    create_s3_bucket "$BUCKET_NAME"
    
    # Enable versioning
    enable_bucket_versioning "$BUCKET_NAME"
    
    # Set bucket tags
    set_bucket_tags "$BUCKET_NAME"
    
    # Set bucket policy
    set_bucket_policy "$BUCKET_NAME"
    
    # Create or use provided sample file
    if [ -z "$UPLOAD_FILE" ]; then
        UPLOAD_FILE=$(create_sample_file)
    fi
    
    # Upload file to bucket
    upload_file_to_bucket "$BUCKET_NAME" "$UPLOAD_FILE"
    
    # Display bucket information
    display_bucket_info "$BUCKET_NAME"
    
    log_success "S3 bucket setup complete!"
    
    # Export for use by other scripts
    echo ""
    echo "To use this bucket in other scripts, export:"
    echo "  export BUCKET_NAME=$BUCKET_NAME"
}

# Run main function
main "$@"
