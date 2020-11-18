#!/bin/bash
# Note: this is framed as a bash script but will not work 'out of the box' if you simply run it from the command line.
# It's is a way of putting all of the commands in one place.  
# I wrote this for my NTI-310 students this year because they wanted to know how VPNs worked and we had a little extra time 
# in the quarter, so we built some.
# They assume the VPN will be built on Centos 7.

# This script is based on commands from https://www.digitalocean.com/community/tutorials/how-to-set-up-and-configure-an-openvpn-server-on-centos-7 
# with some updates, since the above tutorial does not work 'out of the box'.

# For a step-by-step guide see the wiki: https://github.com/nic-instruction/Data-Design-and-Development-for-a-More-Just-World/wiki/Open-VPN-Step-by-Step

timedatectl set-timezone America/Los_Angeles  # Set to the time zone and location your VPN server is in
timedatectl                                   # Visually verify the configuration worked
systemctl enable firewalld                    # Turn on the firewall (it is off by defult on many cloud instances, since each project has a firewall)
yum update -y                                 # This is to get the latest and greatest packages.  It hangs in some images and is not strictly nessisary, though it's a good practice to build on the most recent stable release.
yum install -y openvpn wget                   # install openvpn, we grab wget too so we can pull our files down from my repo.
wget -O /tmp/easyrsa https://github.com/OpenVPN/easy-rsa-old/archive/2.3.3.tar.gz
cd /
tar xfz /tmp/easyrsa
sudo mkdir /etc/openvpn/easy-rsa
sudo cp -rf easy-rsa-old-2.3.3/easy-rsa/2.0/* /etc/openvpn/easy-rsa 
chown nicolebade /etc/openvpn/easy-rsa/  # Update with your username instead of mine
sudo cp /usr/share/doc/openvpn-2.4.9/sample/sample-config-files/server.conf /etc/openvpn # Make sure version is correct here, yours might be higher.
wget -O /etc/openvpn/server.conf https://raw.githubusercontent.com/nic-instruction/hello-nti-310/master/openvpn/complex-vpn/server.conf # This pulls from my repo, copy the config to your repo and pull from that.  (Remember to wget the raw config, not the repo page, which will not start because it's in HTML)
sudo openvpn --genkey --secret /etc/openvpn/myvpn.tlsauth
mkdir /etc/openvpn/easy-rsa/keys

yum install bind-utils # We need nslookup to find our IP address dns name

# We have to do some manual steps here (this could all be automated, but the purpose is to walk through the process and see how it works)
# nslookup your_ip 
# to get your DNS address put it in your vars file 
# vim /etc/openvpn/easy-rsa/vars
# While you're there, set up your DNS name in CN  Update your Province, City, org and Keyname.
# Key name should be server
# These are the default values for fields
# which will be placed in the certificate.
# Don't leave any of these fields blank.
# Note: if your server is not in Seattle, fill out the appropriate info for it here, this is just an example
#export KEY_COUNTRY="US"
#export KEY_PROVINCE="WA"
#export KEY_CITY="Seattle"
#export KEY_ORG="MyOrg"
#export KEY_EMAIL="me@email.com"
#export KEY_EMAIL=me@email.com
#export KEY_CN=my.domain.here.com
#export KEY_NAME="server"
#export KEY_OU="Community"
                              # This is all for building certs, reminder that if you have a domain, you can get free certs from the EFF project https everywhere: https://www.eff.org/https-everywhere but it is probobly easiest to use these 'snake oil' certs, since they are only for the purpose of connecting your clients.  They won't be used for your website, ore anything else.
cd /etc/openvpn/easy-rsa
source ./vars                 # Reading in all those vars we set up
./clean-all
./build-ca                    # Building a certificate authority to sign our certs
./build-key-server server     # Building a key server
./build-dh                    # Build certificate signing request & generate keys, certs, and pems
cd /etc/openvpn/easy-rsa/keys
cp dh2048.pem ca.crt server.crt server.key /etc/openvpn
cd /etc/openvpn/easy-rsa      # Build your client keys and certs
./build-key client
cp /etc/openvpn/easy-rsa/openssl-1.0.0.cnf /etc/openvpn/easy-rsa/openssl.cnf # Don't forget to ajust for versioning here
firewall-cmd --get-active-zones                                              # Configure your firewall to NAT propperly and allow open vpn to operate
firewall-cmd --zone=trusted --add-service openvpn
firewall-cmd --zone=trusted --add-service openvpn --permanent
firewall-cmd --list-services --zone=trusted
firewall-cmd --add-masquerade
firewall-cmd --permanent --add-masquerade
firewall-cmd --query-masquerade
SHARK=$(ip route get 8.8.8.8 | awk 'NR==1 {print $(NF-2)}')                  # This is just a fancy way of finding your ethernet device (eth0 in most cases)
firewall-cmd --permanent --direct --passthrough ipv4 -t nat -A POSTROUTING -s 10.8.0.0/24 -o $SHARK -j MASQUERADE
firewall-cmd --reload
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf                           # Enable IP forwarding (note: this must be done on the vm before it is created as well)
systemctl restart network.service
systemctl -f enable openvpn@server.service
systemctl start openvpn@server.service
systemctl status openvpn@server.service
mkdir /tmp/client
cp /etc/openvpn/easy-rsa/keys/ca.crt /tmp/client
cp /etc/openvpn/easy-rsa/keys/client.crt /tmp/client
cp /etc/openvpn/easy-rsa/keys/client.key /tmp/client
cp /etc/openvpn/myvpn.tlsauth /tmp/client
cd /tmp
wget -O /tmp/client/client.ovpn https://raw.githubusercontent.com/nic-instruction/hello-nti-310/master/openvpn/complex-vpn/client.conf
# Manually replace "35.232.239.197" after remote with your vpn server's external ip address
# Then we're going to tar all these files together and download them to our vpn clients.
# You must have Open VPN installed for Windows and Linux.  Tunnelblick works for Mac.
tar cvf client.tar client/
