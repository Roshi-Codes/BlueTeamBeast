#Requires -Version 5
<#
.Synopsis
    Deploys the Splunk Forwarder and Sysmon to remote Windows hosts that are running PowerShell V2 and newer.

.DESCRIPTION
    This PowerShell script has been developed to deploy Splunk Universal Forwarders and Sysmon monitoring across windows devices using WinRM.
    It will add the nessasary lines to Splunk's inputs.conf to gather Sysmon generated event logs.
    It will also add lines to inputs.conf needed to gather PowerShell event logs created in Microsoft-Windows-PowerShell/Operational when logging is enabled.
    You will need to update props.conf and transforms.conf to take full advantage of Sysmon logs in Splunk.
    These will need changing on the Splunk Server and they may need to be created in "/opt/splunk/etc/system/local" Example: 
    https://www.splunk.com/en_us/blog/tips-and-tricks/monitoring-network-traffic-with-sysmon-and-splunk.html
    You will require an Windows account that has the correct permissions on all hosts the services will be installed on. Usually a domain account.
    For remote hosts running PowerShell V2 and newer.
    PSv3 and above support the PS function for copying to a remote machine "Copy-Item -ToSession".
    PSv2 does not correctly support Copy-Item -ToSession, the command often fails with files over a few MB.
    For this reason the script has been set up to require you to host the Splunk Forwarder .msi file and the 3 Sysmon files on a http server. 
    Method for hosting the files so is in the notes below.

.PARAMETER HostingServer
    Required. 
    Specifies the IP address and port number of the HTTP server hosting your files.

.PARAMETER DeploymentServer
   Required. 
   Specifies the IP address and port number of your Splunk deployment server: host:port

.PARAMETER ReceivingIndexer
   Required.
   Specifies the IP address and port number of your Splunk deployment server: host:port

.PARAMETER SplunkUsername
   Required.
   Specifies the local Splunk Admin username to be set on the hosts.

.PARAMETER SplunkPass
   Required.
   Specifies the local Splunk Admin password to be set on the hosts.
                              
.EXAMPLE
   .\Deploy-SplunkAndSysmon.ps1 -HostingServer 192.168.10.10:80 -DeploymentServer 192.168.1.10:8089 -ReceivingIndexer 192.168.1.10:9997 -SplunkUsername admin -SplunkPass Pa$$w0rd

.EXAMPLE
   .\Deploy-SplunkAndSysmon.ps1 -H 192.168.10.10:80 -D 192.168.1.10:8089 -R 192.168.1.10:9997 -U admin -P Pa$$w0rd

.INPUTS
   You will be prompted for a username and password for the remote hosts.
   SplunkForwarder*.msi and the Sysmon files (Sysmon*.exe, sysmonconfig.xml and Eula.txt)
   A text file containing one IP address per line for each hosts you want to deploy the Forwarders and Sysmon to will be required.
   The IP:PORT of the HTTP server hosting your Splunk & Sysmon files.
   They must follow the following naming convention exactly:
   Sysmon files required: Sysmon64.exe, Eula.txt, sysmonconfig.xml
   Splunk Forwarder: splunkforwarder.msi

.OUTPUTS
    Service statuses are output to the console.

.NOTES
    To host the SplunkForwarder msi and Sysmon files on a HTTP server, first rename the msi installer to splunkforwarder.msi (Removing version number)
    Then make sure the Sysmon files are named as follows: Sysmon64.exe  Eula.txt  sysmonconfig.xml
    One of the easiest ways to server them on a HTTP server is to create a dedicated folder on a linux server and run a simple http server in the folder:
    "Python -m SimpleHTTPServer"
    This script is designed to work with the Sysmon 64bit installer simply because of the naming.
    To download and install the 32bit version you can either change the script where the 
    Get-ServiceFiles function is called with the installer name passed as a parameter or 
    change the name of your executable to match Sysmon64.exe

.FUNCTIONALITY
    Sends commands to remote hosts to download the required files from specified server and install the Splunk and Sysmon services.

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
         
         [Alias("D")]                        
         [Parameter(ValueFromPipelineByPropertyName, Mandatory=$True, 
                     HelpMessage='You must enter an IP and Port. Example: "192.168.1.1:8000"')]
         [ValidateNotNullorEmpty()]
         [ValidateLength(9,21)]
         [ValidatePattern('^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|`
                           2[0-4][0-9]|25[0-5]):([0-9]{1,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2]`
                           [0-9]|6553[0-5])$')]
         [string]$DeploymentServer,  
         
         [Alias("R")]
         [Parameter(ValueFromPipelineByPropertyName, Mandatory=$True, 
                     HelpMessage='You must enter an IP and Port. Example: "192.168.1.1:8000"')]
         [ValidateNotNullorEmpty()]
         [ValidateLength(9,21)]
         [ValidatePattern('^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|`
                           2[0-4][0-9]|25[0-5]):([0-9]{1,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2]`
                           [0-9]|6553[0-5])$')]
         [string]$ReceivingIndexer,
         
         [Alias("U")]
         [Parameter(ValueFromPipelineByPropertyName, Mandatory=$True, 
                     HelpMessage='You must enter the username you wish to set for the local Splunk admin user for Forwarder for management')]
         [ValidateNotNullorEmpty()]
         [string]$SplunkUsername,

         # PowerShell SecureString is not used here because it must be provided to the Splunk Forwarder in plaintext at the time of installation. 
         # Converting a SecureString back to plain text was not introduced until PowerShell v7 and compatibility with v5 is the current aim.
         [Alias("P")]
         [Parameter(ValueFromPipelineByPropertyName, Mandatory=$True, 
                     HelpMessage='You must enter the password you wish to set for the Splunk admin user for the Forwarder for management')]
         [ValidateNotNullorEmpty()]
         [ValidateLength(8,256)]
         [string]$SplunkPass
      )

#----------------------------------------------------[Imports]----------------------------------------------------

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

#------------------------------------------------[Initialisations]------------------------------------------------

# This gets the current working directory 
#$loc = Get-Location

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

# Installs Splunk to the default path $env:SystemDrive\Program Files\SplunkUniversalForwarder
function Install_Splunk($rindex,$dserv,$splunkU,$splunkP){
        
   # You must replace the arguements with the areguements you want to run on your own splunk forwarder, the default here will gather all Event Logs and Network performance. Leave the '/quiet' at the end
   Start-Process -FilePath $env:SystemDrive\splunkforwarder.msi –Wait -Verbose –ArgumentList "AGREETOLICENSE=yes SPLUNKUSERNAME=`"$($splunkU)`" SPLUNKPASSWORD=`"$($splunkP)`" RECEIVING_INDEXER=`"$($rindex)`" DEPLOYMENT_SERVER=`"$($dserv)`" WINEVENTLOG_APP_ENABLE=1 WINEVENTLOG_SEC_ENABLE=1 WINEVENTLOG_SYS_ENABLE=1 WINEVENTLOG_FWD_ENABLE=1 WINEVENTLOG_SET_ENABLE=1 ENABLEADMON=1 PERFMON=network /quiet"
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
Get-ServiceFiles -url "http://$($HostingServer)/splunkforwarder.msi" -path "$($env:SystemDrive)\splunkforwarder.msi" -sesh $s
Get-ServiceFiles -url "http://$($HostingServer)/Sysmon64.exe" -path "$($env:SystemDrive)\Program Files\sysmon\Sysmon64.exe" -sesh $s
Get-ServiceFiles -url "http://$($HostingServer)/Eula.txt" -path "$($env:SystemDrive)\Program Files\sysmon\Eula.txt" -sesh $s
Get-ServiceFiles -url "http://$($HostingServer)/sysmonconfig.xml" -path "$($env:SystemDrive)\Program Files\sysmon\sysmonconfig.xml" -sesh $s

# The Install_Splunk function is sent to the all remote endpoints and then called on all the endpoints at the same time. These are performed as jobs.
Write-Output "Installing Splunk Universal Forwarders, this can take a long time in virtual environments with low resources! Please wait..."
$installjob = Invoke-Command -Session $s -ScriptBlock $Function:Install_Splunk -ArgumentList $ReceivingIndexer,$DeploymentServer,$SplunkUsername,$SplunkPass -AsJob

#The job results are retrieved once the jobs are completed
Wait-Job $installjob | Out-Null
Get-ChildJobs $installjob

# The installation file is deleted
Invoke-Command -Session $s -ScriptBlock {Remove-Item $env:SystemDrive\splunkforwarder.msi}

# The Install_Sysmon function is sent to the all remote endpoints and then called on all the endpoints at the same time. These are performed as jobs.
Write-Output "Installing the Sysmon service, this can take a long time in virtual environments with low resources! Please wait..."
$installjob = Invoke-Command -Session $s -ScriptBlock $Function:Install_Sysmon -AsJob

#The job results are retrieved once the jobs are completed
Wait-Job $installjob | Out-Null
Get-ChildJobs $installjob

# Add the required config to gather Sysmon events to inputs.conf on the remote hosts, then restart the Splunk Forwarder to load the new inputs.conf file.
Invoke-Command -Session $s -ScriptBlock {
      add-content -Path "$env:SystemDrive\Program Files\SplunkUniversalForwarder\etc\system\local\inputs.conf" `
      -Value "`n`n[WinEventLog://Microsoft-Windows-Sysmon/Operational]";`
      add-content -Path "$env:SystemDrive\Program Files\SplunkUniversalForwarder\etc\system\local\inputs.conf" `
      -Value "disabled = false";`
      add-content -Path "$env:SystemDrive\Program Files\SplunkUniversalForwarder\etc\system\local\inputs.conf" `
      -Value "renderXml = true";`
      add-content -Path "$env:SystemDrive\Program Files\SplunkUniversalForwarder\etc\system\local\inputs.conf" `
      -Value "`n[WinEventLog://Microsoft-Windows-PowerShell/Operational]";`
      add-content -Path "$env:SystemDrive\Program Files\SplunkUniversalForwarder\etc\system\local\inputs.conf" `
      -Value "disabled = false";`
      Set-Location -Path "$env:SystemDrive\Program Files\SplunkUniversalForwarder\bin\"; .\splunk.exe restart
   }

foreach ($sesh in $s){
    Write-Host $s.ComputerName
    Invoke-Command -ScriptBlock {Write-Output $env:COMPUTERNAME; Get-Service SplunkForwarder; Get-Service Sysmon*}
}

# The sessions are closed and any open jobs removed
Write-Output "Closing session"
Remove-PSSession -Session $s
Remove-Job *