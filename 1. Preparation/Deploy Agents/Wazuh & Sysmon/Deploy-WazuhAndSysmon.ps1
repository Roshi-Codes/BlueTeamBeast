#Requires -Version 5
<#
.Synopsis
    Deploys the Wazuh agent and Sysmon to remote Windows hosts running PowerShell V3 and newer.

.DESCRIPTION
    This PowerShell script has been developed to deploy Wazuh agents and Sysmon monitoring across windows devices using WinRM.
    It will add the nessasary lines to Wazuh's ossec.conf to gather Sysmon generated event logs.
    This script uses the automated deployment method using "ossec-authd", in Security Onion this is located in /var/ossec/bin.
    ossec-authd needs to be running on the Wazuh server before you execute this scritpt!
    Ensure ossec-authd is only running for as long as necesarry as it will authenticate all agents that connect. 
    You will require an Windows account that has the correct permissions on all hosts the agent will be installed on. Usually a domain account or JEA (Not tested with JEA).
    For remote hosts running PowerShell V3 and newer.
    PSv3 and above support the PS function for copying to a remote machine "Copy-Item -ToSession". This function is unreliable on PSv2.
                              
.PARAMETER AuthdServer
   Required. 
   Specifies the IP address and port number of your Wazuh Authd server: host:port

.PARAMETER AuthdPort
   The default port for the Authd service is 1515, this will be provided if no option is supplied.

.PARAMETER ReceivingServer
   Required.
   Specifies the IP address and port number of your logging server: host:port

.PARAMETER ReceivingPort
   The default port for the wazuh logging service is 1514, this will be provided if no option is supplied.
                            
.EXAMPLE
   .\Deploy-WazuhAndSysmon.ps1 -AuthdServer 192.168.1.10:1515 -AuthdPort 1515 -ReceivingServer 192.168.1.10:1514 -ReceivingPort 1514

.EXAMPLE
   .\Deploy-WazuhAndSysmon.ps1 -A 192.168.1.10:1515 -R 192.168.1.10:1514 -AP 1515 -RP 1514

.INPUTS
    wazuh-agent*.msi and the Sysmon files (Sysmon*.exe, sysmonconfig.xml and Eula.txt)
    are required on the local machine and you will be prompted to select them.
    You will also be prompted for a username and password for the remote hosts.
    A text file containing one IP address per line for each hosts you want to deploy the forwarder to will be required.

.OUTPUTS
    Two log files are created, Wazuh_Status_Log.txt and Sysmon_Status_Log.txt.
    These are saved to the directory you execute the script from.
    These are logs of the IP addresses and service statuses.

.FUNCTIONALITY
    The Wazuh Agent and Sysmon's required files are sent to the remote hosts and services are installed.
    ossec.conf in the Wazuh install directory is updated to forward Sysmon events.

.DISCLAIMER OF WARRANTY.
   THERE IS NO WARRANTY FOR THE PROGRAM.  
   EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT
   HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY
   OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO,
   THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
   PURPOSE.  THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM
   IS WITH YOU.  SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF
   ALL NECESSARY SERVICING, REPAIR OR CORRECTION.

.LIMITATION OF LIABILITY.
   IN NO EVENT WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MODIFIES AND/OR 
   CONVEYS THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY
   GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE
   USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF
   DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD
   PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER PROGRAMS),
   EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
   SUCH DAMAGES.

#>

#---------------------------------------------------[Parameters]--------------------------------------------------

[CmdletBinding()]

      Param(
         [Alias("A")]                        
         [Parameter(ValueFromPipelineByPropertyName, Mandatory=$True, 
                     HelpMessage='You must enter an IP. Example: "192.168.1.1"')]
         [ValidateNotNullorEmpty()]
         [ValidateLength(9,21)]
         [ValidatePattern('^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|`
                           2[0-4][0-9]|25[0-5])$')]
         [string]$AuthdServer,  
         
         [Alias("R")]
         [Parameter(ValueFromPipelineByPropertyName, Mandatory=$True, 
                     HelpMessage='You must enter an IP. Example: "192.168.1.1"')]
         [ValidateNotNullorEmpty()]
         [ValidateLength(9,21)]
         [ValidatePattern('^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|`
                           2[0-4][0-9]|25[0-5])$')]
         [string]$ReceivingServer,

         [Alias("AP")]                        
         [Parameter(ValueFromPipelineByPropertyName, Mandatory=$false, 
                     HelpMessage='You can enter an PORT if you are not using the default Wazuh ports. Example: "1515"')]
         [ValidateNotNullorEmpty()]
         [ValidateLength(1,25)]
         [ValidatePattern('^([0-9]{1,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2]`
                           [0-9]|6553[0-5])$')]
         [string]$AuthdPort = "1515",

         [Alias("RP")]                        
         [Parameter(ValueFromPipelineByPropertyName, Mandatory=$false, 
                     HelpMessage='You can enter an PORT if you are not using the default Wazuh ports. Example: "1514"')]
         [ValidateNotNullorEmpty()]
         [ValidateLength(1,5)]
         [ValidatePattern('^([0-9]{1,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2]`
                           [0-9]|6553[0-5])$')]
         [string]$ReceivingPort = "1514"
      )

#----------------------------------------------------[Imports]----------------------------------------------------

Add-Type -AssemblyName PresentationFramework    # Required for popup message boxes
Add-Type -AssemblyName System.Windows.Forms     # Required for file selection windows
[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

#------------------------------------------------[Initialisations]------------------------------------------------

# This gets the current working directory 
# $loc = Get-Location

#---------------------------------------------------[Functions]---------------------------------------------------

# You will be prompted for your Windows DOMAIN/USER username and password when you run the script. !!!NEVER STORE YOUR PASSWORD IN PLAINTEXT!!!
# If you do not want to type in your username each time you run the script, uncomment and replace the credentials below with the domian name and username
function Get-Creds(){

    $creds = Get-Credential -Message "Enter your domain credentials to connect to the end points" # -UserName domain\user
    if (-Not $creds.UserName -or -not $creds.Password){
       $msgbox2 = [System.Windows.Forms.Messagebox]::Show('You must enter your username and password to create the sessions...','Warning','OKCancel','warning')
       switch ($msgbox2){ ok {Get-Creds} cancel {exit}}
    }
    return $creds
 }

 # Prompts the user for specific files
function Get-File(){
   [CmdletBinding()]
   
      Param(                        
         [Parameter(ValueFromPipelineByPropertyName)]
         $msg,
         [Parameter(ValueFromPipelineByPropertyName)]
         $filter,
         [Parameter(ValueFromPipelineByPropertyName)]
         $title
      )
      
      $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{    # Sets up the file browser window to open at the Desktop location by default
         InitialDirectory = [Environment]::GetFolderPath('Desktop')
         Filter = $filter                                                           # Sets the filter passed at the function call 
         Title = $title                                                             # Sets the title passed at the function call
         }
      [System.Windows.Forms.MessageBox]::Show($msg,'File Select','OK','Information')   # Opens a popup and displays the message ($msg) passed at the function call
      $null = $FileBrowser.ShowDialog()                                                # Opens the file browser
      if (-Not $FileBrowser.FileName){                                                 # If the user does not select a file this will prompt them to either select a file or cancel which will exit
         $msgbox1 = [System.Windows.Forms.Messagebox]::Show('You must select a file to continue...','File Select','OKCancel','warning')
         switch ($msgbox1){ ok {Get-File} cancel {exit}}
      } 
      return $FileBrowser
   }

# Function to retrieve the job and then remove it from the job list
function Get-ChildJobs(){
   [CmdletBinding()]
   
      Param(                        
         [Parameter(ValueFromPipelineByPropertyName)]
         $jobs
      )
      process {
         Get-Job -IncludeChildJob | Wait-Job | Out-Null       
         foreach ($j in $jobs.ChildJobs){@(Receive-Job $j)}
         Remove-Job *
      }
   }

   # Installs Splunk to the default path $env:SystemDrive\Program Files\SplunkUniversalForwarder
function Install_Wazuh($rindex,$aserv,$sport,$aport){
        
    # Add any arguements to the arguement list. The deployment variables for Wazuh can found at:
    # https://documentation.wazuh.com/3.9/installation-guide/installing-wazuh-agent/deployment_variables/deployment_variables_windows.html#deployment-variables-windows
    Start-Process -FilePath $env:SystemDrive\wazuh-agent.msi –Wait -Verbose –ArgumentList "/q ADDRESS=`"$($rindex)`" SERVER_PORT=`"$($sport)`" AUTHD_SERVER=`"$($aserv)`" AUTHD_PORT=`"$($aport)`""
}
 
# Installs Sysmon to the created Sysmon path
function Install_Sysmon(){
   & "$($env:SystemDrive)\Program Files\sysmon\Sysmon64.exe" -accepteula -i "$($env:SystemDrive)\Program Files\sysmon\sysmonconfig.xml" 2> $null
}

#---------------------------------------------------[Execution]---------------------------------------------------

# User is promted for credentials
$creds = Get-Creds   

# The user is prompted to select the file containing the IP address or the targets
$hostsfile = Get-File -msg "You will now be prompted to select the file containing the IPs OR Hostnames of the targets you wish to gather information from."`
                      -filter "All files (*.txt)| *.*" -title "Select your hosts file"
$computers = (Get-Content -path $hostsfile.FileName)
#$computers = $computers[1..($computers.Length-1)]  # IF the first line causes an error, it is blank and needs to be removed, uncomment the start of this line.

# The user is prompted to select the Wazuh install msi
$wazuhmsi = Get-File -msg "You must now select your Wazuh agent msi installer file" -filter "Install file (wazuh-agent*.msi)|wazuh-agent*.msi" -title "Select your Wazuh agent msi"

# The user is promted to select the 3 files needed for Sysmon to install
$sysmon64 = Get-File -msg "You will now be prompted to select the install .exe file for sysmon" -filter "Install file (Sysmon*.exe)|Sysmon*.exe" -title "Select your Sysmon install .exe"
$eula = Get-File -msg "You will now be prompted to select the sysmon EULA.txt" -filter "Text File (EULA.txt)|EULA.txt" -title "Select your Sysmon EULA text file"
$sysmonconfig = Get-File -msg "You will now be prompted to select the sysmonconfig.xml" -filter "xml File (sysmonconfig.xml)|sysmonconfig.xml" -title "Select your sysmon config xml file"

# Sessions are created to the computers in $computers, first copying the files over then installing the sysmon service, then attempting to get the service status
Write-Output "Connecting..."
$s = New-PSSession -ComputerName $computers -Credential $creds

# A directory is created for sysmon on the remote computers
Invoke-Command -Session $s -ScriptBlock {new-item -ItemType directory -path "$($env:SystemDrive)\Program Files\" -name "sysmon"}

Write-Output "Transfering files"
# The splunk install file is copied to the root of the remote hard drive, this happens one endpoint at a time as Powershell v5 cannot copy one to many.
foreach ($sesh in $s){Copy-Item $wazuhmsi.FileName -ToSession $sesh "$($env:SystemDrive)\wazuh-agent.msi"}
foreach ($sesh in $s){Copy-Item $sysmon64.FileName -ToSession $sesh "$($env:SystemDrive)\Program Files\sysmon\Sysmon64.exe"}
foreach ($sesh in $s){Copy-Item $eula.FileName -ToSession $sesh "$($env:SystemDrive)\Program Files\sysmon\Eula.txt"}
foreach ($sesh in $s){Copy-Item $sysmonconfig.FileName -ToSession $sesh "$($env:SystemDrive)\Program Files\sysmon\sysmonconfig.xml"}

### Splunk is installed first ###

# The Install_Wazuh function is sent to the all remote endpoints and then called on all the endpoints at the same time. These are performed as jobs.
Write-Output "Installing Wazuh agents, this can take a long time in virtual environments with low resources! Please wait..."
$installjob = Invoke-Command -Session $s -ScriptBlock $Function:Install_Wazuh -ArgumentList $ReceivingServer,$AuthdServer,$ReceivingPort,$AuthdPort -AsJob

# The jobs are retrieved to display the results after they finish
Wait-Job $installjob | Out-Null
Get-ChildJobs $installjob

# The installation file is deleted
Invoke-Command -Session $s -ScriptBlock {Remove-Item $env:SystemDrive\wazuh-agent.msi}

### Sysmon is then installed ###

# The Install_Sysmon function is sent to the all remote endpoints and then called on all the endpoints at the same time. These are performed as jobs.
Write-Output "Installing the Sysmon service, this can take a long time in virtual environments with low resources! Please wait..."
$installjob = Invoke-Command -Session $s -ScriptBlock $Function:Install_Sysmon -AsJob

#The job results are retrieved once the jobs are completed
Wait-Job $installjob | Out-Null
Get-ChildJobs $installjob

# Add the required config to gather Sysmon events to ossec.conf on the remote hosts, then restart the Wazuh agent to load the new ossec.conf file.
# The last lines must first be removed as all config must fall inside the ossec_config tags. The closing tag is re-appened at the end.
Invoke-Command -Session $s -ScriptBlock {
   ((Get-Content -path "$env:SystemDrive\Program Files (x86)\ossec-agent\ossec.conf") -replace '<!-- END of Default Configuration. -->','')`
    | Set-Content -Path "$env:SystemDrive\Program Files (x86)\ossec-agent\ossec.conf";`
   ((Get-Content -path "$env:SystemDrive\Program Files (x86)\ossec-agent\ossec.conf") -replace '</ossec_config>','  <localfile>')`
    | Set-Content -Path "$env:SystemDrive\Program Files (x86)\ossec-agent\ossec.conf";`
   add-content -Path "$env:SystemDrive\Program Files (x86)\ossec-agent\ossec.conf" `
   -Value "    <location>Microsoft-Windows-Sysmon/Operational</location>";`
   add-content -Path "$env:SystemDrive\Program Files (x86)\ossec-agent\ossec.conf" `
   -Value "    <log_format>eventchannel</log_format>";`
   add-content -Path "$env:SystemDrive\Program Files (x86)\ossec-agent\ossec.conf" `
   -Value "  </localfile>";`
   add-content -Path "$env:SystemDrive\Program Files (x86)\ossec-agent\ossec.conf" `
   -Value "</ossec_config>";`
   Restart-Service -Name OssecSvc -Force
}
 
foreach ($sesh in $s){
    Write-Host $s.ComputerName
    Invoke-Command -ScriptBlock {Write-Output $env:COMPUTERNAME; Get-Service OssecSvc; Get-Service Sysmon*}
}

# The sessions are closed and any open jobs removed
Write-Output "Closing session"
Remove-PSSession -Session $s
Remove-Job *