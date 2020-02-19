#Requires -Version 5
<#
.Synopsis
    Retrieves the content of users Documents, Downloads and Desktops folders on remote hosts.

.DESCRIPTION
    Uses WINRM to connect to remote hosts and list files from the Documents, Downloads and Desktop folders of remote hosts.
    The content of the folders is output to the console and a CSV file saved to the chosen location
                              
.EXAMPLE
    .\Get-Folder-Content.ps1

.INPUTS
    You will be prompted for a username and password for the remote hosts.
    A text file containing one IP address per line for each hosts you want to check the agent status.
    Select an Output folder.

.OUTPUTS
    A folder for each remote computer will be created.
    A csv file will be created in the folders for each information type collected.

.FUNCTIONALITY
    Gets folder content of remote hosts.

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

Add-Type -AssemblyName System.Windows.Forms
[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

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

# The user is asked to select the output directory
function Get-Folder(){
        [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms")|Out-Null
        $foldername = New-Object System.Windows.Forms.FolderBrowserDialog
        $foldername.Description = "Select a folder"
        $foldername.rootfolder = "MyComputer"
        [System.Windows.Forms.Messagebox]::Show('You will now be prompted to select the folder to save the output to.','Folder Select','ok','information')
        $null = $foldername.ShowDialog()
        if (-Not $foldername.SelectedPath){
            $msgbox3 = [System.Windows.MessageBox]::Show('You must select a folder to output the results to...','Warning','OKCancel','warning')
            switch ($msgbox3){ ok {Get-Folder} cancel {exit}}
        }
        else{return $foldername}
    }

# Function for retrieving jobs and outputting to a csv
function Get-ChildJobs(){
    [CmdletBinding()]
    
                Param(                        
                [Parameter(ValueFromPipelineByPropertyName)]
                $jobs,$filename)
    
                process {
                Get-Job -IncludeChildJob | Wait-Job | Out-Null
                foreach ($j in $jobs.ChildJobs){@(Receive-Job $j | Export-Csv -NoTypeInformation -Path "$($output)$($j.location)\$($filename)") }
                Remove-Job *
                }
        }

function Get_FolderContent(){
    Get-Item -Path "$($env:userprofile)\..\*\Desktop\*" -ErrorAction SilentlyContinue | Select-Object -Property Mode,FullName
    Get-Item -Path "$($env:userprofile)\..\*\Documents\*" -ErrorAction SilentlyContinue | Select-Object -Property Mode,FullName
    Get-Item -Path "$($env:userprofile)\..\*\Downloads\*" -ErrorAction SilentlyContinue | Select-Object -Property Mode,FullName
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

# The user is asked to select the output directory
$foldername = Get-Folder

# The output folder is created in the chosen directory
$folder = Get-Date -Format dd-HHmmss
new-item -ItemType directory -path $foldername.SelectedPath -name "$folder"
$output = "$($foldername.SelectedPath)\$($folder)\"
Write-Output "Output folder: $output"

foreach ($c in $computers){
        new-item -ItemType directory -path "$output" -name "$c"
    }

$foldercontent = Invoke-Command -Session $s -ScriptBlock $function:Get_FolderContent -AsJob
Get-ChildJobs -jobs $foldercontent -filename "Folder_Content.csv"

Remove-PSSession $s