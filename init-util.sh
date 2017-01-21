#!/bin/bash
#
# Author: Burke Azbill
# Target OS: Photon OS 1.0 (https://vmware.github.io/photon/)
# https://github.com/burkeazbill/util-01a
# 
# 

# Update system
tdnf -y upgrade
tdnf install -y gawk git ntp sudo

#### Configure util VM user accounts
# Disable password complexity
sed -i '/pam_cracklib.so/s/^/# /' /etc/pam.d/system-password
echo 'root:VMware1!' | chpasswd
## Set root pw to never expire
chage -M 99999 root
## Setup jenkins user/data directory
groupadd -g 1000 jenkins
useradd -d /srv/jenkins -u 1000 -g 1000 -m -s /bin/bash jenkins
chage -M 99999 jenkins
## Setup holadmin user - for SSH and sudo
useradd -d /home/holadmin -m holadmin
echo 'holadmin:VMware1!' | chpasswd
chage -M 99999 holadmin
usermod -aG wheel holadmin

# Set Photon OS to use static IP:
# For VMware Hands On Labs use, nested VMs should be
# on 192.168.120.0 network. Assigning static ip here
# Be sure to setup DNS entries for 192.168.120.91
# for: gitlab.rainpole.com, mail.rainpole.com, util-01a.rainpole.com and util-01a.corp.local 
cat > /etc/systemd/network/10-eth0-static-en.network << "EOF"
[Match]
Name=eth0

[Network]
Address=192.168.120.91/24
Gateway=192.168.120.1
DNS=192.168.110.10

[DHCP]
UseDNS=false
EOF
chmod 644 /etc/systemd/network/10-eth0-static-en.network
# Disable DHCP:
# sed -i 's/DHCP=.*/DHCP=no/' /etc/systemd/network/10-dhcp-en.network
rm -f /etc/systemd/network/10-dhcp-en.network

# Now restart the network service to apply all changes:
systemctl daemon-reload
systemctl restart systemd-networkd

# Insert pod NTP Server at top of ntp.conf:
sed -i '1s/^/server ntp.corp.local \n/' /etc/ntp.conf

# Enable/Start ntpd
systemctl enable ntpd
systemctl start ntpd
# Check time:
ntpq -p
# Expected output:
# remote           refid      st t when poll reach   delay   offset  jitter
# ==============================================================================
# *router.corp.loc LOCAL(1)         6 u   61   64    1    1.235    0.327   0.001

# Set Hostname:
hostnamectl set-hostname util-01a.corp.local

#Prepare Docker
systemctl enabled docker
systemctl start docker
curl -L https://github.com/docker/compose/releases/download/1.8.1/docker-compose-`uname -s`-`uname -m` > /usr/bin/docker-compose
chmod +x /usr/bin/docker-compose

# Prepare Docker aliases for ANYONE that logs into VM:
touch /etc/profile.d/alias.sh
chmod 644 /etc/profile.d/alias.sh
echo alias rmcontainers= > /etc/profile.d/alias.sh
echo alias rmimages= >> /etc/profile.d/alias.sh
sed -i '/rmcontainers=/s/$/\x27docker stop $(docker ps -a -q); docker rm $(docker ps -a -q)\x27/' /etc/profile.d/alias.sh
sed -i '/rmimages=/s/$/\x27docker rmi $(docker images -q)\x27/' /etc/profile.d/alias.sh

# Import ControlCenter public auth key to authorized_keys
echo ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAp7fYaIex88KRGhNWTYIwqJn/jtDp9ZV71WtBSpi9/LFhMh0f87n+W8Ms3QgA2WdEcTJRLoc3blHGo3a6TIqDGuVmGwgJjXpQA65aHjQS5P3gv86vDELuTlKev3BumcvmqpGeoyKY4zn4RLtdiWDCLI+rMEkWAPyV7RbbNzuaJoQUKTdfv1iBfWo0thoQzTj9KluTgM6FWXz7iyNB4J7NXIeYfxfbQgl3mAGdQkc11cgrnfFfjIRVA/nE5pUbOErJ9cUEMscb5iXMPQvs2zKcfZ0FYd4+TwfRpPwzYVC/vmS9kO7jrGQbtkOzTyf1GqOXCQ4URX2cPWS4zthXS5gm5Q== controlcenter > ~/.ssh/authorized_keys

# Update ssh to NOT allow root
# Change PermitRootLogin to “no” in /etc/ssh/sshd_config
sed -i 's/PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
# Uncomment the line that prohibits password authentication for root:
sed -i '/^#.* prohibit/s/^#//' /etc/ssh/sshd_config
# End result: root can only ssh with key based authentication

systemctl restart sshd

# Update sudoers to not prompt for pw and execute all commands for %wheel group members
# Get the line numbers of this entry in sudoers file
line=$(sed -n '/%wheel ALL=(ALL) ALL/=' /etc/sudoers);
# Get the line number of the second occurance of that string
line=$(echo $line | cut -d " " -f 2)
# Now replace that line with an updated line: -- using double quotes to allow variable to be translated!
sed -i "${line} s/%wheel ALL=(ALL) ALL/%wheel ALL=(ALL) NOPASSWD: ALL/" /etc/sudoers

#################################################################### Prepare for GitLab: ####################################################################
mkdir -p /srv/gitlab/gitlab /srv/gitlab/redis /srv/gitlab/postgresql
mkdir -p /root/git
cd /root/git
git clone https://github.com/gitlabhq/omnibus-gitlab.git
mv omnibus-gitlab gitlab
cd gitlab/docker
# Delete the port 443 mapping:
sed -i '/443:443/d' ./docker-compose.yml
# change the port 80 mapping to port 82:
sed -i 's/80:80/82:80/g'  ./docker-compose.yml
# change the port 22 mapping to port 1022:
sed -i 's/22:22/1022:22/'  ./docker-compose.yml
sed -i 's/https/http/g'  ./docker-compose.yml
sed -i 's/gitlab.example.com/gitlab.rainpole.com/g'  ./docker-compose.yml
sed -i '/hostname:/a\ \ container_name: "gitlab"' ./docker-compose.yml
# Build and launch Container:
docker-compose up -d
#### Additional Gitlab Notes:
# GitLab URL: http://gitlab.rainpole.com:82
# Initial page load will prompt for PW - set to VMware1!
# Login as root / VMware1!
# Create a Group(s)
# Update e-mail address of root to administrator@corp.local (or as desired)

#################################################################### Prepare for iRedMail ####################################################################
#
# TO DO: Update /etc/postfix/helo_access.pcre to comment out the following line:
# /(\.local)$/ REJECT ACCESS DENIED. Your email was rejected because the sending mail server does not identify itself correctly (${1})
# 
# Also remove the following plug-ins from /opt/iredapd/settings.py
# "reject_null_sender", "reject_sender_login_mismatch", "greylisting", amavisd_wblist"
# The line should result in the following:
# plugins = ["throttle", "sql_alias_access_policy"]

mkdir -p /srv/iredmail/vmail
cd ~/git
git clone https://github.com/burkeazbill/docker-iredmail.git
mv docker-iredmail iredmail
cd iredmail
# Update iredmail.cfg file for HOL vPod use:
sed -i 's/yourdomain.lab/rainpole.com/g' ./iredmail.cfg
# Note the use of single quote on next line - this is due to ! being special char
sed -i 's/Passw0rd!/VMware1!/g' ./iredmail.cfg
sed -i 's/x.x.x.x/192.168.110.10/g' ./iredmail.cfg
sed -i 's/domain2.lab domain3.lab/corp.local abigtelco.com/g' ./iredmail.cfg
sed -i 's/# NTPSERVER=.*/NTPSERVER="ntp.corp.local"/g' ./iredmail.cfg
sed -i 's/PRIMARY_DOMAIN_USERS=.*/PRIMARY_DOMAIN_USERS="administrator ceo cfo cio cloudadmin cmo devmgr devuser ecomops epa infosec itmgr itop-notification gitlab jdev ldev loginsight projmgr rpadmin"/g' ./iredmail.cfg
# Update docker-compose file with hostname:
sed -i 's/utility/mail.rainpole.com/g' ./docker-compose.yml
# now, add two lines to the iredmail.sh script to add all the primary domain users to the corp.local domain as well
sed -i '/duration=/i\ \ \ \ \ \ \ \ /bin/bash create_mail_user_SQL.sh corp.local $PRIMARY_DOMAIN_USERS' iredmail/iredmail.sh
sed -i '/duration=/i\ \ \ \ \ \ \ \ /usr/bin/mysql -uroot -p$PASSWD vmail < /opt/iredmail/iRedMail-$IREDMAIL_VERSION/tools/output.sql' iredmail/iredmail.sh
# Build and launch Container:
docker-compose up -d
#### Additional iRedMail Notes:
# Webmail Administration: http://mail.rainpole.com/iredadmin
# Login as postmaster@rainpole.com / VMware1!
#
# Webmail URL: http://mail.rainpole.com


#################################################################### Now do Jenkins ####################################################################
mkdir -p /srv/jenkins
cd ~/git
git clone https://github.com/jenkinsci/docker.git
mv docker jenkins
cd jenkins
sed -i '/build:/a\ \ container_name: "jenkins"' ./docker-compose.yml
sed -i '/jenkins_home/d' ./docker-compose.yml
sed -i '/volumes/a\ \ \ \ - /srv/jenkins:/var/jenkins_home' ./docker-compose.yml
sed -i 's/git curl/git ntp curl/' ./Dockerfile
#  TO DO !!!
#

#################################################################### Artifactory ?? ####################################################################

#################################################################### Harbor ?? ####################################################################

#################################################################### Other(s) ?? ####################################################################
echo If all went well, http://gitlab.rainpole.com:82 should load
echo Webmail admin should eventually load at http://mail.rainpole.com/iredadmin (iredmail takes a while to finish loading - ie: 20 min or so)
echo Webmail client should eventually load at http://mail.rainpole.com/
echo Make sure to setup NTP inside each of the containers. See notes in http://bit.ly/util-01a for details from Burke on how to do this
