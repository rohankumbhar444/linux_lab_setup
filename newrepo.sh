#!/bin/bash
# EX200 Lab Setup Script - RHEL 9.x + NTP Server + Repo Setup + Auto ISO Detect + Permanent Mount
# Author: Modified for Auto-detect ISO/DVD

# === Variables ===
HOSTNAME="content.example.com"
SERVER_IP=$(hostname -I | awk '{print $1}')
NET_PREFIX=$(ip -o -f inet addr show | awk '/scope global/ {split($4,a,"/"); print a[1]}' | head -n1 | cut -d'.' -f1-3).0/24
RHSM_USER="rohankumbhar444"
RHSM_PASS="RohanAshu@1109"

WEB_ROOT="/var/www/html/rhel9"
ISO_MOUNT="/mnt/rhel9iso"

# === Root check ===
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root"
    exit 1
fi

# === Step 0: Detect ISO/DVD device ===
echo "[+] Detecting ISO/DVD device..."
ISO_DEVICE=$(blkid -t TYPE="iso9660" -o device | head -n1)

if [ -z "$ISO_DEVICE" ]; then
    echo "ERROR: No ISO/DVD device found! Please insert or attach RHEL ISO."
    exit 1
else
    echo "[+] ISO/DVD device detected: $ISO_DEVICE"
fi

# === Step 1: Permanent mount setup ===
mkdir -p $ISO_MOUNT
if ! grep -q "$ISO_MOUNT" /etc/fstab; then
    echo "$ISO_DEVICE  $ISO_MOUNT  iso9660  ro,auto  0  0" >> /etc/fstab
fi
mount -a || { echo "ERROR: Failed to mount $ISO_DEVICE"; exit 1; }

# === Step 2: Set Hostname ===
hostnamectl set-hostname $HOSTNAME
if ! grep -q "$HOSTNAME" /etc/hosts; then
    echo "$SERVER_IP   $HOSTNAME" >> /etc/hosts
fi

# === Step 3: Register to Red Hat Subscription ===
subscription-manager unregister >/dev/null 2>&1
subscription-manager clean
subscription-manager register --username="$RHSM_USER" --password="$RHSM_PASS" --auto-attach
if [ $? -ne 0 ]; then
    echo "ERROR: Registration failed!"
    exit 1
fi

# === Step 4: Enable Required Repositories ===
subscription-manager repos --enable=rhel-9-for-x86_64-baseos-rpms \
                           --enable=rhel-9-for-x86_64-appstream-rpms

# === Step 5: Install Apache + createrepo + chrony ===
dnf install httpd createrepo chrony -y || { echo "ERROR: Package install failed"; exit 1; }

# === Step 6: Enable Apache ===
systemctl enable --now httpd

# === Step 7: Create web root folders ===
mkdir -p $WEB_ROOT/BaseOS
mkdir -p $WEB_ROOT/AppStream

# === Step 8: Copy RPMs from mounted ISO ===
echo "[+] Copying RPM packages from mounted ISO..."
rsync -av $ISO_MOUNT/BaseOS/Packages/ $WEB_ROOT/BaseOS/
rsync -av $ISO_MOUNT/AppStream/Packages/ $WEB_ROOT/AppStream/

# === Step 9: Set Permissions ===
chown -R apache:apache $WEB_ROOT
chmod -R 755 $WEB_ROOT

# === Step 10: Run createrepo ===
createrepo $WEB_ROOT/BaseOS
createrepo $WEB_ROOT/AppStream

# === Step 11: Apache Alias Config ===
cat <<EOF > /etc/httpd/conf.d/rhel9.repo.conf
Alias /rhel9.6/x86_64/dvd/BaseOS $WEB_ROOT/BaseOS
Alias /rhel9.6/x86_64/dvd/AppStream $WEB_ROOT/AppStream

<Directory "$WEB_ROOT/BaseOS">
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

<Directory "$WEB_ROOT/AppStream">
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>
EOF

systemctl restart httpd

# === Step 12: Firewall ===
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=ntp
firewall-cmd --reload

# === Step 13: NTP Server Setup ===
cat <<EOF > /etc/chrony.conf
pool 2.rhel.pool.ntp.org iburst
allow $NET_PREFIX
local stratum 10
sourcedir /run/chrony-dhcp
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
leapsectz right/UTC
logdir /var/log/chrony
local stratum 10
EOF

if ! grep -q "classroom.example.com" /etc/hosts; then
    echo "$SERVER_IP   classroom.example.com" >> /etc/hosts
fi
systemctl enable --now chronyd

# === Done ===
echo
echo "=============================="
echo " Server & Repo setup complete!"
echo "=============================="
echo "Server IP: $SERVER_IP"
echo "BaseOS URL: http://$HOSTNAME/rhel9.6/x86_64/dvd/BaseOS"
echo "AppStream URL: http://$HOSTNAME/rhel9.6/x86_64/dvd/AppStream"
echo "NTP Server: classroom.example.com (IP: $SERVER_IP)"

~                                                                           
