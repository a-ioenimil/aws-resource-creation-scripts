#!/bin/bash

set -e
set -o pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source utility functions and configuration
source "$PROJECT_ROOT/lib/utils.sh"
source "$PROJECT_ROOT/config/config.sh"

INSTANCE_NAME_VAR="$INSTANCE_NAME"
KEY_NAME="$KEY_PAIR_NAME"
KEY_FILE="$PROJECT_ROOT/keys/${KEY_PAIR_NAME}.pem"
TYPE="$INSTANCE_TYPE"
SG_ID=""
REGION="$AWS_REGION"

show_help() {
    head -35 "$0" | grep -E "^#" | sed 's/^# //' | sed 's/^#//'
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                INSTANCE_NAME_VAR="$2"
                shift 2
                ;;
            -k|--key-name)
                KEY_NAME="$2"
                KEY_FILE="$PROJECT_ROOT/keys/${KEY_NAME}.pem"
                shift 2
                ;;
            -t|--type)
                TYPE="$2"
                shift 2
                ;;
            -s|--security-group)
                SG_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
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

create_key_pair() {
    log_info "Creating EC2 key pair: $KEY_NAME"
    
    # Create keys directory if it doesn't exist
    mkdir -p "$PROJECT_ROOT/keys"
    
    # Check if key pair already exists in AWS
    if key_pair_exists "$KEY_NAME" "$REGION"; then
        log_warning "Key pair '$KEY_NAME' already exists in AWS"
        
        # Check if we have the local .pem file
        if [ -f "$KEY_FILE" ]; then
            log_info "Using existing key file: $KEY_FILE"
            return 0
        else
            log_warning "Local key file not found. You may need to delete the key pair and recreate it."
            log_warning "To delete: aws ec2 delete-key-pair --key-name $KEY_NAME --region $REGION"
            log_info "Continuing with existing key pair in AWS..."
            return 0
        fi
    fi
    
    # Create the key pair
    aws ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --query 'KeyMaterial' \
        --output text \
        --region "$REGION" > "$KEY_FILE"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create key pair"
        exit 1
    fi
    
    # Set secure permissions on the key file
    chmod 400 "$KEY_FILE"
    
    log_success "Key pair created and saved to: $KEY_FILE"
    
    # Tag the key pair
    aws ec2 create-tags \
        --resources "$KEY_NAME" \
        --tags "Key=$PROJECT_TAG_KEY,Value=$PROJECT_TAG" \
        --region "$REGION" 2>/dev/null || true
    
    # Track for cleanup
    track_resource "key_pairs" "$KEY_NAME"
}

get_or_create_security_group() {
    if [ -n "$SG_ID" ]; then
        log_info "Using provided security group: $SG_ID"
        return 0
    fi
    
    log_info "Checking for existing security group: $SECURITY_GROUP_NAME"
    
    # Try to get existing security group
    SG_ID=$(security_group_exists "$SECURITY_GROUP_NAME" "$REGION")
    
    if [ -n "$SG_ID" ]; then
        log_info "Using existing security group: $SG_ID"
        return 0
    fi
    
    log_info "Creating new security group..."
    
    # Get the default VPC ID
    local vpc_id=$(get_default_vpc_id)
    
    # Create security group
    SG_ID=$(aws ec2 create-security-group \
        --group-name "$SECURITY_GROUP_NAME" \
        --description "$SECURITY_GROUP_DESC" \
        --vpc-id "$vpc_id" \
        --region "$REGION" \
        --query 'GroupId' \
        --output text)
    
    # Tag the security group
    aws ec2 create-tags \
        --resources "$SG_ID" \
        --tags "Key=$PROJECT_TAG_KEY,Value=$PROJECT_TAG" \
               "Key=Name,Value=$SECURITY_GROUP_NAME" \
        --region "$REGION"
    
    # Add SSH rule (port 22)
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port "$SSH_PORT" \
        --cidr "$SSH_CIDR" \
        --region "$REGION"
    
    # Add HTTP rule (port 80)
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port "$HTTP_PORT" \
        --cidr "$HTTP_CIDR" \
        --region "$REGION"
    
    log_success "Security group created: $SG_ID"
    track_resource "security_groups" "$SG_ID"
}

launch_ec2_instance() {
    log_info "Launching EC2 instance..."
    
    # Get the AMI ID for the current region
    local ami_id=$(get_ami_id "$REGION")
    log_info "Using AMI: $ami_id"
    
    # Launch the instance
    local instance_info=$(aws ec2 run-instances \
        --image-id "$ami_id" \
        --instance-type "$TYPE" \
        --key-name "$KEY_NAME" \
        --security-group-ids "$SG_ID" \
        --tag-specifications \
            "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME_VAR},{Key=$PROJECT_TAG_KEY,Value=$PROJECT_TAG},{Key=Environment,Value=$ENVIRONMENT_TAG}]" \
        --region "$REGION" \
        --output json)
    
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log_error "Failed to launch EC2 instance"
        exit 1
    fi
    
    # Extract instance ID
    local instance_id=$(echo "$instance_info" | jq -r '.Instances[0].InstanceId')
    
    if [ -z "$instance_id" ] || [ "$instance_id" == "null" ]; then
        log_error "Failed to extract instance ID from response"
        exit 1
    fi
    
    log_success "Instance launched: $instance_id"
    
    # Track for cleanup
    track_resource "instances" "$instance_id"
    
    echo "$instance_id"
}

wait_and_get_public_ip() {
    local instance_id="$1"
    
    # Wait for instance to be running
    wait_for_instance_running "$instance_id" "$REGION"
    
    # Get the public IP address
    local public_ip=$(get_instance_public_ip "$instance_id" "$REGION")
    
    # Sometimes public IP takes a moment to be assigned
    local retries=10
    while [ "$public_ip" == "None" ] || [ -z "$public_ip" ]; do
        if [ $retries -le 0 ]; then
            log_warning "Could not retrieve public IP. Instance may not have a public IP assigned."
            public_ip="N/A"
            break
        fi
        log_info "Waiting for public IP assignment..."
        sleep 5
        public_ip=$(get_instance_public_ip "$instance_id" "$REGION")
        ((retries--))
    done
    
    echo "$public_ip"
}

display_instance_info() {
    local instance_id="$1"
    local public_ip="$2"
    
    print_separator
    echo -e "${GREEN}EC2 Instance Created Successfully${NC}"
    print_separator
    
    # Get detailed instance info
    local instance_info=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$REGION" \
        --output json)
    
    echo ""
    echo "Instance Details:"
    echo "  Instance ID:     $instance_id"
    echo "  Instance Name:   $INSTANCE_NAME_VAR"
    echo "  Instance Type:   $(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].InstanceType')"
    echo "  AMI ID:          $(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].ImageId')"
    echo "  State:           $(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].State.Name')"
    echo "  Public IP:       $public_ip"
    echo "  Private IP:      $(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].PrivateIpAddress')"
    echo "  Security Group:  $SG_ID"
    echo "  Key Pair:        $KEY_NAME"
    echo "  Availability Zone: $(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].Placement.AvailabilityZone')"
    echo ""
    echo "Tags:"
    echo "$instance_info" | jq -r '.Reservations[0].Instances[0].Tags[] | "  - \(.Key): \(.Value)"'
    echo ""
    
    if [ -f "$KEY_FILE" ]; then
        echo "SSH Connection:"
        echo "  ssh -i \"$KEY_FILE\" ec2-user@$public_ip"
    fi
    
    print_separator
}


main() {
    parse_args "$@"
    
    log_info "=========================================="
    log_info "AWS EC2 Instance Creation Script"
    log_info "=========================================="
    
    # Check AWS environment
    check_aws_environment
    
    # Override region if set
    export AWS_DEFAULT_REGION="$REGION"
    
    log_info "Configuration:"
    log_info "  Instance Name: $INSTANCE_NAME_VAR"
    log_info "  Instance Type: $TYPE"
    log_info "  Key Pair: $KEY_NAME"
    log_info "  Region: $REGION"
    
    # Create key pair
    create_key_pair
    
    # Get or create security group
    get_or_create_security_group
    
    # Launch EC2 instance
    INSTANCE_ID=$(launch_ec2_instance)
    
    # Wait for instance and get public IP
    PUBLIC_IP=$(wait_and_get_public_ip "$INSTANCE_ID")
    
    # Display instance information
    display_instance_info "$INSTANCE_ID" "$PUBLIC_IP"
    
    log_success "EC2 instance setup complete!"
    
    # Export for use by other scripts
    echo ""
    echo "To use this instance in other scripts, export:"
    echo "  export INSTANCE_ID=$INSTANCE_ID"
    echo "  export PUBLIC_IP=$PUBLIC_IP"
}

# Run main function
main "$@"
