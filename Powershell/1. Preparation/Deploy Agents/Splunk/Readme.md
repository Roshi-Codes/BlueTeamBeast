# Deploy Splunk Forwarders across your domain

You will need to read to comments in the scripts and change the install commandline arguements as necessary in your environment.

Both scripts require command line arguements for your Splunk -DeploymentServer and -ReceivingIndexer.
The backwards compatible script also requires an arguement for -HostingServer with ip and port that the msi is hosted on

You will be prompted to select a file containing a list of target IPs.
This contains 1 IP address per line of systems you want to deploy on.

## Deploy-SplunkForwarder.ps1

* If your remote hosts are running PSv3+ you can run the standard script, you will need on this files on same host you run the script from. You will be prompted to select it:
    * Your SplunkForwarder msis

## Deploy-SplunkForwarderBackwardsCompatible.ps1

* If you have hosts running PSv2 then you will need to use the backwards compatible script. This will also work on newer versions.
* However for this you need to host the msi on a http server.
* Your Splunk forwarder file name will be a long one containing version numbers, in order to be compatible with the script you MUST rename this file to: __"splunkforwarder.msi"__


Make sure you have changed the commandline options in the "Install_Splunk" function to what you want to forward! The script is just an example!

A list of IPs and splunk forwarder status will be printed at the end and output to a file called "Forwarder_Status_Log.txt"
