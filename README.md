# vagrant

Vagrantfiles and scripts

## centos-7-mdadm

Vagrantfile that deploys bento/centos7, adds second disk and migrates OS to mdadm raid 1 without reboot.
Additional adds 4 disks and builds raid 10 with 5 partitions, then mounts them to /mnt.

## centos-7 kerberized nfs and ssh

Vagrantfile and scripts to deploy nfs storage with kerberos authentication and traffic encryption. After deployment there will be 3 servers:

- ns-server (bind + kerberos kdc)
- nfs-server (nfs v3 with udp support)
- nfs-client

All servers have 2 NICs:

- eth0 (public for first initialization, updates and software installation)
- eth1 (dmz for domain traffic)

Use:

```bash
firewall-cmd --get-active-zone
firewall-cmd --zone-dmz --list-all
```

to see firewall configuration.

Working domain is TEST.LAB.

After deployment SSH access will work using kerberos authentication without password. Just get ticket and go. Default user vagrant(password: vagrant) are already added as principal in kerberos DB. So steps for vagrant user are:

```shell
(nfs-client)$ kinit
(nfs-client)$ ssh ns-server.test.lab (or any other server in domain)
(nfs-client)$ klist (will show granted tickets)
```

Server **nfs-client.test.lab** will authomaticaly mount 2 nfs shared directories from **nfs-server.test.lab**:

- /mnt/nfs/pub (ro, withouth kerberos auth over udp protocol)
- /mnt/nfs/pub/uploads (rw, with kerberos privacy over tcp protocol)

To get access from general non-priveleged user (default vagrant) to uploads share, get ticket like in ssh example:

```shell
(nfs-client)$ kinit
(nfs-client)$ ls -l /mnt/nfs/pub
(nfs-client)$ ls -l /mnt/nfs/pub/uploads
```

> Note!\
> Kerberos privacy works only over tcp protocol. To switch from tcp to udp under nfs3, use proto=udp,sec=sys in mount options on nfs-client. Probably this is due to redhat nfs realization, so kerberos over udp works in some releases of rhel, but state is unknown. Bug was reported, but closed by red hat in 2013 - <https://bugzilla.redhat.com/show_bug.cgi?id=681929>
