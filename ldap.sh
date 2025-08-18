#!/bin/bash
# LDAP + NFS Auto Setup Script - RHEL/CentOS 9 (Production-safe & Fixed)
# Author: Rohan Kumbhar (Improved: Migration + OU + LDAPS + Logging)

set -e
set -o pipefail

# Variables
LDAP_PASS="redhat"
LDAP_PASS_FILE="/etc/openldap/passwd"
CERT_DIR="/etc/openldap/certs"
LDAP_DOMAIN="example.com"
LDAP_ORG="ifuture technology"
LDAP_OU="kalyan office"
LDAP_CN="content.example.com"
LDAP_EMAIL="root@content.example.com"
LDAP_BASE="dc=example,dc=com"
GUEST_DIR="/home/guests"
MIGRATION_DIR="/usr/share/MigrationTools"
LOG_FILE="/var/log/ldap_nfs_setup.log"
NFS_ALLOWED_NET="192.168.183.0/24"

# Logging
exec > >(tee -i $LOG_FILE)
exec 2>&1

echo "=== Step 1: Install git ==="
dnf install git -y

echo "=== Step 2: Prepare /root/ldap and clone repo ==="
mkdir -p /root/ldap
cd /root/ldap
if [ ! -d "LDAP-PACKAGES" ]; then
    git clone https://github.com/rohankumbhar444/LDAP-PACKAGES.git
fi

echo "=== Step 3: Enable codeready repo and install dependencies ==="
subscription-manager repos --enable codeready-builder-for-rhel-9-x86_64-rpms
dnf install perl-IO-Stringy -y
dnf install /root/ldap/LDAP-PACKAGES/perl-Config-IniFiles-3.000003-6.el9.noarch.rpm -y

echo "=== Step 3.1: Install openldap and clients from repo ==="
dnf install openldap openldap-clients -y

echo "=== Step 3.2: Install openldap-servers and nss-pam-ldapd from offline RPM ==="
dnf install /root/ldap/LDAP-PACKAGES/openldap-servers-*.rpm -y
dnf install /root/ldap/LDAP-PACKAGES/nss-pam-ldapd-*.rpm -y

echo "=== Step 4: Generate LDAP admin password ==="
slappasswd -s $LDAP_PASS -n > $LDAP_PASS_FILE
chmod 600 $LDAP_PASS_FILE

echo "=== Step 5: Generate SSL certificate (auto non-interactive) ==="
mkdir -p $CERT_DIR
openssl req -new -x509 -nodes \
  -out $CERT_DIR/cert.pem \
  -keyout $CERT_DIR/priv.pem \
  -days 365 \
  -subj "/C=IN/ST=Maharashtra/L=Thane/O=$LDAP_ORG/OU=$LDAP_OU/CN=$LDAP_CN/emailAddress=$LDAP_EMAIL"
chown ldap:ldap $CERT_DIR/*
chmod 600 $CERT_DIR/priv.pem
chmod 644 $CERT_DIR/cert.pem

echo "=== Step 6: Prepare LDAP database (DB_CONFIG fix) ==="
mkdir -p /var/lib/ldap
if [ ! -f /var/lib/ldap/DB_CONFIG ]; then
    cat > /var/lib/ldap/DB_CONFIG <<EOF
set_cachesize 0 2097152 0
set_lg_bsize 2097152
set_lg_dir /var/lib/ldap
set_flags DB_LOG_AUTOREMOVE
EOF
fi
chown ldap:ldap /var/lib/ldap/DB_CONFIG
chown -R ldap:ldap /var/lib/ldap/

echo "=== Step 7: Enable and start slapd ==="
systemctl enable --now slapd
systemctl is-active --quiet slapd || { echo "slapd failed to start"; exit 1; }
ss -lt | grep ldap || echo "LDAP listening check skipped."

echo "=== Step 8: Add LDAP schemas (correct order) ==="
cd /etc/openldap/schema/
ldapadd -Y EXTERNAL -H ldapi:/// -f cosine.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f nis.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f inetorgperson.ldif

echo "=== Step 9: Apply LDIF changes ==="
cp /root/ldap/LDAP-PACKAGES/changes.ldif /etc/openldap/
ldapmodify -Y EXTERNAL -H ldapi:/// -f /etc/openldap/changes.ldif

cp /root/ldap/LDAP-PACKAGES/base.ldif /etc/openldap/
if ! ldapsearch -x -b "$LDAP_BASE" -LLL dn | grep -q dn; then
    ldapadd -x -w $LDAP_PASS -D "cn=manager,$LDAP_BASE" -f /etc/openldap/base.ldif
fi

echo "=== Step 9.1: Create required OUs for migration ==="
ldapadd -x -w $LDAP_PASS -D "cn=manager,$LDAP_BASE" <<EOF
dn: ou=Users,$LDAP_BASE
objectClass: organizationalUnit
ou: Users

dn: ou=Groups,$LDAP_BASE
objectClass: organizationalUnit
ou: Groups
EOF

echo "=== Step 10: Create guest users locally ==="
mkdir -p $GUEST_DIR
for i in {1..5}; do
  if ! id ldapuser$i &>/dev/null; then
      useradd -d $GUEST_DIR/ldapuser$i ldapuser$i
      echo "ldapuser$i:$LDAP_PASS" | chpasswd
  fi
done
chmod -R 755 $GUEST_DIR

echo "=== Step 11: Migrate users to LDAP ==="
cp -rf /root/ldap/LDAP-PACKAGES/MigrationTools $MIGRATION_DIR
chmod -R 755 $MIGRATION_DIR/*
cd $MIGRATION_DIR

# Auto-edit migrate_common.ph
sed -i "s/^\$DEFAULT_MAIL_DOMAIN.*/\$DEFAULT_MAIL_DOMAIN = \"$LDAP_DOMAIN\";/" migrate_common.ph
sed -i "s/^\$DEFAULT_BASE.*/\$DEFAULT_BASE = \"$LDAP_BASE\";/" migrate_common.ph

grep ldapuser /etc/passwd > passwd
./migrate_passwd.pl passwd users.ldif

# Fix users LDIF to use correct OU
sed -i "s/cn=Users,dc=tolharadys,dc=net/ou=Users,$LDAP_BASE/g" users.ldif
sed -i '/^krbName:/d;/^objectClass: kerberosSecurityObject/d;/^objectClass: inetLocalMailRecipient/d;/^mailHost:/d;/^mailRoutingAddress:/d' users.ldif
ldapadd -x -w $LDAP_PASS -D "cn=manager,$LDAP_BASE" -f users.ldif

grep ldapuser /etc/group > group
./migrate_group.pl group group.ldif
sed -i "s/cn=Groups,dc=tolharadys,dc=net/ou=Groups,$LDAP_BASE/g" group.ldif
ldapadd -x -w $LDAP_PASS -D "cn=manager,$LDAP_BASE" -f group.ldif

echo "=== Step 12: Configure firewall for LDAP & LDAPS ==="
firewall-cmd --permanent --add-service=ldap
firewall-cmd --permanent --add-service=ldaps
firewall-cmd --reload

echo "=== Step 13: Configure logging ==="
grep -q "local4.* /var/log/ldap.log" /etc/rsyslog.conf || echo "local4.* /var/log/ldap.log" >> /etc/rsyslog.conf
systemctl restart rsyslog.service
systemctl restart slapd

echo "=== Step 14: Install and configure NFS server ==="
dnf install -y nfs-utils rpcbind
if ! grep -q "$GUEST_DIR" /etc/exports; then
    echo "$GUEST_DIR $NFS_ALLOWED_NET(rw,sync)" >> /etc/exports
fi
systemctl enable --now rpcbind nfs-server
showmount -e
firewall-cmd --permanent --add-service=nfs
firewall-cmd --permanent --add-service=rpc-bind
firewall-cmd --permanent --add-service=mountd
firewall-cmd --reload

echo "=== LDAP + NFS auto setup completed successfully! ==="

