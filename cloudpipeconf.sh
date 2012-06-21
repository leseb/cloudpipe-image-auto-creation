#!/bin/bash

###########################################
#
# Turn base ubuntu image into cloudpipe
#
###########################################


PACKAGES="vim openvpn bridge-utils unzip"

function eprint {
    echo "updating $FILE ..."
}


# first of all, install openvpn

apt-get update && apt-get -y install $PACKAGES

if [ $? = "0" ]; then
    echo "successful packages installation!"
else
    echo "error during packages installation!"
    exit 1
fi


#edit /etc/network/interfaces

FILE="/etc/network/interfaces"
eprint

cat > $FILE << FILE_EOF
# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto eth0
iface eth0 inet manual
  up ifconfig $IFACE 0.0.0.0 up
  down ifconfig $IFACE down

auto br0
iface br0 inet dhcp
  bridge_ports eth0
FILE_EOF


#edit /etc/rc.local

FILE="/etc/rc.local"
eprint

cat > $FILE << FILE_EOF

. /lib/lsb/init-functions

echo Downloading payload from userdata
wget http://169.254.169.254/latest/user-data -O /tmp/payload.b64
echo Decrypting base64 payload
openssl enc -d -base64 -in /tmp/payload.b64 -out /tmp/payload.zip

mkdir -p /tmp/payload
echo Unzipping payload file
unzip -o /tmp/payload.zip -d /tmp/payload/

# if the autorun.sh script exists, run it
if [ -e /tmp/payload/autorun.sh ]; then
    echo Running autorun.sh
    cd /tmp/payload
    chmod 700 /etc/openvpn/server.key
    sh /tmp/payload/autorun.sh
    if [ ! -e /etc/openvpn/dh1024.pem ]; then
        openssl dhparam -out /etc/openvpn/dh1024.pem 1024
    fi
else
  echo rc.local : No autorun script to run
fi
FILE_EOF


#edit /etc/openvpn/server.conf.template

FILE="/etc/openvpn/server.conf.template"
eprint
cat > $FILE << FILE_EOF
port 1194
proto udp
dev tap0
up "/etc/openvpn/up.sh br0"
down "/etc/openvpn/down.sh br0"
script-security 3 system

persist-key
persist-tun

ca ca.crt
cert server.crt
key server.key  # This file should be kept secret

dh dh1024.pem
ifconfig-pool-persist ipp.txt

server-bridge VPN_IP DHCP_SUBNET DHCP_LOWER DHCP_UPPER

client-to-client
keepalive 10 120
comp-lzo

max-clients 1

user nobody
group nogroup

persist-key
persist-tun

status openvpn-status.log

verb 3
mute 20
FILE_EOF


#edit /etc/openvpn/up.sh

FILE="/etc/openvpn/up.sh"
eprint

cat > $FILE << FILE_EOF
#!/bin/sh

BR=$1
DEV=$2
MTU=$3
/sbin/ifconfig $DEV mtu $MTU promisc up
/sbin/brctl addif $BR $DEV
FILE_EOF

chmod a+x $FILE


#edit /etc/openvpn/down.sh

FILE="/etc/openvpn/down.sh"
eprint

cat > $FILE << FILE_EOF
#!/bin/sh

BR=$1
DEV=$2

/usr/sbin/brctl delif $BR $DEV
/sbin/ifconfig $DEV down
FILE_EOF

chmod a+x $FILE


exit 0
