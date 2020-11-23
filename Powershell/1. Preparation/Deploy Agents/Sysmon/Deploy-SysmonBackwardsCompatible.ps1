#Requires -Version 5
<#
.Synopsis
    Deploys Sysmon to remote Windows hosts that are running PowerShell V2 and newer.

.DESCRIPTION
    This PowerShell script has been developed to deploy Splunk Universal Forwarders across windows devices using WinRM.
    You will require an Windows account that has the correct permissions on all hosts the forwarder will be installed on. Usually a domain account.
    For remote hosts running PowerShell V3 and newer.
    PSv3 and above support the PS function for copying to a remote machine "Copy-Item -ToSession".
    PSv2 does not support Copy-Item -ToSession, the command often fails with files over a few MB.
    For this reason the script has been set up to require you to host the 3 Sysmon files on a http server. Method for doing so is in the notes below.

.PARAMETER HostingServer
    Required. 
    Specifies the IP address and port number of the HTTP server hosting your files.
                              
.EXAMPLE
    .\Deploy-SysmonBackwardsCompatible.ps1 -HostingServer 10.10.10.10:80

.INPUTS
   You will be prompted for a username and password for the remote hosts.
   A text file containing one IP address per line for each hosts you want to deploy the forwarder to will be required.
   The IP:PORT of the HTTP server hosting your Sysmon files.
   Sysmon files required: Sysmon64.exe, Eula.txt, sysmonconfig.xml

.OUTPUTS
    Sysmon_Status_Log.txt is saved to the directory you run the script from.
    This is a log of the IP addresses and Sysmon status.

.NOTES
    This script is designed to work with the 64bit installer simply because of the naming.
    To download and install the 32bit version you can either change the script where the 
    Get-SysmonFiles function is called with the installer name passed as a parameter or 
    change the name of your executable to match Sysmon64.exe

.FUNCTIONALITY
    Sends commands to remote hosts to download the required files from specified server and install the Sysmon service.

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
         [string]$HostingServer         
      )

#----------------------------------------------------[Imports]----------------------------------------------------

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

#------------------------------------------------[Initialisations]------------------------------------------------

# This gets the current working directory 
$loc = Get-Location

#---------------------------------------------------[Functions]---------------------------------------------------

# The user is asked to select certain files 
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
        [System.Windows.MessageBox]::Show($msg,'File Select','ok','information')
        $null = $FileBrowser.ShowDialog()
        if (-Not $FileBrowser.FileName){
            $msgbox1 = [System.Windows.Forms.Messagebox]::Show('You must select a file to continue...','File Select','OKCancel','warning')
            switch ($msgbox1){ ok {Get-File} cancel {exit}}
        } 
        return $FileBrowser.FileName
    }


# You will be prompted for your username and password when you run the script. !!!NEVER STORE YOUR PASSWORD IN PLAINTEXT!!!
# If you do not want to type in your usename each time you run the script, uncomment and replace the credentials below with the domian name and username
function Get-Creds(){

        $creds = Get-Credential -Message "Enter your domain credentials to connect to the end points" # -UserName domain\user
        if (-Not $creds.UserName -or -not $creds.Password){
            $msgbox2 = [System.Windows.Forms.Messagebox]::Show('You must enter your username and password to create the sessions...','Warning','OKCancel','warning')
            switch ($msgbox2){ ok {Get-Creds} cancel {exit}}
        }
        return $creds
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

function Get-SysmonFiles {
    param (
        [Parameter(ValueFromPipelineByPropertyName)]
            $url,$path,$sesh
            )

        # The file is downloaded from the HTTP server to the remote hosts
        $downloadjob = Invoke-Command -Session $sesh -ScriptBlock {(New-Object Net.WebClient).DownloadFile($using:url, $using:path) } -AsJob
        Wait-Job $downloadjob | Out-Null
        Get-ChildJobs -jobs $downloadjob
}


function Install_Sysmon() 
{
& "$($env:SystemDrive)\Program Files\sysmon\Sysmon64.exe" -accepteula -i "$($env:SystemDrive)\Program Files\sysmon\sysmonconfig.xml" 2> $null
}

#---------------------------------------------------[Execution]---------------------------------------------------

# User is promted for credentials
$creds = Get-Creds
# The user is prompted to select the file containing the IP address or the targets
$hostsfile = Get-File -msg "You will now be prompted to select the file containing the IPs OR Hostnames of the targets you wish to gather information from." -filter “All files (*.*)| *.*” -title "Select your hosts file"
$computers = (Get-Content -path $hostsfile)             # The file is read by powershell adding the contents to $computers
#$computers = $computers[1..($computers.Length-1)]      # The first line is blank and needs to be removed


# Sessions are created to the computers in $computers, first copying the files over then installing the sysmon service, then attempting to get the service status
Write-Output "Connecting..."
$s = New-PSSession -ComputerName $computers -Credential $creds

# A directory is created for sysmon on the remote computers
Invoke-Command -Session $s -ScriptBlock {new-item -ItemType directory -path "$($env:SystemDrive)\Program Files\" -name "sysmon"}

Write-Output "Downloading"
Get-SysmonFiles -url "http://$($HostingServer)/Sysmon64.exe" -path "$($env:SystemDrive)\Program Files\sysmon\Sysmon64.exe" -sesh $s
Get-SysmonFiles -url "http://$($HostingServer)/Eula.txt" -path "$($env:SystemDrive)\Program Files\sysmon\Eula.txt" -sesh $s
Get-SysmonFiles -url "http://$($HostingServer)/sysmonconfig.xml" -path "$($env:SystemDrive)\Program Files\sysmon\sysmonconfig.xml" -sesh $s


# The install function is invoked across all machines in $computers simultaneously
Write-Output "Installing, this can take a long time in virtual environments with low resources! Please wait..."
$installjob = Invoke-Command -Session $s -ScriptBlock $Function:Install_Sysmon -AsJob
#The job results are retrieved once the jobs are completed
Wait-Job $installjob
Get-ChildJobs $installjob


# The hostname and service status from each endpoint will be added to the $status list. 
$status = New-Object System.Collections.Generic.List[System.Object]
$statusjob = $(Invoke-Command -Session $s -ScriptBlock {(Get-Service Sysmon*).Status} 2> $null)
foreach ($job in $statusjob.ChildJobs){
    $return = Receive-Job $job
    if ($return.status -eq 0) {$return = "Service not found!"}
    $status.Add("$($job.location) - $($return)")
}

# The sessions are closed
Write-Output "Closing session"
Remove-PSSession -Session $s
Remove-Job *

# $status is output to both a log file and the terminal to end the script
$statusPath = $loc.path + "\Sysmon_Status_Log.txt"
$status | out-file $statusPath
Write-Output $status
