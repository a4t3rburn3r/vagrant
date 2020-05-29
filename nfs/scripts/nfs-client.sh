#!/bin/sh -eux

# correcting dns server coz nat interface gets from DHCP own data
sed -i "/nameserver/s/^/#/" /etc/resolv.conf
sed -i "/search/s/^/#/" /etc/resolv.conf
echo "nameserver 10.0.51.100" >> /etc/resolv.conf
echo "domain test.lab" >> /etc/resolv.conf
echo "search test.lab" >> /etc/resolv.conf

# ===================
# Kerberos NFS client

# installing server, client and pam module
yum install krb5-workstation pam_krb5 time -y

# backup current realm config
cp /etc/krb5.conf /etc/krb5.conf_bak
# changing default realm from EXAMPLE.COM to working realm and kdc server
sed -i "s/# default_realm = EXAMPLE.COM/ default_realm = TEST.LAB/g" /etc/krb5.conf
sed -i "s/# EXAMPLE.COM = {/ TEST.LAB = {/g" /etc/krb5.conf
sed -i "s/#  kdc = kerberos.example.com/  kdc = ns-server.test.lab/g" /etc/krb5.conf
sed -i "s/#  admin_server = kerberos.example.com/  admin_server = ns-server.test.lab/g" /etc/krb5.conf
sed -i "s/# }/ }/g" /etc/krb5.conf
sed -i "s/# .example.com = EXAMPLE.COM/ .test.lab = TEST.LAB/g" /etc/krb5.conf
sed -i "s/# example.com = EXAMPLE.COM/ test.lab = TEST.LAB/g" /etc/krb5.conf

# creating kerberos principal list for random keys
echo "nfs/nfs-client.test.lab" >> /tmp/rand_principals
echo "host/nfs-client.test.lab" >> /tmp/rand_principals
# creating kerberos principal list for keytab file
echo "nfs/nfs-client.test.lab" >> /tmp/keytab_principals
echo "host/nfs-client.test.lab" >> /tmp/keytab_principals

# this thing i peeked from oracle kerberos manual
# automatic prinicipal creation
awk '{ print "ank -randkey", $1 }' < /tmp/rand_principals | time kadmin -p root/admin -w adminp > /dev/null
# automatic add principals to keytab file
# coz service can not type password by yourself =)
awk '{ print "ktadd", $1 }' < /tmp/keytab_principals | time kadmin -p root/admin -w adminp > /dev/null

rm -f /tmp/*principals

authconfig --enablekrb5 --update

# ssh kerberos authentication
cp /etc/ssh/sshd_config /etc/ssh/sshd_config_bak
cp /etc/ssh/ssh_config /etc/ssh/ssh_config_bak
sed -i "s/GSSAPIAuthentication no/GSSAPIAuthentication yes/g" /etc/ssh/sshd_config
sed -i "s/#GSSAPIStrictAcceptorCheck yes/GSSAPIStrictAcceptorCheck no/g" /etc/ssh/sshd_config
sed -i "s/\tGSSAPIAuthentication yes/\tGSSAPIAuthentication yes\n\tGSSAPIDelegateCredentials yes\n/g" /etc/ssh/ssh_config
systemctl reload sshd

# ==========
# NFS client

# installing nfs and rpc servers
yum install nfs-utils -y

# creating directory structure and mounting resources
mkdir -p /mnt/nfs/pub
echo "nfs-server.test.lab:/mnt/nfs/pub /mnt/nfs/pub nfs ro,hard,sync,intr,nosuid,noexec,noac,nfsvers=3,proto=udp,sec=sys 0 0" >> /etc/fstab
echo "nfs-server.test.lab:/mnt/nfs/pub/uploads /mnt/nfs/pub/uploads nfs rw,hard,sync,intr,nosuid,noexec,noac,nfsvers=3,proto=tcp,sec=krb5p 0 0" >> /etc/fstab
systemctl restart nfs
mount -a

# to check if server accepts v3 udp connection use rpcinfo -u nfs-server.test.lab nfs
# to see exported folders use showmount -e nfs-server.test.lab

# ========
# Firewall
# nfs-client firewall
# eth0 - public (ssh)
# eth1 - dmz (ssh)
systemctl enable firewalld
sleep 3
systemctl start firewalld
sleep 3
firewall-cmd --permanent --zone=dmz --change-interface=eth1
firewall-cmd --reload
