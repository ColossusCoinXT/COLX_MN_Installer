#!/bin/bash

TMP_FOLDER=$(mktemp -d)
CONFIG_FILE="ColossusCoinXT.conf"
DEFAULT_USER="colossusmn1"
DEFAULT_PORT=51572
DEFAULT_SSH_PORT=22
DAEMON_BINARY="colxd"
CLI_BINARY="colx-cli"
DAEMON_BINARY_FILE="/usr/local/bin/$DAEMON_BINARY"
CLI_BINARY_FILE="/usr/local/bin/$CLI_BINARY"
DAEMON_ZIP="https://github.com/ColossusCoinXT/ColossusCoinXT/releases/download/v1.0.3/colx-1.0.3-x86_64-linux-gnu.tar.gz"
GITHUB_REPO="https://github.com/ColossusCoinXT/ColossusCoinXT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

function checks() 
{
  if [[ $(lsb_release -d) != *16.04* ]]; then
    echo -e "${RED}You are not running Ubuntu 16.04. Installation is cancelled.${NC}"
    exit 1
  fi

  if [[ $EUID -ne 0 ]]; then
     echo -e "${RED}$0 must be run as root.${NC}"
     exit 1
  fi

  if [ -n "$(pidof $DAEMON_BINARY)" ]; then
    echo -e "The colx daemon is already running. ColossusXT does not support multiple masternodes on one host."
    NEW_NODE="n"
    clear
  else
    NEW_NODE="new"
  fi
}

function prepare_system() 
{
  clear
  echo -e "Checking if swap space is required."
  PHYMEM=$(free -g | awk '/^Mem:/{print $2}')
  
  if [ "$PHYMEM" -lt "2" ]; then
    SWAP=$(swapon -s get 1 | awk '{print $1}')
    if [ -z "$SWAP" ]; then
      echo -e "${GREEN}Server is running without a swap file and less than 2G of RAM, creating a 2G swap file.${NC}"
      dd if=/dev/zero of=/swapfile bs=1024 count=2M
      chmod 600 /swapfile
      mkswap /swapfile
      swapon -a /swapfile
    else
      echo -e "${GREEN}Swap file already exists.${NC}"
    fi
  else
    echo -e "${GREEN}Server is running with at least 2G of RAM, no swap file needed.${NC}"
  fi
  
  echo -e "${GREEN}Updating package manager${NC}."
  apt update
  
  echo -e "${GREEN}Upgrading existing packages, it may take some time to finish.${NC}"
  DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade 
  
  echo -e "${GREEN}Installing all dependencies for the colx coin master node, it may take some time to finish.${NC}"
  apt install -y software-properties-common
  apt-add-repository -y ppa:bitcoin/bitcoin
  apt update
  apt install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    make software-properties-common build-essential libtool autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev \
    libboost-program-options-dev libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git wget pwgen curl \
    bsdmainutils libdb4.8-dev libdb4.8++-dev libzmq3-dev libminiupnpc-dev libgmp3-dev ufw fail2ban htop unzip
  clear
  
  if [ "$?" -gt "0" ]; then
      echo -e "${RED}Not all of the required packages were installed correctly.\n"
      echo -e "Try to install them manually by running the following commands:${NC}\n"
      echo -e "apt update"
      echo -e "apt -y install software-properties-common"
      echo -e "apt-add-repository -y ppa:bitcoin/bitcoin"
      echo -e "apt update"
      echo -e "apt install -y make software-properties-common build-essential libtool autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev \
    libboost-program-options-dev libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git wget pwgen curl \
    bsdmainutils libdb4.8-dev libdb4.8++-dev libzmq3-dev libminiupnpc-dev libgmp3-dev ufw fail2ban htop unzip"
   exit 1
  fi

  clear
}

function deploy_binary() 
{
  if [ -f $DAEMON_BINARY_FILE ]; then
    echo -e "${GREEN}colx daemon binary file already exists, using binary from $DAEMON_BINARY_FILE.${NC}"
  else
    cd $TMP_FOLDER

    archive=colx.tar.gz

    echo -e "${GREEN}Downloading $DAEMON_ZIP and deploying the colx service.${NC}"
    wget $DAEMON_ZIP -O $archive >/dev/null 2>&1

    tar -xvzf $archive >/dev/null 2>&1
    rm $archive

    cp $TMP_FOLDER/colx-1.0.3/bin/colxd /usr/local/bin/ >/dev/null 2>&1
    cp $TMP_FOLDER/colx-1.0.3/bin/colx-cli /usr/local/bin/ >/dev/null 2>&1

    chmod +x /usr/local/bin/colx*;

    cd
  fi
}

function enable_firewall() 
{
  echo -e "${GREEN}Setting up firewall to allow access on port $DAEMON_PORT.${NC}"

  apt install ufw -y >/dev/null 2>&1

  ufw disable >/dev/null 2>&1
  ufw allow $DAEMON_PORT/tcp comment "colx Masternode port" >/dev/null 2>&1
  ufw allow $[DAEMON_PORT+1]/tcp comment "colx Masernode RPC port" >/dev/null 2>&1
  
  ufw allow $SSH_PORTNUMBER/tcp comment "Custom SSH port" >/dev/null 2>&1
  ufw limit $SSH_PORTNUMBER/tcp >/dev/null 2>&1

  ufw logging on >/dev/null 2>&1
  ufw default deny incoming >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1

  echo "y" | ufw enable >/dev/null 2>&1

  echo -e "${GREEN}Setting up fail2ban for additional server security."
  systemctl enable fail2ban >/dev/null 2>&1
  systemctl start fail2ban >/dev/null 2>&1
}

function add_daemon_service() 
{
  cat << EOF > /etc/systemd/system/$USER_NAME.service
[Unit]
Description=colx deamon service
After=network.target
[Service]
Type=forking
User=$USER_NAME
Group=$USER_NAME
WorkingDirectory=$DATA_DIR
ExecStart=$DAEMON_BINARY_FILE -datadir=$DATA_DIR -daemon
ExecStop=$CLI_BINARY_FILE -datadir=$DATA_DIR stop
Restart=always
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=10s
StartLimitInterval=120s
StartLimitBurst=5
  
[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3

  echo -e "${GREEN}Starting the colx service from $DAEMON_BINARY_FILE on port $DAEMON_PORT.${NC}"
  systemctl start $USER_NAME.service >/dev/null 2>&1
  
  echo -e "${GREEN}Enabling the service to start on reboot.${NC}"
  systemctl enable $USER_NAME.service >/dev/null 2>&1

  if [[ -z $(pidof $DAEMON_BINARY) ]]; then
    echo -e "${RED}The colx masternode service is not running${NC}. You should start by running the following commands as root:"
    echo "systemctl start $USER_NAME.service"
    echo "systemctl status $USER_NAME.service"
    echo "less /var/log/syslog"
    exit 1
  fi
}

function ask_port() 
{
  read -e -p "$(echo -e $YELLOW Enter a port to run the colx service on: $NC)" -i $DEFAULT_PORT DAEMON_PORT
}

function ask_user() 
{  
  read -e -p "$(echo -e $YELLOW Enter a new username to run the colx service as: $NC)" -i $DEFAULT_USER USER_NAME

  if [ -z "$(getent passwd $USER_NAME)" ]; then
    useradd -m $USER_NAME
    USER_PASSWORD=$(pwgen -s 12 1)
    echo "$USER_NAME:$USER_PASSWORD" | chpasswd

    home_dir=$(sudo -H -u $USER_NAME bash -c 'echo $HOME')
    DATA_DIR="$home_dir/.colx"
        
    mkdir -p $DATA_DIR
    chown -R $USER_NAME: $DATA_DIR >/dev/null 2>&1
    
    sudo -u $USER_NAME bash -c : && RUNAS="sudo -u $USER_NAME"
  else
    clear
    echo -e "${RED}User already exists. Please enter another username.${NC}"
    ask_user
  fi
}

function check_port() 
{
  declare -a PORTS

  PORTS=($(netstat -tnlp | awk '/LISTEN/ {print $4}' | awk -F":" '{print $NF}' | sort | uniq | tr '\r\n'  ' '))
  ask_port

  while [[ ${PORTS[@]} =~ $DAEMON_PORT ]] || [[ ${PORTS[@]} =~ $[DAEMON_PORT+1] ]]; do
    clear
    echo -e "${RED}Port in use, please choose another port:${NF}"
    ask_port
  done
}

function ask_ssh_port()
{
  read -e -p "$(echo -e $YELLOW Enter a port for SSH connections to your VPS: $NC)" -i $DEFAULT_SSH_PORT SSH_PORTNUMBER

  sed -i "s/[#]\{0,1\}[ ]\{0,1\}Port [0-9]\{2,\}/Port ${SSH_PORTNUMBER}/g" /etc/ssh/sshd_config
  systemctl reload sshd
}

function create_config() 
{
  RPCUSER=$(pwgen -s 8 1)
  RPCPASSWORD=$(pwgen -s 15 1)
  cat << EOF > $DATA_DIR/$CONFIG_FILE
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcallowip=127.0.0.1
rpcport=$[DAEMON_PORT+1]
listen=1
server=1
daemon=1
staking=1
port=$DAEMON_PORT
addnode=seed.colossusxt.org
addnode=seed.colossuscoinxt.org
addnode=seed.colxt.net
addnode=38.127.169.152:41720
addnode=45.63.77.48:36320
addnode=45.32.156.225:34510
addnode=207.246.92.47:49780
addnode=207.246.119.26:53658
addnode=51.15.196.167:51572
addnode=37.97.161.74:45852
addnode=45.32.144.121:43366
addnode=45.77.56.142:51572
addnode=104.238.147.168:51572
addnode=209.250.235.101:49076
addnode=45.76.132.221:51572
addnode=172.104.247.86:35186
addnode=50.3.81.137:36768
addnode=185.243.112.221:45444
addnode=45.32.157.28:51572
addnode=192.169.6.9:57880
addnode=198.13.43.51:56610
addnode=173.199.118.174:51572
addnode=136.144.178.31:40950
addnode=176.58.98.153:52776
addnode=145.239.82.9:37784
addnode=209.250.250.193:54974
addnode=45.32.141.103:38120
addnode=192.169.7.207:51980
addnode=45.32.203.135:57536
addnode=45.32.205.47:51316
addnode=5.9.13.72:60486
addnode=173.212.214.116:51572
addnode=93.104.209.98:51572
addnode=173.249.16.132:51572
addnode=45.63.66.201:51572
addnode=153.178.79.117:57331
addnode=79.143.177.206:51572
addnode=94.177.230.81:51572
addnode=104.237.2.189:51572
addnode=54.171.195.136:54274
addnode=107.185.82.34:59561
addnode=108.219.244.55:49468
addnode=72.181.128.245:58854
addnode=192.169.7.102:54980
addnode=81.169.133.70:49984
addnode=209.207.2.137:52120
addnode=126.43.212.228:57884
addnode=209.203.205.156:54435
addnode=86.91.106.184:51529
addnode=181.214.57.13:58348
addnode=192.169.7.134:53388
addnode=47.52.119.89:55160
addnode=129.125.45.179:64570
addnode=213.136.79.142:36048
addnode=84.192.226.177:60741
addnode=24.187.129.102:41394
addnode=73.5.184.5:56528
addnode=86.7.59.98:57871
addnode=81.82.237.94:53802
addnode=82.31.146.24:55836
addnode=113.23.29.64:27657
addnode=192.52.167.120:35078
addnode=217.61.0.156:4434
addnode=71.237.69.166:50199
addnode=18.218.151.195:58478
addnode=32.211.77.93:62260
addnode=45.77.53.166:51572
addnode=45.56.162.47:42186
addnode=99.248.70.73:54203
addnode=82.211.30.118:51572
addnode=202.161.123.218:51333
addnode=93.14.62.75:64855
addnode=188.146.235.244:40175
addnode=126.241.236.94:62031
addnode=23.95.226.179:64067
addnode=114.160.118.54:65111
addnode=84.142.47.108:49582
addnode=182.237.20.126:52126
addnode=86.81.128.209:51960
addnode=88.247.159.251:63083
addnode=45.63.70.203:43658
addnode=90.191.217.220:59132
addnode=67.165.94.226:63006
addnode=94.242.54.22:63612
addnode=184.152.224.135:62971
addnode=50.98.116.40:51755
addnode=201.81.144.25:50398
addnode=89.217.156.75:50888
addnode=119.29.152.164:54401
addnode=192.232.212.81:35730
addnode=45.26.47.239:55184
addnode=5.108.165.160:10456
addnode=68.196.104.108:51572
addnode=119.29.152.164:61280
addnode=174.92.167.92:45128
addnode=72.207.218.84:50116
addnode=207.189.24.169:51619
addnode=76.24.141.100:56557
addnode=68.96.58.222:59616
addnode=185.29.241.89:28675
addnode=178.4.223.135:56042
addnode=24.148.14.21:64196
addnode=86.166.27.233:56794
addnode=174.75.119.93:47311
addnode=58.182.110.143:10476
addnode=116.240.94.131:51142
addnode=93.224.40.110:59102
addnode=95.90.255.43:1834
addnode=140.143.194.34:55131
addnode=185.245.84.52:50157
addnode=172.245.173.72:51792
addnode=206.189.160.220:42760
addnode=159.65.76.161:39922
addnode=60.104.54.79:50741
addnode=80.221.194.126:60801
addnode=46.163.166.50:57877
addnode=178.84.208.50:44968
addnode=218.221.190.31:63489
addnode=70.82.250.174:49945
addnode=67.167.243.172:61879
addnode=118.89.142.85:53827
addnode=112.17.243.16:22619
addnode=46.116.22.191:54515
addnode=76.175.70.186:56185
addnode=206.189.160.209:56430
addnode=101.164.72.195:60287
addnode=118.89.142.85:58444
EOF
}

function create_key() 
{
  read -e -p "$(echo -e $YELLOW Enter your master nodes private key. Leave it blank to generate a new private key.$NC)" PRIV_KEY

  if [[ -z "$PRIV_KEY" ]]; then
    sudo -u $USER_NAME $DAEMON_BINARY_FILE -datadir=$DATA_DIR -daemon >/dev/null 2>&1
    sleep 5

    if [ -z "$(pidof $DAEMON_BINARY)" ]; then
    echo -e "${RED}colx deamon couldn't start, could not generate a private key. Check /var/log/syslog for errors.${NC}"
    exit 1
    fi

    PRIV_KEY=$(sudo -u $USER_NAME $CLI_BINARY_FILE -datadir=$DATA_DIR masternode genkey) 
    sudo -u $USER_NAME $CLI_BINARY_FILE -datadir=$DATA_DIR stop >/dev/null 2>&1
  fi
}

function update_config() 
{
  DAEMON_IP=$(ip route get 1 | awk '{print $NF;exit}')
  cat << EOF >> $DATA_DIR/$CONFIG_FILE
logtimestamps=1
maxconnections=256
masternode=1
masternodeaddr=$DAEMON_IP:$DAEMON_PORT
masternodeprivkey=$PRIV_KEY
EOF
  chown $USER_NAME: $DATA_DIR/$CONFIG_FILE >/dev/null
}

function add_log_truncate()
{
  LOG_FILE="$DATA_DIR/debug.log";

  mkdir ~/.colx >/dev/null 2>&1
  cat << EOF >> ~/.colx/clearlog-$USER_NAME.sh
/bin/date > $LOG_FILE
EOF

  chmod +x ~/.colx/clearlog-$USER_NAME.sh

  if ! crontab -l | grep "~/colx/clearlog-$USER_NAME.sh"; then
    (crontab -l ; echo "0 0 */2 * * ~/.colx/clearlog-$USER_NAME.sh") | crontab -
  fi
}

function show_output() 
{
 echo
 echo -e "================================================================================================================================"
 echo
 echo -e "Your colx coin master node is up and running." 
 echo -e " - it is running as user ${GREEN}$USER_NAME${NC} and it is listening on port ${GREEN}$DAEMON_PORT${NC} at your VPS address ${GREEN}$DAEMON_IP${NC}."
 echo -e " - the ${GREEN}$USER_NAME${NC} password is ${GREEN}$USER_PASSWORD${NC}"
 echo -e " - the colx configuration file is located at ${GREEN}$DATA_DIR/$CONFIG_FILE${NC}"
 echo -e " - the masternode privkey is ${GREEN}$PRIV_KEY${NC}"
 echo
 echo -e "You can manage your colx service from the cmdline with the following commands:"
 echo -e " - ${GREEN}systemctl start $USER_NAME.service${NC} to start the service for the given user."
 echo -e " - ${GREEN}systemctl stop $USER_NAME.service${NC} to stop the service for the given user."
 echo
 echo -e "The installed service is set to:"
 echo -e " - auto start when your VPS is rebooted."
 echo -e " - clear the ${GREEN}$LOG_FILE${NC} log file every 2nd day."
 echo
 echo -e "You can interrogate your masternode using the following commands when logged in as $USER_NAME:"
 echo -e " - ${GREEN}${CLI_BINARY} stop${NC} to stop the daemon"
 echo -e " - ${GREEN}${DAEMON_BINARY} -daemon${NC} to start the daemon"
 echo -e " - ${GREEN}${CLI_BINARY} getinfo${NC} to retreive your nodes status and information"
 echo
 echo -e "You can run ${GREEN}htop${NC} if you want to verify the colx service is running or to monitor your server."
 if [[ $SSH_PORTNUMBER -ne $DEFAULT_SSH_PORT ]]; then
 echo
 echo -e " ATTENTION: you have changed your SSH port, make sure you modify your SSH client to use port $SSH_PORTNUMBER so you can login."
 fi
 echo 
 echo -e "================================================================================================================================"
 echo
}

function setup_node() 
{
  ask_user
  ask_ssh_port
  check_port
  create_config
  create_key
  update_config
  enable_firewall
  add_daemon_service
  add_log_truncate
  show_output
}

clear

echo
echo -e "========================================================================================================="
echo -e "${GREEN}"
echo -e "                                        888888 88     88\"\"Yb"
echo -e "                                        88__   88     88__dP"
echo -e "                                        88\"\"   88     88\"\"\"" 
echo -e "                                        888888 88ood8 88" 
echo                          
echo -e "${NC}"
echo -e "This script will automate the installation of your colx coin masternode and server configuration by"
echo -e "performing the following steps:"
echo
echo -e " - Create a swap file if VPS is < 2GB RAM for better performance"
echo -e " - Prepare your system with the required dependencies"
echo -e " - Obtain the latest colx masternode files from the colx GitHub repository"
echo -e " - Create a user and password to run the colx masternode service"
echo -e " - Install the colx masternode service"
echo -e " - Update your system with a non-standard SSH port (optional)"
echo -e " - Add DDoS protection using fail2ban"
echo -e " - Update the system firewall to only allow; SSH, the masternode ports and outgoing connections"
echo -e " - Add some scheduled tasks for system maintenance"
echo
echo -e "The script will output ${YELLOW}questions${NC}, ${GREEN}information${NC} and ${RED}errors${NC}"
echo -e "When finished the script will show a summary of what has been done."
echo
echo -e "Script created by the colx team"
echo -e " - GitHub: https://github.com/ColossusCoinXT"
echo -e " - Discord: https://discord.gg/pRbDzPd"
echo 
echo -e "========================================================================================================="
echo
read -e -p "$(echo -e $YELLOW Do you want to continue? [Y/N] $NC)" CHOICE

if [[ ("$CHOICE" == "n" || "$CHOICE" == "N") ]]; then
  exit 1;
fi

checks

if [[ "$NEW_NODE" == "new" ]]; then
  prepare_system
  deploy_binary
  setup_node
else
    echo -e "${GREEN}The colx daemon is already running. colx does not support multiple masternodes on one host.${NC}"
  get_info
  exit 0
fi
