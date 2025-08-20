#!/bin/bash
# ==========================================================
# Local Private Registry + Dockerfiles HTTP Serve Setup Script + Remote Athena user setup
# Registry Name : registry.lab.example.com
# User          : admin
# Password      : redhat
# Remote Node   : node2
# Author        : Rohan
# ==========================================================

REGISTRY_NAME="registry.lab.example.com"
REGISTRY_PORT="5000"
REGISTRY_CONTAINER_NAME="myregistry"
REGISTRY_DATA_DIR="/opt/registry/data"
AUTH_DIR="/opt/registry/auth"
DOCKERFILES_DIR="/opt/registry/dockerfiles"

# Remote node where athena user will be created
REMOTE_NODE="node1"
ATHENA_USER="athena"
ATHENA_PASS="redhat"

# 👉 DHCP ने मिळालेला primary IP घ्या
SERVER_IP=$(hostname -I | awk '{print $1}')

echo "=== Step 0: Create Athena user on remote node ($REMOTE_NODE) with rootless Podman setup ==="
ssh root@$REMOTE_NODE bash <<EOF
id $ATHENA_USER &>/dev/null
if [ \$? -ne 0 ]; then
    useradd $ATHENA_USER
    echo "$ATHENA_USER:$ATHENA_PASS" | chpasswd
    echo "✅ User $ATHENA_USER created with password $ATHENA_PASS on $REMOTE_NODE"
else
    echo "ℹ User $ATHENA_USER already exists on $REMOTE_NODE"
fi

# Enable rootless Podman for Athena
loginctl enable-linger $ATHENA_USER
echo "✅ Rootless Podman enabled for $ATHENA_USER on $REMOTE_NODE"
EOF

echo "=== Step 1: Install podman, httpd-tools and Apache on local server ==="
dnf install -y podman httpd-tools httpd

echo "=== Step 2: Create required directories ==="
mkdir -p $REGISTRY_DATA_DIR
mkdir -p $AUTH_DIR
mkdir -p $DOCKERFILES_DIR

echo "=== Step 3: Create htpasswd file for authentication ==="
htpasswd -bBc $AUTH_DIR/htpasswd admin redhat

echo "=== Step 4: Run registry container ==="
podman rm -f $REGISTRY_CONTAINER_NAME 2>/dev/null
podman run -d --name $REGISTRY_CONTAINER_NAME \
  -p ${REGISTRY_PORT}:5000 \
  -v $REGISTRY_DATA_DIR:/var/lib/registry:z \
  -v $AUTH_DIR:/auth:z \
  -e "REGISTRY_AUTH=htpasswd" \
  -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
  -e "REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd" \
  docker.io/library/registry:2

echo "=== Step 5: Add entry to /etc/hosts ==="
if ! grep -q "$REGISTRY_NAME" /etc/hosts; then
    echo "$SERVER_IP   $REGISTRY_NAME" >> /etc/hosts
fi

echo "=== Step 6: Firewall allow ==="
firewall-cmd --permanent --add-port=${REGISTRY_PORT}/tcp
firewall-cmd --permanent --add-service=http
firewall-cmd --reload

echo "=== Step 7: Configure registries.conf to allow insecure registry ==="
REG_CONF="/etc/containers/registries.conf"
if ! grep -q "$REGISTRY_NAME:$REGISTRY_PORT" $REG_CONF; then
    cat <<EOC >> $REG_CONF

[[registry]]
location = "$REGISTRY_NAME:$REGISTRY_PORT"
insecure = true
blocked = false
EOC
fi

echo "=== Step 8: Test login from local server ==="
podman login -u admin -p redhat $REGISTRY_NAME:$REGISTRY_PORT --tls-verify=false

echo "=== Step 9: Copy RHCSA-Container files into $DOCKERFILES_DIR ==="
if [ -d "/root/RHCSA-Container-master" ]; then
    cp -r /root/RHCSA-Container-master/* $DOCKERFILES_DIR/
    echo "✅ RHCSA Container files are now available at: $DOCKERFILES_DIR"
else
    echo "❌ Directory /root/RHCSA-Container-master not found!"
fi

echo "=== Step 10: Serve Dockerfiles via Apache HTTP with directory listing ==="
WEBROOT="/var/www/html/dockerfiles"
mkdir -p $WEBROOT
cp -r $DOCKERFILES_DIR/* $WEBROOT/
chown -R apache:apache $WEBROOT
chmod -R 755 $WEBROOT

APACHE_CONF="/etc/httpd/conf.d/dockerfiles.conf"
cat <<EOC > $APACHE_CONF
Alias /dockerfiles $WEBROOT
<Directory $WEBROOT>
    Options +Indexes +FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>
EOC

systemctl enable --now httpd

echo "=== DONE ==="
echo "Registry running at: http://$REGISTRY_NAME:$REGISTRY_PORT"
echo "Dockerfiles available via HTTP at: http://$SERVER_IP/dockerfiles/"
echo "Athena user rootless enabled on remote node ($REMOTE_NODE)."
echo "Students can login as $ATHENA_USER with password $ATHENA_PASS"
echo "Students can download all Dockerfiles into current directory using just:"
echo "wget http://$SERVER_IP/dockerfiles/"
