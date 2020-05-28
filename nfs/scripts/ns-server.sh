#!/bin/sh -eux

# ===
# DNS

# installing bind
yum install bind -y

# configuring bind service
cp /etc/named.conf /etc/named.conf_bak
sed -i "s/listen-on port 53 { 127.0.0.1; };/listen-on port 53 { 127.0.0.1; 10.0.51.100; };/g" /etc/named.conf
sed -i "s#allow-query     { localhost; };#allow-query     { localhost; 10.0.51.0/24; };#g" /etc/named.conf
sed -i "s/dnssec-validation yes;/dnssec-validation no;/g" /etc/named.conf
sed -i "s/\trecursion yes;/\trecursion yes;\n\tforward only;\n\tforwarders { 208.67.222.222; 208.67.220.220; };\n/g" /etc/named.conf
sed -i 's/zone "." IN {/zone "test.lab" {\n\ttype master;\n\tfile "test.lab.zone";\n\tallow-update { none; };\n};\n\nzone "51.0.10.in-addr.arpa" {\n\ttype master;\n\tfile "test.lab.revzone";\n\tallow-update { none; };\n};\n\nzone "." IN {/g' /etc/named.conf

# creatinf forward zone
cat <<EOF >/var/named/test.lab.zone
\$TTL 86400
@ IN SOA ns-server.test.lab. test.lab. (
 2020052401 ; Serial
 1d ; refresh
 2h ; retry
 4w ; expire
 1h ) ; min cache
 IN NS ns-server.test.lab.

ns-server  IN A 10.0.51.100
nfs-server IN A 10.0.51.101
nfs-client IN A 10.0.51.102
EOF

# creating revers zone
cat <<EOF >/var/named/test.lab.revzone
\$TTL 86400
@ IN SOA ns-server.test.lab. test.lab. (
 2020052401 ; Serial
 1d ; refresh
 2h ; retry
 4w ; expire
 1h ) ; min cache
 IN NS ns-server.test.lab.

100 IN PTR ns-server.test.lab.
101 IN PTR nfs-server.test.lab.
102 IN PTR nfs-client.test.lab.
EOF

# enabling and starting dns service
systemctl enable named && systemctl start named

# correcting dns server coz nat interface gets from DHCP own data
sed -i "/nameserver/s/^/#/" /etc/resolv.conf
sed -i "/search/s/^/#/" /etc/resolv.conf
echo "nameserver 10.0.51.100" >> /etc/resolv.conf
echo "domain test.lab" >> /etc/resolv.conf
echo "search test.lab" >> /etc/resolv.conf

# ================
# Kerberos service

# installing server, client and pam module
yum install krb5-server krb5-workstation pam_krb5 time -y

# backup current kdc config
cp /var/kerberos/krb5kdc/kdc.conf /var/kerberos/krb5kdc/kdc.conf_bak
# configuring realm and disabling kerberos 4
# by enforcing aes-256 and enabling client obligatory preauthentication befor getting ticket
sed -i "s/EXAMPLE.COM/TEST.LAB/g" /var/kerberos/krb5kdc/kdc.conf
sed -i "s/#master_key_type = aes256-cts/master_key_type = aes256-cts\n  default_principal_flags = +preauth\n/g" /var/kerberos/krb5kdc/kdc.conf

# backup acl config and correct domain access rights to kerberos database
cp /var/kerberos/krb5kdc/kadm5.acl /var/kerberos/krb5kdc/kadm5.acl_bak
sed -i "s/EXAMPLE.COM/TEST.LAB/g" /var/kerberos/krb5kdc/kadm5.acl

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

# creating kerberos database
kdb5_util create -s -r TEST.LAB -P testlabdp

# start end enable kerberos
systemctl enable krb5kdc kadmin
systemctl start krb5kdc kadmin

# creating kerberos principal list with passwords
echo "root/admin adminp" >> /tmp/principals
echo "vagrant vagrant" >> /tmp/principals
# creating kerberos principal list for random keys
echo "host/ns-server.test.lab" >> /tmp/rand_principals
# creating kerberos principal list for keytab file
echo "host/ns-server.test.lab" >> /tmp/keytab_principals

# this thing i peeked from oracle kerberos manual
# automatic prinicipal creation
awk '{ print "ank -pw", $2, $1 }' < /tmp/principals | time /usr/sbin/kadmin.local > /dev/null
awk '{ print "ank -randkey", $1 }' < /tmp/rand_principals | time /usr/sbin/kadmin.local > /dev/null
# automatic add principals to keytab file
# coz service can not type password by yourself =)
awk '{ print "ktadd", $1 }' < /tmp/keytab_principals | time /usr/sbin/kadmin.local > /dev/null

rm -f rm /tmp/*principals

authconfig --enablekrb5 --update

# ssh kerberos authentication
cp /etc/ssh/sshd_config /etc/ssh/sshd_config_bak
cp /etc/ssh/ssh_config /etc/ssh/ssh_config_bak
sed -i "s/GSSAPIAuthentication no/GSSAPIAuthentication yes/g" /etc/ssh/sshd_config
sed -i "s/#GSSAPIStrictAcceptorCheck yes/GSSAPIStrictAcceptorCheck no/g" /etc/ssh/sshd_config
sed -i "s/\tGSSAPIAuthentication yes/\tGSSAPIAuthentication yes\n\tGSSAPIDelegateCredentials yes\n/g" /etc/ssh/ssh_config
systemctl reload sshd

# ========
# Firewall
# ns-server firewall
# eth0 - public (ssh)
# eth1 - dmz (dns kadmin kpasswd kerberos ssh)
systemctl enable firewalld
sleep 3
systemctl start firewalld
sleep 3
firewall-cmd --permanent --zone=dmz --change-interface=eth1
sleep 3
for service_name in dns kerberos kadmin kpasswd
  do
    firewall-cmd --permanent --zone=dmz --add-service=${service_name} && firewall-cmd --reload
  done
