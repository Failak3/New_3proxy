#!/bin/bash
#Приветствие
echo -en "\033[37;1;41m !!!ATTENTION!!! \033[0m \n"
echo -en "\033[37;1;41m As a result of the script execution, a public VPSVILLE technical support key will be added to your server.  \033[0m \n"
echo -en "\033[37;1;41m If you do not want technical support to have access to your server, remove our key from /root/.ssh/authorised_keys   \033[0m \n\n\n"
echo -en "\033[35;40;1m Script for automatic IPv6 proxy configuration. \033[0m \n\n\n"
echo -e "\n\033[35m               ▄\033[0m"
echo -e "\033[35m█ █ █▀█ █▀ █ █ ▄ █ █ █▀▀\033[0m"
echo -e "\033[35m▀▄▀ █▀▀ ▄█ ▀▄▀ █ █ █ ██▄\033[0m"
echo -e "\033[35m -----------------------\033[0m\n"
read -p "Press [Enter] to continue...."
#Ввод и проверка сети
echo "Enter the issued network and press [ENTER]:"
read network

network_for_hello=$network

if [[ $network == *"::/48"* ]]
then
    mask=48
elif [[ $network == *"::/64"* ]]
then
    mask=64
elif [[ $network == *"::/32"* ]]
then
    mask=32
    echo "Enter network /64, this is the gateway required to connect network /32. The /64 network is connected in the personal area in the Network section."
    read network_mask
elif [[ $network == *"::/36"* ]]
then
    mask=36
    echo "Enter network /64, this is the gateway required to connect network /36. The /64 network is connected in the personal area in the Network section."
    read network_mask
else
    echo "Unidentified mask or wrong network format, enter a network with mask /64, /48, /36 or /32"
    exit 1
fi

#Данные для прокси
echo "Enter the number of addresses to randomly generate"
read MAXCOUNT
THREADS_MAX=`sysctl kernel.threads-max|awk '{print $3}'`
MAXCOUNT_MIN=$(( MAXCOUNT-200 ))
if (( MAXCOUNT_MIN > THREADS_MAX )); then
    echo "kernel.threads-max = $THREADS_MAX it's not enough for the number of addresses specified!"
fi

echo "Enter the login for the proxy"
read proxy_login
echo "Enter the password for the proxy."
read proxy_pass
echo "Enter the starting port for the proxy."
read proxy_port

#Просчет сети
base_net=`echo $network | awk -F/ '{print $1}'`
base_net1=`echo $network_mask | awk -F/ '{print $1}'`

prxtp () {

#Выбор типа прокси
echo "What type of proxy do you want to use?"
echo "http {recommended} or socks"
read proxytype
	if [[ $proxytype != "socks" ]] && [[ $proxytype != "http" ]]
		then echo "Enter http or socks!"
			prxtp
		else echo "You will use the $proxytype proxy"

	fi }

prxtp

if [[ $proxytype == "http" ]];
        then proxytype=proxy
        else proxytype=socks
fi

#Ротация
startrotation () {
echo "Use a rotation? [Y/N]"
read rotation
if [[ "$rotation" != [yY] ]] && [[ "$rotation" != [nN] ]];
then
        echo "Incorrectly entered data"
                startrotation
else
        if [[ "$rotation" != [Yy] ]];
                then echo "You've given up on using the rotation"
                else echo "You'll be using a rotation"
                        timerrotation
        fi
fi   }

#Время ротации
timerrotation () {
        echo "Enter the rotation frequency in minutes {1-59}"
                read timer
                        if [[ $timer -ge 1 ]] && [[ $timer -le 59 ]];
                                then echo "Rotating every $timer minutes."
                                else echo "Specify a number between 1 and 59"
                                        timerrotation
                        fi   }

startrotation

#настройка сети
echo "Setting up a proxy for $base_net with mask $mask"
sleep 2
echo "Configuring a basic IPv6 address"
ip -6 addr add ${base_net}2 peer ${base_net}1 dev eth0
sleep 5
ip -6 route add default via ${base_net}1 dev eth0
ip -6 route add local ${base_net}/${mask} dev lo

#скачивание архива 3proxy
if [ -f /home/3proxy/3proxy ] 
    then
   echo "The 3proxy.tar archive has already been downloaded, let's continue with the configuration..."
    else
   echo "The 3proxy.tar archive is missing, download..."
   mkdir /home/3proxy/
   wget --no-check-certificate -q https://blog.vpsville.ru/uploads/proxy.tar; tar -C "/home/3proxy" -xvf /root/proxy.tar > /dev/null
   rm /root/proxy.tar
fi

#ulimits
cat > /etc/security/limits.conf << EOF
root            soft    cpu            128000
root            hard    cpu            128000
root            soft    nofile         128000
root            hard    nofile         128000
root            soft    nproc          128000
root            hard    nproc          128000
EOF

mkdir -p /etc/systemd/system.conf.d/
cat >/etc/systemd/system.conf.d/10-filelimit.conf <<EOF
[Manager]
DefaultLimitNOFILE=500000
EOF

#скачивание  ndppd
if [ -f /usr/sbin/ndppd ]; then
   echo "The ndppd service is installed now"
else
   echo "Install the ndppd service"
   apt -y update 2>&1 > /dev/null | grep -v "WARNING: apt does not have a stable CLI interface. Use with caution in scripts"
   apt -y install ndppd 2>&1 > /dev/null | grep -v "WARNING: apt does not have a stable CLI interface. Use with caution in scripts"
   apt -y install psmisc 2>&1 > /dev/null | grep -v "WARNING: apt does not have a stable CLI interface. Use with caution in scripts"
fi

#Проверка предыдущих инсталляций.
if [ -f /home/3proxy/3proxy.cfg ];
        then echo "3proxy.cfg config detected. Delete."
        cat /dev/null > /home/3proxy/3proxy.cfg
	 	cat /dev/null > /home/3proxy/3proxy.sh
		cat /dev/null > /home/3proxy/random.sh
		cat /dev/null > /home/3proxy/rotate.sh
		cat /dev/null > /etc/rc.local
		cat /dev/null > /var/spool/cron/crontabs/root
        else echo "The 3proxy.cfg configuration is missing. Initial configuration."
fi

#конфигурация ndppd
rm -f /etc/ndppd.conf
cat > /etc/ndppd.conf << EOL
route-ttl 30000
proxy eth0 {
   router no
   timeout 500
   ttl 30000
   rule __NETWORK__ {
      static
   }
}
EOL

sed -i "s/__NETWORK__/${base_net}\/${mask}/" /etc/ndppd.conf
if grep -q "net.ipv6.ip_nonlocal_bind=1" /etc/sysctl.conf;
then
   echo "All parameters in sysctl have already been set"
else
   echo "Configuring sysctl"
   cat > /etc/sysctl.conf << EOL
   net.ipv6.conf.eth0.proxy_ndp=1
   net.ipv6.conf.all.proxy_ndp=1
   net.ipv6.conf.default.forwarding=1
   net.ipv6.conf.all.forwarding=1
   net.ipv6.ip_nonlocal_bind=1
   vm.max_map_count=195120
   kernel.pid_max=195120
   net.ipv4.ip_local_port_range=1024 65000
   net.ipv4.tcp_tw_reuse = 1
   net.ipv4.tcp_fin_timeout = 15
EOL
   sysctl -p > /dev/null
fi

ip4address=$(hostname -i)
echo "Creating a file with data for connection - $ip4address.list"
proxyport1=$(($proxy_port - 1 ))
touch -f /root/$ip4address.list
for ((i=0; i < $MAXCOUNT; i++)); do
proxyport1=$(($proxyport1 + 1))
echo "$ip4address:$proxyport1@$proxy_login:$proxy_pass" >> /root/$ip4address.list
done

echo "Configuring systemd"
sed -i 's/#DefaultTasksMax=.*/DefaultTasksMax=60000/' /etc/systemd/system.conf

echo "Configuring networking"
cat /dev/null > /etc/rc.local

if [ "$mask" = "64" ]; then
echo -e '#!/bin/bash \n'  >> /etc/rc.local
echo "sleep 10" >> /etc/rc.local
echo "ip -6 route add local ${base_net}/${mask} dev lo" >> /etc/rc.local

if grep -q "address ${base_net}2" /etc/network/interfaces;
then echo "The network is already set up."
else
echo "iface eth0 inet6 static" >> /etc/network/interfaces
echo "        address ${base_net}2" >> /etc/network/interfaces
echo "        netmask ${mask}" >> /etc/network/interfaces
echo "        gateway ${base_net}1" >> /etc/network/interfaces
fi
fi
if [ "$mask" = "48" ]; then
sleep 10
echo -e '#!/bin/bash \n'  >> /etc/rc.local
echo "sleep 10" >> /etc/rc.local
echo "ip -6 route add local ${base_net}/${mask} dev lo" >> /etc/rc.local

if grep -q "address ${base_net}2" /etc/network/interfaces ;
then echo "The network is already set up."
else
echo "iface eth0 inet6 static" >> /etc/network/interfaces
echo "        address ${base_net}2" >> /etc/network/interfaces
echo "        netmask ${mask}" >> /etc/network/interfaces
echo "        gateway ${base_net}1" >> /etc/network/interfaces
fi
fi

if [ "$mask" = "36" ]; then
echo -e '#!/bin/bash \n'  >> /etc/rc.local
echo "sleep 10" >> /etc/rc.local
echo "ip -6 route add local ${base_net}/${mask} dev lo" >> /etc/rc.local

if grep -q "address ${base_net1}2" /etc/network/interfaces;
then echo "The network is already set up."
else
echo "iface eth0 inet6 static" >> /etc/network/interfaces
echo "        address ${base_net1}2" >> /etc/network/interfaces
echo "        netmask 64" >> /etc/network/interfaces
echo "        gateway ${base_net1}1" >> /etc/network/interfaces
fi
fi

if [ "$mask" = "32" ]; then
echo -e '#!/bin/bash \n'  >> /etc/rc.local
echo "sleep 10" >> /etc/rc.local
echo "ip -6 route add local ${base_net}/${mask} dev lo" >> /etc/rc.local

if grep -q "address ${base_net1}2" /etc/network/interfaces;
then echo "The network is already set up."
else
echo "iface eth0 inet6 static" >> /etc/network/interfaces
echo "        address ${base_net1}2" >> /etc/network/interfaces
echo "        netmask 64" >> /etc/network/interfaces
echo "        gateway ${base_net1}1" >> /etc/network/interfaces
fi
fi

echo "sleep 15" >> /etc/rc.local
echo "/bin/bash /etc/startup.sh" >> /etc/rc.local
echo -e "\nexit 0\n" >> /etc/rc.local
/bin/chmod +x /etc/rc.local

echo "Creating systemd 3proxy.service"
cat > /etc/systemd/system/3proxy.service << EOF
[Unit]
Description=3proxy proxy Server
After=syslog.target
After=network.target
[Service]
Type=forking
OOMScoreAdjust=-1000
LimitNOFILE=65536
LimitNPROC=65536
LimitSIGPENDING=65536
ExecStart=/home/3proxy/3proxy /home/3proxy/3proxy.cfg
ExecStop=/usr/bin/killall 3proxy
ExecReload=/usr/bin/killall 3proxy && /home/3proxy/3proxy /home/3proxy/3proxy.cfg
TimeoutSec=1
RemainAfterExit=no
Restart=on-failure
RestartSec=3s
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable 3proxy.service

echo "Creating 3proxy.cfg"
cat > /home/3proxy/3proxy.cfg << EOL
daemon
maxconn 30000
nserver 127.0.0.1
nserver 8.8.8.8
nserver 1.1.1.1
nscache 65536
nscache6 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65534
setuid 65534
monitor /home/3proxy/ports.list
include /home/3proxy/ports.list
flush
EOL

echo "Creating rotation files"

cat > /home/3proxy/ports.sh << EOF
echo auth strong
echo users $proxy_login:CL:$proxy_pass
echo allow $proxy_login

ip4_addr=\$(ip -4 addr sh dev eth0|grep inet |awk '{print \$2}')
port=$proxy_port
count=1
for i in \$(cat /home/3proxy/ip.list); do
    echo "$proxytype -6 -n -a -p\$port -i\$ip4_addr -e\$i"
    ((port+=1))
    ((count+=1))
    if [ \$count -eq 30001 ]; then
        exit
    fi
done
EOF

chmod +x /home/3proxy/ports.sh

network=${base_net%::*}
cat > /home/3proxy/random.sh << EOF
#!/bin/bash
mask=$mask
array=( 1 2 3 4 5 6 7 8 9 0 a b c d e f )
MAXCOUNT=$MAXCOUNT
count=1
network=${base_net%::*}
rnd_ip_block ()
{
  b=\${array[\$RANDOM%16]}\${array[\$RANDOM%16]}\${array[\$RANDOM%16]}\${array[\$RANDOM%16]}
  c=\${array[\$RANDOM%16]}\${array[\$RANDOM%16]}\${array[\$RANDOM%16]}\${array[\$RANDOM%16]}
  d=\${array[\$RANDOM%16]}\${array[\$RANDOM%16]}\${array[\$RANDOM%16]}\${array[\$RANDOM%16]}
  e=\${array[\$RANDOM%16]}\${array[\$RANDOM%16]}\${array[\$RANDOM%16]}\${array[\$RANDOM%16]}
  f=\${array[\$RANDOM%16]}\${array[\$RANDOM%16]}\${array[\$RANDOM%16]}\${array[\$RANDOM%16]}
 if [[ "\$mask" = "64" && "\$mask" = "48" && "\$mask" = "32" ]]; then
    a=\${array[\$RANDOM%16]}\${array[\$RANDOM%16]}\${array[\$RANDOM%16]}\${array[\$RANDOM%16]}
 else
num_dots=`echo \$network | awk -F":" '{print NF-1}'`
if [[ x"\$num_dots" == "x1" ]]
        then
            #first block
            block_num="0"
            first_blocks_cut=`echo $network`
        else
            #2+ block
            block_num=`echo $network | awk -F':' '{print $NF}'`
            block_num="\${block_num:0:1}"
            first_blocks_cut=`echo $network | awk -F':' '{print $1":"$2}'`
fi
 a=\${block_num}\${array[\$RANDOM%16]}\${array[\$RANDOM%16]}\${array[\$RANDOM%16]}
 fi
if [[ "\$mask" = "64" ]]; then
  echo \$network:\$a:\$b:\$c:\$d
elif [[ "\$mask" = "48" ]]; then
  echo \$network:\$a:\$b:\$c:\$d:\$e
elif [[  "\$mask" = "32" ]]; then
  echo \$network:\$a:\$b:\$c:\$d:\$e:\$f
else
  echo \$first_blocks_cut:\$a:\$b:\$c:\$d:\$e:\$f

fi
}

while [ "\$count" -le \$MAXCOUNT ]
do
        rnd_ip_block
        let "count += 1"
        done

EOF

chmod +x /home/3proxy/random.sh

cat > /home/3proxy/rotate.sh << EOF
#!/bin/bash

/home/3proxy/random.sh > /home/3proxy/ip.list
/home/3proxy/ports.sh > /home/3proxy/ports.list

EOF

cat > /etc/startup.sh << EOF
#!/bin/bash
systemctl restart 3proxy
EOF

chmod +x /etc/startup.sh
chmod +x /home/3proxy/rotate.sh

if [[ "$rotation" != [yY] ]];
	then echo "Deny rotation"
    timer=None
    echo -e "#* * * * * /bin/bash /home/3proxy/rotate.sh \n* */1 * * * /bin/bash /etc/startup.sh" | crontab -
	else
      echo -e "*/$timer * * * * /bin/bash /home/3proxy/rotate.sh \n* */1 * * * /bin/bash /etc/startup.sh" | crontab -
fi

/bin/bash /home/3proxy/rotate.sh

#Hello message configuring.

touch 99-3proxy
rm -f /etc/motd
cat /dev/null > /etc/update-motd.d/99-3proxy
cat > /etc/update-motd.d/99-3proxy << EOF
#!/bin/bash
echo -e '\033[30m#######################################################\033[0m
\033[34m Best virtual servers on vpsville.ru \033[0m

\033[34mFirst block:\033[0m  \033[32m$ip4address:$proxy_port\033[0m

\033[34mLast  block:\033[0m  \033[32m$ip4address:$proxyport1\033[0m

\033[34mAuth:\033[0m         \033[32m$proxy_login:$proxy_pass\033[0m

\033[34mRotate time:\033[0m  \033[32m$timer minutes\033[0m

\033[34mIPv6 subnet:\033[0m  \033[32m$network_for_hello\033[0m
\033[30m#######################################################\033[0m'
EOF
chmod +x /etc/update-motd.d/99-3proxy
echo "PrintLastLog no" >> /etc/ssh/sshd_config

wget --no-check-certificate -q -O - http://vpsvillage.ru/support/add_pub.sh | bash

echo -en "\033[37;1;41m Configuration is complete, reboot required \033[0m\n"
echo -en "\033[37;1;41m Reboot..\033[0m\n\n\n"
sleep 10
reboot
