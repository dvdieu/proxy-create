#!/bin/sh
random() {
	tr </dev/urandom -dc A-Za-z0-9 | head -c5
	echo
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
main_interface=$(ip route get 8.8.8.8 | awk -- '{printf $5}')

gen64() {
	ip64() {
		echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
	}
	echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}


install_squid() {
    echo "installing squid"
    yum -y install squid

    sudo touch /etc/squid/squid_passwd

    # create pass proxy
    
  
    # install net-tools
    sudo yum install net-tools -y

    #system config proxy
    echo "* hard nofile 999999" >>  /etc/security/limits.conf
    echo "* soft nofile 999999" >>  /etc/security/limits.conf
    echo "net.ipv6.conf.$main_interface.proxy_ndp=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.proxy_ndp=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.default.forwarding=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    echo "net.ipv6.ip_nonlocal_bind = 1" >> /etc/sysctl.conf
    sysctl -p
    systemctl stop firewalld
    systemctl disable firewalld
    cd $WORKDIR
}


gen_user_pass(){
        printf "phucmn:$(openssl passwd -crypt 'PzlPk76')\n" | sudo tee -a /etc/squid/htpasswd
}

set_user_pass_to_file(){
        cat <<EOF
$(gen_user_pass)
EOF
}



gen_firewalld(){
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "sudo firewall-cmd --permanent --add-port=$port/tcp"
    done
}

gen_iptables() {
    cat <<EOF
    $(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA}) 
EOF
}

gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig '$main_interface' inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

gen_data() {
    user=$(awk -F ":" '{print $1}' ${WORKFILEUSER})
    pass=$(awk -F ":" '{print $2}' ${WORKFILEUSER})
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "phucmn/PzlPk76/$IP4/$port/$(gen64 $IP6)"
    done
}

gen_config_squid() {
    cat <<EOF
        # ...
        auth_param basic program /usr/lib64/squid/basic_ncsa_auth /etc/squid/htpasswd
        auth_param basic realm proxy
        acl authenticated proxy_auth REQUIRED
        # ...
        http_access allow localhost
        http_access allow authenticated
        # And finally deny all other access to this proxy
        http_access deny all


        http_access allow localhost manager
        http_access deny manager

        $(awk -F "/" '{print "http_port " $4 ""}' ${WORKDATA}) 
        
        coredump_dir /var/spool/squid

        #http_access allow all
        acl to_ipv4 dst ipv4
        http_access deny to_ipv4

        dns_v4_first off

        $(awk -F "/" '{print "acl user" $4 " myportname " $4 ""}' ${WORKDATA}) 


        $(awk -F "/" '{print "tcp_outgoing_address " $5 " user" $4 ""}' ${WORKDATA})


        forwarded_for delete
        via off
        follow_x_forwarded_for deny all
        request_header_access X-Forwarded-For deny all
        request_header_access From deny all
        request_header_access Referer deny all
        request_header_access User-Agent deny all
        request_header_access Authorization allow all
        request_header_access Proxy-Authorization allow all
        request_header_access Cache-Control allow all
        request_header_access Content-Length allow all
        request_header_access Content-Type allow all
        request_header_access Date allow all
        request_header_access Host allow all
        request_header_access If-Modified-Since allow all
        request_header_access Pragma allow all
        request_header_access Accept allow all
        request_header_access Accept-Charset allow all
        request_header_access Accept-Encoding allow all
        request_header_access Accept-Language allow all
        request_header_access Connection allow all
        request_header_access All deny all
EOF
    
}

gen_file_proxy(){
    cat <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

FIRST_PORT=10000
LAST_PORT=10150

WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
WORKDATAFIREWALLD="${WORKDIR}/firewalld.sh"
WORKFILEUSER="${WORKDIR}/file_user_pass.txt"

# create folder proxy-install
mkdir $WORKDIR && cd $_


install_squid

set_user_pass_to_file >$WORKDIR/file_user_pass.txt



#gen port
echo "open public port...."
gen_firewalld >$WORKDIR/firewalld.sh

#public port by firewalld
bash $WORKDATAFIREWALLD
firewall-cmd --reload
echo "end add port"

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal ip = ${IP4}. Exteranl sub for ip6 = ${IP6}"

echo "gen file data"
gen_data >$WORKDIR/data.txt

echo "gen file boot_ifconfig"
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
echo NM_CONTROLLED="no" >> /etc/sysconfig/network-scripts/ifcfg-${main_interface}
chmod +x $WORKDIR/boot_*.sh /etc/rc.local

echo "vi rc.local"
cat >>/etc/rc.local <<EOF
systemctl start NetworkManager.service
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
EOF

bash /etc/rc.local

echo "gen file config"
gen_config_squid >$WORKDIR/squid.conf
mv /etc/squid/squid.conf /etc/squid/squid.conf.bk
cp $WORKDIR/squid.conf /etc/squid/squid.conf
systemctl restart squid

echo "gen file proxy"
gen_file_proxy >$WORKDIR/proxy.txt
