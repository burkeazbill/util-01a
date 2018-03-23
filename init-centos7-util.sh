#!/bin/bash
#
# Author: Burke Azbill
# Target OS: CentOS 7
# https://github.com/burkeazbill/util-01a
#
#

# Update system
echo "updating system and installing essentials"
yum install -y net-tools deltarpm perl make open-vm-tools git yum-utils wget ntp unzip curl tar bzip2 hostname rsyslog openssl epel-release
yum reinstall -y systemd
yum update --skip-broken -y
systemctl restart vmtoolsd

# Install Docker CE — https://docs.docker.com/engine/installation/linux/centos/#docker-ce
# https://docs.docker.com/engine/installation/linux/linux-postinstall/#allow-access-to-the-remote-api-through-a-firewall
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum-config-manager --enable docker-ce-edge
Yum-config-manager —-enable docker-ce-test

# Refresh the cache:
sudo yum makecache fast
yum list docker-ce.x86_64  --showduplicates |sort -r
yum install -y docker-ce.x86_64
yum clean all
rm -rf /var/cache/yum
curl -L https://github.com/docker/compose/releases/download/1.19.0/docker-compose-`uname -s`-`uname -m` > /usr/bin/docker-compose
chmod +x /usr/bin/docker-compose
systemctl start docker
systemctl enable docker

# Stop and disable the firewall
systemctl stop firewalld
systemctl disable firewalld

# Disable SELINUX
sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config
setenforce 0

# Set Hostname:
hostnamectl set-hostname util-01a.corp.local

echo "Preparing Docker"
# Prepare Docker aliases for ANYONE that logs into VM:
#!/bin/bash
cat > /etc/profile.d/alias.sh << "EOF"
# Setup Docker aliases
alias rmcontainers='docker stop $(docker ps -a -q); docker rm $(docker ps -a -q)'
alias rmimages='docker rmi $(docker images -q)'
alias rmvolumes='docker volume rm $(docker volume ls -f dangling=true -q)'

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

# Specify DNS servers for Docker containers:
cat > /etc/docker/daemon.json << "EOF"
{
  "dns": ["192.168.110.10"]
}
EOF

#### Configure util VM user accounts
## Set root pw to never expire
chage -M -1 root

# Disable filesystem check on boot
for fs in `cat /proc/mounts | grep ext[234] | cut -f 1 -d ' '` ; do tune2fs -c 0 -i 0 ${fs} ; done

echo "adding jenkins and holadmin users..."
## Setup jenkins user/data directory
groupadd -g 1000 jenkins
useradd -d /srv/jenkins -u 1000 -g 1000 -m -s /bin/bash jenkins
chage -M -1 jenkins
## Setup holuser user - for SSH and sudo
useradd -d /home/holuser -m holuser
echo 'holuser:VMware1!' | chpasswd
chage -M -1 holuser
usermod -aG wheel holuser

# Make sure Postfix is disabled/stopped
systemctl stop postfix
systemctl disable postfix
yum erase -y postfix

# Configure NTP:
# Comment out all the default pool servers:
sed -i '/centos.pool.ntp.org/s/^/#/g' /etc/ntp.conf
# Now add our custom ntp server below the last line of the default pool servers:
sed -i '/server 3.centos.pool.ntp.org/aserver ntp.corp.local \n' /etc/ntp.conf

# Enable/Start ntpd
systemctl enable ntpd
systemctl start ntpd
# Check time:
ntpq -p
# Expected output:
# remote           refid      st t when poll reach   delay   offset  jitter
# ==============================================================================
# *router.corp.loc LOCAL(1)         6 u   61   64    1    1.235    0.327   0.001

echo "Imporing ControlCenter public auth key to authorized_keys"
mkdir ~/.ssh
echo ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAp7fYaIex88KRGhNWTYIwqJn/jtDp9ZV71WtBSpi9/LFhMh0f87n+W8Ms3QgA2WdEcTJRLoc3blHGo3a6TIqDGuVmGwgJjXpQA65aHjQS5P3gv86vDELuTlKev3BumcvmqpGeoyKY4zn4RLtdiWDCLI+rMEkWAPyV7RbbNzuaJoQUKTdfv1iBfWo0thoQzTj9KluTgM6FWXz7iyNB4J7NXIeYfxfbQgl3mAGdQkc11cgrnfFfjIRVA/nE5pUbOErJ9cUEMscb5iXMPQvs2zKcfZ0FYd4+TwfRpPwzYVC/vmS9kO7jrGQbtkOzTyf1GqOXCQ4URX2cPWS4zthXS5gm5Q== controlcenter > ~/.ssh/authorized_keys

echo "Reconfiguring SSH to not allow root - only key based auth"
# Update ssh to NOT allow root
# Uncomment PermitRootLogin to “yes” in /etc/ssh/sshd_config
sed -i '/^#PermitRootLogin/s/^#//' /etc/ssh/sshd_config
# Set password authentication to no (allowing only key based auth)
# NOTE: If the following line is uncommented, then SFTP with username/password will not work
# sed -i "s/PasswordAuthentication yes/PasswordAuthentication no/g" /etc/ssh/sshd_config
# End result: root can only ssh with key based authentication

systemctl restart sshd

# Update sudoers to not prompt for pw and execute all commands for %wheel group members
# Find and comment out the line that starts with %wheel
sed -i '/^%wheel/s/^/# /' /etc/sudoers
# Now uncomment the line that allows all members of wheel to execute commands without password:
sed -i '/NOPASSWD/s/^#//' /etc/sudoers
echo cat /root/*-readme.txt >> /root/.bashrc
echo "" > /root/00-util-01a-readme.txt
echo ============================== Util-01a ======================================  >> /root/00-util-01a-readme.txt
echo Welcome to the utility server!   >> /root/00-util-01a-readme.txt
echo SFTP/SCP is available on this server using the root account or holuser account  >> /00-root/util-01a-readme.txt
echo Depending on which additional content Burke has installed,  >> /root/00-util-01a-readme.txt
echo you may receive additional info-text below this.  >> /root/00-util-01a-readme.txt
#################################################################### Prepare for GitLab: ####################################################################
echo "Beginning GitLab Configuration..."
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
echo "" > /root/gitlab-readme.txt
echo ============================== GitLab ======================================  >> /root/gitlab-readme.txt
echo GitLab URL: http://gitlab.rainpole.com:82 >> /root/gitlab-readme.txt
echo Initial page load will prompt for PW - set to VMware1! >> /root/gitlab-readme.txt
echo Login as root / VMware1! >> /root/gitlab-readme.txt
echo Create a Group >> /root/gitlab-readme.txt
echo Update e-mail address of root to administrator@corp.local or as desired >> /root/gitlab-readme.txt
echo To access the console of the GitLab container:  >> /root/gitlab-readme.txt
echo   docker exec -it gitlab /bin/bash >> /root/gitlab-readme.txt
cat /root/gitlab-readme.txt

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
./deploy.sh

#################################################################### Now do Jenkins ####################################################################
echo "Beginning Jenkins Configuration -- NEEDS UPDATE/VALIDATION!!!!"
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
#################################################################### Chef ####################################################################
# NOTE - to continue adding Containers to PhotonOS, you'll need to resize /dev/sda2 from the default 8GB to much larger
# TIP: Boot to Ultimate Boot CD (UBCD) and use the Partition Magic tool to resize the partition
echo "Beginning Chef Configuration -- NEEDS UPDATE/VALIDATION!!!!"
mkdir -p /srv/chef/root
mkdir /srv/chef/logs
mkdir /srv/chef/data
mkdir ~/git

cd ~/git
git clone https://github.com/c-buisson/chef-server.git
cd chef-server
mkdir certs

# Create Configure NTP script:
# Specify DNS servers for Docker:
cat > configure_ntp.sh << "EOF"
#!/bin/bash
# Comment out all the default pool servers: -- need to add this into configure_chef.sh
sed -i '/ubuntu.pool.ntp.org/s/^/#/g' /etc/ntp.conf
sed -i '/ntp.ubuntu.com/s/^/#/' /etc/ntp.conf
# Now add our custom ntp server below the last line of the default pool servers:
sed -i '/server ntp.ubuntu.com/aserver ntp.corp.local \n' /etc/ntp.conf
service ntp start
EOF
chmod 755 configure_ntp.sh

# Search and replace values in configure_chef.sh
sed -i 's/admin@myorg.com "passwd"/administrator@rainpole.com "VMware1!"/g' ./configure_chef.sh
sed -i 's/my_org "Default organization"/rainpole "Rainpole Organization"/g' ./configure_chef.sh
sed -i '/^.*Creating tar file/ichef-manage-ctl reconfigure --accept-license' ./configure_chef.sh

# Update Dockerfile Volume mappings
sed -i 's/\/var\/log/["\/srv\/chef\/data:\/var\/opt\/opscode\/","\/srv\/chef\/logs:\/var\/log\/opscode","\/srv\/chef\/root:\/root"]/' ./Dockerfile
# Update Dockerfile to include installation of ntp
sed -i 's/wget curl rsync/wget curl rsync ntp/' ./Dockerfile
sed -i 's/configure_chef.sh/configure_chef.sh configure_ntp.sh/' ./Dockerfile

# NOTE: Place your .crt and .key files in the certs folder. Ideally, the filename should match the FQDN of your host - for example: chef.rainpole.com.crt chef.rainpole.com.key
sed -i '/COPY/aCOPY .\/certs\/* \/var\/opt\/opscode\/nginx\/ca\/' ./Dockerfile
sed -i '/configure_chef.sh/i\ \ \ \ \/usr\/local\/bin\/configure_ntp.sh' ./run.sh

docker build -t chef .
docker run --privileged --name chef -d --restart=always -e CONTAINER_NAME=chef.rainpole.com -e SSL_PORT=4443 -p 4443:4443 -v /srv/chef/data:/var/opt/opscode/ -v /srv/chef/logs:/var/log/opscode/ -v /srv/chef/root:/root/ chef


echo "NOTE: this section doesn't fully work, you must get into the container and issue the following commands:'" > /root/chef-readme.txt
echo "docker build -t chef ." >> /root/chef-readme.txt
echo "docker run --privileged --name chef -d --restart=always -e CONTAINER_NAME=chef.rainpole.com -e SSL_PORT=4443 -p 4443:4443 chef" >> /root/chef-readme.txt
echo "chef-server-ctl reconfigure --accept-license" >> /root/chef-readme.txt

# I can't get chef-manage to install and reconfigure inside docker - apparently a "Known Issue"
echo "chef-server-ctl install chef-manage" >> /root/chef-readme.txt
# echo "chef-server-ctl install opscode-reporting" >> /root/chef-readme.txt
echo "chef-server-ctl install opscode-push-jobs-server" >> /root/chef-readme.txt
echo "chef-server-ctl reconfigure" >> /root/chef-readme.txt
echo "chef-manage-ctl reconfigure --accept-license" >> /root/chef-readme.txt
echo You should now be able to log in to Chef Manage at https://chef.rainpole.com as administrator / VMware1! >> /root/chef-readme.txt
#################################################################### Artifactory ?? ###############################################################

#################################################################### Harbor ?? ####################################################################

#################################################################### S/FTP Server Configuration ####################################################


##################################################################
echo "If all went well, http://gitlab.rainpole.com:82 should load"
echo "Webmail admin should eventually load at http://mail.rainpole.com/iredadmin (iredmail takes a while to finish loading - ie: 20 min or so)"
echo "Webmail client should eventually load at http://mail.rainpole.com/"
echo "Make sure to setup NTP inside each of the containers. See notes in http://bit.ly/util-01a for details from Burke on how to do this"
echo "This system requires a reboot and docker-compose up -d for each of the containers"

