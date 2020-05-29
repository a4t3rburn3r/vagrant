# CentOS software raid deployment

Vagrantfile deploys bento/centos7, adds second disk and migrates OS to mdadm raid 1 mirror without reboot.

Additional adds 4 disks and builds raid 10 with 5 GPT partitions, then mounts them to /mnt.