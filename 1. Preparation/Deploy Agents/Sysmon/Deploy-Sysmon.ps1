#Requires -Version 5
<#
.Synopsis
    Deploys Sysmon to remote Windows hosts running PowerShell V3 and newer.

.DESCRIPTION
    This PowerShell script has been developed to deploy Splunk Universal Forwarders across windows devices using WinRM.
    You will require an Windows account that has the correct permissions on all hosts the forwarder will be installed on. Usually a domain account.
    For remote hosts running PowerShell V3 and newer.
    PSv3 and above support the PS function for copying to a remote machine "Copy-Item -ToSession".
                              
.EXAMPLE
    .\Deploy-Sysmon.ps1

.INPUTS
    The Sysmon installer exe, sysmonconfig.xml and Eula.txt are required on the local machine and you will be prompted to select them.
    You will also be prompted for a username and password for the remote hosts.
    A text file containing one IP address per line for each hosts you want to deploy the forwarder to will be required.

.OUTPUTS
    Sysmon_Status_Log.txt is saved to the directory you run the script from.
    This is a log of the IP addresses and Sysmon status.

.FUNCTIONALITY
    Sysmon required files are sent to the remote hosts and sysmon is installed.

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

# The user is promted to select the 3 files needed for Sysmon to install
$sysmon64 = Get-File -msg "You will now be prompted to select the install .exe file for sysmon" -filter "Install file (Sysmon*.exe)|Sysmon*.exe" -title "Select your Sysmon install .exe"
$eula = Get-File -msg "You will now be prompted to select the sysmon EULA.txt" -filter "Text File (EULA.txt)|EULA.txt" -title "Select your Sysmon EULA text file"
$sysmonconfig = Get-File -msg "You will now be prompted to select the sysmonconfig.xml" -filter "xml File (sysmonconfig*.xml)|sysmonconfig*.xml" -title "Select your sysmon config xml file"


# Sessions are created to the computers in $computers, first copying the files over then installing the sysmon service, then attempting to get the service status
Write-Output "Connecting..."
$s = New-PSSession -ComputerName $computers -Credential $creds


# A directory is created for sysmon on the remote computers
Invoke-Command -Session $s -ScriptBlock {new-item -ItemType directory -path "$($env:SystemDrive)\Program Files\" -name "sysmon"}


# The 3 required files are transfered to the endpoints one at a time as powershell does not support copying one to many
Write-Output "Transfering files"
foreach ($sesh in $s){Copy-Item $sysmon64 -ToSession $sesh "$($env:SystemDrive)\Program Files\sysmon\Sysmon64.exe"}
foreach ($sesh in $s){Copy-Item $eula -ToSession $sesh "$($env:SystemDrive)\Program Files\sysmon\Eula.txt"}
foreach ($sesh in $s){Copy-Item $sysmonconfig -ToSession $sesh "$($env:SystemDrive)\Program Files\sysmon\sysmonconfig.xml"}


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
