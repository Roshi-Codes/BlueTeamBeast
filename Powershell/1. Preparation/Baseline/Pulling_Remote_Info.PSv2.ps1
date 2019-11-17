Add-Type -AssemblyName System.Windows.Forms
[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

# The user is asked to select the file containing the IP address or the targets
function filegrab(){
$FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ InitialDirectory = [Environment]::GetFolderPath('Desktop') }
[System.Windows.Forms.MessageBox]::Show('You will now be prompted to select the file containing the IPs OR Hostnames of the targets you wish to gather information from.','File Select','ok','information')
$null = $FileBrowser.ShowDialog()
if (-Not $FileBrowser.FileName){
$msgbox1 = [System.Windows.Forms.Messagebox]::Show('You must select a file to continue...','File Select','OKCancel','warning')
switch ($msgbox1){ ok {filegrab} cancel {exit}}
}
$computers = (get-content -path $FileBrowser.FileName)
return $computers
}

$computers = filegrab
$computers = $computers[1..($computers.Length-1)]

# The user is asked to select the output directory
function getfolder(){
[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms")|Out-Null
$foldername = New-Object System.Windows.Forms.FolderBrowserDialog
$foldername.Description = "Select a folder"
$foldername.rootfolder = "MyComputer"
[System.Windows.Forms.Messagebox]::Show('You will now be prompted to select the folder to save the output to.','Folder Select','ok','information')
$null = $foldername.ShowDialog()
if (-Not $foldername.SelectedPath){
$msgbox3 = [System.Windows.MessageBox]::Show('You must select a folder to output the results to...','Warning','OKCancel','warning')
switch ($msgbox3){ ok {getfolder} cancel {exit}}
}
else{return $foldername}
}
$foldername = getfolder

# You will be prompted for your username and password when you run the script. !!!NEVER STORE YOUR PASSWORD IN PLAINTEXT!!!
# If you do not want to type in your usename each time you run the script, uncomment and replace the credentials below with the domian name and username
function getcreds(){
$creds = Get-Credential -Message "Enter your domain credentials to connect to the end points" # -UserName domain\user
if (-Not $creds.UserName -or -not $creds.Password){
$msgbox2 = [System.Windows.Forms.Messagebox]::Show('You must enter your username and password to create the sessions...','Warning','OKCancel','warning')
switch ($msgbox2){ ok {getcreds} cancel {exit}}
}
return $creds
}
$creds = getcreds
 
$folder = Get-Date -Format dd-HHmmss
$system = "c:\windows\sys*\"
$temp = "C:\Windows\Temp\"
$recyclebin ="C:\`$Recycle.Bin\"
$users = "C:\Users\"

# The output folder is created in the chosen directory
new-item -ItemType directory -path $foldername.SelectedPath -name "$folder"
$output = "$($foldername.SelectedPath)\$($folder)\"
echo "Output folder: $output"

#create a script log that will record the entire PS script
new-item -ItemType file -path "$output" -Name "scriptlog.txt"
#sets the script log as a variable
$scriptlog = "$($output)scriptlog.txt"
#this starts the script log, trying to just log modules that can't be enumerated/pulled has proved problematic, this catches more data than required but is better than not having the data. It will also log any unexpected erros
Start-Transcript -Append $scriptlog

# Function used for hashing
function hasher {
    [CmdletBinding()]
    Param (
        $hashpath
    )

    $md5 = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
    $result = @{}

    Function Hash-It {

            [CmdletBinding()]

            Param(                        
            [Parameter(ValueFromPipelineByPropertyName=$true)]
            $FullName)

            process {
            try {
            $hash = [System.BitConverter]::ToString($md5.ComputeHash([System.IO.File]::ReadAllBytes($FullName)))
            $result.add($FullName, $hash)
            
            }
            catch{}
            }
    }

    dir $hashpath -Recurse | Hash-It
    $result.GetEnumerator() | Select-Object -Property Key,Value
}   

# Function for retrieving jobs and outputting to a csv
function jobretrieve(){
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


foreach ($c in $computers)
{
    new-item -ItemType directory -path "$output" -name "$c"
}


# Sessions are connected
echo "Connecting..."
$s = New-PSSession -ComputerName $computers -Credential $creds
echo "Connected! Querying:"


echo "Processes.."
$procJob = Invoke-Command -Session $s -ScriptBlock{get-wmiobject win32_process | select Name,ProcessID,ParentProcessID,CommandLine,ExecutablePath} -AsJob
jobretrieve -jobs $procJob -filename "processes.csv"

echo "Services.."
$servJob = Invoke-Command -Session $s -ScriptBlock{Get-Service} -AsJob 
jobretrieve -jobs $servJob -filename "services.csv"

#echo "Netroute.."
#$netJob = Invoke-Command -Session $s -ScriptBlock{Get-NetRoute} -AsJob #

echo "DNS.."
$dnsJob = Invoke-Command -Session $s -ScriptBlock{ipconfig /displaydns} -AsJob
jobretrieve -jobs $dnsJob -filename "dns.csv"

#echo "arp table.."
#$arpJob = Invoke-Command -Session $s -ScriptBlock{Get-NetNeighbor -AddressFamily IPv4} -AsJob  #

echo "dll list.."
$dllJob = Invoke-Command -Session $s -ScriptBlock{get-process -module 2>$null} -AsJob
jobretrieve -jobs $dllJob -filename "dlllist.csv"

echo "Net shares.."
$sharesJob = Invoke-Command -Session $s -ScriptBlock{net share} -AsJob
jobretrieve -jobs $sharesJob -filename "netshare.csv"

echo "Scheduled Tasks.."
#$tasksJob = Invoke-Command -Session $s -ScriptBlock{Get-ScheduledTask} -AsJob #
#echo "More schtasks.."
$schJob = Invoke-Command -Session $s -ScriptBlock{schtasks /query} -AsJob
jobretrieve -jobs $schJob -filename "schtasks.csv"

#echo "Netstat.."
#$netstat = Invoke-Command -Session $s -ScriptBlock{Get-NetTCPConnection -State Established,Listen,TimeWait} -AsJob #
#jobretrieve -jobs $netstat -filename "netstat.csv"

echo "pulling Kerberos tickets.."
$kerb = Invoke-Command -Session $s -ScriptBlock{klist} -AsJob
jobretrieve -jobs $kerb -filename "Kerberos.csv"

echo "prefetch items.."
$prefetch = Invoke-Command -Session $s -ScriptBlock{Get-ChildItem c:\windows\prefetch | Sort-Object LastWriteTime} -AsJob
jobretrieve -jobs $prefetch -filename "prefetch.csv"

echo "hashing Sys* folders, please be patient.."
$syshash = Invoke-Command -Session $s -ScriptBlock $function:hasher -ArgumentList $system -AsJob
jobretrieve -jobs $syshash -filename "system32_hashes.csv"

echo "Recycle Bin.."
$recyclehash = Invoke-Command -Session $s -ScriptBlock $function:hasher -ArgumentList $recyclebin -AsJob
jobretrieve -jobs $recyclehash -filename "recyclebin_hashes.csv"

echo "Temp files.."
$temphash = Invoke-Command -Session $s -ScriptBlock $function:hasher -ArgumentList $temp  -AsJob
jobretrieve -jobs $temphash -filename "temp_hashes.csv"

echo "User Folders.."
$usrhash = Invoke-Command -Session $s -ScriptBlock $function:hasher -ArgumentList $users  -AsJob
jobretrieve -jobs $usrhash -filename "users_hashes.csv"

echo "Pulling logon sessions"
$logonsessions = Invoke-Command -Session $s -ScriptBlock{
    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [string[]]
        $ComputerName = 'localhost'
    )

    $LogonMap = @{}
    Get-WmiObject -ComputerName $ComputerName -Class Win32_LoggedOnUser  | %{
    
        $Identity = $_.Antecedent | Select-String 'Domain="(.*)",Name="(.*)"'
        $LogonSession = $_.Dependent | Select-String 'LogonId="(\d+)"'

        $LogonMap[$LogonSession.Matches[0].Groups[1].Value] = New-Object PSObject -Property @{
            Domain = $Identity.Matches[0].Groups[1].Value
            UserName = $Identity.Matches[0].Groups[2].Value
        }
    }

    Get-WmiObject -ComputerName $ComputerName -Class Win32_LogonSession | %{
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
jobretrieve -jobs $logonsessions -filename "logonsessions.csv"


Remove-PSSession -Session $s

# This opens a window to the folder containing your pulled data
invoke-item $output