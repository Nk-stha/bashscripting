#!/bin/bash

################################################################################
# AWS EC2 Information Gatherer for Terraform Configuration
# Description: Production-ready script to gather all necessary AWS EC2 details
#              for Terraform configuration including AMIs, instance types,
#              VPCs, subnets, and security groups.
# Version: 1.0.0
################################################################################

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# Log file configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/aws-ec2-info-$(date +%Y%m%d-%H%M%S).log"
readonly OUTPUT_FILE="${SCRIPT_DIR}/aws-ec2-details-$(date +%Y%m%d-%H%M%S).md"

################################################################################
# Logging Functions
################################################################################

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_section() {
    echo -e "\n${BOLD}${CYAN}========================================${NC}" | tee -a "$LOG_FILE"
    echo -e "${BOLD}${CYAN}$1${NC}" | tee -a "$LOG_FILE"
    echo -e "${BOLD}${CYAN}========================================${NC}\n" | tee -a "$LOG_FILE"
}

################################################################################
# Validation Functions
################################################################################

check_prerequisites() {
    log_section "Checking Prerequisites"
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        log_info "Visit: https://aws.amazon.com/cli/"
        exit 1
    fi
    log_info "✓ AWS CLI is installed: $(aws --version)"
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it first."
        log_info "Install with: sudo apt-get install jq (Ubuntu/Debian) or sudo yum install jq (RHEL/CentOS)"
        exit 1
    fi
    log_info "✓ jq is installed: $(jq --version)"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured properly."
        log_info "Please run: aws configure"
        exit 1
    fi
    
    local caller_identity
    caller_identity=$(aws sts get-caller-identity)
    local account_id
    account_id=$(echo "$caller_identity" | jq -r '.Account')
    local user_arn
    user_arn=$(echo "$caller_identity" | jq -r '.Arn')
    
    log_info "✓ AWS Credentials configured"
    log_info "  Account ID: $account_id"
    log_info "  User ARN: $user_arn"
}

################################################################################
# Region Selection
################################################################################

select_region() {
    log_section "AWS Region Selection"
    
    echo -e "${BLUE}Enter AWS Region Name${NC}"
    echo -e "${YELLOW}Examples: us-east-1, us-west-2, ap-south-1, eu-west-1${NC}"
    echo -e "${YELLOW}(Type 'list' to see all available regions)${NC}"
    echo ""
    
    while true; do
        read -rp "Enter AWS Region: " region_input
        
        # Convert to lowercase for comparison
        region_input=$(echo "$region_input" | tr '[:upper:]' '[:lower:]' | xargs)
        
        # Check if user wants to see the list
        if [[ "$region_input" == "list" ]]; then
            echo ""
            echo -e "${CYAN}Available AWS Regions:${NC}"
            echo ""
            
            # Get and display all available regions (using us-east-1 as default, but returns all regions)
            local regions
            regions=$(aws ec2 describe-regions --region us-east-1 --query 'Regions[*].[RegionName]' --output text | sort)
            
            local i=1
            while read -r region_name; do
                printf "%2d) %s\n" "$i" "$region_name"
                ((i++))
            done <<< "$regions"
            
            echo ""
            continue
        fi
        
        # Validate region name
        if aws ec2 describe-regions --region us-east-1 --region-names "$region_input" &> /dev/null; then
            SELECTED_REGION="$region_input"
            log_info "✓ Valid region selected: $SELECTED_REGION"
            
            # Add region to metadata table
            echo "| **Selected Region** | \`$SELECTED_REGION\` |" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            
            # Add table of contents placeholder
            cat >> "$OUTPUT_FILE" << 'TOC_EOF'

## 📑 Table of Contents

1. [AMI (OS Images)](#-ami-application-and-os-images)
2. [Instance Types](#-instance-types)
3. [VPC Details](#-vpc-virtual-private-cloud)
4. [Subnets (Public & Private)](#-subnets)
5. [Security Groups](#-security-groups-firewalls)
6. [SSH Key Pairs](#-ssh-key-pairs)
7. [Terraform Configuration](#-terraform-configuration-example)

---

TOC_EOF
            break
        else
            log_error "Invalid region name: '$region_input'"
            echo -e "${YELLOW}Tip: Type 'list' to see all available regions${NC}"
            echo ""
        fi
    done
}

################################################################################
# AMI Information Gathering
################################################################################

get_ami_details() {
    log_section "Gathering AMI (OS Image) Details"
    
    cat >> "$OUTPUT_FILE" << 'AMI_HEADER'
## 💿 AMI (Application and OS Images)

> **Note:** These are the latest available AMIs in your selected region. AMI IDs are region-specific.

AMI_HEADER
    echo "" >> "$OUTPUT_FILE"
    
    # Popular AMI owners
    local ami_owners=("amazon" "099720109477" "679593333241")  # Amazon, Canonical (Ubuntu), AWS Marketplace
    
    log_info "Fetching popular AMIs..."
    
    echo "### Latest Operating System Images" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Amazon Linux 2
    echo "#### 🐧 Amazon Linux 2 AMIs" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "| AMI ID | AMI Name | Created Date | Description |" >> "$OUTPUT_FILE"
    echo "|:-------|:---------|:-------------|:------------|" >> "$OUTPUT_FILE"
    
    local al2_amis
    al2_amis=$(aws ec2 describe-images \
        --region "$SELECTED_REGION" \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
                  "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-5:] | reverse(@) | [].[ImageId,Name,CreationDate,Description]' \
        --output text)
    
    echo "$al2_amis" | while IFS=$'\t' read -r ami_id name creation_date description; do
        local short_name="${name:0:45}"
        [[ ${#name} -gt 45 ]] && short_name="${short_name}..."
        local short_desc="${description:0:35}"
        [[ ${#description} -gt 35 ]] && short_desc="${short_desc}..."
        echo "| \`$ami_id\` | $short_name | $creation_date | $short_desc |" >> "$OUTPUT_FILE"
    done
    echo "" >> "$OUTPUT_FILE"
    
    # Ubuntu AMIs
    echo "" >> "$OUTPUT_FILE"
    echo "#### 🟠 Ubuntu AMIs (LTS Releases)" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "| AMI ID | AMI Name | Created Date | Description |" >> "$OUTPUT_FILE"
    echo "|:-------|:---------|:-------------|:------------|" >> "$OUTPUT_FILE"
    
    local ubuntu_amis
    ubuntu_amis=$(aws ec2 describe-images \
        --region "$SELECTED_REGION" \
        --owners 099720109477 \
        --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-*-amd64-server-*" \
                  "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-5:] | reverse(@) | [].[ImageId,Name,CreationDate,Description]' \
        --output text)
    
    echo "$ubuntu_amis" | while IFS=$'\t' read -r ami_id name creation_date description; do
        local short_name="${name:0:45}"
        [[ ${#name} -gt 45 ]] && short_name="${short_name}..."
        local short_desc="${description:0:35}"
        [[ ${#description} -gt 35 ]] && short_desc="${short_desc}..."
        echo "| \`$ami_id\` | $short_name | $creation_date | $short_desc |" >> "$OUTPUT_FILE"
    done
    echo "" >> "$OUTPUT_FILE"
    
    log_info "✓ AMI details saved to output file"
}

################################################################################
# Instance Type Information
################################################################################

get_instance_types() {
    log_section "Gathering Available Instance Types"
    
    cat >> "$OUTPUT_FILE" << 'INSTANCE_HEADER'

---

## ⚡ Instance Types

> **Info:** This section lists all EC2 instance types available in your selected region with their specifications.

INSTANCE_HEADER
    echo "" >> "$OUTPUT_FILE"
    
    log_info "Fetching instance types (this may take a moment)..."
    
    # Get all instance types available in the region
    local instance_types
    instance_types=$(aws ec2 describe-instance-types \
        --region "$SELECTED_REGION" \
        --query 'InstanceTypes[].[InstanceType,VCpuInfo.DefaultVCpus,MemoryInfo.SizeInMiB,InstanceStorageInfo.TotalSizeInGB,NetworkInfo.NetworkPerformance,ProcessorInfo.SupportedArchitectures[0]]' \
        --output text | sort)
    
    # Group by instance family
    echo "### Instance Types by Family" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    local current_family=""
    while IFS=$'\t' read -r instance_type vcpus memory_mib storage network_perf arch; do
        local family="${instance_type%%.*}"
        
        if [[ "$family" != "$current_family" ]]; then
            current_family="$family"
            echo "" >> "$OUTPUT_FILE"
            echo "#### 📌 Instance Family: \`$family\`" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            echo "| Instance Type | vCPUs | Memory (GiB) | Storage | Network Performance | Architecture |" >> "$OUTPUT_FILE"
            echo "|:--------------|------:|-------------:|:--------|:--------------------|:-------------|" >> "$OUTPUT_FILE"
        fi
        
        local memory_gib=$((memory_mib / 1024))
        local storage_display="EBS Only"
        [[ -n "$storage" && "$storage" != "None" ]] && storage_display="${storage} GB"
        
        echo "| \`$instance_type\` | $vcpus | $memory_gib | $storage_display | $network_perf | \`$arch\` |" >> "$OUTPUT_FILE"
    done <<< "$instance_types"
    
    # Summary of instance families
    local families
    families=$(echo "$instance_types" | awk '{print $1}' | sed 's/\..*//' | sort -u)
    
    echo "" >> "$OUTPUT_FILE"
    echo "<details>" >> "$OUTPUT_FILE"
    echo "<summary><b>📈 Summary of Instance Families Available (Click to expand)</b></summary>" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    while read -r family; do
        local count
        count=$(echo "$instance_types" | grep "^$family\." | wc -l)
        echo "- **$family**: $count instance types available" >> "$OUTPUT_FILE"
    done <<< "$families"
    echo "" >> "$OUTPUT_FILE"
    echo "</details>" >> "$OUTPUT_FILE"
    
    log_info "✓ Instance type details saved to output file"
}

################################################################################
# VPC Information
################################################################################

get_vpc_details() {
    log_section "Gathering VPC Details"
    
    cat >> "$OUTPUT_FILE" << 'VPC_HEADER'

---

## 🌐 VPC (Virtual Private Cloud)

> **Info:** Virtual Private Clouds (VPCs) provide isolated network environments for your AWS resources.

VPC_HEADER
    echo "" >> "$OUTPUT_FILE"
    
    local vpcs
    vpcs=$(aws ec2 describe-vpcs \
        --region "$SELECTED_REGION" \
        --query 'Vpcs[].[VpcId,CidrBlock,IsDefault,State,Tags[?Key==`Name`].Value|[0]]' \
        --output text)
    
    if [[ -z "$vpcs" ]]; then
        log_warn "No VPCs found in region $SELECTED_REGION"
        echo "No VPCs found in this region." >> "$OUTPUT_FILE"
        return
    fi
    
    echo "### Available VPCs in Region" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "| VPC Name | VPC ID | CIDR Block | State | Default VPC |" >> "$OUTPUT_FILE"
    echo "|:---------|:-------|:-----------|:------|:------------|" >> "$OUTPUT_FILE"
    
    while IFS=$'\t' read -r vpc_id cidr is_default state name; do
        local vpc_name="${name:-Unnamed}"
        local default_marker="❌ No"
        [[ "$is_default" == "True" ]] && default_marker="✅ Yes"
        
        echo "| **$vpc_name** | \`$vpc_id\` | \`$cidr\` | $state | $default_marker |" >> "$OUTPUT_FILE"
        
        log_info "Processing VPC: $vpc_id ($vpc_name)"
    done <<< "$vpcs"
    
    log_info "✓ VPC details saved to output file"
}

################################################################################
# Subnet Information
################################################################################

get_subnet_details() {
    log_section "Gathering Subnet Details (Public & Private)"
    
    cat >> "$OUTPUT_FILE" << 'SUBNET_HEADER'

---

## 🔌 Subnets

> **Info:** Subnets are subdivisions of VPCs. Public subnets have internet access, private subnets do not.

SUBNET_HEADER
    echo "" >> "$OUTPUT_FILE"
    
    local subnets
    subnets=$(aws ec2 describe-subnets \
        --region "$SELECTED_REGION" \
        --query 'Subnets[].[SubnetId,VpcId,CidrBlock,AvailabilityZone,AvailableIpAddressCount,MapPublicIpOnLaunch,State,Tags[?Key==`Name`].Value|[0]]' \
        --output text)
    
    if [[ -z "$subnets" ]]; then
        log_warn "No subnets found in region $SELECTED_REGION"
        echo "No subnets found in this region." >> "$OUTPUT_FILE"
        return
    fi
    
    # Create subnet rows
    local public_subnets=""
    local private_subnets=""
    
    while IFS=$'\t' read -r subnet_id vpc_id cidr az available_ips map_public state name; do
        local subnet_name="${name:-Unnamed}"
        local subnet_row="| **$subnet_name** | \`$subnet_id\` | \`$vpc_id\` | \`$cidr\` | $az | $available_ips | $state |\n"
        
        if [[ "$map_public" == "True" ]]; then
            public_subnets+="$subnet_row"
        else
            private_subnets+="$subnet_row"
        fi
    done <<< "$subnets"
    
    # Write public subnets
    echo "" >> "$OUTPUT_FILE"
    echo "### 🌍 Public Subnets" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    if [[ -n "$public_subnets" ]]; then
        echo "| Subnet Name | Subnet ID | VPC ID | CIDR Block | Availability Zone | Available IPs | State |" >> "$OUTPUT_FILE"
        echo "|:------------|:----------|:-------|:-----------|:------------------|---------------:|:------|" >> "$OUTPUT_FILE"
        echo -e "$public_subnets" >> "$OUTPUT_FILE"
    else
        echo "No public subnets found." >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
    
    # Write private subnets
    echo "" >> "$OUTPUT_FILE"
    echo "### 🔒 Private Subnets" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    if [[ -n "$private_subnets" ]]; then
        echo "| Subnet Name | Subnet ID | VPC ID | CIDR Block | Availability Zone | Available IPs | State |" >> "$OUTPUT_FILE"
        echo "|:------------|:----------|:-------|:-----------|:------------------|---------------:|:------|" >> "$OUTPUT_FILE"
        echo -e "$private_subnets" >> "$OUTPUT_FILE"
    else
        echo "No private subnets found." >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
    
    log_info "✓ Subnet details saved to output file"
}

################################################################################
# Security Group (Firewall) Information
################################################################################

get_security_group_details() {
    log_section "Gathering Security Group (Firewall) Details"
    
    cat >> "$OUTPUT_FILE" << 'SG_HEADER'

---

## 🛡️ Security Groups (Firewalls)

> **Info:** Security groups act as virtual firewalls controlling inbound and outbound traffic to your instances.

SG_HEADER
    echo "" >> "$OUTPUT_FILE"
    
    local security_groups
    security_groups=$(aws ec2 describe-security-groups \
        --region "$SELECTED_REGION" \
        --query 'SecurityGroups[].[GroupId,GroupName,VpcId,Description]' \
        --output text)
    
    if [[ -z "$security_groups" ]]; then
        log_warn "No security groups found in region $SELECTED_REGION"
        echo "No security groups found in this region." >> "$OUTPUT_FILE"
        return
    fi
    
    while IFS=$'\t' read -r group_id group_name vpc_id description; do
        echo "#### 🔐 Security Group: \`$group_name\`" >> "$OUTPUT_FILE"
        echo "- **Group ID**: $group_id" >> "$OUTPUT_FILE"
        echo "- **Group Name**: $group_name" >> "$OUTPUT_FILE"
        echo "- **VPC ID**: $vpc_id" >> "$OUTPUT_FILE"
        echo "- **Description**: $description" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        
        # Get inbound rules
        echo "" >> "$OUTPUT_FILE"
        echo "**Inbound Rules:**" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        
        local inbound_rules
        inbound_rules=$(aws ec2 describe-security-groups \
            --region "$SELECTED_REGION" \
            --group-ids "$group_id" \
            --query 'SecurityGroups[0].IpPermissions[].[IpProtocol,FromPort,ToPort,IpRanges[0].CidrIp,Ipv6Ranges[0].CidrIpv6,UserIdGroupPairs[0].GroupId]' \
            --output text 2>/dev/null)
        
        if [[ -n "$inbound_rules" ]]; then
            echo "| Protocol | Port Range | Source CIDR/SG | Description |" >> "$OUTPUT_FILE"
            echo "|:---------|:-----------|:---------------|:------------|" >> "$OUTPUT_FILE"
            
            while IFS=$'\t' read -r protocol from_port to_port ipv4_cidr ipv6_cidr source_sg; do
                local port_range="All"
                [[ -n "$from_port" ]] && port_range="$from_port"
                [[ -n "$to_port" && "$to_port" != "$from_port" ]] && port_range="$from_port-$to_port"
                
                local source="${ipv4_cidr:-${ipv6_cidr:-${source_sg:-N/A}}}"
                local source_type="Custom"
                [[ "$source" == "0.0.0.0/0" ]] && source_type="🌐 Anywhere (IPv4)"
                [[ "$source" == "::/0" ]] && source_type="🌐 Anywhere (IPv6)"
                [[ "$source" =~ ^sg- ]] && source_type="🔗 Security Group"
                
                echo "| \`$protocol\` | $port_range | \`$source\` | $source_type |" >> "$OUTPUT_FILE"
            done <<< "$inbound_rules"
        else
            echo "No inbound rules configured." >> "$OUTPUT_FILE"
        fi
        
        echo "" >> "$OUTPUT_FILE"
        
        # Get outbound rules
        echo "" >> "$OUTPUT_FILE"
        echo "**Outbound Rules:**" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        
        local outbound_rules
        outbound_rules=$(aws ec2 describe-security-groups \
            --region "$SELECTED_REGION" \
            --group-ids "$group_id" \
            --query 'SecurityGroups[0].IpPermissionsEgress[].[IpProtocol,FromPort,ToPort,IpRanges[0].CidrIp,Ipv6Ranges[0].CidrIpv6,UserIdGroupPairs[0].GroupId]' \
            --output text 2>/dev/null)
        
        if [[ -n "$outbound_rules" ]]; then
            echo "| Protocol | Port Range | Destination CIDR/SG | Description |" >> "$OUTPUT_FILE"
            echo "|:---------|:-----------|:--------------------|:------------|" >> "$OUTPUT_FILE"
            
            while IFS=$'\t' read -r protocol from_port to_port ipv4_cidr ipv6_cidr dest_sg; do
                local port_range="All"
                [[ -n "$from_port" ]] && port_range="$from_port"
                [[ -n "$to_port" && "$to_port" != "$from_port" ]] && port_range="$from_port-$to_port"
                
                local destination="${ipv4_cidr:-${ipv6_cidr:-${dest_sg:-N/A}}}"
                local dest_type="Custom"
                [[ "$destination" == "0.0.0.0/0" ]] && dest_type="🌐 Anywhere (IPv4)"
                [[ "$destination" == "::/0" ]] && dest_type="🌐 Anywhere (IPv6)"
                [[ "$destination" =~ ^sg- ]] && dest_type="🔗 Security Group"
                
                echo "| \`$protocol\` | $port_range | \`$destination\` | $dest_type |" >> "$OUTPUT_FILE"
            done <<< "$outbound_rules"
        else
            echo "No outbound rules configured." >> "$OUTPUT_FILE"
        fi
        
        echo "" >> "$OUTPUT_FILE"
        echo "---" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        
    done <<< "$security_groups"
    
    log_info "✓ Security group details saved to output file"
}

################################################################################
# Key Pair Information
################################################################################

get_key_pair_details() {
    log_section "Gathering SSH Key Pair Details"
    
    cat >> "$OUTPUT_FILE" << 'KEY_HEADER'

---

## 🔑 SSH Key Pairs

> **Info:** SSH key pairs are used for secure authentication when connecting to EC2 instances.

KEY_HEADER
    echo "" >> "$OUTPUT_FILE"
    
    local key_pairs
    key_pairs=$(aws ec2 describe-key-pairs \
        --region "$SELECTED_REGION" \
        --query 'KeyPairs[].[KeyName,KeyPairId,KeyFingerprint,KeyType]' \
        --output text)
    
    if [[ -z "$key_pairs" ]]; then
        log_warn "No key pairs found in region "$SELECTED_REGION""
        echo "No SSH key pairs found in this region." >> "$OUTPUT_FILE"
        return
    fi
    
    echo "### Available Key Pairs in Region" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "| Key Pair Name | Key Pair ID | Key Fingerprint | Key Type |" >> "$OUTPUT_FILE"
    echo "|:--------------|:------------|:----------------|:---------|" >> "$OUTPUT_FILE"
    
    while IFS=$'\t' read -r key_name key_id fingerprint key_type; do
        echo "| **$key_name** | \`$key_id\` | \`$fingerprint\` | \`$key_type\` |" >> "$OUTPUT_FILE"
    done <<< "$key_pairs"
    
    echo "" >> "$OUTPUT_FILE"
    
    log_info "✓ Key pair details saved to output file"
}

################################################################################
# Generate Terraform Example
################################################################################

generate_terraform_example() {
    log_section "Generating Terraform Configuration Example"
    
    cat >> "$OUTPUT_FILE" << 'TF_HEADER'

---

## 📦 Terraform Configuration Example

> **Info:** This is a production-ready Terraform configuration template. Replace the variable values with the IDs from the sections above.

### Production-Ready Configuration

TF_HEADER
    echo "" >> "$OUTPUT_FILE"
    echo '```hcl' >> "$OUTPUT_FILE"
    echo '# Provider configuration' >> "$OUTPUT_FILE"
    echo 'provider "aws" {' >> "$OUTPUT_FILE"
    echo "  region = \"$SELECTED_REGION\"" >> "$OUTPUT_FILE"
    echo '}' >> "$OUTPUT_FILE"
    echo '' >> "$OUTPUT_FILE"
    echo '# Variables (customize these based on the details above)' >> "$OUTPUT_FILE"
    echo 'variable "ami_id" {' >> "$OUTPUT_FILE"
    echo '  description = "AMI ID for the EC2 instance"' >> "$OUTPUT_FILE"
    echo '  type        = string' >> "$OUTPUT_FILE"
    echo '  # See AMI section above for available AMI IDs' >> "$OUTPUT_FILE"
    echo '}' >> "$OUTPUT_FILE"
    echo '' >> "$OUTPUT_FILE"
    echo 'variable "instance_type" {' >> "$OUTPUT_FILE"
    echo '  description = "Instance type"' >> "$OUTPUT_FILE"
    echo '  type        = string' >> "$OUTPUT_FILE"
    echo '  default     = "t3.micro"' >> "$OUTPUT_FILE"
    echo '  # See Instance Types section above for available types' >> "$OUTPUT_FILE"
    echo '}' >> "$OUTPUT_FILE"
    echo '' >> "$OUTPUT_FILE"
    echo 'variable "subnet_id" {' >> "$OUTPUT_FILE"
    echo '  description = "Subnet ID for the EC2 instance"' >> "$OUTPUT_FILE"
    echo '  type        = string' >> "$OUTPUT_FILE"
    echo '  # See Subnet Details section above for available subnet IDs' >> "$OUTPUT_FILE"
    echo '}' >> "$OUTPUT_FILE"
    echo '' >> "$OUTPUT_FILE"
    echo 'variable "security_group_ids" {' >> "$OUTPUT_FILE"
    echo '  description = "List of security group IDs"' >> "$OUTPUT_FILE"
    echo '  type        = list(string)' >> "$OUTPUT_FILE"
    echo '  # See Security Groups section above for available group IDs' >> "$OUTPUT_FILE"
    echo '}' >> "$OUTPUT_FILE"
    echo '' >> "$OUTPUT_FILE"
    echo 'variable "key_name" {' >> "$OUTPUT_FILE"
    echo '  description = "SSH key pair name"' >> "$OUTPUT_FILE"
    echo '  type        = string' >> "$OUTPUT_FILE"
    echo '  # See SSH Key Pairs section above for available key names' >> "$OUTPUT_FILE"
    echo '}' >> "$OUTPUT_FILE"
    echo '' >> "$OUTPUT_FILE"
    echo '# EC2 Instance Resource' >> "$OUTPUT_FILE"
    echo 'resource "aws_instance" "example" {' >> "$OUTPUT_FILE"
    echo '  ami                    = var.ami_id' >> "$OUTPUT_FILE"
    echo '  instance_type          = var.instance_type' >> "$OUTPUT_FILE"
    echo '  subnet_id              = var.subnet_id' >> "$OUTPUT_FILE"
    echo '  vpc_security_group_ids = var.security_group_ids' >> "$OUTPUT_FILE"
    echo '  key_name               = var.key_name' >> "$OUTPUT_FILE"
    echo '' >> "$OUTPUT_FILE"
    echo '  # Root volume configuration' >> "$OUTPUT_FILE"
    echo '  root_block_device {' >> "$OUTPUT_FILE"
    echo '    volume_size           = 20' >> "$OUTPUT_FILE"
    echo '    volume_type           = "gp3"' >> "$OUTPUT_FILE"
    echo '    delete_on_termination = true' >> "$OUTPUT_FILE"
    echo '    encrypted             = true' >> "$OUTPUT_FILE"
    echo '  }' >> "$OUTPUT_FILE"
    echo '' >> "$OUTPUT_FILE"
    echo '  # Metadata options for IMDSv2' >> "$OUTPUT_FILE"
    echo '  metadata_options {' >> "$OUTPUT_FILE"
    echo '    http_endpoint               = "enabled"' >> "$OUTPUT_FILE"
    echo '    http_tokens                 = "required"' >> "$OUTPUT_FILE"
    echo '    http_put_response_hop_limit = 1' >> "$OUTPUT_FILE"
    echo '  }' >> "$OUTPUT_FILE"
    echo '' >> "$OUTPUT_FILE"
    echo '  # Enable detailed monitoring' >> "$OUTPUT_FILE"
    echo '  monitoring = true' >> "$OUTPUT_FILE"
    echo '' >> "$OUTPUT_FILE"
    echo '  # Tags' >> "$OUTPUT_FILE"
    echo '  tags = {' >> "$OUTPUT_FILE"
    echo '    Name        = "terraform-ec2-instance"' >> "$OUTPUT_FILE"
    echo '    Environment = "production"' >> "$OUTPUT_FILE"
    echo '    ManagedBy   = "Terraform"' >> "$OUTPUT_FILE"
    echo '  }' >> "$OUTPUT_FILE"
    echo '}' >> "$OUTPUT_FILE"
    echo '' >> "$OUTPUT_FILE"
    echo '# Outputs' >> "$OUTPUT_FILE"
    echo 'output "instance_id" {' >> "$OUTPUT_FILE"
    echo '  description = "ID of the EC2 instance"' >> "$OUTPUT_FILE"
    echo '  value       = aws_instance.example.id' >> "$OUTPUT_FILE"
    echo '}' >> "$OUTPUT_FILE"
    echo '' >> "$OUTPUT_FILE"
    echo 'output "instance_public_ip" {' >> "$OUTPUT_FILE"
    echo '  description = "Public IP address of the EC2 instance"' >> "$OUTPUT_FILE"
    echo '  value       = aws_instance.example.public_ip' >> "$OUTPUT_FILE"
    echo '}' >> "$OUTPUT_FILE"
    echo '' >> "$OUTPUT_FILE"
    echo 'output "instance_private_ip" {' >> "$OUTPUT_FILE"
    echo '  description = "Private IP address of the EC2 instance"' >> "$OUTPUT_FILE"
    echo '  value       = aws_instance.example.private_ip' >> "$OUTPUT_FILE"
    echo '}' >> "$OUTPUT_FILE"
    echo '```' >> "$OUTPUT_FILE"
    
    # Add helpful footer
    cat >> "$OUTPUT_FILE" << 'FOOTER_EOF'

---

## 📚 Quick Reference Guide

### How to Use This Report with Terraform

1. **Choose an AMI**: Select an AMI ID from the [AMI section](#-ami-application-and-os-images)
2. **Select Instance Type**: Pick an instance type from the [Instance Types section](#-instance-types)
3. **Choose Subnet**: Select a subnet ID from the [Subnets section](#-subnets)
   - Use **Public Subnet** if your instance needs direct internet access
   - Use **Private Subnet** for internal-only instances
4. **Configure Security**: Select security group IDs from the [Security Groups section](#-security-groups-firewalls)
5. **SSH Access**: Choose a key pair from the [SSH Key Pairs section](#-ssh-key-pairs)

### 🔒 Security Best Practices

- ✅ Always use encrypted EBS volumes
- ✅ Enable IMDSv2 for instance metadata
- ✅ Use security groups with least-privilege access
- ✅ Regularly rotate SSH keys
- ✅ Enable detailed monitoring for production instances
- ✅ Use private subnets for databases and backend services
- ✅ Implement proper tagging strategy for resource management

### 🎯 Next Steps

1. **Review Resources**: Examine all available resources in your region
2. **Plan Architecture**: Design your infrastructure based on requirements
3. **Update Terraform**: Modify the configuration example with your chosen values
4. **Initialize Terraform**: Run `terraform init` in your project directory
5. **Validate**: Run `terraform plan` to preview changes
6. **Deploy**: Run `terraform apply` to create resources

### 📖 Additional Resources

- [AWS EC2 Documentation](https://docs.aws.amazon.com/ec2/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

---

<div align="center">

**Generated by AWS EC2 Information Gatherer**  
*Production-Ready Infrastructure Discovery Tool*

</div>

FOOTER_EOF
    
    log_info "✓ Terraform example configuration generated"
}

################################################################################
# Main Function
################################################################################

main() {
    echo -e "${BOLD}${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║   AWS EC2 Information Gatherer for Terraform Configuration    ║"
    echo "║                    Production-Ready Script                     ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    log_info "Script started at $(date)"
    log_info "Log file: $LOG_FILE"
    log_info "Output file: $OUTPUT_FILE"
    
    # Get AWS account info for header
    local caller_identity
    caller_identity=$(aws sts get-caller-identity)
    local account_id
    account_id=$(echo "$caller_identity" | jq -r '.Account')
    local user_arn
    user_arn=$(echo "$caller_identity" | jq -r '.Arn')
    
    # Initialize output file with professional header
    cat > "$OUTPUT_FILE" << 'HEADER_EOF'
<div align="center">

# 🚀 AWS EC2 Infrastructure Report

### Production-Ready Resource Discovery for Terraform Configuration

![AWS](https://img.shields.io/badge/AWS-EC2-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-Compatible-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)
![Status](https://img.shields.io/badge/Status-Production-success?style=for-the-badge)

</div>

---

## 📋 Document Metadata

| Property | Value |
|----------|-------|
HEADER_EOF
    
    echo "| **Generated** | $(date '+%Y-%m-%d %H:%M:%S %Z') |" >> "$OUTPUT_FILE"
    echo "| **AWS Account** | \`$account_id\` |" >> "$OUTPUT_FILE"
    echo "| **IAM Principal** | \`$user_arn\` |" >> "$OUTPUT_FILE"
    echo "| **Script Version** | \`1.0.0\` |" >> "$OUTPUT_FILE"
    echo "| **Purpose** | Terraform EC2 Configuration Reference |" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "---" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Run all gathering functions
    check_prerequisites
    select_region
    get_ami_details
    get_instance_types
    get_vpc_details
    get_subnet_details
    get_security_group_details
    get_key_pair_details
    generate_terraform_example
    
    # Final summary
    log_section "Summary"
    log_info "All information has been gathered successfully!"
    log_info ""
    log_info "Output saved to: $OUTPUT_FILE"
    log_info "Log file saved to: $LOG_FILE"
    log_info ""
    log_info "You can now use this information to configure your Terraform EC2 resources."
    log_info "Open the output file for detailed information about all available resources."
    
    echo ""
    echo -e "${GREEN}${BOLD}✓ Script completed successfully!${NC}"
    echo ""
}

################################################################################
# Script Entry Point
################################################################################

# Trap errors and cleanup
trap 'log_error "Script failed at line $LINENO. Exit code: $?"' ERR

# Run main function
main "$@"
