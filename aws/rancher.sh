#!/bin/bash
set -e

# Update system packages
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common

# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Add ubuntu user to docker group for non-root access
usermod -aG docker ubuntu

# Load required kernel modules for networking
modprobe -q iptable_nat || true
modprobe -q nf_nat || true
modprobe -q nf_conntrack || true
modprobe -q nf_conntrack_ipv4 || true
modprobe -q ip6table_nat || true
modprobe -q nf_nat_ipv6 || true

# Run Rancher (no restart on first run to avoid reset-flag loop)
docker run -d --name rancher-init \
  -p 80:80 -p 443:443 \
  --privileged \
  --cap-add NET_ADMIN \
  --cap-add NET_RAW \
  -v /var/lib/rancher:/var/lib/rancher \
  rancher/rancher:latest

# Wait for Rancher to initialize
echo "Waiting for Rancher to initialize..."
for i in {1..300}; do
  if docker exec rancher-init curl -s -k https://localhost/v1/management.cattle.io.clusters &>/dev/null; then
    echo "Rancher is ready!"
    break
  fi
  echo "Still initializing... ($i/300)"
  sleep 2
done

# Now enable restart policy and remove the init container name constraint
docker update --restart=unless-stopped rancher-init

# Print the correct access URL using the instance's public IP (not the internal container IP Rancher logs)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)
BOOTSTRAP_PASSWORD=$(docker logs rancher-init 2>&1 | grep -oP 'Bootstrap Password: \K\S+' | tail -1)
echo "-----------------------------------------"
echo "Rancher is ready. Access it at:"
echo "https://${PUBLIC_IP}/dashboard/?setup=${BOOTSTRAP_PASSWORD}"
echo "-----------------------------------------"