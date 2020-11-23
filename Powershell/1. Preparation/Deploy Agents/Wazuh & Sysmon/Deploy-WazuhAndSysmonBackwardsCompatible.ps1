#Requires -Version 5
<#
.Synopsis
    Deploys the Wazuh HID agent and Sysmon to remote Windows hosts that are running PowerShell V2 and newer.

.DESCRIPTION
    This PowerShell script has been developed to deploy Wazuh HID agents and Sysmon monitoring across windows devices using WinRM.
    It will add the nessasary lines to Wazuh's ossec.conf to gather Sysmon generated event logs.
    You may need to tune your Wazuh receiving server to correctly parse Sysmon events.
    You will require an Windows account that has the correct permissions on all hosts the services will be installed on. Usually a domain account.
    For remote hosts running PowerShell V2 and newer.
    PSv3 and above support the PS function for copying to a remote machine "Copy-Item -ToSession". 
    If your remote hosts have PSv3 it is recommended to use "Deploy-WazuhAndSysmon.ps1"
    PSv2 does not correctly support Copy-Item -ToSession, the command often fails with files over a few MB.
    For this reason the script has been set up to require you to host the Wazuh install file and the 3 Sysmon files on a http server. 
    Method for hosting the files so is in the notes below.

.PARAMETER HostingServer
    Required. 
    Specifies the IP address and port number of the HTTP server hosting your files.

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
   .\Deploy-SplunkAndSysmon.ps1 -HostingServer 192.168.10.10:80 -AuthdServer 192.168.1.10:1515 -AuthdPort 1515 -ReceivingServer 192.168.1.10:1514 -ReceivingPort 1514

.EXAMPLE
   .\Deploy-SplunkAndSysmon.ps1 -H 192.168.10.10:80 -A 192.168.1.10:1515 -R 192.168.1.10:1514 -AP 1515 -RP 1514

.INPUTS
   You will be prompted for a username and password for the remote hosts.
   wazuh-agent*.msi and the Sysmon files (Sysmon*.exe, sysmonconfig.xml and Eula.txt)
   They must follow the following naming convention exactly:
   Sysmon files required: Sysmon64.exe, Eula.txt, sysmonconfig.xml
   Splunk Forwarder: wazuh-agent.msi
   A text file containing one IP address per line for each hosts you want to deploy the HID agents and Sysmon to will be required.
   The IP:PORT of the HTTP server hosting your Wazuh & Sysmon files.
   
.OUTPUTS
    Sysmon_Status_Log.txt is saved to the directory you run the script from.
    This is a log of the IP addresses and Sysmon status.

.NOTES
    To host the Wazuh msi on a HTTP server, first rename the msi installer to wazuh-agent.msi (Removing version number)
    Then make sure the Sysmon files are named as follows: Sysmon64.exe  Eula.txt  sysmonconfig.xml
    One of the easiest ways to server them on a HTTP server is to create a dedicated folder on a linux server and run a simple http server in the folder:
    "Python -m SimpleHTTPServer"
    This script is designed to work with the Sysmon 64bit installer simply because of the naming.
    To download and install the 32bit version you can either change the script where the 
    Get-SysmonFiles function is called with the installer name passed as a parameter or 
    change the name of your executable to match Sysmon64.exe

.FUNCTIONALITY
    Sends commands to remote hosts to download the required files from specified server and install the Wazuh and Sysmon services.

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
         [Alias("H")]
         [Parameter(ValueFromPipelineByPropertyName, Mandatory=$True, 
                     HelpMessage='You must enter an IP and Port. Example: "192.168.1.1:8000"')]
         [ValidateNotNullorEmpty()]
         [ValidateLength(9,21)]
         [ValidatePattern('^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|`
                           2[0-4][0-9]|25[0-5]):([0-9]{1,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2]`
                           [0-9]|6553[0-5])$')]
         [string]$HostingServer,
         
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

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
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

function Get-ServiceFiles {
    param (
        [Parameter(ValueFromPipelineByPropertyName)]
            $url,$path,$sesh
            )
    # The file is downloaded from the HTTP server to the remote hosts
    $downloadjob = Invoke-Command -Session $sesh -ScriptBlock {(New-Object Net.WebClient).DownloadFile($using:url, $using:path) } -AsJob
    Wait-Job $downloadjob | Out-Null
    Get-ChildJobs -jobs $downloadjob
}

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
                      -filter “All files (*.*)| *.*” -title "Select your hosts file"
$computers = (Get-Content -path $hostsfile.FileName)
#$computers = $computers[1..($computers.Length-1)] # IF the first line causes an error it is blank and needs to be removed, uncomment the start of this line.

# Sessions are created to the computers in $computers
Write-Output "Connecting..."
$s = New-PSSession -ComputerName $computers -Credential $creds

# A directory is created for sysmon on the remote computers
Invoke-Command -Session $s -ScriptBlock {new-item -ItemType directory -path "$($env:SystemDrive)\Program Files\" -name "sysmon"}

# The url is the location of your hosted files - simple python http server will work.
# Path that the path the files are saved to on the remote host - If you change this you must change the location to match thoughout the rest of the script.
Write-Output "Downloading"
Get-ServiceFiles -url "http://$($HostingServer)/wazuh-agent.msi" -path "$($env:SystemDrive)\wazuh-agent.msi" -sesh $s
Get-ServiceFiles -url "http://$($HostingServer)/Sysmon64.exe" -path "$($env:SystemDrive)\Program Files\sysmon\Sysmon64.exe" -sesh $s
Get-ServiceFiles -url "http://$($HostingServer)/Eula.txt" -path "$($env:SystemDrive)\Program Files\sysmon\Eula.txt" -sesh $s
Get-ServiceFiles -url "http://$($HostingServer)/sysmonconfig.xml" -path "$($env:SystemDrive)\Program Files\sysmon\sysmonconfig.xml" -sesh $s

# The Install_Wazuh function is sent to the all remote endpoints and then called on all the endpoints at the same time. These are performed as jobs.
Write-Output "Installing Wazuh agents, this can take a long time in virtual environments with low resources! Please wait..."
$installjob = Invoke-Command -Session $s -ScriptBlock $Function:Install_Wazuh -ArgumentList $ReceivingServer,$AuthdServer,$ReceivingPort,$AuthdPort -AsJob

#The job results are retrieved once the jobs are completed
Wait-Job $installjob | Out-Null
Get-ChildJobs $installjob

# The installation file is deleted
Invoke-Command -Session $s -ScriptBlock {Remove-Item $env:SystemDrive\wazuh-agent.msi}

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