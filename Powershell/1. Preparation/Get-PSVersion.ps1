<#
.Synopsis
   Queries remote computers for their powershell version and sorts them into 3 files.

.DESCRIPTION
   WINRM is used to connect to remote computers in the environment. The version of PowerShell is then queried on the remote host and added to the appropriate list. 
   The lists are then output to files. This is for other scripts that require lists of hosts to execute scripts on.
   You will require an Windows account that has the correct permissions on all hosts the forwarder will be installed on. Usually a domain account.
   Run the script and follow the prompts.

.EXAMPLE
   .\Get-PSVersion.ps1

.INPUTS
   You will be prompted for a username and password for the remote hosts.
   A text file containing one IP address per line for each hosts you want to deploy the forwarder to will be required.

.OUTPUTS
   Text files containing the IP's of relevant hosts:
   PSv3PlusHosts.txt
   PSv2Hosts.txt
   PSv1Hosts.txt

.FUNCTIONALITY
   Enumerates remote hosts PowerShell version

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
Global $loc = Get-Location
Global $v1computers = New-Object System.Collections.Generic.List[System.Object]
Global $v2computers = New-Object System.Collections.Generic.List[System.Object]
Global $v3pluscomputers = New-Object System.Collections.Generic.List[System.Object]

#---------------------------------------------------[Functions]---------------------------------------------------

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


# Gets the remote versions of PS
function Get-RemotePSversion(){
[CmdletBinding()]

        Param(                        
            [Parameter(ValueFromPipelineByPropertyName)]
            $sesh
        )
        $verJob = Invoke-Command -Session $sesh -ScriptBlock{$PSVersionTable.PSVersion.Major} -AsJob
        foreach ($c in $verJob.ChildJobs){
            $ver = Receive-Job $c -Keep
            if   ($ver -gt 2) {$v3pluscomputers.add($c.location)}
            elif ($ver -eq 2) {$v2computers.add($c.location)}
            elif ($ver -eq 1) {$v1computers.add($c.location)}
            else {Write-Error "Error with PS version on" + $c.location}
            Remove-Job $c
        }
    }

function Save-File{
[CmdletBinding()]

        Param(                        
            [Parameter(ValueFromPipelineByPropertyName)]
            $hosts,
            [Parameter(ValueFromPipelineByPropertyName)]
            $filename,
            [Parameter(ValueFromPipelineByPropertyName)]
            $ver
        )
        $filePath = $loc.path + "\" + $filename + ".txt"
        Write-Host $ver + " hosts:"
        Write-Host $hosts
        $hosts | out-file $filePath
    }
    
#---------------------------------------------------[Execution]---------------------------------------------------

# User is promted for credentials
$creds = Get-Creds

# The user is prompted to select the file containing the IP address or the targets
$hostsfile = Get-File -msg "You will now be prompted to select the file containing the IPs OR Hostnames of the targets you wish to gather information from." -filter “All files (*.*)| *.*” -title "Select your hosts file"
# The file is read by PowerShell adding the contents to $computers
$computers = (Get-Content -path $hostsfile.FileName) 
#$computers = $computers[1..($computers.Length-1)]  # IF the first line causes an error, it is blank and needs to be removed, uncomment the start of this line.


# Sessions are created to the computers in $computers
Write-Output "Connecting..."
$s = New-PSSession -ComputerName $computers -Credential $creds


# The remote versions of PowerShell are retrieved
Get-RemotePSversion -sesh $s

# Files are saved containing host IP's
Save-File -hosts $v1computers -filename "PSv1Hosts" -ver "PSv1"
Save-File -hosts $v2computers -filename "PSv2Hosts" -ver "PSv2"
Save-File -hosts $v3pluscomputers -filename "PSv3PlusHosts" -ver "PSv3+"

Write-Output "Closing sessions"
Remove-PSSession -Session $s
Remove-Job *