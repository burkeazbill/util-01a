#!/bin/bash
#
# Author: Burke Azbill
# Target OS: Photon OS 2.0 (https://vmware.github.io/photon/)
# https://github.com/burkeazbill/util-01a
# 
# 

# Set ENV variables:
export docker_compose_version=1.22.0

# Update system
echo "updating system..."
tdnf -y upgrade
echo "Installing awk, git, ntp, and sudo"
tdnf install -y gawk git ntp sudo tar gzip iputils

# Colorize the prompt and add aliases
cat > /etc/profile.d/alias.sh << "EOF"
# Setup Docker aliases
alias rmcontainers='docker stop $(docker ps -a -q); docker rm $(docker ps -a -q)'
alias rmimages='docker rmi $(docker images -q)'
alias rmvolumes='docker volume rm $(docker volume ls -q -f dangling=true)'
alias cleanimages='docker rmi $(docker images -q -f dangling=true)'

# Colorize the console:
alias less='less --RAW-CONTROL-CHARS'
alias ls='ls --color=auto'

# Colorize the prompt: (source: Michael Durant reply here: https://unix.stackexchange.com/questions/148/colorizing-your-terminal-and-shell-environment)
git_branch () { git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/'; }
HOST='\033[02;36m\]\h'; HOST=' '$HOST
TIME='\033[01;31m\]\t \033[01;32m\]'
LOCATION=' \033[01;34m\]`pwd | sed "s#\(/[^/]\{1,\}/[^/]\{1,\}/[^/]\{1,\}/\).*\(/[^/]\{1,\}/[^/]\{1,\}\)/\{0,1\}#\1_\2#g"`'
BRANCH=' \033[00;33m\]$(git_branch)\[\033[00m\]\n\$ '
PS1=$TIME$USER$HOST$LOCATION$BRANCH
PS2='\[\033[01;36m\]>'
EOF
chmod 644 /etc/profile.d/alias.sh

#### Configure util VM user accounts
echo "Disabling password complexity"
sed -i '/pam_cracklib.so/s/^/# /' /etc/pam.d/system-password
echo 'root:VMware1!' | chpasswd
## Set root pw to never expire
chage -M -1 root

echo "adding jenkins and holadmin users..."
## Setup jenkins user/data directory
groupadd -g 1000 jenkins
useradd -d /srv/jenkins -u 1000 -g 1000 -m -s /bin/bash jenkins
chage -M -1 jenkins
## Setup holadmin user - for SSH and sudo
useradd -d /home/holadmin -m holadmin
echo 'holadmin:VMware1!' | chpasswd
chage -M 9999-19 holadmin
usermod -aG wheel holadmin

echo "Reconfiguring network..."
# Disable DHCP:
# sed -i 's/DHCP=.*/DHCP=no/' /etc/systemd/network/10-dhcp-en.network
# rm -f /etc/systemd/network/10-dhcp-en.network
# Remove all existing network configurations, it will be re-built later in this script
rm -f /etc/systemd/network/*.network

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

# Now restart the network service to apply all changes:
systemctl daemon-reload
systemctl restart systemd-networkd

echo "Configuring NTP"
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

echo "Preparing Docker"
echo "Cleaning up old docker and installing new..."
# Can find latest static binaries here: https://download.docker.com/linux/static/stable/x86_64/
tdnf erase -y docker
curl -L'#' https://download.docker.com/linux/static/stable/x86_64/docker-18.03.1-ce.tgz | tar --strip-components=1 -C /usr/bin -xzf - 

groupadd -r docker

echo '[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network.target docker.socket
Requires=docker.socket

[Service]
Type=notify
ExecStart=/usr/bin/dockerd -H fd:// -s overlay2 
ExecReload=/bin/kill -s HUP $MAINPID
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target
' > /etc/systemd/system/docker.service

echo '[Unit]
Description=Docker Socket for the API
PartOf=docker.service

[Socket]
ListenStream=/var/run/docker.sock
SocketMode=0660
SocketUser=root
SocketGroup=docker

[Install]
WantedBy=sockets.target
' > /etc/systemd/system/docker.socket

systemctl enable docker
systemctl start docker
# Find current releases od docker-compose here: https://github.com/docker/compose/releases
curl -L https://github.com/docker/compose/releases/download/$docker_compose_version/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Prepare Docker aliases for ANYONE that logs into VM:
#touch /etc/profile.d/alias.sh
#chmod 644 /etc/profile.d/alias.sh
#echo alias rmcontainers= > /etc/profile.d/alias.sh
#echo alias rmimages= >> /etc/profile.d/alias.sh
#echo alias rmvolumes= >> /etc/profile.d/alias.sh
#sed -i '/rmcontainers=/s/$/\x27docker stop $(docker ps -a -q); docker rm $(docker ps -a -q)\x27/' /etc/profile.d/alias.sh
#sed -i '/rmimages=/s/$/\x27docker rmi $(docker images -q)\x27/' /etc/profile.d/alias.sh
#sed -i '/rmvolumes=/s/$/\x27docker  volume rm $(docker volume ls -f dangling=true -q)\x27/' /etc/profile.d/alias.sh

echo "Imporing ControlCenter public auth key to authorized_keys"
echo ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAp7fYaIex88KRGhNWTYIwqJn/jtDp9ZV71WtBSpi9/LFhMh0f87n+W8Ms3QgA2WdEcTJRLoc3blHGo3a6TIqDGuVmGwgJjXpQA65aHjQS5P3gv86vDELuTlKev3BumcvmqpGeoyKY4zn4RLtdiWDCLI+rMEkWAPyV7RbbNzuaJoQUKTdfv1iBfWo0thoQzTj9KluTgM6FWXz7iyNB4J7NXIeYfxfbQgl3mAGdQkc11cgrnfFfjIRVA/nE5pUbOErJ9cUEMscb5iXMPQvs2zKcfZ0FYd4+TwfRpPwzYVC/vmS9kO7jrGQbtkOzTyf1GqOXCQ4URX2cPWS4zthXS5gm5Q== controlcenter > ~/.ssh/authorized_keys

echo "Reconfiguring SSH to allow root - only key based auth"
# Update ssh to NOT allow root to ssh with password (must use key)
# Change PermitRootLogin to “yes” in /etc/ssh/sshd_config
sed -i 's/PermitRootLogin no/PermitRootLogin yes/g' /etc/ssh/sshd_config
# Uncomment the line that prohibits password authentication for root:
sed -i '/^#.* prohibit/s/^#//' /etc/ssh/sshd_config
# Change the Port from default of 22 to custom 1022:
sed -i 's/#Port 22/Port 1022/g' /etc/ssh/sshd_config
# Open firewall port 1022:
# Rules must be added to the iptables script file in order to be available
# after a reboot
echo iptables -I INPUT -p tcp --dport 1022 -j accept >> /etc/systemd/scripts/iptables

# OPTIONAL: Allow for ping and ping response (default firewall rule blocks ICMP requests)
echo iptables -A OUTPUT -p icmp -j ACCEPT >> /etc/systemd/scripts/iptables
echo iptables -A INPUT -p icmp -j ACCEPT >> /etc/systemd/scripts/iptables

# End result: root can only ssh with key based authentication on port 1022
systemctl restart sshd

# Update sudoers to not prompt for pw and execute all commands for %wheel group members
# Get the line numbers of this entry in sudoers file
line=$(sed -n '/%wheel ALL=(ALL) ALL/=' /etc/sudoers);
# Get the line number of the second occurance of that string
line=$(echo $line | cut -d " " -f 2)
# Now replace that line with an updated line: -- using double quotes to allow variable to be translated!
sed -i "${line} s/%wheel ALL=(ALL) ALL/%wheel ALL=(ALL) NOPASSWD: ALL/" /etc/sudoers

#################################################################### Prepare for GitLab: ####################################################################
echo "Beginning GitLab Configuration..."
### NOTE: GitLab needs memory! A PhotonOS 2.0 VM with only 2GB is insufficient for running only GitLab
mkdir -p /srv/gitlab/gitlab /srv/gitlab/redis /srv/gitlab/postgresql /srv/gitlab-runner
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
# docker-compose up -d
echo  "GitLab CE is ready to compose, run: 'docker-compose up -d' from /root/git/gitlab/docker" > /root/git/gitlab-readme.txt

# Setup Cron Job to run this hourly to make sure Gitlab keeps running:
# Enable crond
tdnf install -y cronie
systemctl enable crond
systemctl start crond
cat > /etc/cron.hourly/checkgitlab.sh << "EOF"
#!/bin/bash
curl gitlab.rainpole.com:82 -f -s -o /dev/null || docker-compose -f /root/git/gitlab/docker/docker-compose.yml restart
EOF
chmod +x /etc/cron.hourly/checkgitlab.sh
#  
#### Additional Gitlab Notes:
echo "GitLab URL: http://gitlab.rainpole.com:82"
echo "Initial page load will prompt for PW - set to VMware1!"
echo "Login as root / VMware1!"
echo "Create a Group(s)"
echo "Update e-mail address of root to administrator@corp.local (or as desired)"
# docker run -d --name gitlab-runner --restart always -v /srv/gitlab-runner/config:/etc/gitlab-runner -v /var/run/docker.sock:/var/run/docker.sock gitlab/gitlab-runner:alpine


#################################################################### Prepare for iRedMail ####################################################################
#
# Also remove the following plug-ins from /opt/iredapd/settings.py
# "reject_null_sender", "reject_sender_login_mismatch", "greylisting", amavisd_wblist"
# The line should result in the following:
# plugins = ["throttle", "sql_alias_access_policy"]
# 
echo "Beginning iRedMail Configuration"
mkdir -p /srv/iredmail/vmail
cd ~/git
git clone https://github.com/burkeazbill/docker-iredmail.git
mv docker-iredmail iredmail
cd iredmail
# Update iredmail.cfg file for HOL vPod use:
sed -i 's/yourdomain.lab/rainpole.com/g' ./iredmail.cfg
# Note the use of single quote on next line - this is due to ! being special char
sed -i 's/Passw0rd!/VMware1!/g' ./iredmail.cfg
sed -i 's/domain2.lab domain3.lab/corp.local abigtelco.com/g' ./iredmail.cfg
sed -i 's/x.x.x.x/192.168.110.10/g' ./iredmail.cfg
sed -i 's/# NTPSERVER=.*/NTPSERVER="ntp.corp.local"/g' ./iredmail.cfg
sed -i 's/PRIMARY_DOMAIN_USERS=.*/PRIMARY_DOMAIN_USERS="administrator ceo cfo cio cloudadmin cmo devmgr devuser ecomops epa infosec itmgr itop-notification gitlab jdev ldev loginsight projmgr rpadmin"/g' ./iredmail.cfg
# Update docker-compose file with hostname:
sed -i 's/utility/mail.rainpole.com/g' ./docker-compose.yml
# now, add two lines to the iredmail.sh script to add all the primary domain users to the corp.local domain as well
sed -i '/duration=/i\ \ \ \ \ \ \ \ /bin/bash create_mail_user_SQL.sh corp.local $PRIMARY_DOMAIN_USERS' iredmail/iredmail.sh
sed -i '/duration=/i\ \ \ \ \ \ \ \ /usr/bin/mysql -uroot -p$PASSWD vmail < /opt/iredmail/iRedMail-$IREDMAIL_VERSION/tools/output.sql' iredmail/iredmail.sh
# Build and launch Container:
echo  "iRedMail is ready to compose, run: 'docker-compose up -d' from /root/git/iredmail" > /root/git/iredmail-readme.txt
#### Additional iRedMail Notes:
echo "Webmail Administration: http://mail.rainpole.com/iredadmin" >> /root/git/iredmail-readme.txt
echo "Login as postmaster@rainpole.com / VMware1!" >> /root/git/iredmail-readme.txt
echo "Webmail URL: http://mail.rainpole.com" >> /root/git/iredmail-readme.txt


#################################################################### Now do Jenkins ####################################################################
# echo "Beginning Jenkins Configuration -- NEEDS UPDATE/VALIDATION!!!!"
# mkdir -p /srv/jenkins
# cd ~/git
# git clone https://github.com/jenkinsci/docker.git
# mv docker jenkins
# cd jenkins
# sed -i '/build:/a\ \ container_name: "jenkins"' ./docker-compose.yml
# sed -i '/jenkins_home/d' ./docker-compose.yml
# sed -i '/volumes/a\ \ \ \ - /srv/jenkins:/var/jenkins_home' ./docker-compose.yml
# sed -i 's/git curl/git ntp curl/' ./Dockerfile
#  TO DO !!!
#
#################################################################### Chef ####################################################################
# NOTE - to continue adding Containers to PhotonOS, you'll need to resize /dev/sda2 from the default 8GB to much larger
# TIP: Boot to Ultimate Boot CD (UBCD) and use the Partition Magic tool to resize the partition
# echo "Beginning Chef Configuration -- NEEDS UPDATE/VALIDATION!!!!"
# mkdir -p /srv/chef/root
# mkdir /srv/chef/logs
# mkdir /srv/chef/data
# mkdir ~/git
# 
# cd ~/git
# git clone https://github.com/c-buisson/chef-server.git
# cd chef-server
# sed -i 's/admin@myorg.com "passwd"/administrator@rainpole.com "VMware1!"/g' ./configure_chef.sh
# sed -i 's/my_org "Default organization"/rainpole "Rainpole Organization"/g' ./configure_chef.sh
# sed -i 's/\/root \/var\/log/["\/srv\/chef\/data:\/var\/opt\/opscode\/","\/srv\/chef\/logs:\/var\/log\/opscode","\/srv\/chef\/root:\/root"]/' ./Dockerfile
# NOTE: Place your .crt and .key files in the certs folder. Ideally, the filename should match the FQDN of your host - for example: chef.rainpole.com.crt chef.rainpole.com.key
# sed -i '/COPY/aCOPY .\/certs\/* \/var\/opt\/opscode\/nginx\/ca\//' ./Dockerfile

# echo "NOTE: this section doesn't fully work, you must get into the container and issue the following commands:'" > /root/git/chef-readme.txt
# echo "docker build -t chef ." >> /root/git/chef-readme.txt
# echo "docker run --privileged --name chef -d --restart=always -e CONTAINER_NAME=chef.rainpole.com -e SSL_PORT=4443 -p 4443:4443 chef" >> /root/git/chef-readme.txt
# echo "chef-server-ctl reconfigure --accept-license" >> /root/git/chef-readme.txt
# I can't get chef-manage to install and reconfigure inside docker - apparently a "Known Issue"
# echo "chef-server-ctl install chef-manage" >> /root/git/chef-readme.txt
# echo "chef-server-ctl install opscode-reporting" >> /root/git/chef-readme.txt
# echo "chef-server-ctl install opscode-push-jobs-server" >> /root/git/chef-readme.txt
# echo "chef-server-ctl reconfigure" >> /root/git/chef-readme.txt
# echo "chef-manage-ctl reconfigure --accept-license" >> /root/git/chef-readme.txt
# echo "You should now be able to log in to Chef Manage at https://chef.rainpole.com as administrator / VMware1!" >> /root/git/chef-readme.txt
#################################################################### Artifactory ?? ####################################################################

#################################################################### Harbor ?? ####################################################################

#################################################################### Other(s) ?? ####################################################################
echo "If all went well, http://gitlab.rainpole.com:82 should load"
echo "Webmail admin should eventually load at http://mail.rainpole.com/iredadmin (iredmail takes a while to finish loading - ie: 20 min or so)"
echo "Webmail client should eventually load at http://mail.rainpole.com/"
echo "Make sure to setup NTP inside each of the containers. See notes in http://bit.ly/util-01a for details from Burke on how to do this"
echo "This system requires a reboot and docker-compose up -d for each of the containers"
