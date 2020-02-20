#Requires -Version 5
<#
.Synopsis
    Copies, imports, executes Get-InjectedThread, then deletes the full Stop-Thread.ps1 script.

.DESCRIPTION
    Uses WINRM to create remote sessions to hosts. Stop-Thread.ps1 is copied across to the remote hosts.
    It is then imported to the session. The function Stop-Thread is executed on the remote machine and
    results displayed on your host. The Stop-Thread.ps1 script is then removed from the remote machine
    to prevent tampering.

.PARAMETER ThreadID
    Required
    The ThreadID of the Thread you wish to stop.
                              
.EXAMPLE
    .\Stop_Remote_Thread.ps1 -ThreadID 1234 -RemoteHost 192.168.1.1

.INPUTS
    Stop-Thread.ps1 is required to be in the same path as this script.
    You will be prompted for a username and password for the remote hosts.
    A text file containing one IP address per line for each hosts you want to deploy the forwarder to will be required.

.NOTES
    Credit and thanks to Jared Atkinson (@jaredcatkinson), https://gist.github.com/jaredcatkinson, for Stop-Thread.ps1

.FUNCTIONALITY
    Terminates a specified Thread on a remote machine based on thread ID.

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
        [Alias("Id")]                        
        [Parameter(ValueFromPipelineByPropertyName, Mandatory=$True, 
            HelpMessage='You must enter a Threadid"')]
        [ValidateNotNullorEmpty()]
        [string]$ThreadId,  
         
        [Alias("IP")]
        [Parameter(ValueFromPipelineByPropertyName, Mandatory=$True, 
                    HelpMessage='You must enter an IP and Port. Example: "192.168.1.1:8000"')]
        [ValidateNotNullorEmpty()]
        [ValidateLength(9,21)]
        [ValidatePattern('^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|`
                          2[0-4][0-9]|25[0-5])$')]
        [string]$RemoteHost

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

#---------------------------------------------------[Execution]---------------------------------------------------

# The install_Splunk script should be in the same folder as this script.
$StopThreadLoc = $loc.Path + "\Stop-Thread.ps1"
if(-not (Test-Path $StopThreadLoc)){Write-Error "This script requires Stop-Thread.ps1 to be in the same path. Exiting.."; Exit}

# User is promted for credentials
$creds = Get-Creds

# Sessions are created to the computers in $computers
Write-Output "Connecting..."
$s = New-PSSession -ComputerName $RemoteHost -Credential $creds

foreach ($sesh in $s){
        Copy-Item $StopThreadLoc -ToSession $sesh $HOME\Stop-Thread.ps1
        Write-Host "Checking $($sesh.Location)"
        Invoke-Command -ComputerName $sesh -ScriptBlock {Import-Module $HOME\Stop-Thread.ps1; Stop-Thread -ThreadId using:$ThreadId ; Remove-Item $HOME\Stop-Thread.ps1}
    }

Remove-PSSession $s