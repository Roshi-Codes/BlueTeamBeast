Add-Type -AssemblyName System.Windows.Forms
[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

# This is designed to be executed in conjunction with install_Splunk.ps1, it will not work without this and a list of target machines.
# Either IPs or hostnames IF the machine you are running it from uses the domain dns! If not you must use IP addresses!

# This gets the current working directory 
$loc = Get-Location

# The install_Splunk script should be in the same folder as this script.
$SplunkLoc = $loc.Path + "\Install_Splunk.ps1"
if(-not (Test-Path $SplunkLoc)){Write-Error "This script requires install_Splunk.ps1 to be in the same path. Exiting.."; Exit}

# Prompts the user for the IP address and port hosting the files
$IPaddress = Read-Host -Prompt 'Input the IP address and port number HOSTING your Splunk Forwarder msi (NOT the IP you want to index to), example: 192.168.1.10:9000  '

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

$installjob = Invoke-Command -Session $s -FilePath $SplunkLoc -ArgumentList $IPaddress -AsJob
jobretrieve $installjob

# The hostname and service status will be added to the $status array. The sessions are then closed
$statusjob = Invoke-Command -Session $s -ScriptBlock {Get-Service SplunkForwarder} -AsJob

$status = @()

foreach ($job in $statusjob.ChildJobs){
$return = Receive-Job $job
if ($return.status -eq 0) {$return = "Service not found!"}
$status.Add("$($job.location) - $($return)")
}

echo "Closing sessions"
Remove-PSSession -Session $s
Remove-Job *

# $status is output to both a log file and the terminal to end the script
$statusPath = $loc.path + "\Forwarders_Status_Log.txt"
$status | out-file $statusPath
echo $status