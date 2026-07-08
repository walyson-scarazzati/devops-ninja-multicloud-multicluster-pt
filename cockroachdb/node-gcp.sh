#!/bin/bash
#!/bin/bash
apt-get update
apt-get install -y chrony
systemctl enable chrony
systemctl restart chrony
chronyc tracking
wget -qO- https://binaries.cockroachdb.com/cockroach-v24.1.5.linux-amd64.tgz | tar  xvz
cp -i cockroach-v24.1.5.linux-amd64/cockroach /usr/local/bin/