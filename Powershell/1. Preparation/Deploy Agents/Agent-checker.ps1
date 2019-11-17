Add-Type -AssemblyName System.Windows.Forms
[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

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


Echo "Starting sessions.."
$sessions = New-PSSession -ComputerName $computers -Credential $creds
Echo "Connected to $sessions"

$checkjob = Invoke-Command -Session $sessions -ScriptBlock {echo $env:COMPUTERNAMEl; get-service | Where-Object {$_.name -like "SplunkForwarder","Sysmon64"}} -AsJob
jobretrieve -jobs $checkjob

echo "End"