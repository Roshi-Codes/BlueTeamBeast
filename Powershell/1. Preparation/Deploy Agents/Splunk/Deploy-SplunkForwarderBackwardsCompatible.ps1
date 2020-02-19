#Requires -Version 5
<#
.Synopsis
   Deploy Splunk Universal Forwarders to remote Windows hosts that are running PowerShell V2 and newer.

.DESCRIPTION
   This PowerShell script has been developed to deploy Splunk Universal Forwarders across windows devices using WinRM where the remote host is running PowerShell v2.
   You will require an Windows account that has the correct permissions on all hosts the forwarder will be installed on. Usually a domain account.
   By defult you must provide IP addresses and port numbers for the DEPLOYMENT SERVER, RECEIVING INDEXER and the HOST hosting your splunk msi file. <host:port>
   These are provided are parameters when running the scipt. This flag accepts only a single receiver. 
   To specify multiple receivers (i.e. to implement load balancing), configure this setting through the Splunk CLI
   or outputs.conf. Ask your Splunk expert or Splunk documentation at https://docs.splunk.com/Documentation/Forwarder
   PSv2 does not support Copy-Item -ToSession, the command often fails with files over a few MB.
   For this reason the script has been set up to require you to host the SplunkForwarder msi on a http server. Method for doing so is in the notes below.
   
.PARAMETER DeploymentServer
   Required. 
   Specifies the IP address and port number of your deployment server: host:port

.PARAMETER ReceivingIndexer
   Required. 
   Specifies the IP address and port number of your deployment server: host:port

.PARAMETER HostingServer
   Required. 
   Specifies the IP address and port number of the HTTP server hosting your SplunkForwarder msi
                              
.EXAMPLE
   .\Deploy-SplunkForwarders.ps1 -DeploymentServer 192.168.1.10:8080 -ReceivingIndexer 192.168.1.10:8010 -HostingServer 10.10.10.10:80

.EXAMPLE
   .\Deploy-SplunkForwarders.ps1 -D 192.168.1.10:8080 -R 192.168.1.10:8010 -H 10.10.10.10:80

.INPUTS
   You will be prompted for a username and password for the remote hosts.
   A text file containing one IP address per line for each hosts you want to deploy the forwarder to will be required.
   The IP:PORT of the HTTP server hosting your SplunkForwarder msi.
   Deployment and Recieving Indexer IP:PORT combinations for Splunk.

.OUTPUTS
   Forwarders_Status_Log_v2.txt is saved to the directory you run the script from.
   This is a log of the IP addresses and SplunkForwarder status.

.NOTES
   To host the SplunkForwarder msi on a HTTP server, first rename the msi installer to splunkforwarder.msi (Removing version number) 
   One of the easiest ways to server it on a HTTP server is to create a dedicated folder on a linux server and run a simple http server in the folder:
   "Python -m SimpleHTTPServer"

.FUNCTIONALITY
   Deploying SplunkForwarders to remote hosts.

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
         
         [Alias("H")]
         [Parameter(ValueFromPipelineByPropertyName, Mandatory=$True, 
                     HelpMessage='You must enter an IP and Port. Example: "192.168.1.1:8000"')]
         [ValidateNotNullorEmpty()]
         [ValidateLength(9,21)]
         [ValidatePattern('^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|`
                           2[0-4][0-9]|25[0-5]):([0-9]{1,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2]`
                           [0-9]|6553[0-5])')]
         [string]$HostingServer         
      )
      
#----------------------------------------------------[Imports]----------------------------------------------------

Add-Type -AssemblyName System.Windows.Forms
[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

#------------------------------------------------[Initialisations]------------------------------------------------

# This gets the current working directory 
$loc = Get-Location

#---------------------------------------------------[Functions]---------------------------------------------------

# You will be prompted for your username and password when you run the script. !!!NEVER STORE YOUR PASSWORD IN PLAINTEXT!!!
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
      
      $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
         InitialDirectory = [Environment]::GetFolderPath('Desktop') 
         Title = $title
         }
      [System.Windows.Forms.MessageBox]::Show($msg,'File Select','ok','information')
      $null = $FileBrowser.ShowDialog()
      if (-Not $FileBrowser.FileName){
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


function Install_Splunk($rindex,$dserv){
        
        # You must replace the arguements with the areguements you want to run on your own splunk forwarder, leave the '/quiet' at the end
        Start-Process -FilePath $env:SystemDrive\splunkforwarder.msi –Wait -Verbose –ArgumentList "AGREETOLICENSE=yes RECEIVING_INDEXER=`"$($rindex)`" DEPLOYMENT_SERVER=`"$($dserv)`" WINEVENTLOG_APP_ENABLE=1 WINEVENTLOG_SEC_ENABLE=1 WINEVENTLOG_SYS_ENABLE=1 WINEVENTLOG_FWD_ENABLE=1 WINEVENTLOG_SET_ENABLE=1 SPLUNKUSER=admin GENRANDOMPASSWORD=1 ENABLEADMON=1 /quiet"
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

Write-Output "Downloading"
# Location of your hosted splunkforwarder - simple python http server will work.
$url = "http://$($HostingServer)/splunkforwarder.msi"
# Path that the msi is saved to on the remote host - If you change this you must change the location to match thoughout the rest of the script.
$path = "$($env:SystemDrive)\splunkforwarder.msi"

# The file is downloaded from the HTTP server to the remote hosts
$downloadjob = Invoke-Command -Session $s -ScriptBlock {(New-Object Net.WebClient).DownloadFile($using:url, $using:path) } -AsJob
Wait-Job $downloadjob | Out-Null
Get-ChildJobs -jobs $downloadjob

# The install command is sent to the remote hosts
Write-Output "Installing, this can take a long time in virtual environments with low resources! Please wait..."
$installjob = Invoke-Command -Session $s -ScriptBlock $Function:Install_Splunk -ArgumentList $ReceivingIndexer,$DeploymentServer -AsJob
Wait-Job $installjob | Out-Null
Get-ChildJobs -jobs $installjob

# The hostname and service status will be added to the $status list.
$statusjob = Invoke-Command -Session $s -ScriptBlock {(Get-Service SplunkForwarder).Status} -AsJob
Wait-Job $statusjob | Out-Null

$status = New-Object System.Collections.Generic.List[System.Object]

foreach ($job in $statusjob.ChildJobs){
         $job | Out-Null
         $return = Receive-Job $job
         
         if ($return.status -eq 0) {$return = "Service not found!"}
         else {$return = $return | Select-Object  -Property PSComputerName,Value}
         $status.Add($return)
}

# $status is output to both a log file and the terminal to end the script
$statusPath = $loc.path + "\Forwarders_Status_Log_v2.txt"
Write-Output $status
$status | out-file $statusPath

# SplunkForwarder install file is cleaned up on remote hosts
Invoke-Command -Session $s -ScriptBlock {Remove-Item $env:SystemDrive\splunkforwarder.msi} 

# Sessions are closed to remote hosts
Write-Output "Closing sessions"
Remove-PSSession -Session $s
Remove-Job * 