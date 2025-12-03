#!/bin/bash
set -e

# Update system
apt-get update
apt-get install -y python3 python3-pip

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Add user to docker group
usermod -aG docker ubuntu || true

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Format and mount persistent disk for PostgreSQL data
DEVICE_NAME="/dev/disk/by-id/google-postgres-data"
MOUNT_POINT="/mnt/postgres-data"

# Check if disk is already formatted
if ! blkid $DEVICE_NAME; then
echo "Formatting persistent disk..."
mkfs.ext4 -F $DEVICE_NAME
fi

# Create mount point
mkdir -p $MOUNT_POINT

# Mount the disk
mount $DEVICE_NAME $MOUNT_POINT

# Add to fstab for automatic mounting on reboot
if ! grep -q "$DEVICE_NAME" /etc/fstab; then
echo "$DEVICE_NAME $MOUNT_POINT ext4 defaults 0 2" >> /etc/fstab
fi

# Create PostgreSQL data directory on persistent disk
mkdir -p $MOUNT_POINT/data
chmod 700 $MOUNT_POINT/data

# Log completion
echo "VM initialization complete" | tee /var/log/startup-complete.log