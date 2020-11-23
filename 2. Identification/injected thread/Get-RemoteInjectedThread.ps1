#Requires -Version 5
<#
.Synopsis
    Copies, imports executes then deletes the full Get-InjectedThread.ps1 script.

.DESCRIPTION
    Uses WINRM to create remote sessions to hosts. Get-InjectedThread.ps1 is copied across to the remote hosts.
    It is then imported to the session. The function Get-InjectedThread is executed on the remote machine and
    results displayed on your host. The Get-InjectedThread.ps1 script is then removed from the remote machine
    to prevent tampering.
                              
.EXAMPLE
    .\Get_Injected_Remote_Test.ps1

.INPUTS
    Get-InjectedThread.ps1 is required to be in the same path as this script.
    You will be prompted for a username and password for the remote hosts.
    A text file containing one IP address per line for each hosts you want to deploy the forwarder to will be required.

.OUTPUTS

    ProcessName               : ThreadStart.exe
    ProcessId                 : 7784
    Path                      : C:\Users\tester\Desktop\ThreadStart.exe
    KernelPath                : C:\Users\tester\Desktop\ThreadStart.exe
    CommandLine               : "C:\Users\tester\Desktop\ThreadStart.exe"
    PathMismatch              : False
    ThreadId                  : 14512
    AllocatedMemoryProtection : PAGE_EXECUTE_READWRITE
    MemoryProtection          : PAGE_EXECUTE_READWRITE
    MemoryState               : MEM_COMMIT
    MemoryType                : MEM_PRIVATE
    BasePriority              : 8
    IsUniqueThreadToken       : False
    Integrity                 : MEDIUM_MANDATORY_LEVEL
    Privilege                 : SeChangeNotifyPrivilege
    LogonId                   : 999
    SecurityIdentifier        : S-1-5-21-386661145-2656271985-3844047388-1001
    UserName                  : DESKTOP-HMTGQ0R\SYSTEM
    LogonSessionStartTime     : 3/15/2017 5:45:38 PM
    LogonType                 : System
    AuthenticationPackage     : NTLM
    BaseAddress               : 4390912
    Size                      : 4096
    Bytes                     : {144, 195, 0, 0...}

.NOTES
    Credit and thanks to Jared Atkinson (@jaredcatkinson), https://gist.github.com/jaredcatkinson, for Get-InjectedThread and the above example output

.FUNCTIONALITY
    Gets injected threads on remote machines.

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


#---------------------------------------------------[Execution]---------------------------------------------------

# The install_Splunk script should be in the same folder as this script.
$GetinjectedLoc = $loc.Path + "\Get-InjectedThread.ps1"
if(-not (Test-Path $GetinjectedLoc)){Write-Error "This script requires Get-InjectedThread.ps1 to be in the same path. Exiting.."; Exit}

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

foreach ($sesh in $s){
        Copy-Item $GetinjectedLoc -ToSession $sesh $env:SystemDrive\Get-InjectedThread.ps1
        Write-Host "Checking $($sesh.Location)"
        Invoke-Command -Session $sesh -ScriptBlock {Import-Module $env:SystemDrive\Get-InjectedThread.ps1; Get-InjectedThread; Remove-Item $env:SystemDrive\Get-InjectedThread.ps1}
    }

Remove-PSSession -Session $s