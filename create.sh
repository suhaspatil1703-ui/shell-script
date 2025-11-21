#!/usr/bin/env bash
set -euo pipefail

source "./config.env"

log() { echo "$1"; }


if ! command -v aws &>/dev/null; then
  echo "AWS CLI not installed."; exit 1
fi


if ! aws sts get-caller-identity &>/dev/null; then
  echo "AWS credentials not set."; exit 1
fi

export AWS_REGION


if aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" &>/dev/null; then
  log "Key pair already exists."
else
  log "Creating key pair..."
  aws ec2 create-key-pair --key-name "$KEY_PAIR_NAME" \
      --query 'KeyMaterial' --output text > "${KEY_PAIR_NAME}.pem"
  chmod 400 "${KEY_PAIR_NAME}.pem"
fi


if aws ec2 describe-security-groups --group-names "$SEC_GROUP_NAME" &>/dev/null; then
  SG_ID=$(aws ec2 describe-security-groups --group-names "$SEC_GROUP_NAME" --query 'SecurityGroups[0].GroupId' --output text)
  log "Security group exists: $SG_ID"
else
  log "Creating security group..."
  SG_ID=$(aws ec2 create-security-group \
            --group-name "$SEC_GROUP_NAME" \
            --description "Demo SG" \
            --query 'GroupId' --output text)
  aws ec2 authorize-security-group-ingress \
      --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0
fi


EXISTING=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$INSTANCE_NAME" \
  --query "Reservations[].Instances[].InstanceId" --output text)

if [ "$EXISTING" != "None" ] && [ -n "$EXISTING" ]; then
  log "Instance already exists: $EXISTING"
else
  log "Launching EC2 instance..."
  INSTANCE_ID=$(aws ec2 run-instances \
      --image-id "$AMI_ID" \
      --instance-type "$INSTANCE_TYPE" \
      --key-name "$KEY_PAIR_NAME" \
      --security-groups "$SEC_GROUP_NAME" \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
      --query 'Instances[0].InstanceId' --output text)

  log "Waiting for instance..."
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
  EXISTING="$INSTANCE_ID"
fi

PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $EXISTING --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

BUCKET_NAME="${S3_BUCKET_PREFIX}-$(date +%s)-$RANDOM"

log "Creating S3 bucket: $BUCKET_NAME"
if [ "$AWS_REGION" == "us-east-1" ]; then
  aws s3api create-bucket --bucket "$BUCKET_NAME"
else
  aws s3api create-bucket --bucket "$BUCKET_NAME" \
     --create-bucket-configuration LocationConstraint="$AWS_REGION"
fi


cat <<EOF > "$SUMMARY_FILE"
EC2 + S3 Creation Summary
-------------------------
Instance Name: $INSTANCE_NAME
Instance ID: $EXISTING
Public IP: $PUBLIC_IP
Security Group: $SEC_GROUP_NAME
Key Pair: $KEY_PAIR_NAME
S3 Bucket: $BUCKET_NAME
EOF

log "Resources created successfully!"
