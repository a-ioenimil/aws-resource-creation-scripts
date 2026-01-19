#!/bin/bash

set -e
set -o pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source utility functions and configuration
source "$PROJECT_ROOT/lib/utils.sh"
source "$PROJECT_ROOT/config/config.sh"


SG_NAME="$SECURITY_GROUP_NAME"
SG_DESC="$SECURITY_GROUP_DESC"
REGION="$AWS_REGION"
DRY_RUN=false


show_help() {
    head -30 "$0" | grep -E "^#" | sed 's/^# //' | sed 's/^#//'
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                SG_NAME="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
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

create_security_group() {
    log_info "Creating security group: $SG_NAME"
    
    # Check if security group already exists
    local existing_sg=$(security_group_exists "$SG_NAME" "$REGION")
    if [ -n "$existing_sg" ]; then
        log_warning "Security group '$SG_NAME' already exists with ID: $existing_sg"
        log_info "Using existing security group"
        echo "$existing_sg"
        return 0
    fi
    
    # Get the default VPC ID
    local vpc_id=$(get_default_vpc_id)
    if [ -z "$vpc_id" ]; then
        log_error "Could not find default VPC. Please specify a VPC ID."
        exit 1
    fi
    log_info "Using VPC: $vpc_id"
    
    # Check for Dry Run
    if [ "$DRY_RUN" = "true" ]; then
        log_plan_create "Would create Security Group '$SG_NAME' in VPC '$vpc_id'"
        log_plan "  -> Description: $SG_DESC"
        log_plan_modify "Would tag Security Group with:"
        log_plan "  -> $PROJECT_TAG_KEY=$PROJECT_TAG"
        log_plan "  -> Name=$SG_NAME"
        echo "sg-dry-run-placeholder"
        return 0
    fi

    # Create the security group
    local sg_id=$(aws ec2 create-security-group \
        --group-name "$SG_NAME" \
        --description "$SG_DESC" \
        --vpc-id "$vpc_id" \
        --region "$REGION" \
        --query 'GroupId' \
        --output text)
    
    if [ -z "$sg_id" ]; then
        log_error "Failed to create security group"
        exit 1
    fi
    
    log_success "Security group created: $sg_id"
    
    # Tag the security group
    log_info "Tagging security group..."
    aws ec2 create-tags \
        --resources "$sg_id" \
        --tags "Key=$PROJECT_TAG_KEY,Value=$PROJECT_TAG" \
               "Key=Name,Value=$SG_NAME" \
               "Key=Environment,Value=$ENVIRONMENT_TAG" \
        --region "$REGION"
    
    log_success "Security group tagged with $PROJECT_TAG_KEY=$PROJECT_TAG"
    
    echo "$sg_id"
}

add_ssh_rule() {
    local sg_id="$1"
    
    log_info "Adding SSH rule (port $SSH_PORT) from $SSH_CIDR..."
    
    if [ "$DRY_RUN" = "true" ]; then
        local log_sg_id="$sg_id"
        if [[ "$sg_id" == *"placeholder"* ]]; then log_sg_id="(known after creation)"; fi
        log_plan_create "Would add inbound rule to $log_sg_id: TCP 22 (SSH) from $SSH_CIDR"
        return 0
    fi

    # Check if rule already exists
    local existing_rule=$(aws ec2 describe-security-groups \
        --group-ids "$sg_id" \
        --region "$REGION" \
        --query "SecurityGroups[0].IpPermissions[?FromPort==\`$SSH_PORT\` && ToPort==\`$SSH_PORT\` && IpProtocol==\`tcp\`].IpRanges[?CidrIp==\`$SSH_CIDR\`]" \
        --output text 2>/dev/null)
    
    if [ -n "$existing_rule" ]; then
        log_warning "SSH rule already exists, skipping..."
        return 0
    fi
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port "$SSH_PORT" \
        --cidr "$SSH_CIDR" \
        --region "$REGION"
    
    log_success "SSH rule added successfully"
}

add_http_rule() {
    local sg_id="$1"
    
    log_info "Adding HTTP rule (port $HTTP_PORT) from $HTTP_CIDR..."
    
    if [ "$DRY_RUN" = "true" ]; then
        local log_sg_id="$sg_id"
        if [[ "$sg_id" == *"placeholder"* ]]; then log_sg_id="(known after creation)"; fi
        log_plan_create "Would add inbound rule to $log_sg_id: TCP 80 (HTTP) from $HTTP_CIDR"
        return 0
    fi

    # Check if rule already exists
    local existing_rule=$(aws ec2 describe-security-groups \
        --group-ids "$sg_id" \
        --region "$REGION" \
        --query "SecurityGroups[0].IpPermissions[?FromPort==\`$HTTP_PORT\` && ToPort==\`$HTTP_PORT\` && IpProtocol==\`tcp\`].IpRanges[?CidrIp==\`$HTTP_CIDR\`]" \
        --output text 2>/dev/null)
    
    if [ -n "$existing_rule" ]; then
        log_warning "HTTP rule already exists, skipping..."
        return 0
    fi
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port "$HTTP_PORT" \
        --cidr "$HTTP_CIDR" \
        --region "$REGION"
    
    log_success "HTTP rule added successfully"
}

display_security_group_info() {
    local sg_id="$1"
    
    if [ "$DRY_RUN" = "true" ]; then
        return 0
    fi

    print_separator
    echo -e "${GREEN}Security Group Created Successfully${NC}"
    print_separator
    
    # Get detailed security group info
    local sg_info=$(aws ec2 describe-security-groups \
        --group-ids "$sg_id" \
        --region "$REGION" \
        --output json)
    
    echo ""
    echo "Security Group Details:"
    echo "  ID:          $sg_id"
    echo "  Name:        $(echo "$sg_info" | jq -r '.SecurityGroups[0].GroupName')"
    echo "  Description: $(echo "$sg_info" | jq -r '.SecurityGroups[0].Description')"
    echo "  VPC ID:      $(echo "$sg_info" | jq -r '.SecurityGroups[0].VpcId')"
    echo ""
    echo "Inbound Rules:"
    echo "$sg_info" | jq -r '.SecurityGroups[0].IpPermissions[] | 
        "  - Protocol: \(.IpProtocol), Port: \(.FromPort)-\(.ToPort), Source: \(.IpRanges[].CidrIp // .Ipv6Ranges[].CidrIpv6 // "N/A")"'
    echo ""
    echo "Tags:"
    echo "$sg_info" | jq -r '.SecurityGroups[0].Tags[] | "  - \(.Key): \(.Value)"'
    
    print_separator
}


main() {
    parse_args "$@"
    
    log_info "=========================================="
    log_info "AWS Security Group Creation Script"
    log_info "=========================================="
    
    # Check AWS environment
    check_aws_environment
    
    # Override region if set
    export AWS_DEFAULT_REGION="$REGION"
    
    log_info "Configuration:"
    log_info "  Security Group Name: $SG_NAME"
    log_info "  Region: $REGION"
    log_info "  SSH Access: Port $SSH_PORT from $SSH_CIDR"
    log_info "  HTTP Access: Port $HTTP_PORT from $HTTP_CIDR"
    
    # Create security group
    SG_ID=$(create_security_group)
    
    # Add inbound rules
    add_ssh_rule "$SG_ID"
    add_http_rule "$SG_ID"
    
    # Track resource for cleanup
    track_resource "security_groups" "$SG_ID"
    
    # Display security group information
    display_security_group_info "$SG_ID"
    
    log_success "Security group setup complete!"
    
    # Export for use by other scripts
    echo ""
    echo "To use this security group in other scripts, export:"
    echo "  export SECURITY_GROUP_ID=$SG_ID"
}

# Run main function
main "$@"
