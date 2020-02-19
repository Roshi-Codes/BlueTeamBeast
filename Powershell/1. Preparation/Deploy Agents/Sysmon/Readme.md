<h1>Deploy Sysmon agents across your domain<h1>

You will need your Sysmon64.exe, Eula.txt, sysmonconfig.xml files.
If your remote hosts are running PSv3+ you can run the standard script, you will need your install files on the same host you run the script from.

If you have hosts running PSv2 then you will need to use the backwards compatible script. This will also work on newer versions.
However for this you need to host the install files on a http server.
Your files must be named as above in order to be compatible with the script.

You will be prompted to select a file containing a list of target IPs.
This contains 1 IP address per line of systems you want to deploy on.

The backwards compatible script also requires an arguement for -HostingServer with ip and port that the install files are hosted on