#!/bin/bash
#
# Author: Burke Azbill
# Target OS: Photon OS 1.0 (https://vmware.github.io/photon/)
# https://github.com/burkeazbill/util-01a
# 
# This file is for use when testing PhotonOS 
#
# Add some important tools
tdnf install -y gawk git ntp sudo tar
# Disable password complexity
sed -i '/pam_cracklib.so/s/^/# /' /etc/pam.d/system-password
echo 'root:VMware1!' | chpasswd
## Set root pw to never expire
chage -M 99999 root

#Prepare Docker
systemctl enable docker
systemctl start docker
curl -L https://github.com/docker/compose/releases/download/1.8.1/docker-compose-`uname -s`-`uname -m` > /usr/bin/docker-compose
chmod +x /usr/bin/docker-compose

# Prepare Docker aliases for ANYONE that logs into VM:
touch /etc/profile.d/alias.sh
chmod 644 /etc/profile.d/alias.sh
echo alias rmcontainers= > /etc/profile.d/alias.sh
echo alias rmimages= >> /etc/profile.d/alias.sh
echo alias rmvolumes= >> /etc/profile.d/alias.sh
sed -i '/rmcontainers=/s/$/\x27docker stop $(docker ps -a -q); docker rm $(docker ps -a -q)\x27/' /etc/profile.d/alias.sh
sed -i '/rmimages=/s/$/\x27docker rmi $(docker images -q)\x27/' /etc/profile.d/alias.sh
sed -i '/rmvolumes=/s/$/\x27docker  volume rm $(docker volume ls -f dangling=true -q)\x27/' /etc/profile.d/alias.sh

## Optionally add the txts command https://github.com/armandino/TxtStyle 
# for colorizing console text - just uncomment the following lines:
#git clone git://github.com/armandino/TxtStyle.git
#cd TxtStyle
#python setup.py install
#ps -u | txts -n ps #Example output
#echo Visit https://github.com/armandino/TxtStyle for more info!

# Optionally install color cat (ccat) https://github.com/jingweno/ccat
# Just uncomment the following lines:
#tdnf install -y go # install pre-req
#source /etc/profile # Re-load profile to set necessary environment variables
#ln -s /usr/share/gocode/bin/ccat /usr/local/bin/ccat # create symbolic link for the ccat command
