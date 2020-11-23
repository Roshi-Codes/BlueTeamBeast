#Requires -Version 5
<#
.Synopsis
   Queries remote hosts for specific processes and/or files

.DESCRIPTION
    This script uses WINRM to connenct to remote hosts and searches for named processes and files
    Specify the process names or file names in the Initialisations below.
                              
.EXAMPLE
    .\Find-Process-or-File.ps1

.INPUTS
    Modify the arrays in the Initialisations below.

.OUTPUTS
    The computer name and process/file name are output to the console if found.

.FUNCTIONALITY
    Search remote hosts for processes and files.

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

Global $processes = ("exampleprocess1", "exampleprocess2", "powershell")
Global $files = ("example1","example2")

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


# This function gets the processes from an endpoint and checks if any match with the processes in $processes below
function Find-Process
        {
        # $processes is an array of processes you want to search for.
        Write-Output "Checking processes on $($env:COMPUTERNAME))"
        Foreach ($process in $processes)
            {
            if($null -ne (Get-Process $process -ErrorAction SilentlyContinue)) 
                {
                # Uncomment the line below to stop any found processes. BE CAREFUL killing processes
                ####Stop-Process -Name $process -Force  ### WARNING ARE YOU SURE YOU WANT TO UNCOMMENT THIS LINE?
                Write-Output "Process found on $env:COMPUTERNAME!!!!"
                }
        }
    }


# This function searches the downloads folder for files specified in $files below
function Find-File
        {
        # $files is an array of file names to search for, change as needed
        Write-Output "Checking files on $($env:COMPUTERNAME)"
        foreach ($file in $files)
            {
            if($null -ne (Get-ChildItem -Path "$($env:userprofile)\..\*\Downloads\*" -Filter *$file* -ErrorAction SilentlyContinue))
                {
                Write-Output "$($file) found on $env:COMPUTERNAME!!!!"
                }
            }
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

# This program can be run once or left to repeatedly search until stopped with 'ctl + C' by uncommenting lines 77, 80 and 81
# If you choose to run until stopped it is recommended to remove any open sessions from powershell using remove-pssession after using 'ctrl + c' to cancel
# being careful not to kill any sessions you may have open in other windows
##while( 1 -eq 1){
    Invoke-Command -Session $s -ScriptBlock ${function:Find-Process}
    Invoke-Command -Session $s -ScriptBlock ${function:Find-File}
##    Start-Sleep -s 60
##}

Remove-PSSession $sessions