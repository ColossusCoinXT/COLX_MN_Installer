# ColossusCoinXT
Shell script to install a [COLX Masternode](http://colossuscoinxt.org/) on a Linux server running Ubuntu 14.04, 16.04 or 18.04. Use it on your own risk.

***
## Installation:
```
# wget -q https://raw.githubusercontent.com/ColossusCoinXT/COLX_MN_Installer/master/COLX_MN_Installer.sh
# chmod +x COLX_MN_Installer.sh && ./COLX_MN_Installer.sh
```
***

## Desktop wallet setup

After the MN is up and running, you need to configure the desktop wallet accordingly. Here are the steps for Windows Wallet
1. Open the COLX Coin Desktop Wallet.
2. Go to RECEIVE and create a New Address: **MN1**
3. Send **10000000** **COLX** to **MN1**.
4. Wait for 6 confirmations.
5. Go to **Tools -> "Debug console - Console"**
6. Type the following command: **masternode outputs**
7. Go to  ** Tools -> "Open Masternode Configuration File"
8. Add the following entry:
```
Alias Address Privkey TxHash Output_index
```
* Alias: **MN1**
* Address: **VPS_IP:PORT**
* Privkey: **Masternode Private Key**
* TxHash: **First value from Step 6**
* Output index:  **Second value from Step 6**
9. Save and close the file.
10. Go to **Masternode Tab**. If you tab is not shown, please enable it from: **Settings - Options - Wallet - Show Masternodes Tab**
11. Click **Update status** to see your node. If it is not shown, close the wallet and start it again. Make sure the wallet is unlocked.
12. Open **Debug Console** and type:
```
startmasternode "alias" "0" "MN1"
```
***

## Usage:
```
colx-cli mnsync status
colx-cli getinfo
colx-cli masternode status
```

Also, if you want to check/start/stop **COLX** , run one of the following commands as **root**:

**Ubuntu 18.04**:  
```
sudo service ColossusXT start #To start COLX service
sudo service ColossusXT stop #To stop COLX service
sudo service ColossusXT restart #To restart COLX service
```

**Ubuntu 16.04**:
```
systemctl status COLX #To check the service is running.
systemctl start COLX #To start COLX service.
systemctl stop COLX #To stop COLX service.
systemctl is-enabled COLX #To check whetether COLX service is enabled on boot or not.
```
**Ubuntu 14.04**:  
```
/etc/init.d/COLX start #To start COLX service
/etc/init.d/COLX stop #To stop COLX service
/etc/init.d/COLX restart #To restart COLX service
```

***
