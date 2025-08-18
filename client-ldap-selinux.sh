#!/bin/bash
# Combined Lab Setup Script: LDAP Client -> Q3 SELinux -> Repo Cleanup (on Node1)
# Author: Rohan

NODE1="node1.example.com"
SCRIPT_NAME="ldap_client_remote.sh"
REMOTE_LOG="/tmp/ldap_setup.log"
TEMP_REPO="/etc/yum.repos.d/rhel.repo"

echo "==================================="
echo " Step 1: Setting up LDAP Client on $NODE1 "
echo "==================================="

# Generate remote LDAP script
cat <<'EOF_REMOTE' > /tmp/$SCRIPT_NAME
#!/bin/bash

LDAP_DOMAIN="content.example.com"
LDAP_BASE="dc=example,dc=com"
LDAP_BIND_DN="cn=manager,dc=example,dc=com"
LDAP_PASSWORD="redhat"
HOMEDIR_PARENT="/home/guests"
TEMP_REPO="/etc/yum.repos.d/rhel.repo"
LOG_FILE="/tmp/ldap_setup.log"

echo "$(date) - Script started" > $LOG_FILE

# Step 0: Create temporary yum repo
cat > $TEMP_REPO <<EOF
[BaseOS]
name=BaseOS
baseurl=http://content.example.com/rhel9/BaseOS
enabled=1
gpgcheck=0

[AppStream]
name=AppStream
baseurl=http://content.example.com/rhel9/AppStream
enabled=1
gpgcheck=0
EOF

echo "$(date) - Temporary yum repo created." >> $LOG_FILE

# Step 1: Auto-detect LDAP server IP
LDAP_SERVER_IP=$(getent hosts $LDAP_DOMAIN | awk '{print $1}')
if [ -z "$LDAP_SERVER_IP" ]; then
    echo "$(date) - Error: Could not detect LDAP server IP" >> $LOG_FILE
    rm -f $TEMP_REPO
    exit 1
fi
echo "$(date) - Detected LDAP server IP: $LDAP_SERVER_IP" >> $LOG_FILE

# Step 2: Install packages
echo "$(date) - Installing required packages..." >> $LOG_FILE
dnf install -y sssd realmd oddjob oddjob-mkhomedir nfs-utils &>> $LOG_FILE

# Step 3: Configure authselect
echo "$(date) - Configuring authselect..." >> $LOG_FILE
authselect select sssd with-mkhomedir --force &>> $LOG_FILE

# Step 4: Create sssd.conf
cat > /etc/sssd/sssd.conf <<EOF_SSSD
[sssd]
services = nss, pam
config_file_version = 2
domains = LDAP

[domain/LDAP]
id_provider = ldap
auth_provider = ldap
chpass_provider = ldap
ldap_uri = ldap://$LDAP_SERVER_IP
ldap_search_base = $LDAP_BASE
ldap_default_bind_dn = $LDAP_BIND_DN
ldap_default_authtok = $LDAP_PASSWORD
ldap_tls_reqcert = allow
override_homedir = $HOMEDIR_PARENT/%u
enumerate = true
EOF_SSSD

chmod 600 /etc/sssd/sssd.conf
systemctl enable --now oddjobd.service
systemctl restart sssd &>> $LOG_FILE

echo "$(date) - LDAP client setup completed." >> $LOG_FILE
EOF_REMOTE

# Copy and run LDAP script on Node1
scp /tmp/$SCRIPT_NAME $NODE1:/tmp/
ssh $NODE1 "bash /tmp/$SCRIPT_NAME; cat /tmp/ldap_setup.log"

# -------------------------------
# Step 2: Q3 SELinux Lab Setup (Node1 वर चालेल)
# -------------------------------
echo "==================================="
echo " Step 2: Setting up Q3 SELinux Lab on $NODE1 "
echo "==================================="

ssh $NODE1 bash -s <<'EOF_SELINUX'
dnf install httpd policycoreutils-python-utils -y

# Configure Apache on port 82
sed -i 's/Listen 80/Listen 82/' /etc/httpd/conf/httpd.conf

# Create test HTML page
mkdir -p /var/www/html
echo "<h1>Cheers to you for a job well done! No one can compare to your creativity and passion.</h1>" > /var/www/html/index.html
chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html

# SELinux: intentionally block port 82
semanage port -d -t http_port_t -p tcp 82 2>/dev/null

# Start Apache (will fail due to SELinux)
systemctl enable httpd
systemctl start httpd

# Stop firewall
systemctl stop firewalld
systemctl disable firewalld

# Display Apache status + SELinux status
echo "-----------------------------------"
echo "Apache status and SELinux context:"
systemctl status httpd --no-pager
sestatus
echo "To test: curl http://localhost:82"
echo "-----------------------------------"
EOF_SELINUX

# -------------------------------
# Step 3: Cleanup temporary repo (Node1 वर)
# -------------------------------
echo "==================================="
echo " Step 3: Deleting temporary yum repo from $NODE1 "
echo "==================================="
ssh $NODE1 "rm -f $TEMP_REPO && echo 'Temporary repo deleted from $NODE1'"

echo "==================================="
echo " Combined Lab Setup Completed on $NODE1 ! "
echo "==================================="
#for debuging
# 1. SELinux context verify कर
# semanage port -l | grep http
# इथे 82 दिसणार नाही (फक्त 80, 443 वगैरे दिसतील)
# 2. SELinux log तपास
# ausearch -m AVC,USER_AVC -ts recent
# 3. Port 82 allow कर
# sudo semanage port -a -t http_port_t -p tcp 82
# 4. पुन्हा start कर Apache
# systemctl restart httpd
# systemctl status httpd
# 5. Check कर की service चालू आहे का
# curl http://localhost:82
