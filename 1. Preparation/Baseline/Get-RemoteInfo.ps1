#Requires -Version 5
<#
.Synopsis
   Gets a selection of baselining information from remote hosts

.DESCRIPTION
    This scripts uses WINRM to connect to remote hosts and queries them for a range of information:
    Processes, Services, NetRoutes, DNS Cache, Arp Table, dll list, Shares, Scheduled Tasks, NetStats,
    Cached Kerberos Tickets, Prefetch Items. File hashes of the folders for System32, Recycle Bin, Temp files, Users
                            
.EXAMPLE
    .\Get_Remote_Info.ps1

.INPUTS
   You will be prompted for a username and password for the remote hosts.
   A text file containing one IP address per line for each hosts you want to check the agent status.
   Select an Output folder.

.OUTPUTS
    A folder for each remote computer will be created.
    A csv file will be created in the folders for each information type collected.

.FUNCTIONALITY
    Connect to remote hosts and query them for information

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

$folder = Get-Date -Format dd-HHmmss
$system = "c:\windows\sys*\"
$temp = "C:\Windows\Temp\"
$recyclebin ="C:\`$Recycle.Bin\"
$users = "C:\Users\"

#---------------------------------------------------[Functions]---------------------------------------------------

# The user is asked to select the file containing the IP address or the targets
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

# Function for retrieving jobs and outputting to a csv
function Save-RemoteJob(){
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

#---------------------------------------------------[Execution]---------------------------------------------------

# User is promted for credentials
$creds = Get-Creds

# The user is prompted to select the file containing the IP address or the targets
$hostsfile = Get-File -msg "You will now be prompted to select the file containing the IPs OR Hostnames of the targets you wish to gather information from." -filter “All files (*.*)| *.*” -title "Select your hosts file"
# The file is read by PowerShell adding the contents to $computers
$computers = (Get-Content -path $hostsfile.FileName) 
#$computers = $computers[1..($computers.Length-1)]  # IF the first line causes an error, it is blank and needs to be removed, uncomment the start of this line.

# User selects output folder
$foldername = Get-Folder


# The output folder is created in the chosen directory
new-item -ItemType directory -path $foldername.SelectedPath -name "$folder"
$output = "$($foldername.SelectedPath)\$($folder)\"
Write-Output "Output folder: $output"

# create a script log that will record the entire PS script
new-item -ItemType file -path "$output" -Name "scriptlog.txt"
# sets the script log as a variable
$scriptlog = "$($output)scriptlog.txt"
# this starts the script log, trying to just log modules that can't be enumerated/pulled has proved problematic, 
# this catches more data than required but is better than not having the data. It will also log any unexpected erros
Start-Transcript -Append $scriptlog


foreach ($c in $computers)
{
    new-item -ItemType directory -path "$output" -name "$c"
}

# Sessions are connected
Write-Output "Connecting..."
$s = New-PSSession -ComputerName $computers -Credential $creds
Write-Output "Connected! Querying:"


Write-Output "Processes.."
$procJob = Invoke-Command -Session $s -ScriptBlock{get-wmiobject win32_process | Select-Object Name,ProcessID,ParentProcessID,CommandLine,ExecutablePath} -AsJob
Save-RemoteJob $procJob "processes.csv"
Write-Output "Services.."
$servJob = Invoke-Command -Session $s -ScriptBlock{Get-Service} -AsJob 
Save-RemoteJob $servJob "services.csv"
Write-Output "Netroute.."
$netJob = Invoke-Command -Session $s -ScriptBlock{Get-NetRoute} -AsJob
Save-RemoteJob $netJob "Netroute.csv"
Write-Output "DNS.."
$dnsJob = Invoke-Command -Session $s -ScriptBlock{Get-DnsClientCache} -AsJob
Save-RemoteJob $dnsJob "dns.csv"
Write-Output "arp table.."
$arpJob = Invoke-Command -Session $s -ScriptBlock{Get-NetNeighbor -AddressFamily IPv4} -AsJob
Save-RemoteJob $arpJob "arp.csv"
Write-Output "dll list.."
$dllJob = Invoke-Command -Session $s -ScriptBlock{get-process -module} -AsJob
Save-RemoteJob $dllJob "dlllist.csv"
Write-Output "Net shares.."
$sharesJob = Invoke-Command -Session $s -ScriptBlock{net share} -AsJob
Save-RemoteJob $sharesJob "netshare.csv"
Write-Output "Scheduled Tasks.."
$tasksJob = Invoke-Command -Session $s -ScriptBlock{Get-ScheduledTask} -AsJob
Save-RemoteJob $tasksJob "scheduledtask.csv"
Write-Output "More schtasks.."
$schJob = Invoke-Command -Session $s -ScriptBlock{schtasks /query} -AsJob
Save-RemoteJob $schJob "schtasks.csv"
Write-Output "Netstat.."
$netstat = Invoke-Command -Session $s -ScriptBlock{Get-NetTCPConnection -State Established,Listen,TimeWait} -AsJob
Save-RemoteJob $netstat "netstat.csv"
Write-Output "pulling Kerberos tickets.."
$kerb = Invoke-Command -Session $s -ScriptBlock{klist} -AsJob
Save-RemoteJob $kerb "Kerberos.csv"
Write-Output "prefetch items.."
$prefetch = Invoke-Command -Session $s -ScriptBlock{Get-ChildItem c:\windows\prefetch | Sort-Object LastWriteTime} -AsJob
Save-RemoteJob $prefetch "prefetch.csv"
Write-Output "hashing Sys* folders, please be patient.."
$syshash = Invoke-Command -Session $s -ScriptBlock{Get-ChildItem $Using:system -Recurse | Get-FileHash -Algorithm MD5} -AsJob
Save-RemoteJob $syshash "system32hash.csv"
Write-Output "Recycle Bin.."
$recyclehash = Invoke-Command -Session $s -ScriptBlock{Get-ChildItem $Using:recyclebin -Recurse | Get-FileHash -Algorithm MD5} -AsJob
Save-RemoteJob $recyclehash "recyclebin.csv"
Write-Output "Temp files.."
$temphash = Invoke-Command -Session $s -ScriptBlock{Get-ChildItem $Using:temp -Recurse | Get-FileHash -Algorithm MD5} -AsJob
Save-RemoteJob $temphash "temp.csv"
Write-Output "User Folders.."
$usrhash = Invoke-Command -Session $s -ScriptBlock{Get-ChildItem $Using:users -Recurse | Get-FileHash -Algorithm MD5} -AsJob
Save-RemoteJob $usrhash "users.csv"

Write-Output "Pulling logon sessions"
$logonsessions = Invoke-Command -Session $s -ScriptBlock{
    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [string[]]
        $ComputerName = 'localhost'
    )

    $LogonMap = @{}
    Get-WmiObject -ComputerName $ComputerName -Class Win32_LoggedOnUser  | ForEach-Object{
    
        $Identity = $_.Antecedent | Select-String 'Domain="(.*)",Name="(.*)"'
        $LogonSession = $_.Dependent | Select-String 'LogonId="(\d+)"'

        $LogonMap[$LogonSession.Matches[0].Groups[1].Value] = New-Object PSObject -Property @{
            Domain = $Identity.Matches[0].Groups[1].Value
            UserName = $Identity.Matches[0].Groups[2].Value
        }
    }

    Get-WmiObject -ComputerName $ComputerName -Class Win32_LogonSession | ForEach-Object{
        $LogonType = $Null
        switch($_.LogonType) {
            $null {$LogonType = 'None'}
            0 { $LogonType = 'System' }
            2 { $LogonType = 'Interactive' }
            3 { $LogonType = 'Network' }
            4 { $LogonType = 'Batch' }
            5 { $LogonType = 'Service' }
            6 { $LogonType = 'Proxy' }
            7 { $LogonType = 'Unlock' }
            8 { $LogonType = 'NetworkCleartext' }
            9 { $LogonType = 'NewCredentials' }
            10 { $LogonType = 'RemoteInteractive' }
            11 { $LogonType = 'CachedInteractive' }
            12 { $LogonType = 'CachedRemoteInteractive' }
            13 { $LogonType = 'CachedUnlock' }
            default { $LogonType = $_.LogonType}
        }

        New-Object PSObject -Property @{
            UserName = $LogonMap[$_.LogonId].UserName
            Domain = $LogonMap[$_.LogonId].Domain
            LogonId = $_.LogonId
            LogonType = $LogonType
            AuthenticationPackage = $_.AuthenticationPackage
            Caption = $_.Caption
            Description = $_.Description
            InstallDate = $_.InstallDate
            Name = $_.Name
            StartTime = $_.ConvertToDateTime($_.StartTime)
            ComputerName = $_.PSComputerName
        }
    }} -AsJob

Save-RemoteJob $logonsessions "logonsessions.csv"

Remove-PSSession -Session $s

# This opens a window to the folder containing your pulled data
Invoke-Item $output