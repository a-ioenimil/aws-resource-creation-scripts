#!/bin/bash

set -e
set -o pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source utility functions and configuration
source "$PROJECT_ROOT/lib/utils.sh"
source "$PROJECT_ROOT/config/config.sh"

# =============================================================================
# Script Variables (can be overridden by command line args)
# =============================================================================
REGION="$AWS_REGION"
TAG_VALUE="$PROJECT_TAG"
TAG_KEY="$PROJECT_TAG_KEY"
FORCE_DELETE=false
DRY_RUN=false

show_help() {
    head -32 "$0" | grep -E "^#" | sed 's/^# //' | sed 's/^#//'
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -t|--tag)
                TAG_VALUE="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_DELETE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
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

confirm_deletion() {
    if [ "$FORCE_DELETE" = true ]; then
        return 0
    fi
    
    echo ""
    log_warning "This will delete ALL resources with tag $TAG_KEY=$TAG_VALUE"
    echo ""
    read -p "Are you sure you want to proceed? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
}

find_tagged_instances() {
    log_info "Finding EC2 instances with tag $TAG_KEY=$TAG_VALUE..."
    
    local instances=$(aws ec2 describe-instances \
        --filters "Name=tag:$TAG_KEY,Values=$TAG_VALUE" \
                  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text \
        --region "$REGION" 2>/dev/null)
    
    echo "$instances"
}

terminate_instances() {
    local instances="$1"
    
    if [ -z "$instances" ] || [ "$instances" == "None" ]; then
        log_info "No instances found to terminate"
        return 0
    fi
    
    local instance_array=($instances)
    local count=${#instance_array[@]}
    
    log_info "Found $count instance(s) to terminate:"
    for instance in "${instance_array[@]}"; do
        echo "  - $instance"
    done
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would terminate instances: $instances"
        return 0
    fi
    
    log_info "Terminating instances..."
    aws ec2 terminate-instances \
        --instance-ids $instances \
        --region "$REGION" > /dev/null
    
    log_info "Waiting for instances to terminate..."
    aws ec2 wait instance-terminated \
        --instance-ids $instances \
        --region "$REGION" 2>/dev/null || true
    
    log_success "Instances terminated successfully"
}

find_tagged_security_groups() {
    log_info "Finding security groups with tag $TAG_KEY=$TAG_VALUE..."
    
    local security_groups=$(aws ec2 describe-security-groups \
        --filters "Name=tag:$TAG_KEY,Values=$TAG_VALUE" \
        --query 'SecurityGroups[*].GroupId' \
        --output text \
        --region "$REGION" 2>/dev/null)
    
    echo "$security_groups"
}

delete_security_groups() {
    local security_groups="$1"
    
    if [ -z "$security_groups" ] || [ "$security_groups" == "None" ]; then
        log_info "No security groups found to delete"
        return 0
    fi
    
    local sg_array=($security_groups)
    local count=${#sg_array[@]}
    
    log_info "Found $count security group(s) to delete:"
    for sg in "${sg_array[@]}"; do
        echo "  - $sg"
    done
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would delete security groups: $security_groups"
        return 0
    fi
    
    # Delete each security group
    local failed=0
    for sg_id in "${sg_array[@]}"; do
        log_info "Deleting security group: $sg_id"
        
        # First, try to remove all ingress and egress rules
        aws ec2 revoke-security-group-ingress \
            --group-id "$sg_id" \
            --region "$REGION" \
            --ip-permissions "$(aws ec2 describe-security-groups --group-ids "$sg_id" --query 'SecurityGroups[0].IpPermissions' --output json --region "$REGION")" 2>/dev/null || true
        
        # Delete the security group
        if aws ec2 delete-security-group \
            --group-id "$sg_id" \
            --region "$REGION" 2>/dev/null; then
            log_success "Security group $sg_id deleted"
        else
            log_warning "Failed to delete security group $sg_id (may be in use)"
            ((failed++)) || true
        fi
    done
    
    if [ $failed -gt 0 ]; then
        log_warning "$failed security group(s) could not be deleted"
    fi
}

find_tagged_buckets() {
    log_info "Finding S3 buckets with tag $TAG_KEY=$TAG_VALUE..."
    
    local buckets=""
    
    # List all buckets and check tags
    local all_buckets=$(aws s3api list-buckets \
        --query 'Buckets[*].Name' \
        --output text 2>/dev/null)
    
    for bucket in $all_buckets; do
        # Check if bucket has our tag
        local tags=$(aws s3api get-bucket-tagging \
            --bucket "$bucket" 2>/dev/null | \
            jq -r ".TagSet[] | select(.Key==\"$TAG_KEY\" and .Value==\"$TAG_VALUE\") | .Value" 2>/dev/null)
        
        if [ "$tags" == "$TAG_VALUE" ]; then
            buckets="$buckets $bucket"
        fi
    done
    
    echo "$buckets" | xargs
}

delete_s3_buckets() {
    local buckets="$1"
    
    if [ -z "$buckets" ]; then
        log_info "No S3 buckets found to delete"
        return 0
    fi
    
    local bucket_array=($buckets)
    local count=${#bucket_array[@]}
    
    log_info "Found $count S3 bucket(s) to delete:"
    for bucket in "${bucket_array[@]}"; do
        echo "  - $bucket"
    done
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would delete buckets: $buckets"
        return 0
    fi
    
    # Delete each bucket
    for bucket_name in "${bucket_array[@]}"; do
        log_info "Deleting bucket: $bucket_name"
        
        # Empty the bucket first (including versioned objects)
        empty_s3_bucket "$bucket_name"
        
        # Delete the bucket
        if aws s3api delete-bucket \
            --bucket "$bucket_name" 2>/dev/null; then
            log_success "Bucket $bucket_name deleted"
        else
            log_warning "Failed to delete bucket $bucket_name"
        fi
    done
}

find_tagged_key_pairs() {
    log_info "Finding key pairs with tag $TAG_KEY=$TAG_VALUE..."
    
    local key_pairs=$(aws ec2 describe-key-pairs \
        --filters "Name=tag:$TAG_KEY,Values=$TAG_VALUE" \
        --query 'KeyPairs[*].KeyName' \
        --output text \
        --region "$REGION" 2>/dev/null)
    
    # Also get from tracking file
    local tracked_keys=$(get_tracked_resources "key_pairs")
    
    # Combine and deduplicate
    local all_keys="$key_pairs $tracked_keys"
    echo "$all_keys" | tr ' ' '\n' | sort -u | tr '\n' ' ' | xargs
}

delete_key_pairs() {
    local key_pairs="$1"
    
    if [ -z "$key_pairs" ] || [ "$key_pairs" == "None" ]; then
        log_info "No key pairs found to delete"
        return 0
    fi
    
    local kp_array=($key_pairs)
    local count=${#kp_array[@]}
    
    log_info "Found $count key pair(s) to delete:"
    for kp in "${kp_array[@]}"; do
        echo "  - $kp"
    done
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would delete key pairs: $key_pairs"
        return 0
    fi
    
    # Delete each key pair
    for key_name in "${kp_array[@]}"; do
        if [ -z "$key_name" ]; then
            continue
        fi
        
        log_info "Deleting key pair: $key_name"
        
        if aws ec2 delete-key-pair \
            --key-name "$key_name" \
            --region "$REGION" 2>/dev/null; then
            log_success "Key pair $key_name deleted"
            
            # Also remove local key file if it exists
            local key_file="$PROJECT_ROOT/keys/${key_name}.pem"
            if [ -f "$key_file" ]; then
                rm -f "$key_file"
                log_info "Removed local key file: $key_file"
            fi
        else
            log_warning "Failed to delete key pair $key_name"
        fi
    done
}

cleanup_tracking_file() {
    if [ -f "$RESOURCE_TRACKING_FILE" ]; then
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY RUN] Would remove tracking file: $RESOURCE_TRACKING_FILE"
        else
            rm -f "$RESOURCE_TRACKING_FILE"
            log_info "Removed tracking file: $RESOURCE_TRACKING_FILE"
        fi
    fi
}

display_summary() {
    print_separator
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}DRY RUN COMPLETED${NC}"
        echo "No resources were actually deleted."
        echo "Run without --dry-run to perform actual deletion."
    else
        echo -e "${GREEN}CLEANUP COMPLETED${NC}"
        echo "All tagged resources have been cleaned up."
    fi
    print_separator
}


main() {
    parse_args "$@"
    
    log_info "=========================================="
    log_info "AWS Resource Cleanup Script"
    log_info "=========================================="
    
    # Check AWS environment
    check_aws_environment
    
    # Override region if set
    export AWS_DEFAULT_REGION="$REGION"
    
    log_info "Configuration:"
    log_info "  Region: $REGION"
    log_info "  Tag Filter: $TAG_KEY=$TAG_VALUE"
    log_info "  Dry Run: $DRY_RUN"
    
    # Confirm deletion
    confirm_deletion
    
    echo ""
    log_info "Starting cleanup process..."
    echo ""
    
    # Step 1: Find and terminate EC2 instances first
    log_info "Step 1/4: Cleaning up EC2 instances"
    INSTANCES=$(find_tagged_instances)
    terminate_instances "$INSTANCES"
    echo ""
    
    # Step 2: Delete security groups (after instances are terminated)
    log_info "Step 2/4: Cleaning up security groups"
    SECURITY_GROUPS=$(find_tagged_security_groups)
    delete_security_groups "$SECURITY_GROUPS"
    echo ""
    
    # Step 3: Delete S3 buckets
    log_info "Step 3/4: Cleaning up S3 buckets"
    BUCKETS=$(find_tagged_buckets)
    delete_s3_buckets "$BUCKETS"
    echo ""
    
    # Step 4: Delete key pairs
    log_info "Step 4/4: Cleaning up key pairs"
    KEY_PAIRS=$(find_tagged_key_pairs)
    delete_key_pairs "$KEY_PAIRS"
    echo ""
    
    # Cleanup tracking file
    cleanup_tracking_file
    
    # Display summary
    display_summary
}

# Run main function
main "$@"
