# BlueTeamBeast
Powershell Scripts for Blue Teams and Incident Responce.

Disclaimer: I am GCIH (July 2019) GCIA (November 2019) and GCFE (June 2020) certified. However all information here and within this repository is given as a general guide to help fellow incident responders, it is given with NO WARRENTY and NO GUARANTEE of effectiveness. If you are concerned with any advice in here or not sure on anything, I suggest doing your own further research or pay an expert to implement a solution for you.

This repository contains a series of scripts to aid in a range of blue team tasks across your network.

The scripts use WinRM (Windows Remote Management). As with many things there are multiple ways to achive your end goals, with these scripts I have used WinRM across a domain setting. This allows you to use a terminal that is not joined to the domain, for instance a dedicated IR device, to manage Windows assets joined to the domain. 

-!!- At the time of writing there appeared to be issues with WinRM working from some linux deivces so I recommend using a hardened Windows VM dedicated to the task -!!-

There are lots of guides for enabling WinRM.
A quick overview, there are 3 main settings required to be set in Group Policy:
- Allow remote server management through WinRM
- Enable WinRM service
- Enable predefined Windows Firewall Rule

When first implimenting I used the guide here: http://www.mustbegeek.com/how-to-enable-winrm-via-group-policy/

If you are using a device not joined to the domain I suggest giving your device a fixed IP.
This fixed IP must be added to the WinRM Trusted hosts GP. You must also add the IP ranges of the networks you wish to manage to your IR devices trusted hosts. 
The answer given here is a clear guide on how to add trusted hosts using powershell:
https://stackoverflow.com/questions/21548566/how-to-add-more-than-one-machine-to-the-trusted-hosts-list-using-winrm

You must use an account with the correct priviledges for the tasks you want to carry out. WinRM will not 'drop creds' on the devices you manage in the same way a direct logon or RDP session will. I highly recommend an account/s dedicated to this purpose. The exact permissions and nature of your accounts should be something you discuss with the appropriate members of your team or organisation.


The common methodology used in these scripts is creating sessions to target machines and then invoking commands or scripts to run in memory on the target. 

I will start by uploading scripts to help with the preparation phase of the IR cycle. Deploying agents and baselining systems.

Where possible I will provide scripts for multiple versions of powershell on endpoints, ALL scripts must be initiated from a host running at least PSv5. Example: IF your environment still has hosts using PSv2, you will need to have an IR device running PSv5.
