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
# State Backend Initialization Script
# =============================================================================
# This script creates an S3 bucket with versioning enabled to store the
# infrastructure state file. This allows state syncing across machines.
# =============================================================================

BUCKET_NAME=""
REGION="$AWS_REGION"

show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Initialize an S3 bucket for remote state storage"
    echo ""
    echo "Options:"
    echo "  -b, --bucket NAME    S3 bucket name (required)"
    echo "  -r, --region REGION  AWS region (default: $AWS_REGION)"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 --bucket my-terraform-state-bucket"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -b|--bucket)
                BUCKET_NAME="$2"
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

main() {
    parse_args "$@"
    
    log_info "=========================================="
    log_info "AWS State Backend Initialization"
    log_info "=========================================="
    
    # Check AWS environment
    check_aws_environment
    
    if [ -z "$BUCKET_NAME" ]; then
        log_error "Bucket name is required. Use -b or --bucket to specify."
        show_help
        exit 1
    fi
    
    log_info "Configuration:"
    log_info "  Bucket Name: $BUCKET_NAME"
    log_info "  Region: $REGION"
    
    # Initialize the state bucket
    init_state_bucket "$BUCKET_NAME" "$REGION"
    
    log_success "State backend initialization complete!"
}

# Run main function
main "$@"
