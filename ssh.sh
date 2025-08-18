#!/bin/bash
# =======================================================
# Full Automation 3-Machine Setup with multiple hostnames
# terminal + node1 + node2
# =======================================================

# Root check
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root on terminal"
    exit 1
fi

# === Function to read IP and hostnames ===
read_machine_info() {
    local var_ip=$1
    local var_name=$2
    read -p "Enter $var_name IP: " IP
    read -p "Enter space-separated hostnames for $var_name (first will be primary hostname): " HOSTNAMES
    echo "$IP|$HOSTNAMES"
}

# === Read machine info ===
TERMINAL_INFO=$(read_machine_info "SERVER_IP" "terminal")
NODE1_INFO=$(read_machine_info "NODE1_IP" "node1")
NODE2_INFO=$(read_machine_info "NODE2_IP" "node2")

read -p "SSH username on node1/node2: " SSH_USER

# === Parse IP and hostnames ===
TERMINAL_IP=$(echo $TERMINAL_INFO | cut -d'|' -f1)
TERMINAL_HOSTNAMES=$(echo $TERMINAL_INFO | cut -d'|' -f2)
TERMINAL_PRIMARY=$(echo $TERMINAL_HOSTNAMES | awk '{print $1}')

NODE1_IP=$(echo $NODE1_INFO | cut -d'|' -f1)
NODE1_HOSTNAMES=$(echo $NODE1_INFO | cut -d'|' -f2)
NODE1_PRIMARY=$(echo $NODE1_HOSTNAMES | awk '{print $1}')

NODE2_IP=$(echo $NODE2_INFO | cut -d'|' -f1)
NODE2_HOSTNAMES=$(echo $NODE2_INFO | cut -d'|' -f2)
NODE2_PRIMARY=$(echo $NODE2_HOSTNAMES | awk '{print $1}')

# === Generate /etc/hosts file ===
HOSTS_FILE="/tmp/hosts.tmp"
cat > $HOSTS_FILE <<EOF
$TERMINAL_IP   $TERMINAL_HOSTNAMES
$NODE1_IP      $NODE1_HOSTNAMES
$NODE2_IP      $NODE2_HOSTNAMES
127.0.0.1      localhost
EOF

echo "[+] Generated /etc/hosts file:"
cat $HOSTS_FILE

# === Update terminal /etc/hosts and primary hostname ===
cp $HOSTS_FILE /etc/hosts
hostnamectl set-hostname $TERMINAL_PRIMARY

# === Generate SSH key on terminal if not exists ===
if [ ! -f /root/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
fi

# === Copy /etc/hosts and setup primary hostname on Node1 & Node2 ===
for NODE_IP in $NODE1_IP $NODE2_IP; do
    NODE_PRIMARY=$(grep $NODE_IP $HOSTS_FILE | awk '{print $2}')
    scp $HOSTS_FILE $SSH_USER@$NODE_IP:/tmp/hosts.tmp
    ssh $SSH_USER@$NODE_IP "sudo cp /tmp/hosts.tmp /etc/hosts && sudo hostnamectl set-hostname $NODE_PRIMARY"
done

# === Copy terminal key to Node1 & Node2 for passwordless SSH ===
for NODE_IP in $NODE1_IP $NODE2_IP; do
    ssh-copy-id -i /root/.ssh/id_rsa.pub $SSH_USER@$NODE_IP
done

# === Generate SSH keys on Node1 & Node2 if not exists ===
for NODE_IP in $NODE1_IP $NODE2_IP; do
    ssh $SSH_USER@$NODE_IP "if [ ! -f /home/$SSH_USER/.ssh/id_rsa ]; then ssh-keygen -t rsa -N '' -f /home/$SSH_USER/.ssh/id_rsa; fi"
done

# === Node1 ↔ Node2 key exchange ===
ssh $SSH_USER@$NODE1_IP "cat /home/$SSH_USER/.ssh/id_rsa.pub" | ssh $SSH_USER@$NODE2_IP "cat >> /home/$SSH_USER/.ssh/authorized_keys"
ssh $SSH_USER@$NODE2_IP "cat /home/$SSH_USER/.ssh/id_rsa.pub" | ssh $SSH_USER@$NODE1_IP "cat >> /home/$SSH_USER/.ssh/authorized_keys"

# === Test passwordless SSH ===
echo "[+] Testing passwordless SSH:"
ssh $SSH_USER@$NODE1_IP "hostname; echo 'SSH terminal -> node1 works!'"
ssh $SSH_USER@$NODE2_IP "hostname; echo 'SSH terminal -> node2 works!'"
ssh $SSH_USER@$NODE1_IP "ssh $SSH_USER@$NODE2_IP 'hostname; echo SSH node1 -> node2 works!'"
ssh $SSH_USER@$NODE2_IP "ssh $SSH_USER@$NODE1_IP 'hostname; echo SSH node2 -> node1 works!'"

echo "=============================="
echo " 3-Machine full automation setup completed successfully!"
echo "=============================="

