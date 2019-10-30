Use these scripts to deploy Splunk Forwarders across your domain using WinRM.
You will need to read to comments in the scripts and change as nessasary in your environment.

Once you have made the changes you will need to host your splunkforwarder msi file.
You can either host it on an internal web server or use a network share.
Your splunk forwarder file name will be a long one containing version numbers, 
in order to be compatible with the script you MUST rename this file to "splunkforwarder.msi".

You will need a targets.txt file in the same path as these scripts.
This contains 1 IP address per line of systems you want to deploy on.
An example is included here with the scripts, delete the current content are replace with your own IPs.

Double check in the install_splunk.ps1, make sure you have set the correct IP/share name.
Make sure you have changed the commandline options in the "fileinstall" function to what you want to forward! The script is just an example!

Launch PowerShell and navigate to the directory with these scripts in.
Run the deploy_splunk_forwarder.ps1
No command line options are required.
This script will enumerate your targets.txt and initiate a session with each host, 
it will then will push the install_splunk.ps1 script to the host and run it, inturn downloading your msi and installing it on the host.
It will then make sure the service has been created and if the service is not running, attempt to start it.

Warning: Currently the script only tries to start the service!
If the service is installed but does not start this is currently not handled.
A list of IPs and splunk forwarder status will be printed at the end and output to a file called "Forwarder_Status.txt"


Planned Update:
Run the install process as jobs so that the forwarder can be installed on more than one host at once.
Parse command line parameters instead of the need to edit the ps1 file.
