#!/bin/bash
# EX200 Updated Automation Check Script (check.sh)
# Author: Rohan (Modified)
# Run as root to verify exam tasks on node1 and node2

NODE1="node1.example.com"
NODE2="node2.example.com"

TOTAL_MARKS=300
PASS_MARKS=210
TOTAL_SCORE=0

# Marks allocation
declare -A MARKS
for i in {1..22}; do
    MARKS[$i]=11   # default 11 marks
done
MARKS[3]=20
MARKS[15]=25
MARKS[16]=25
MARKS[19]=20
MARKS[20]=20
MARKS[21]=20
MARKS[22]=10

echo "===================================="
echo "       EX200 Exam Check Script       "
echo "===================================="
echo "Total Marks : $TOTAL_MARKS"
echo "Pass Marks  : $PASS_MARKS"
echo "Q1–14, Q17, Q18 : 11 marks each (Q3=20)"
echo "Q15 & Q16      : 25 marks each"
echo "Q19, Q20, Q21  : 20 marks each"
echo "Q22            : 10 marks (virtual-guest)"
echo "===================================="

# helper function
run_check() {
    local cmd="$1"
    local qno="$2"
    local node="$3"

    ssh $node "$cmd" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "Q$qno on $node : PASS (+${MARKS[$qno]})"
        TOTAL_SCORE=$((TOTAL_SCORE + MARKS[$qno]))
    else
        echo "Q$qno on $node : FAIL (+0)"
    fi
}

echo "========= Node1 Checks (Q1–Q16) ========="

run_check "hostnamectl status | grep 'node1.example.com'" 1 $NODE1
run_check "yum repolist | grep -E 'BaseOS|AppStream'" 2 $NODE1

EXPECTED_MSG="Cheers to you for a job well done! No one can compare to your creativity and passion."
Q3_RESPONSE=$(ssh $NODE1 "curl -s http://localhost:82")
if [[ "$Q3_RESPONSE" == *"$EXPECTED_MSG"* ]]; then
    echo "Q3 on $NODE1 : PASS (+${MARKS[3]})"
    TOTAL_SCORE=$((TOTAL_SCORE + MARKS[3]))
else
    echo "Q3 on $NODE1 : FAIL (+0)"
fi

ssh $NODE1 "getent group sysadmin | grep -qw natasha && getent group sysadmin | grep -qw harry && getent passwd sarah | grep -q '/sbin/nologin'"
if [ $? -eq 0 ]; then
    echo "Q4 on $NODE1 : PASS (+${MARKS[4]})"
    TOTAL_SCORE=$((TOTAL_SCORE + MARKS[4]))
else
    echo "Q4 on $NODE1 : FAIL (+0)"
fi

ssh $NODE1 "crontab -u natasha -l | grep -q 'EX200 in progress'"
if [ $? -eq 0 ]; then
    echo "Q5 on $NODE1 : PASS (+${MARKS[5]})"
    TOTAL_SCORE=$((TOTAL_SCORE + MARKS[5]))
else
    echo "Q5 on $NODE1 : FAIL (+0)"
fi

ssh $NODE1 "[ -d /home/manager ] && stat -c '%G %A' /home/manager | grep -q 'sysadmin' && stat -c '%A' /home/manager | grep -q 's'"
if [ $? -eq 0 ]; then
    echo "Q6 on $NODE1 : PASS (+${MARKS[6]})"
    TOTAL_SCORE=$((TOTAL_SCORE + MARKS[6]))
else
    echo "Q6 on $NODE1 : FAIL (+0)"
fi

ssh $NODE1 "grep -q 'server classroom.example.com iburst' /etc/chrony.conf && timedatectl show | grep -q 'NTPSynchronized=yes'"
if [ $? -eq 0 ]; then
    echo "Q7 on $NODE1 : PASS (+${MARKS[7]})"
    TOTAL_SCORE=$((TOTAL_SCORE + MARKS[7]))
else
    echo "Q7 on $NODE1 : FAIL (+0)"
fi

PASS8=1
for u in ldapuser1 ldapuser2 ldapuser3 ldapuser4 ldapuser5; do
    ssh $NODE1 "[ $(id -u $u 2>/dev/null) ] && [ -w /home/$u ]" || PASS8=0
done
if [ $PASS8 -eq 1 ]; then
    echo "Q8 on $NODE1 : PASS (+${MARKS[8]})"
    TOTAL_SCORE=$((TOTAL_SCORE + MARKS[8]))
else
    echo "Q8 on $NODE1 : FAIL (+0)"
fi

ssh $NODE1 "id -u alex | grep -q 3456"
if [ $? -eq 0 ]; then
    echo "Q9 on $NODE1 : PASS (+${MARKS[9]})"
    TOTAL_SCORE=$((TOTAL_SCORE + MARKS[9]))
else
    echo "Q9 on $NODE1 : FAIL (+0)"
fi

ssh $NODE1 "[ -d /root/harry-files ] && find /root/harry-files -user harry -perm -4000 | grep -q '.'"
if [ $? -eq 0 ]; then
    echo "Q10 on $NODE1 : PASS (+${MARKS[10]})"
    TOTAL_SCORE=$((TOTAL_SCORE + MARKS[10]))
else
    echo "Q10 on $NODE1 : FAIL (+0)"
fi

ssh $NODE1 "grep -q 'ich' /root/lines"
if [ $? -eq 0 ]; then
    echo "Q12 on $NODE1 : PASS (+${MARKS[12]})"
    TOTAL_SCORE=$((TOTAL_SCORE + MARKS[12]))
else
    echo "Q12 on $NODE1 : FAIL (+0)"
fi

ssh $NODE1 "[ -f /usr/local/backup.tar.bz2 ]"
if [ $? -eq 0 ]; then
    echo "Q13 on $NODE1 : PASS (+${MARKS[13]})"
    TOTAL_SCORE=$((TOTAL_SCORE + MARKS[13]))
else
    echo "Q13 on $NODE1 : FAIL (+0)"
fi

ssh $NODE1 "[ -f /bin/script.sh ] && [ -d /root/d1 ] && find /root/d1 -type f -size +30k -size -50k | grep -q '.'"
if [ $? -eq 0 ]; then
    echo "Q14 on $NODE1 : PASS (+${MARKS[14]})"
    TOTAL_SCORE=$((TOTAL_SCORE + MARKS[14]))
else
    echo "Q14 on $NODE1 : FAIL (+0)"
fi

run_check "podman images | grep process_files" 15 $NODE1
run_check "podman ps -a | grep ascii2pdf" 16 $NODE1

# ================= Node2 Checks (Q17–Q22) =================
echo "========= Node2 Checks (Q17–Q22) ========="

# Q17 placeholder
Q17_SCORE=0

# Q18 check
Q18_SCORE=0
ssh $NODE2 "yum repolist | grep -E 'BaseOS|AppStream'" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Q18 on $NODE2 : PASS (+${MARKS[18]})"
    Q18_SCORE=${MARKS[18]}
else
    echo "Q18 on $NODE2 : FAIL (+0)"
fi

# Q19
Q19_SCORE=0
ssh $NODE2 "lvs myvg/mylv &>/dev/null"
if [ $? -eq 0 ]; then
    SIZE=$(ssh $NODE2 "lvs --noheadings -o LV_SIZE --units m --nosuffix myvg/mylv | xargs | cut -d. -f1")
    if [[ $SIZE -ge 290 && $SIZE -le 330 ]]; then
        echo "Q19 on $NODE2 : PASS (+${MARKS[19]})"
        Q19_SCORE=${MARKS[19]}
    else
        echo "Q19 on $NODE2 : FAIL (+0)"
    fi
else
    echo "Q19 on $NODE2 : FAIL (+0)"
fi

# Q20
Q20_SCORE=0
SWAP_SIZE=$(ssh $NODE2 "lsblk -bno SIZE,TYPE | grep swap | awk '{print \$1/1024/1024}' | cut -d. -f1 | head -1")
if [[ -n "$SWAP_SIZE" ]]; then
    ssh $NODE2 "grep -q swap /etc/fstab"
    if [[ $SWAP_SIZE -ge 500 && $SWAP_SIZE -le 530 && $? -eq 0 ]]; then
        echo "Q20 on $NODE2 : PASS (+${MARKS[20]})"
        Q20_SCORE=${MARKS[20]}
    else
        echo "Q20 on $NODE2 : FAIL (+0)"
    fi
else
    echo "Q20 on $NODE2 : FAIL (+0)"
fi

# Q21
Q21_SCORE=0
ssh $NODE2 "lvs | grep -qw wshare"
if [ $? -eq 0 ]; then
    ssh $NODE2 "grep -q wshare /etc/fstab"
    if [ $? -eq 0 ]; then
        echo "Q21 on $NODE2 : PASS (+${MARKS[21]})"
        Q21_SCORE=${MARKS[21]}
    else
        echo "Q21 on $NODE2 : FAIL (+0)"
    fi
else
    echo "Q21 on $NODE2 : FAIL (+0)"
fi

# Q22
Q22_SCORE=0
PROFILE=$(ssh $NODE2 "tuned-adm active | grep 'Current active profile:' | awk -F': ' '{print \$2}'")
if [[ "$PROFILE" == "virtual-guest" ]]; then
    Q22_SCORE=${MARKS[22]}
    echo "Q22 on $NODE2 : PASS (+$Q22_SCORE)"
else
    echo "Q22 on $NODE2 : FAIL (+0)"
fi

# Q17 auto PASS logic
if (( Q18_SCORE>0 || Q19_SCORE>0 || Q20_SCORE>0 || Q21_SCORE>0 || Q22_SCORE>0 )); then
    Q17_SCORE=${MARKS[17]}
    echo "Q17 on $NODE2 : PASS (+$Q17_SCORE)"
else
    echo "Q17 on $NODE2 : FAIL (+0)"
fi

# Node2 total
TOTAL_SCORE=$((TOTAL_SCORE + Q17_SCORE + Q18_SCORE + Q19_SCORE + Q20_SCORE + Q21_SCORE + Q22_SCORE))

echo "===================================="
echo "FINAL SCORE: $TOTAL_SCORE / $TOTAL_MARKS"
if [ $TOTAL_SCORE -ge $PASS_MARKS ]; then
    echo "RESULT: PASS ✅"
else
    echo "RESULT: FAIL ❌"
fi
