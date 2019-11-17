param([parameter(position=0)] $IPaddress)

function download($IP, $filename) {
echo "Downloading $($filename)..."

$url = "http://$($IP)/$($filename)" 

# Path that the exe is saved to on the end host - If you change this you must change the location to match thoughout the rest of the script.
$path = "$($env:SystemDrive)\Program Files\sysmon\$($filename)"

# Downloads the file from the url and saves to the path - This version is PowerShell V2 compatible
(New-Object Net.WebClient).DownloadFile($url, $path) 

# If you are hosting the Sysmon.exe on a network share, comment out the New-Object command above with a hashtag
# Then uncomment and edit the below line with the network share source.
##Copy-Item "\\change\me\Sysmon64.exe" -Destination $path

# Testing file was created
filetest -testPath $path
}


function filetest($testPath) 
{
$test = Test-Path $testPath
if ($test = "True"){Continue}
elif ($test = "False"){Write-Warning "$($testPath) NOT Found, download unsucessful, Check connectivity and file availibilty, then try installing on $env:COMPUTERNAME again. Leaving session with $env:COMPUTERNAME.."; Exit}
}


function fileinstall 
{
echo "Installing on $env:COMPUTERNAME, this can take a long time in virtual environments with low resources! Please wait..."
& "$($env:SystemDrive)\Program Files\sysmon\Sysmon64.exe" -accepteula -i "$($env:SystemDrive)\Program Files\sysmon\sysmonconfig.xml" 2> $null
}


function servicecheck {
echo "Checking service was created.."
if ($ser = Get-Service Sysmon) 
{ 
    Echo $ser.Status 
    if ( $ser.Status -ne "Running" -or "Starting")
    { Start-Service splunkForwarder }
}
else { 
servicenotfound
}
}


function servicenotfound {
Write-Warning "Service not found, re-trying install.."
fileinstall
if ($ser = Get-Service Sysmon) 
{ 
    Echo $ser.Status 
    if ( $ser.Status -ne "Running" -or "Starting")
    { Start-Service splunkForwarder }
} 
else {Write-Warning "Service still not found, ensure you have the correct permissions to install a service and that all the commandline arguements in the script are correct! Leaving session with $env:COMPUTERNAME.."; Exit}
}


# Sysmon folder is created.
# Path that the exe is saved to on the end host - If you change this you must change the location to match thoughout the rest of the script.
new-item -ItemType directory -path "$($env:SystemDrive)\Program Files\" -name "sysmon"

download -IP $IPaddress -filename Sysmon64.exe
download -IP $IPaddress -filename Eula.txt
download -IP $IPaddress -filename sysmonconfig.xml
fileinstall