Add-Type -AssemblyName System.Windows.Forms
# This is designed to be executed in conjunction with Install_Sysmon.ps1 , it will not work without this and a list of target machines.

# This gets the current working directory 
$loc = Get-Location

# The install_Sysmon script must be in the same folder as this script. This tests for the script.
$SysmonLoc = $loc.Path + "\Install_Sysmon.ps1"
if(-not (Test-Path $SysmonLoc)){Write-Error "This script requires install_sysmon.ps1 to be in the same path. Exiting.."; Exit}

# Prompts the user for the IP address and port hosting the files
$IPaddress = Read-Host -Prompt 'Input the IP address and port number hosting your sysmon files, example: 192.168.1.10:9000  '

# The user is asked to select the file containing the IP address or the targets
function filegrab(){
$FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ InitialDirectory = [Environment]::GetFolderPath('Desktop') }
[System.Windows.MessageBox]::Show('You will now be prompted to select the file containing the IPs OR Hostnames of the targets you wish to gather information from.','File Select','ok','information')
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

# Function to retrieve the job and then remove it from the job list
function jobretrieve(){
[CmdletBinding()]

            Param(                        
            [Parameter(ValueFromPipelineByPropertyName)]
            $jobs)

            process {
            Get-Job -IncludeChildJob | Wait-Job | Out-Null
            foreach ($j in $jobs.ChildJobs){@(Receive-Job $j)}
            Remove-Job *
            }
    }

# Sessions are created to the computers in targets.txt, first installing the forwarder, then attempting to get the service status
# Sessions are connected
echo "Connecting..."
$s = New-PSSession -ComputerName $computers -Credential $creds
echo "Connected!"


echo "Downloading sysmon files and installing.."
$installjob = Invoke-Command -Session $s -FilePath $SysmonLoc -ArgumentList $IPaddress
jobretrieve $installjob

$status = @()
$statusjob = $(Invoke-Command -Session $s -ScriptBlock {(Get-Service Sysmon).Status} 2> $null)
foreach ($job in $statusjob.ChildJobs){
$return = Receive-Job $job
if ($return.status -eq 0) {$return = "Service not found!"}
$status.Add("$($job.location) - $($return)")
}

echo "Closing session"
Remove-PSSession -Session $s
Remove-Job *

# $status is output to both a log file and the terminal to end the script
$statusPath = $loc.path + "\Sysmon_Status_Log.txt"
$status | out-file $statusPath
echo $status
echo "End of script"