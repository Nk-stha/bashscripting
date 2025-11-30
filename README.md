# AWS EC2 Information Gatherer for Terraform

## Overview
This production-ready bash script gathers all necessary AWS EC2 information for Terraform configuration, including:
- ✅ AMI (OS Image) details (Amazon Linux, Ubuntu, etc.)
- ✅ Available instance types in your selected region
- ✅ VPC details
- ✅ Public and Private subnet listings
- ✅ Security Groups (Firewalls) with inbound/outbound rules
- ✅ SSH Key Pairs
- ✅ Sample Terraform configuration

## Prerequisites

### Required Tools
1. **AWS CLI** - Install from https://aws.amazon.com/cli/
   ```bash
   # Verify installation
   aws --version
   ```

2. **jq** - JSON processor
   ```bash
   # Ubuntu/Debian
   sudo apt-get install jq
   
   # RHEL/CentOS/Amazon Linux
   sudo yum install jq
   
   # macOS
   brew install jq
   ```

3. **AWS Credentials** - Configure your AWS credentials
   ```bash
   aws configure
   ```
   You'll need:
   - AWS Access Key ID
   - AWS Secret Access Key
   - Default region (can be changed during script execution)

## Usage

### Basic Usage
```bash
./aws-ec2-info-gatherer.sh
```

### What Happens When You Run It

1. **Prerequisites Check**
   - Verifies AWS CLI is installed
   - Checks for jq installation
   - Validates AWS credentials
   - Displays your AWS account information

2. **Region Selection**
   - Lists all available AWS regions
   - Prompts you to select a region (by number or name)
   - Example: Enter `1` or `us-east-1`

3. **Information Gathering**
   The script will automatically gather:
   - Latest AMIs for popular OS (Amazon Linux, Ubuntu)
   - All available instance types with specifications
   - VPC details with CIDR blocks
   - Subnets categorized as Public/Private
   - Security groups with detailed firewall rules
   - SSH key pairs available in the region

4. **Output Generation**
   - Creates a detailed markdown file: `aws-ec2-details-YYYYMMDD-HHMMSS.md`
   - Creates a log file: `aws-ec2-info-YYYYMMDD-HHMMSS.log`
   - Generates sample Terraform configuration

## Output Files

### Main Output File (Markdown)
The script creates a **professional markdown file** with rich formatting:
```
aws-ec2-details-YYYYMMDD-HHMMSS.md
```

This file includes:
- **📋 Document Metadata**: Generation timestamp, AWS account, IAM user, region
- **📑 Table of Contents**: Easy navigation with clickable links
- **💿 AMI Details**: Latest images with IDs, names, and creation dates (with emojis)
- **⚡ Instance Types**: Organized by family with vCPU, memory, storage specs
- **🌐 VPC Information**: Complete VPC details with CIDR blocks
- **🔌 Subnets**: Separated into 🌍 public and 🔒 private with availability zones
- **🛡️ Security Groups**: Inbound and outbound rules in formatted tables
- **🔑 SSH Key Pairs**: Available key pairs for instance access
- **📦 Terraform Example**: Ready-to-use Terraform configuration template
- **📚 Quick Reference**: Guide on how to use the report with best practices

### Log File
```
aws-ec2-info-YYYYMMDD-HHMMSS.log
```
Contains execution logs for troubleshooting.

## Features

### Production-Ready Features
- ✅ **Error Handling**: Comprehensive error checking and validation
- ✅ **Logging**: Detailed logs for audit and troubleshooting
- ✅ **Color-coded Output**: Easy-to-read console output
- ✅ **Region Validation**: Ensures selected region is valid
- ✅ **Credential Verification**: Checks AWS credentials before execution
- ✅ **Formatted Output**: Clean, organized markdown output
- ✅ **Terraform Integration**: Includes ready-to-use Terraform examples

### Information Categories

#### 1. AMI Details
- Amazon Linux 2 (latest 5 versions)
- Ubuntu LTS (latest 5 versions)
- AMI IDs, names, creation dates, descriptions

#### 2. Instance Types
- All instance types available in the selected region
- Organized by instance family (t3, m5, c5, etc.)
- Specifications: vCPUs, memory, storage, network performance
- Architecture support (x86_64, arm64)

#### 3. VPC Information
- VPC IDs and names
- CIDR blocks
- Default VPC identification
- VPC state

#### 4. Subnet Details
- **Public Subnets**: Auto-assign public IP enabled
- **Private Subnets**: No public IP assignment
- Availability zones
- Available IP addresses
- CIDR blocks
- Associated VPC

#### 5. Security Groups (Firewalls)
- Security group IDs and names
- Descriptions
- Associated VPC
- **Inbound Rules**: Protocol, ports, source
- **Outbound Rules**: Protocol, ports, destination

#### 6. SSH Key Pairs
- Key names
- Key pair IDs
- Fingerprints
- Key types (RSA, ED25519)

## Example Terraform Configuration

The script generates a production-ready Terraform configuration including:

```hcl
provider "aws" {
  region = "us-east-1"  # Your selected region
}

resource "aws_instance" "example" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  key_name               = var.key_name
  
  # Security best practices included:
  # - Encrypted root volume
  # - IMDSv2 enabled
  # - Detailed monitoring
  # - Proper tagging
}
```

## Using the Output with Terraform

1. **Run the script** to gather information
   ```bash
   ./aws-ec2-info-gatherer.sh
   ```

2. **Review the output file** to find:
   - AMI ID for your preferred OS
   - Instance type that fits your needs
   - Subnet ID (public or private)
   - Security group IDs
   - SSH key pair name

3. **Copy the Terraform example** from the output file

4. **Replace the variable values** with actual IDs from the gathered information

5. **Run Terraform commands**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

## Troubleshooting

### AWS CLI Not Found
```bash
# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### jq Not Found
```bash
# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y jq

# Amazon Linux/RHEL
sudo yum install -y jq
```

### AWS Credentials Not Configured
```bash
aws configure
# Enter your Access Key ID, Secret Access Key, and default region
```

### Permission Denied
```bash
chmod +x aws-ec2-info-gatherer.sh
```

## Advanced Usage

### Filtering Output
You can use tools like `grep` to filter the output file:
```bash
# Find all t3 instance types
grep "t3\." aws-ec2-details-*.txt

# Find public subnets
grep -A 5 "Public Subnets" aws-ec2-details-*.txt
```

### Multiple Regions
Run the script multiple times with different regions to compare:
```bash
# Run for us-east-1
./aws-ec2-info-gatherer.sh
# Select region: us-east-1

# Run for eu-west-1
./aws-ec2-info-gatherer.sh
# Select region: eu-west-1
```

## Security Considerations

- The script uses **read-only AWS API calls** - it doesn't modify any resources
- AWS credentials are validated but never logged or displayed
- Output files may contain sensitive information - handle appropriately
- Consider adding output files to `.gitignore` if using version control

## Best Practices

1. **Review Before Using**: Always review the gathered information before using it in Terraform
2. **Keep Updated**: Run the script regularly as AWS adds new instance types and AMIs
3. **Document Choices**: Use the output file to document why you chose specific resources
4. **Version Control**: Save output files for auditing and compliance
5. **Test First**: Use the information in a test environment before production

## Support

For issues or questions:
- Check the log file for detailed error messages
- Verify AWS CLI and jq are properly installed
- Ensure AWS credentials have appropriate permissions (ec2:Describe*, sts:GetCallerIdentity)

## License

This script is provided as-is for DevOps and infrastructure automation purposes.
