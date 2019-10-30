# This is designed to be executed in conjunction with install_Splunk.ps1, it will not work without this and a list of target machines.
# Either IPs or hostnames IF the machine you are running it from uses the domain dns! If not you must use IP addresses!

# This gets the current working directory 
$loc = Get-Location

# The file containing target IPs or Target hostnames is appended to the path.
# For this to work the targets file must be in the same directory as this script.
$TargetLoc = $loc.Path + "\targets.txt"

# If you are using a different directory for your file containing targets comment out the line assigning $TargetLoc above.
# Then replace the below $TargetLoc with the location of the list of IPs/host names to invoke the command on.
$computers = (get-content -path $TargetLoc)

# The install_Splunk script should be in the same folder as this script.
$SplunkLoc = $loc.Path + "\install_Splunk.ps1"

# You will be prompted for your username and password when you run the script. !!!NEVER STORE YOUR PASSWORD IN PLAINTEXT!!!
# If you do not want to type in your usename each time you run the script, uncomment and replace the credentials below with the domian name and user name
$creds = Get-Credential # -Credential domain\user 

$status = @()

# This block will loop through the computers in targets.txt, first installing the forwarder, then attempting to get the service status
# The $comp and service status will be added to the $status array. The session and $return variable are then cleaned up 
foreach ($comp in $computers)
{
echo "Connecting to $comp"
$s = New-PSSession -ComputerName $comp -Credential $creds
Invoke-Command -Session $s -FilePath $SplunkLoc
$return = $(Invoke-Command -Session $s -ScriptBlock {(Get-Service SplunkForwarder).Status} 2> $null)
if ($return.length -eq 0) {$return = "Service not found!"}
$status.Add("$($comp) - $($return)")
echo "Closing session"
Remove-PSSession -Session $s
Remove-Variable $return
}

# $status is output to both a log file and the terminal to end the script
$statusPath = $loc.path + "\Forwarders_Status_Log.txt"
$status | out-file $statusPath
echo $status
echo "End of script"