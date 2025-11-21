#!/usr/bin/env bash
set -euo pipefail

source "./config.env"

log() { echo "$1"; }

export AWS_REGION

# TERMINATE EC2
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$INSTANCE_NAME" \
  --query "Reservations[].Instances[].InstanceId" --output text)

if [ "$INSTANCE_IDS" != "None" ] && [ -n "$INSTANCE_IDS" ]; then
  log "Terminating instance(s): $INSTANCE_IDS"
  aws ec2 terminate-instances --instance-ids $INSTANCE_IDS
  aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS
else
  log "No EC2 instances found."
fi

# DELETE SECURITY GROUP
if aws ec2 describe-security-groups --group-names "$SEC_GROUP_NAME" &>/dev/null; then
  log "Deleting security group $SEC_GROUP_NAME"
  SG_ID=$(aws ec2 describe-security-groups --group-names "$SEC_GROUP_NAME" --query 'SecurityGroups[0].GroupId' --output text)
  aws ec2 delete-security-group --group-id "$SG_ID"
else
  log "Security group not found."
fi

# DELETE KEY PAIR
if aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" &>/dev/null; then
  aws ec2 delete-key-pair --key-name "$KEY_PAIR_NAME"
  log "Key pair deleted."
fi

if [ -f "${KEY_PAIR_NAME}.pem" ]; then
  rm -f "${KEY_PAIR_NAME}.pem"
fi

# DELETE S3 BUCKETS
log "Searching for buckets starting with prefix: $S3_BUCKET_PREFIX"

BUCKETS=$(aws s3api list-buckets --query "Buckets[].Name" --output text)

for b in $BUCKETS; do
  if [[ "$b" == "$S3_BUCKET_PREFIX"* ]]; then
    log "Deleting bucket: $b"
    aws s3 rb "s3://$b" --force
  fi
done

log "Cleanup complete!"
