#Requires -Version 5
<#
.Synopsis
   Deploy Splunk Universal Forwarders to remote Windows hosts running PowerShell V3 and newer.

.DESCRIPTION
   This PowerShell script has been developed to deploy Splunk Universal Forwarders across windows devices using WinRM.
   You will require an Windows account that has the correct permissions on all hosts the forwarder will be installed on. Usually a domain account.
   By defult you must provide IP addresses and port numbers for the DEPLOYMENT SERVER and RECEIVING INDEXER. <host:port>
   These are provided are parameters when running the scipt. This flag accepts only a single receiver. 
   To specify multiple receivers (i.e. to implement load balancing), configure this setting through the Splunk CLI
   or outputs.conf. Ask your Splunk expert or Splunk documentation at https://docs.splunk.com/Documentation/Forwarder
   For remote hosts running PowerShell V3 and newer.
   PSv3 and above support the PS function for copying to a remote machine "Copy-Item -ToSession".
   
.PARAMETER DeploymentServer
   Required. 
   Specifies the IP address and port number of your Splunk deployment server: host:port

.PARAMETER ReceivingIndexer
   Required.
   Specifies the IP address and port number of your Splunk deployment server: host:port
                              
.EXAMPLE
   .\Deploy-SplunkForwarders.ps1 -DeploymentServer 192.168.1.10:8080 -ReceivingIndexer 192.168.1.10:8010

.EXAMPLE
   .\Deploy-SplunkForwarders.ps1 -D 192.168.1.10:8080 -R 192.168.1.10:8010

.INPUTS
   SplunkForwarder msi is required on the local machine and you will be prompted to select it.
   You will also be prompted for a username and password for the remote hosts.
   A text file containing one IP address per line for each hosts you want to deploy the forwarder to will be required.

.OUTPUTS
   Forwarders_Status_Log.txt is saved to the directory you run the script from.
   This is a log of the IP addresses and SplunkForwarder status.

.NOTES
   If any hosts in your environment run PowerShell V2 it is likely this script will not work for many of them as the 
   function Copy-Item is not fully compatible with V2 and often fails on transfers of files over a few MB.

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
         [string]$ReceivingIndexer         
      )

#----------------------------------------------------[Imports]----------------------------------------------------

Add-Type -AssemblyName PresentationFramework
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
      Filter = $filter
      Title = $title
      }
   [System.Windows.Forms.MessageBox]::Show($msg,'File Select','OK','Information')
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
   Start-Process -FilePath $env:SystemDrive\splunkforwarder.msi –Wait -Verbose –ArgumentList "AGREETOLICENSE=yes RECEIVING_INDEXER=`"$($rindex)`" DEPLOYMENT_SERVER=`"$($dserv)`" WINEVENTLOG_APP_ENABLE=1 WINEVENTLOG_SEC_ENABLE=1 WINEVENTLOG_SYS_ENABLE=1 WINEVENTLOG_FWD_ENABLE=1 WINEVENTLOG_SET_ENABLE=1 ENABLEADMON=1 /quiet"
}

#---------------------------------------------------[Execution]---------------------------------------------------

# User is promted for credentials
$creds = Get-Creds   

# The user is prompted to select the file containing the IP address or the targets
$hostsfile = Get-File -msg "You will now be prompted to select the file containing the IPs OR Hostnames of the targets you wish to gather information from."`
                      -filter “All files (*.*)| *.*” -title "Select your hosts file"
$computers = (Get-Content -path $hostsfile.FileName)
#$computers = $computers[1..($computers.Length-1)]  # IF the first line causes an error it is blank and needs to be removed, uncomment the start of this line.

# The user is prompted to select the splunk install msi
$splunkmsi = Get-File -msg "You must now select your splunk forwarder msi installer file" -filter "Install file (splunkforwarder*.msi)|splunkforwarder*.msi" -title "Select your Splunk Forwarder msi"

# Sessions are created to the computers in $computers, first installing the forwarder, then attempting to get the service status
Write-Output "Connecting..."
$s = New-PSSession -ComputerName $computers -Credential $creds

Write-Output "Transfering files"
# The splunk install file is copied to the root of the remote hard drive, this happens one endpoint at a time as powershell cannot copy one to many.
foreach ($sesh in $s){Copy-Item $splunkmsi.FileName -ToSession $sesh C:\splunkforwarder.msi}

Write-Output "Installing, this can take a long time in virtual environments with low resources! Please wait..."
# The fileinstall function is sent to the all remote endpoints and called on the endpoints at the same time. These are performed as jobs.
$installjob = Invoke-Command -Session $s -ScriptBlock $Function:Install_Splunk -ArgumentList $ReceivingIndexer,$DeploymentServer -AsJob

# The jobs are retrieved to display the results after the finish
Wait-Job $installjob | Out-Null
Get-ChildJobs $installjob

# The hostname and service status will be added to the $status array. The sessions are then closed
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
$statusPath = $loc.path + "\Forwarders_Status_Log.txt"
Write-Output $status
$status | out-file $statusPath

Invoke-Command -Session $s -ScriptBlock {Remove-Item $env:SystemDrive\splunkforwarder.msi} 
Write-Output "Closing sessions"
Remove-PSSession -Session $s
Remove-Job * 