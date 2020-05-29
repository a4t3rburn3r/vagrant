#!/bin/sh -eux

# correcting dns server coz nat interface gets from DHCP own data
sed -i "/nameserver/s/^/#/" /etc/resolv.conf
sed -i "/search/s/^/#/" /etc/resolv.conf
echo "nameserver 10.0.51.100" >> /etc/resolv.conf
echo "domain test.lab" >> /etc/resolv.conf
echo "search test.lab" >> /etc/resolv.conf

# ===================
# Kerberos NFS server

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
echo "nfs/nfs-server.test.lab" >> /tmp/rand_principals
echo "host/nfs-server.test.lab" >> /tmp/rand_principals
# creating kerberos principal list for keytab file
echo "nfs/nfs-server.test.lab" >> /tmp/keytab_principals
echo "host/nfs-server.test.lab" >> /tmp/keytab_principals

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
# NFS server

# installing nfs and rpc servers
yum install rpcbind nfs-utils -y

# enabling and starting daemons
systemctl enable rpcbind nfs-server
systemctl start rpcbind nfs-server

# correcting for production server processes to 32 minimum
cp /etc/sysconfig/nfs /etc/sysconfig/nfs_bak
sed -i "s/#RPCNFSDCOUNT=16/RPCNFSDCOUNT=32/g" /etc/sysconfig/nfs

# switching to nfs v3
cp /etc/nfsmount.conf /etc/nfsmount.conf_bak
sed -i "s/# Defaultvers=4/Defaultvers=3/g" /etc/nfsmount.conf
sed -i "s/# Nfsvers=4/Nfsvers=3/g" /etc/nfsmount.conf
echo "#" >> /etc/sysconfig/nfs
echo "# Switch version to 3" >> /etc/sysconfig/nfs
echo 'MOUNTD_NFS_V3="yes"' >> /etc/sysconfig/nfs
echo 'SECURE_NFS="yes"' >> /etc/sysconfig/nfs

# creating export directories
mkdir -p /mnt/nfs/pub/uploads
chown -R nfsnobody:nfsnobody /mnt/nfs/pub
chmod 0555 /mnt/nfs/pub
chmod 0777 /mnt/nfs/pub/uploads
# setting priority fsid to 1 for uploads gives rw access, coz parent ro export directory settings overwrites child rw
echo "/mnt/nfs/pub nfs-client.test.lab(ro,sync,all_squash,no_subtree_check,sec=sys:krb5p,fsid=2)" >> /etc/exports
echo "/mnt/nfs/pub/uploads nfs-client.test.lab(rw,sync,root_squash,no_subtree_check,sec=sys:krb5p,fsid=1)" >> /etc/exports
exportfs -avr
systemctl restart nfs-server rpcbind

# to check if nfs is working use rpcinfo -s
# to check exported directiries use exportfs -v

# ========
# Firewall
# nfs-server firewall
# eth0 - public (ssh)
# eth1 - dmz (nfs nfs3 mountd rpc-bind ssh)

systemctl enable firewalld
sleep 3
systemctl start firewalld
sleep 3
firewall-cmd --permanent --zone=dmz --change-interface=eth1
sleep 3
for service_name in nfs nfs3 mountd rpc-bind
  do
    firewall-cmd --permanent --zone=dmz --add-service=${service_name} && firewall-cmd --reload
  done
