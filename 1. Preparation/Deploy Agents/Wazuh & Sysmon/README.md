# Deploy Wazuh HID agents and Sysmon across your domain

Both scripts require command line arguements for your Wazuh -AuthdServer -AuthdPort -ReceivingServer and -ReceivingPort.
The backwards compatible script also requires an arguement for -HostingServer with ip and port that the files are hosted.

You will be prompted to select a file containing a list of target IPs.
This should contain 1 IP address per line of systems you want to deploy on.

### Deploy-SplunkAndSysmon.ps1

* If your remote hosts are running PSv3+ you can run the standard script, you will need all of these files on same host you run the script from. You will be prompted to select them:
    * Your Wazuh-Agent msi
    * Sysmon*.exe install file
    * EULA.txt (Sys internals EULA)
    * SysmonConfiguration xml file. A popular one is SwiftOnSecurity's configuration found here: <a href="https://github.com/SwiftOnSecurity/sysmon-config" target="_blank">https://github.com/SwiftOnSecurity/sysmon-config</a>

### Deploy-SplunkAndSysmonBackwardsCompatible.ps1

* If you have hosts running PSv2 then you will need to use the backwards compatible script. This will also work on newer versions.
* However for this you need to host the Wazuh-Agent msi, Sysmon*.exe, EULA.txt and a SysmonConfiguration xml files on a http server.
* Your Wazuh-agent file name will be a long one containing version numbers, in order to be compatible with the script you MUST rename this file to "wazuh-agent.msi".
* The Sysmon files will need to follow this naming convention: Sysmon64.exe Eula.txt sysmonconfig.xml


Make sure you have changed the commandline options in the "Install_Splunk" function to what you want to forward! The script is just an example!

A list of IPs, Hostnames and service statused will be printed to the console at the end.