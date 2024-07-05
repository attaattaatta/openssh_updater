#!/bin/bash
# enable debug
#set -x -v
# exit 1 if any error
#set -e -o verbose
#pipefail | verbose

# fixing paths
export PATH=$PATH:/usr/sbin:/usr/sbin:/usr/local/sbin

# set colors
GCV="\033[0;92m"
LRV="\033[1;91m"
YCV="\033[01;33m"
NCV="\033[0m"

# show script version
self_current_version="1.0.10"
printf "\n${YCV}Hello${NCV}, my version is ${YCV}$self_current_version\n${NCV}"

# check privileges
if [[ $EUID -ne 0 ]]
then
	printf "\n${LRV}ERROR - This script must be run as root.${NCV}" 
	exit 1
fi

# validate arguments
if [[ ! $# -eq 0 ]]
then
	printf "\n\n${LRV}ERROR - No arguments allowed${NCV}\n"
	exit 1
fi

EXIT_STATUS=0

check_exit_code() {
if test $EXIT_STATUS != 0
then
	printf "\n\n${LRV}ERROR - last command not succeeded${NCV}\n"
	exit 1
fi

}

# check free space
printf "\n${GCV}Checking free space${NCV}"
current_free_space=$(df -Pm --sync / | awk '{print $4}' | tail -n 1)
space_need_megabytes="2000"
if [[ $current_free_space -le $space_need_megabytes ]]
then
        printf " - ${LRV}FAIL${NCV}";
	EXIT_STATUS=1
        check_exit_code
else
	printf " - ${GCV}OK${NCV}\n"
fi

OPENSSH_MIRROR_HOST="mirror.yandex.ru"
OPENSSH_MIRROR_URL="https://$OPENSSH_MIRROR_HOST/pub/OpenBSD/OpenSSH/portable/"
OPENSSH_UPDATER_DIRECT_URL="https://raw.githubusercontent.com/attaattaatta/openssh_updater"

OPENSSH_BUILD_LOG_FILE="/tmp/openssh_build.$RANDOM.log"
SRC_DIR="/usr/local/src"
INST_SSHD_DIR="$SRC_DIR"/openssh


# check OS
shopt -s nocasematch
REL=$(cat /etc/*release* | head -n 1)
case "$REL" in
        *cent*) distr="rhel";;
	*alma*) distr="rhel";;
	*rocky*) distr="rhel";;
	*oracle*) distr="rhel";;
        *cloud*) distr="rhel";;
        *rhel*) distr="rhel";;
        *debian*) distr="debian";;
        *ubuntu*) distr="ubuntu";;
        *) distr="unknown";;
esac;
shopt -u nocasematch

# check OpenSSH versions
latest_openssh_version=$(printf "GET $OPENSSH_MIRROR_URL HTTP/1.1\nHost:$OPENSSH_MIRROR_HOST\nConnection:Close\n\n" | timeout 5 openssl 2>/dev/null s_client -crlf -connect $OPENSSH_MIRROR_HOST:443 -quiet | sed '1,/^\s$/d' | grep -E -o "openssh-[0-9.]+\w+" | tail -n 1 | sed 's@openssh-@@gi')

latest_openssh_targz_name=$(printf "GET $OPENSSH_MIRROR_URL HTTP/1.1\nHost:$OPENSSH_MIRROR_HOST\nConnection:Close\n\n" | timeout 5 openssl 2>/dev/null s_client -crlf -connect $OPENSSH_MIRROR_HOST:443 -quiet | sed '1,/^\s$/d' | grep -E -o "openssh-[0-9.]+\w+.tar.gz" | tail -n 1)

current_openssh_version=$(2>&1 sshd -V | grep -o -P '\d+\.?\d+\w?\d?+' | head -n 1)

printf "\nLatest OpenSSH server version is ${GCV}$latest_openssh_version${NCV}\n"

printf "Current OpenSSH server version is ${LRV}$current_openssh_version${NCV}\n"

# checking vars are set
if [[ -z $GCV || -z $LRV || -z $YCV || -z $NCV || -z $current_openssh_version || -z $latest_openssh_version || -z $REL || -z $SRC_DIR || -z $INST_SSHD_DIR || -z $OPENSSH_MIRROR_HOST || -z $OPENSSH_MIRROR_URL || -z $OPENSSH_BUILD_LOG_FILE ]]
then
printf "\n${LRV}Some variables or arrays are not defined ${NCV}"
exit 1
fi

openssh_build_cleanup() {
echo 
}

openssh_build_rhel_rpms() {

printf "\nOpenSSH ${GCV}$latest_openssh_version${NCV} RPMs for this system were not found at https://github.com/attaattaatta/openssh_updater/tree/main/RPM \n"
printf "\nTrying to build it from sources, please wait ( logfile - $OPENSSH_BUILD_LOG_FILE ) \n"

{

# install rhel dependencies
yum -y groupinstall 'Development Tools'
for package in gcc glibc-devel initscripts imake rpm-build pam-devel krb5-devel zlib-devel libXt-devel libX11-devel gtk2-devel perl perl-IPC-Cmd
do
yum -y install $package
done
#

# RHEL
# build RPM and install it, if no RPM available online
# spi zhena s https://github.com/boypt/openssh-rpms

cd $INST_SSHD_DIR

if ! which git; then yum -y install git; fi

git config --global http.postBuffer 524288000
git clone https://github.com/boypt/openssh-rpms $INST_SSHD_DIR

sed -i "s@OPENSSHSRC=.*@OPENSSHSRC=$latest_openssh_targz_name@gi" $INST_SSHD_DIR/version.env

source pullsrc.sh >> $OPENSSH_BUILD_LOG_FILE

cd $INST_SSHD_DIR

source compile.sh >> $OPENSSH_BUILD_LOG_FILE

[[ -f /etc/ssh/sshd_config ]] && \cp /etc/ssh/sshd_config /etc/ssh/sshd_config.$(date +%Y%m%d)
} >> $OPENSSH_BUILD_LOG_FILE 2>&1

printf "\n${GCV}Installing RPMs${NCV}\n"
echo
find $INST_SSHD_DIR ! -name '*debug*' ! -path '*SRPMS*' -name '*.rpm'
echo
{

find $INST_SSHD_DIR ! -name '*debug*' ! -path '*SRPMS*' -name '*.rpm' | xargs yum --disablerepo=* localinstall -y 
chmod -v 600 /etc/ssh/ssh_host_*_key
if [[ -d /run/systemd/system && -f /usr/lib/systemd/system/sshd.service ]]
then
mv /usr/lib/systemd/system/sshd.service /usr/lib/systemd/system/sshd.service.$(date +%Y%m%d)
systemctl daemon-reload
fi
} >> $OPENSSH_BUILD_LOG_FILE 2>&1

printf "\n${GCV}Restarting OpenSSH server${NCV}\n";
{
systemctl restart sshd || service sshd restart
} >> $OPENSSH_BUILD_LOG_FILE 2>&1

systemctl status sshd --no-pager || service sshd status
}

openssh_rpm_install() {
{
printf "\n${GCV}Installing RPMs${NCV}\n"
find /tmp/RPM/ ! -name '*debug*' ! -path '*SRPMS*' -name '*.rpm' | xargs yum --disablerepo=* localinstall -y
chmod -v 600 /etc/ssh/ssh_host_*_key
printf "\n${GCV}Restarting OpenSSH server${NCV}\n";
systemctl restart sshd || service sshd restart
} >> $OPENSSH_BUILD_LOG_FILE 2>&1

echo
systemctl status sshd --no-pager || service sshd status
echo

}

opensshd_upgrade() {

BKPRDP="/root/support"
BKPRDP_SIZE=$(du -sm "$BKPRDP" | awk "{print \$1}")
#printf "$BKPRDP current size - $BKPRDP_SIZE MB \n" 2> /dev/null

if [[ ! -f "/tmp/messiah_$(date '+%d-%b-%Y')"_done ]] && \mkdir -p "$BKPRDP"
then
	RUP=$(df "$BKPRDP" | sed 1d | awk "{print \$5}" | sed 's@%@@gi')
	if [[ "$RUP" -le 95 ]]
	then 
		BACKUP_PATH_LIST=("/etc" "/usr/local/mgr5/etc" "/var/spool/cron" "/var/named/domains")
		BDDP="$BKPRDP/$(date '+%d-%b-%Y-%H-%M-%Z')"; \mkdir -p "$BDDP" &> /dev/null
		printf "\nCreating config backup - $BDDP \n"
		for backup_item in "${BACKUP_PATH_LIST[@]}"
		do 
			backup_item_size=$(du -sm --exclude=/etc/ispmysql "$backup_item" | awk "{print \$1}")
			if [[ "$backup_item_size" -lt 2000 ]]
			then \cp -Rfp --parents --reflink=auto "$backup_item" "$BDDP" &> /dev/null;
			else
				printf "${R_C}No backup of $backup_item - $backup_item_size ${NC}\n"
			fi
		done

		\cp -Rfp --parents --reflink=auto "/opt/php"*"/etc/" "$BDDP" &> /dev/null
		\touch "/tmp/messiah_$(date '+%d-%b-%Y')_done" &> /dev/null

	fi
fi

{
\rm -Rf $INST_SSHD_DIR
\mkdir -p $INST_SSHD_DIR
} 2>&1

cd $INST_SSHD_DIR

OS_VER=

# RHEL
if [[ $distr == "rhel" ]]
then

	printf "\nLooks like this is some ${GCV}RHEL (or derivative) OS${NCV}\n"

{
	if echo $REL | grep -i centos | grep -i 7
	then
		OS_VER=centos7
		OS_REL=el7

		sed -i "s/^mirrorlist=/#mirrorlist=/g" /etc/yum.repos.d/CentOS-*
		sed -i "s|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g" /etc/yum.repos.d/CentOS-*
		yum --enablerepo=updates clean metadata

	elif echo $REL | grep -i alma | grep -i 8
	then
		OS_VER=alma8
		OS_REL=el8

	elif echo $REL | grep -i alma | grep -i 9
	then
		OS_VER=alma9
		OS_REL=el9

		yum install -y initscripts

	elif echo $REL | grep -i stream | grep -i 9
	then
		OS_VER=centos9
		OS_REL=el9

		yum install -y initscripts

	elif echo $REL | grep -i stream | grep -i 8
	then
		OS_VER=centos8
		OS_REL=el8

	elif echo $REL | grep -i centos | grep -i 6
	then
		OS_VER=centos6
		OS_REL=el6

	elif echo $REL | grep -i centos | grep -i 5
	then
		OS_VER=centos5
		OS_REL=el5

		yum install -y gcc44 
	fi

} >> $OPENSSH_BUILD_LOG_FILE 2>&1

	if ! [[ -z $OS_VER ]]
	then
		mkdir -p /tmp/RPM &> /dev/null

		printf "\nTrying to find builded RPMs for $OS_VER at https://github.com/attaattaatta/openssh_updater/tree/main/RPM \n"
		printf "GET $OPENSSH_UPDATER_DIRECT_URL/main/RPM/$OS_VER-openssh-$latest_openssh_version-1.$OS_REL.x86_64.rpm HTTP/1.1\nHost:raw.githubusercontent.com\nConnection:Close\n\n" | timeout 10 openssl 2>/dev/null s_client -crlf -connect raw.githubusercontent.com:443 -quiet | sed '1,/^\s$/d' > "/tmp/RPM/$OS_VER-openssh-$latest_openssh_version-1.$OS_REL.x86_64.rpm"
		printf "GET $OPENSSH_UPDATER_DIRECT_URL/main/RPM/$OS_VER-openssh-clients-$latest_openssh_version-1.$OS_REL.x86_64.rpm HTTP/1.1\nHost:raw.githubusercontent.com\nConnection:Close\n\n" | timeout 10 openssl 2>/dev/null s_client -crlf -connect raw.githubusercontent.com:443 -quiet | sed '1,/^\s$/d' > "/tmp/RPM/$OS_VER-openssh-clients-$latest_openssh_version-1.$OS_REL.x86_64.rpm"
		printf "GET $OPENSSH_UPDATER_DIRECT_URL/main/RPM/$OS_VER-openssh-server-$latest_openssh_version-1.$OS_REL.x86_64.rpm HTTP/1.1\nHost:raw.githubusercontent.com\nConnection:Close\n\n" | timeout 10 openssl 2>/dev/null s_client -crlf -connect raw.githubusercontent.com:443 -quiet | sed '1,/^\s$/d' > "/tmp/RPM/$OS_VER-openssh-server-$latest_openssh_version-1.$OS_REL.x86_64.rpm"

		if [[ -f "/tmp/RPM/$OS_VER-openssh-server-$latest_openssh_version-1.$OS_REL.x86_64.rpm" ]] && [[ -f "/tmp/RPM/$OS_VER-openssh-clients-$latest_openssh_version-1.$OS_REL.x86_64.rpm" ]] && [[ -f "/tmp/RPM/$OS_VER-openssh-$latest_openssh_version-1.$OS_REL.x86_64.rpm" ]]
		then
			OPENSSH_FILE_SIZE=$(ls -l "/tmp/RPM/$OS_VER-openssh-$latest_openssh_version-1.$OS_REL.x86_64.rpm" | awk '{print $5}' 2> /dev/null)
			OPENSSH_CLIENTS_FILE_SIZE=$(ls -l "/tmp/RPM/$OS_VER-openssh-clients-$latest_openssh_version-1.$OS_REL.x86_64.rpm" | awk '{print $5}' 2> /dev/null)
			OPENSSH_SERVER_FILE_SIZE=$(ls -l "/tmp/RPM/$OS_VER-openssh-server-$latest_openssh_version-1.$OS_REL.x86_64.rpm" | awk '{print $5}' 2> /dev/null)

			if [[ $OPENSSH_FILE_SIZE -gt 30 ]] && [[ $OPENSSH_CLIENTS_FILE_SIZE -gt 30 ]] && [[ $OPENSSH_SERVER_FILE_SIZE -gt 30 ]]
			then
				openssh_rpm_install

			elif [[ $OPENSSH_FILE_SIZE -eq 0 ]] || [[ $OPENSSH_CLIENTS_FILE_SIZE -eq 0  ]] || [[ $OPENSSH_SERVER_FILE_SIZE -eq 0  ]]
			then
				{
				if ! which curl; then yum -y install curl; fi
				curl "$OPENSSH_UPDATER_DIRECT_URL/main/RPM/$OS_VER-openssh-$latest_openssh_version-1.$OS_REL.x86_64.rpm" -o /tmp/RPM/$OS_VER-openssh-$latest_openssh_version-1.$OS_REL.x86_64.rpm
				curl "$OPENSSH_UPDATER_DIRECT_URL/main/RPM/$OS_VER-openssh-clients-$latest_openssh_version-1.$OS_REL.x86_64.rpm" -o /tmp/RPM/$OS_VER-openssh-clients-$latest_openssh_version-1.$OS_REL.x86_64.rpm
				curl "$OPENSSH_UPDATER_DIRECT_URL/main/RPM/$OS_VER-openssh-server-$latest_openssh_version-1.$OS_REL.x86_64.rpm" -o /tmp/RPM/$OS_VER-openssh-server-$latest_openssh_version-1.$OS_REL.x86_64.rpm
				} >> $OPENSSH_BUILD_LOG_FILE 2>&1

				openssh_rpm_install
			else
				printf "\n${LRV}Downloaded RPMS filesize mismatch${NCV}\n"
				openssh_build_rhel_rpms
			fi
		else
			printf "\n${LRV}Cannot download RPM${NCV}\n"
			openssh_build_rhel_rpms
		fi
	else
		openssh_build_rhel_rpms
	fi

# DEBIAN
elif [[ $distr == "debian" ]]
then
        printf "\nLooks like this is some ${GCV}Debian OS${NCV}\n"
	printf "\nMay be later\n"
	
# UBUNTU
elif [[ $distr == "ubuntu" ]]
then
        printf "\nLooks like this is some ${GCV}Ubuntu OS${NCV}\n"
	printf "\nMay be later\n"
# UNKNOWN
elif [[ $distr == "unknown" ]]
then
        printf "\n${LRV}Sorry, cannot detect this OS${NCV}\n"
        EXIT_STATUS=1
        exit 1
fi

current_openssh_version=$(2>&1 sshd -V | grep -o -P '\d+\.?\d+\w?\d?+' | head -n 1)

if [[ "$current_openssh_version" < "$latest_openssh_version" ]]
then
	printf "\n${LRV}OpenSSH upgrade failed${NCV}\n"
else

	current_openssh_client_version=$(2>&1 ssh -V | grep -o -P '\d+\.?\d+\w?\d?+' | head -n 1)
	current_openssh_server_version=$(2>&1 sshd -V | grep -o -P '\d+\.?\d+\w?\d?+' | head -n 1)
	
	printf "\nCurrent OpenSSH client version is ${GCV}$current_openssh_client_version${NCV}\n"
	printf "Current OpenSSH server version is ${GCV}$current_openssh_server_version${NCV}\n"

	printf "\n${GCV}OpenSSH server upgrade success${NCV}\n"

	printf "\nCheck manually that OpenSSH server works (by open ${LRV}NEW${NCV} ssh session to this server)\n"
fi

}

if [[ "$current_openssh_version" < "$latest_openssh_version" ]]
then
	printf "\n${LRV}OpenSSH server need upgrade${NCV}\n"
	read -p "Continiue upgrading [Y/n]" -n 1 -r
	echo
	if ! [[ $REPLY =~ ^[Nn]$ ]]
	then
		printf "${GCV}Let's try to upgrade OpenSSH server. ${NCV}\n";
		opensshd_upgrade
	else
		printf "\n${GCV}OpenSSH server upgrade was rejected by you. Come back, bro !${NCV}\n";
		exit 1
	fi
		
else
	printf "\n${GCV}OpenSSH server${NCV} looks like is ${GCV}up to date.${NCV}\n"
		
fi
