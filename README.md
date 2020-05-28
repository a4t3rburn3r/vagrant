# vagrant
Vagrantfiles and scripts

## centos-7-mdadm
Vagrantfile that deploys bento/centos7, adds second disk and migrates OS to mdadm raid 1 without reboot.
Additional adds 4 disks and builds raid 10 with 5 partitions, then mounts them to /mnt.
