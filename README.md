# AWS Resource Creation Scripts

<video src="assets/videos/aws_resource_creation.mp4" controls autoplay loop muted></video>

Automated tools for creating and managing AWS resources including EC2 instances, Security Groups, and S3 buckets. This project provides both direct **Bash scripts** and a modern **Go CLI** wrapper for a better user experience.

## Project Overview

This project provides a comprehensive suite of tools to automate the provisioning of AWS infrastructure. You can choose between running raw Bash scripts for direct control or using our interactive CLI tool (`aws-automator`) for a more guided, user-friendly experience.

### Features

- **Interactive CLI Tool**: A Go-based menu system to guide you through creation and cleanup
- **Plan Mode (Dry Run)**: Preview resources before creation with Terraform-style output (`+` create, `~` modify, `-` delete)
- **Remote State Backend**: Optional S3-based state syncing for team collaboration
- **EC2 Instance Creation**: Automated key pair generation, instance launch with Amazon Linux 2 AMI, and tagging
- **Security Group Management**: Create security groups with SSH (port 22) and HTTP (port 80) access rules
- **S3 Bucket Setup**: Create uniquely-named buckets with versioning enabled and sample file upload
- **Resource Cleanup**: Safely terminate all created resources using tag-based filtering
- **Error Handling**: Robust error handling and logging throughout all scripts
- **Idempotency**: Scripts check for existing resources before creation
- **Auto-installation**: AWS CLI is automatically installed if not present

## Project Structure

```
aws-resource-creation-scripts/
├── README.md                           # This file
├── Makefile                            # Build automation
├── go.mod                              # Go module definition
├── cmd/
│   └── aws-automator/
│       └── main.go                     # Go CLI entry point
├── config/
│   └── config.sh                       # Centralized configuration variables
├── lib/
│   └── utils.sh                        # Shared utility functions
├── scripts/
│   ├── create_security_group.sh        # Security group creation
│   ├── create_ec2.sh                   # EC2 instance creation
│   ├── create_s3_bucket.sh             # S3 bucket creation
│   ├── cleanup_resources.sh            # Resource cleanup
│   └── init_state.sh                   # Initialize S3 state backend
├── keys/                               # Generated EC2 key pairs (gitignored)
├── bin/                                # Compiled binaries (gitignored)
└── files/                              # Sample files for S3 upload
```

## Prerequisites

### 1. Environment Configuration

Copy the example environment file and customize it:

```bash
cp .env.example .env
```

Edit `.env` to configure your settings:

```bash
# AWS Configuration
AWS_REGION=us-east-1                    # Your preferred AWS region

# Project Configuration
PROJECT_TAG=AutomationLab               # Tag to identify your resources
ENVIRONMENT_TAG=dev                     # Environment name (dev/staging/prod)

# EC2 Configuration
INSTANCE_TYPE=t3.micro                  # EC2 instance type (t3.micro recommended)
INSTANCE_NAME=AutomationLab-Instance    # Default instance name

# Security Group Configuration
SECURITY_GROUP_NAME=devops-sg           # Security group name
SSH_CIDR=0.0.0.0/0                     # SSH access (restrict in production!)
HTTP_CIDR=0.0.0.0/0                    # HTTP access

# S3 Configuration
S3_BUCKET_PREFIX=automation-lab         # Bucket name prefix

# Remote State Backend (Optional)
# Leave S3_STATE_BUCKET empty to use local-only state
S3_STATE_BUCKET=                        # S3 bucket for remote state
S3_STATE_KEY=state/created_resources.json
S3_STATE_REGION=${AWS_REGION}
```

**Important**: The `.env` file is gitignored to protect your configuration. Always use `.env.example` as a template.

### 2. Install Go (Optional - for CLI Tool)

If you want to use the interactive Go CLI tool, you need to have Go installed (version 1.16+).

**Linux/macOS:**
```bash
# Verify installation
go version
```

### 2. Install AWS CLI (Optional - Auto-installed)

The scripts will automatically install AWS CLI if it's not present. However, you can install it manually:

**Linux (Debian/Ubuntu):**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

**macOS:**
```bash
brew install awscli
```

**Verify installation:**
```bash
aws --version
```

### 3. Configure AWS Credentials

Run the AWS configure command:
```bash
aws configure
```

Enter your credentials when prompted:
- AWS Access Key ID
- AWS Secret Access Key
- Default region (e.g., `us-east-1`)
- Default output format (e.g., `json`)

### 4. Verify AWS Setup

```bash
# Check credentials
aws sts get-caller-identity

# Check configuration
aws configure list
```

### 5. Required IAM Permissions

Your IAM user/role needs the following permissions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:RunInstances",
                "ec2:DescribeInstances",
                "ec2:TerminateInstances",
                "ec2:CreateKeyPair",
                "ec2:DeleteKeyPair",
                "ec2:DescribeKeyPairs",
                "ec2:CreateSecurityGroup",
                "ec2:DeleteSecurityGroup",
                "ec2:DescribeSecurityGroups",
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress",
                "ec2:CreateTags",
                "ec2:DescribeVpcs",
                "ec2:DescribeImages",
                "s3:CreateBucket",
                "s3:DeleteBucket",
                "s3:PutObject",
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:ListBucket",
                "s3:PutBucketVersioning",
                "s3:GetBucketVersioning",
                "s3:PutBucketPolicy",
                "s3:PutBucketTagging",
                "s3:GetBucketTagging",
                "s3:ListAllMyBuckets",
                "s3:ListObjectVersions",
                "sts:GetCallerIdentity"
            ],
            "Resource": "*"
        }
    ]
}
```

### 6. Additional Dependencies

- **jq**: JSON processor for parsing AWS CLI output
  ```bash
  # Ubuntu/Debian
  sudo apt-get install jq
  
  # macOS
  brew install jq
  ```

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/a-ioenimil/aws-resource-creation-scripts.git
cd aws-resource-creation-scripts
```

### Option 1: Using the Go CLI (Recommended)

The Go CLI provides an interactive menu and status tracking.

**1. Build the tool:**
```bash
make build
```

**2. Preview Changes (Dry Run):**
```bash
# See what resources would be created
./bin/aws-automator plan -r all
```

**Output Example:**
```text
[PLAN] + Would create Security Group: devops-sg
[PLAN] + Would launch EC2 Instance:
[PLAN]   -> Type: t3.micro
[PLAN]   -> AMI: ami-0abcdef1234567890
```

**3. Run in Interactive Mode:**
```bash
./bin/aws-automator interactive
```

**4. Run in Auto Mode (One-click setup):**
```bash
./bin/aws-automator auto
```

### Option 2: Using Bash Scripts

If you prefer running individual scripts directly:

**1. Make Scripts Executable**

```bash
chmod +x scripts/*.sh
```

**2. Run Scripts in Order**

```bash
# Step 1: Create Security Group (opens SSH and HTTP ports)
./scripts/create_security_group.sh

# Step 2: Create EC2 Instance (uses security group from step 1)
./scripts/create_ec2.sh

# Step 3: Create S3 Bucket with versioning
./scripts/create_s3_bucket.sh
```

### 3. Clean Up Resources (when done)

```bash
# Preview what will be deleted
./scripts/cleanup_resources.sh --dry-run

# Actually delete resources
./scripts/cleanup_resources.sh --force
```

## Tool Details

### Go CLI Tool (`aws-automator`)

This tool wraps the bash scripts in a convenient interface. It maintains a state file `created_resources.json` to track and display the status of resources.

*   **Interactive Mode**: `aws-automator interactive` - Select actions from a menu.
*   **Auto Creation**: `aws-automator auto` - Runs creation scripts in the correct order with dependency handling.
*   **Plan Mode**: `aws-automator plan -r all` - Simulates execution and shows proposed changes (Dry Run).
*   **Status View**: `aws-automator status` - Shows a table of created instances, SGs, keys, and buckets.
*   **Safe Cleanup**: `aws-automator cleanup` - Prompts for confirmation before deleting tracked resources.
*   **State Management**: `aws-automator state` - Manage remote S3 state backend.

### Remote State Backend

For team collaboration, you can store the state file in S3:

**1. Initialize a state bucket:**
```bash
./bin/aws-automator state init --bucket my-state-bucket
```

**2. Configure your `.env`:**
```bash
S3_STATE_BUCKET=my-state-bucket
```

**3. Sync state manually (if needed):**
```bash
./bin/aws-automator state pull   # Download from S3
./bin/aws-automator state push   # Upload to S3
./bin/aws-automator state show   # Show configuration
```

Once configured, state automatically syncs on every resource change.

### Bash Scripts

### `create_security_group.sh`

Creates a security group with SSH (port 22) and HTTP (port 80) access.

**Usage:**
```bash
./scripts/create_security_group.sh [options]
```

**Options:**
| Option | Description | Default |
|--------|-------------|---------|
| `-n, --name` | Security group name | `devops-sg` |
| `-r, --region` | AWS region | `us-east-1` |
| `-d, --dry-run` | Simulate without creating | - |
| `-h, --help` | Show help | - |

**Example:**
```bash
./scripts/create_security_group.sh --name my-custom-sg --region us-west-2
```

**Output:**
- Security Group ID
- Inbound rules configured
- Tags applied

---

### `create_ec2.sh`

Creates an EC2 instance with key pair generation and tagging.

**Usage:**
```bash
./scripts/create_ec2.sh [options]
```

**Options:**
| Option | Description | Default |
|--------|-------------|---------|
| `-n, --name` | Instance name | `AutomationLab-Instance` |
| `-k, --key-name` | Key pair name | `automation-lab-keypair` |
| `-t, --type` | Instance type | `t2.micro` |
| `-s, --security-group` | Security group ID | Auto-creates if not provided |
| `-r, --region` | AWS region | `us-east-1` |
| `-h, --help` | Show help | - |

**Example:**
```bash
./scripts/create_ec2.sh --name MyWebServer --type t2.small
```

**Output:**
- Instance ID
- Public IP address
- Private IP address
- SSH connection command

---

### `create_s3_bucket.sh`

Creates an S3 bucket with versioning and uploads a sample file.

**Usage:**
```bash
./scripts/create_s3_bucket.sh [options]
```

**Options:**
| Option | Description | Default |
|--------|-------------|---------|
| `-n, --name` | Bucket name prefix | `automation-lab` |
| `-r, --region` | AWS region | `us-east-1` |
| `-f, --file` | File to upload | Creates `welcome.txt` |
| `-h, --help` | Show help | - |

**Example:**
```bash
./scripts/create_s3_bucket.sh --name my-project --region us-east-1
```

**Output:**
- Unique bucket name
- Versioning status
- Uploaded file list
- Access URLs

---

### `cleanup_resources.sh`

Safely terminates all resources created by the scripts.

**Usage:**
```bash
./scripts/cleanup_resources.sh [options]
```

**Options:**
| Option | Description | Default |
|--------|-------------|---------|
| `-r, --region` | AWS region | `us-east-1` |
| `-t, --tag` | Project tag value to filter | `AutomationLab` |
| `-f, --force` | Skip confirmation prompt | `false` |
| `-d, --dry-run` | Preview without deleting | `false` |
| `-h, --help` | Show help | - |

**Example:**
```bash
# Preview resources to be deleted
./scripts/cleanup_resources.sh --dry-run

# Delete all resources without confirmation
./scripts/cleanup_resources.sh --force
```

## Security & Reliability

### State Management & Locking
This tool uses a local JSON file (`created_resources.json`) to track created resources for easier cleanup. To prevent data corruption from concurrent executions, we have implemented:

1.  **File Locking (`flock`)**:
    *   **Exclusive Locks**: Write operations acquire an exclusive lock, preventing race conditions if multiple scripts run simultaneously.
    *   **Shared Locks**: Read operations (like `aws-automator status`) acquire a shared lock, ensuring they don't read partial data during a write.
2.  **Atomic Writes**: Updates are written to a temporary file first, then atomically moved to the final state file.
3.  **Automatic Backups**: Before any modification, a backup (`created_resources.json.backup`) is created.
4.  **Integrity Checks**: The system validates the JSON structure before loading to prevent crashing on corrupted data.

### ⚙️ Configuration

All default values can be modified in `config/config.sh`:

```bash
# AWS Region
export AWS_REGION="us-east-1"

# Project tagging
export PROJECT_TAG="AutomationLab"
export PROJECT_TAG_KEY="Project"
export ENVIRONMENT_TAG="dev"

# EC2 settings
export KEY_PAIR_NAME="automation-lab-keypair"
export INSTANCE_TYPE="t2.micro"
export INSTANCE_NAME="AutomationLab-Instance"

# Security Group settings
export SECURITY_GROUP_NAME="devops-sg"
export SSH_CIDR="0.0.0.0/0"    # Public access
export SSH_PORT="22"
export HTTP_PORT="80"

# S3 settings
export S3_BUCKET_PREFIX="automation-lab"
```

## Resource Tagging

All resources are tagged with:
- `Project=AutomationLab` - Used for resource identification and cleanup
- `Environment=dev` - Environment designation
- `Name=<resource-name>` - Human-readable name

## Security Considerations

1. **SSH Access**: By default, SSH (port 22) is open to `0.0.0.0/0` (public). For production environments, restrict to specific IP ranges by modifying `SSH_CIDR` in `config/config.sh`.

2. **Key Pair Storage**: The `.pem` key files are stored in the `keys/` directory. These are sensitive and should be:
   - Kept secure (chmod 400)
   - Never committed to version control
   - Backed up securely

3. **S3 Bucket Policy**: The default bucket policy allows full access from the creating AWS account.

4. **IAM Best Practices**: Use IAM roles with least privilege. Consider using AWS Organizations SCPs for additional guardrails.

## Troubleshooting

### Common Issues

**1. AWS CLI not configured:**
```
[ERROR] AWS credentials are not configured or invalid.
```
**Solution:** Run `aws configure` and enter valid credentials.

**2. No default VPC:**
```
[ERROR] No default VPC found in region us-east-1
```
**Solution:** Create a default VPC or specify a VPC ID manually.

**3. Permission denied:**
```
An error occurred (UnauthorizedOperation) when calling...
```
**Solution:** Ensure your IAM user has the required permissions listed above.

**4. AMI not found:**
```
[ERROR] Failed to launch EC2 instance
```
**Solution:** The AMI ID varies by region. The script auto-detects the latest Amazon Linux 2 AMI, but you can specify one manually with the `AMI_ID` environment variable.

**5. Bucket name already exists:**
```
BucketAlreadyExists
```
**Solution:** S3 bucket names are globally unique. The script generates unique names, but if you specify a name manually, ensure it's unique.

## Challenges and Resolutions

| Challenge | Resolution |
|-----------|------------|
| AMI IDs vary by region | Implemented dynamic AMI lookup using `describe-images` |
| S3 `LocationConstraint` required for non-us-east-1 | Added conditional logic to handle us-east-1 differently |
| Resources left orphaned after script failures | Added resource tracking in JSON file and tag-based cleanup |
| Security group deletion fails when in use | Added instance termination wait before SG deletion |
| Key pair private key only shown once | Immediate save to file with proper permissions |
| AWS CLI may not be installed | Added automatic installation for Linux and macOS |

## Authors

- **Isaac Obo Enimil** 