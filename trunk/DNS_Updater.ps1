# Powershell DNS Updater for Jenkins Jobs
# By: Justin Hyland
# Desc: Takes input from jenkins, and updates the windows DNS
#

# Include Blacklist
#
if ( Test-Path .\DNS_Blacklist.ps1 ) {
	. .\DNS_Blacklist.ps1
}
else {
	Write-Host "Blacklist file not available"
	exit 1
}

# Grab some environmental variables given via Jenkins
$Server		= "wpcdc02.corp.some_domain.ad"
$Action 	= ${env:Action}
$Zone 		= ${env:Zone}
$Record		= ${env:Record}
$IP_Address	= ${env:IP_Address}
$Force 		= ${env:Force}
$PTR		= ${env:PTR}


"-" * 40
Write-Host "Server: $Server"
Write-Host "Zone: $Zone"
Write-Host "Action: $Action"
Write-Host "Record: $Record"
Write-Host "IP Address: $IP_Address"
Write-Host "Force: $Force"
Write-Host "PTR: $PTR"
"-" * 40

# Test the IP, make sure its a valid Windows format IP (Only matters if $Action = Create)
#
if ( $Action -eq "Create" ) {
	try { 
		$address = [System.Net.IPAddress]::parse($IP_Address)
	}
	catch {
		write-host "The IP '$IP_Address' Not in the correct format"
		exit 1
	}
}

# Default Settings
#
$class=1
$ttl=3600
$fullrecord = "$Record.$Zone"
$namespace='root\MicrosoftDNS'
Write-Host "DNS Server is $Server"
# Check if this A record can be updated
#
If ( $DNSBlacklistArray -contains $Record ) {
	Write-Host "The record $Record is in the DNS Update Blacklist, exiting"
	exit 1
}

$records = Get-WmiObject -ComputerName $Server -Namespace $namespace -Class MicrosoftDNS_AType -Filter "ContainerName='$Zone' AND OwnerName='$fullrecord'" -ErrorAction SilentlyContinue
$count = 0

# Total records matching queries item
#
If ( $records -ne $null ) {
	ForEach ( $objitem in $records ) {
		$count ++
	}
}

# Check the $Action
If ( $Action -eq "Delete" ) {
	If ( $count -eq 0 ) {
		Write-Host "There are no records found for $fullrecord in $Zone"
		exit 1
	}
	
	Write-Host "Deleting $fullrecord from zone $Zone... " -NoNewLine
	try{
		$records.psbase.Delete()
        }
        catch {
                Write-Host "Failed"
                Write-Host "Error:" $error[0]
                exit 1
        }
	Write-Host "Success"
	exit 0
}

If ( $count -ne 0 ) {
	# Apparently this record already exists.. Continue if $Force is a go
	#
	Write-Host "There are $count DNS Record(s) matching '$fullrecord'"
	If ( $Force -ne $TRUE ) {
		Write-Host "Since this record exists already, you need to check the 'Force' option to modify it"
		exit 1
	}
	Else {
		# Force is set, DELETE IT!
		#
		Write-Host "Setting 'Force' is enabled, Continuing"
		Write-Host "Deleting existing record... " -NoNewLine
		
		try{
			$records.psbase.Delete()
		}
		catch {
			Write-Host "Failed"
			Write-Host "Error:" $error[0]
			exit 1
		}
		
		Write-Host "Success"
	}
}


# Create WMI DNS Record Handler
#
Write-Host "Creating new DNS Record for '$fullrecord'... " -NoNewLine
$rec = [WmiClass]"\\$Server\root\MicrosoftDNS:MicrosoftDNS_AType"

try {
	$rec.CreateInstanceFromPropertydata($Server, $Zone, $fullrecord, $class, $ttl, $IP_Address) | out-null
}
catch {
	Write-Host "Failed"
	Write-Host "Error:" $error[0]
	exit 1
}

Write-Host "Success"

# Create PTR Record if specified
#
If ( $PTR -ne $FALSE ) {
	Write-Host "Creating PTR Record for '$fullrecord'... " -NoNewLine
	$octets=$IP_Address.split(".")

	$PTRContainer = $octets[2] + "." + $octets[1] + "." + $octets[0] + ".in-addr.arpa"

	$OwnerName = $octets[3] + "." + $octets[2] + "." + $octets[1] + "." + $octets[0] + ".in-addr.arpa"

	$PTRRecord = [WmiClass]"\\$Server\root\MicrosoftDNS:MicrosoftDNS_PTRType"
	
	try {
		$PTRRecord.createInstanceFromPropertydata($Server, $PTRContainer, $OwnerName, $class, $ttl, $fullrecord) | out-null
	}
	catch {
		Write-Host "Failed"
		Write-Host "Error:" $error[0]
		exit 1
	}

	Write-Host "Success"
}
