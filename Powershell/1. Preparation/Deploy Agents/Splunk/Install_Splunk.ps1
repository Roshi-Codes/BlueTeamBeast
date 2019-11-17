param([parameter(position=0)] $IPaddress)
# Read the comments - You must make changes for this to work in your environment.

function filedownload($IP) {
echo "Downloading Splunk Forwarder..."

# Location of your hosted splunkforwarder - simple python http server will work.
$url = "http://$($IP)/splunkforwarder.msi" 

# Path that the msi is saved to on the end host - If you change this you must change the location to match thoughout the rest of the script.
$path = "$($env:SystemDrive)\splunkforwarder.msi" 

# Downloads the file from the url and saves to the path - This version is PowerShell V2 compatible
(New-Object Net.WebClient).DownloadFile($url, $path) 

# If you are hosting the splunk msi on a network share, comment out the New-Object command above with a hashtag
# Then uncomment and edit the below line with the network share source.
##Copy-Item "\\change\me\splunkforwarder.msi" -Destination $path

# Testing file was created
filetest
}


function filetest {
$test = Test-Path C:\splunkforwarder.msi
if ($test = "True"){Continue}
elif ($test = "False"){Write-Warning "$($env:SystemDrive)\splunkforwarder.msi NOT Found, download unsucessful, Check connectivity and file availibilty, then try installing on $env:COMPUTERNAME again. Leaving session with $env:COMPUTERNAME.."; Exit}
}


function fileinstall {
echo "Installing on $env:COMPUTERNAME, this can take a long time in virtual environments with low resources! Please wait..."

# You must replace the arguements with the areguements you want to run on your own splunk forwarder, leave the '/quiet' at the end
# MAKE SURE YOU CHANGE YOUR RECEIVING_INDEXER & DEPLOYMENT_SERVER IPs!!! 
Start-Process msiexec.exe -wait '/I C:\splunkforwarder.msi AGREETOLICENSE=yes RECEIVING_INDEXER="<IP>:<PORT>" DEPLOYMENT_SERVER="<IP>:<PORT>" WINEVENTLOG_APP_ENABLE=1 WINEVENTLOG_SEC_ENABLE=1 WINEVENTLOG_SYS_ENABLE=1 WINEVENTLOG_FWD_ENABLE=1 WINEVENTLOG_SET_ENABLE=1 SPLUNKUSER=admin GENRANDOMPASSWORD=1 ENABLEADMON=1 /quiet'
}


function servicecheck {
echo "Checking service was created.."
if ($ser = Get-Service SplunkForwarder) 
{ 
    Echo $ser.Status 
    if ( $ser.Status -ne "Running")
    { Start-Service splunkForwarder }
}
else { 
servicenotfound
}
}


function servicenotfound {
Write-Warning "Service not found, re-trying install.."
fileinstall
if ($ser = Get-Service SplunkForwarder) 
{ 
    Echo $ser.Status 
    if ( $ser.Status -ne "Running")
    { Start-Service splunkForwarder }
} 
else {Write-Warning "Service still not found, ensure you have the correct permissions to install a service and that all the commandline arguements in the script are correct! Leaving session with $env:COMPUTERNAME.."; Exit}
}


function filedelete {
# The install file is deleted after install
echo "Cleaning up.."
del C:\splunkforwarder.msi
echo "$env:COMPUTERNAME clean."
}

filedownload -IP $IPaddress
fileinstall
servicecheck
filedelete

echo "`n"
echo "`n"