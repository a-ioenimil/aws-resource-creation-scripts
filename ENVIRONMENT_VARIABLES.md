# Environment Variables Reference

This document describes all environment variables used in the AWS Resource Creation Scripts project.

## 🔧 Configuration Files

- **`.env`**: Your local configuration (gitignored, not tracked)
- **`.env.example`**: Template with all available variables (tracked in git)
- **`config/config.sh`**: Automatically sources `.env` if it exists

## 📝 Variable Descriptions

### AWS Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `AWS_REGION` | `us-east-1` | AWS region where resources will be created |
| `AWS_PROFILE` | _(not set)_ | AWS CLI profile to use (optional, for multiple accounts) |
| `AMI_ID` | _(auto-detect)_ | Specific AMI ID to use for EC2 instances. If not set, the latest Amazon Linux AMI is automatically detected |

### Project Identification

| Variable | Default | Description |
|----------|---------|-------------|
| `PROJECT_TAG` | `AutomationLab` | Value for the Project tag applied to all resources. Used for filtering during cleanup |
| `PROJECT_TAG_KEY` | `Project` | The tag key used for project identification |
| `ENVIRONMENT_TAG` | `dev` | Environment identifier (dev/staging/production/etc.) |

### EC2 Instance Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `INSTANCE_TYPE` | `t2.micro` | EC2 instance type (Free Tier eligible) |
| `INSTANCE_NAME` | `AutomationLab-Instance` | Name tag applied to EC2 instances |
| `KEY_PAIR_NAME` | `automation-lab-keypair` | Name for the SSH key pair |
| `KEY_PAIR_FILE` | `./automation-lab-keypair.pem` | Local path to store the private key file |

### Security Group Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `SECURITY_GROUP_NAME` | `devops-sg` | Name for the security group |
| `SECURITY_GROUP_DESC` | `DevOps Security Group for AutomationLab` | Description for the security group |
| `SSH_PORT` | `22` | Port for SSH access |
| `SSH_CIDR` | `0.0.0.0/0` | CIDR block allowed for SSH (⚠️ restrict in production!) |
| `HTTP_PORT` | `80` | Port for HTTP access |
| `HTTP_CIDR` | `0.0.0.0/0` | CIDR block allowed for HTTP (⚠️ restrict in production!) |

### S3 Bucket Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `S3_BUCKET_PREFIX` | `automation-lab` | Prefix for S3 bucket names. A timestamp and random suffix are automatically appended for uniqueness |
| `S3_SAMPLE_FILE` | `welcome.txt` | Filename for the sample file uploaded to new buckets |
| `S3_SAMPLE_CONTENT` | `Welcome to AWS S3!...` | Content written to the sample file |

### Resource Tracking

| Variable | Default | Description |
|----------|---------|-------------|
| `RESOURCE_TRACKING_FILE` | `./created_resources.json` | JSON file that tracks all created resource IDs for cleanup |

## 🚀 Usage Examples

### Basic Setup

```bash
# 1. Copy the example file
cp .env.example .env

# 2. Edit with your preferences
nano .env

# 3. Run the automation
./bin/aws-automator interactive
```

### Custom Region

```bash
# In .env
AWS_REGION=eu-west-1
```

### Production Environment

```bash
# In .env
ENVIRONMENT_TAG=production
PROJECT_TAG=ProductionApp
INSTANCE_TYPE=t3.medium

# Restrict SSH access to your office IP
SSH_CIDR=203.0.113.0/24
HTTP_CIDR=0.0.0.0/0
```

### Multiple AWS Profiles

```bash
# In .env
AWS_PROFILE=my-company-dev
AWS_REGION=ap-southeast-1
```

### Override Specific AMI

```bash
# In .env
AMI_ID=ami-0abcdef1234567890
```

## 🔒 Security Best Practices

### Do's ✅

- **Always** use `.env.example` as your template
- **Keep** `.env` in `.gitignore` (already configured)
- **Restrict** `SSH_CIDR` to your IP or office network in production
- **Use** different `PROJECT_TAG` values for different environments
- **Rotate** AWS credentials regularly

### Don'ts ❌

- **Never** commit `.env` to version control
- **Never** use `0.0.0.0/0` for SSH in production environments
- **Never** hard-code credentials in `.env` (use AWS CLI configuration)
- **Never** share your `.env` file publicly

## 🔄 How It Works

### Loading Order

1. **Bash Scripts**: 
   ```bash
   # config/config.sh sources .env first
   source .env   # If exists
   
   # Then applies defaults
   export AWS_REGION="${AWS_REGION:-us-east-1}"
   ```

2. **Variable Resolution**:
   - `.env` value (highest priority)
   - Environment variable from shell
   - Default value in `config.sh`

3. **Example Flow**:
   ```bash
   # .env contains:
   AWS_REGION=eu-west-1
   
   # config.sh will use:
   export AWS_REGION="${AWS_REGION:-us-east-1}"
   # Result: AWS_REGION=eu-west-1 (from .env)
   ```

### File Locking

The `RESOURCE_TRACKING_FILE` uses file locking to prevent corruption:

```bash
# Bash writes with EXCLUSIVE lock
flock -x 200

# Go reads with SHARED lock  
syscall.Flock(fd, syscall.LOCK_SH)
```

## 🧪 Testing Your Configuration

### Verify Environment Loading

```bash
# Source the config
source config/config.sh

# Check variables
echo "Region: $AWS_REGION"
echo "Project: $PROJECT_TAG"
echo "Instance Type: $INSTANCE_TYPE"
```

### Validate AWS Credentials

```bash
# Check identity
aws sts get-caller-identity

# Check region
aws configure get region
```

### Dry Run

```bash
# Test cleanup without deleting
./scripts/cleanup_resources.sh --dry-run
```

## 📚 Related Files

- [`.env.example`](.env.example) - Template file (track in git)
- [`.env`](.env) - Your local config (gitignored)
- [`config/config.sh`](config/config.sh) - Loads .env and defines defaults
- [`.gitignore`](.gitignore) - Ensures .env is not committed
- [`README.md`](README.md) - Main project documentation

## 🆘 Troubleshooting

### Variables Not Loading

```bash
# Check if .env exists
ls -la .env

# Verify config.sh can find it
grep "ENV_FILE" config/config.sh

# Manually source and test
source .env
echo $AWS_REGION
```

### Permission Denied

```bash
# Make sure .env is readable
chmod 644 .env
```

### Syntax Errors in .env

```bash
# .env should NOT have:
# - `export` keywords
# - Spaces around `=`
# - Quotes around values (unless needed)

# ✅ Correct:
AWS_REGION=us-east-1

# ❌ Wrong:
export AWS_REGION = "us-east-1"
```

---

**Last Updated**: January 13, 2026
