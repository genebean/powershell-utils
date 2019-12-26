param (
    [String]$VirtualCenter = "vcenter-prod1.ops.puppetlabs.net",
    [String]$VMwareUserName,
    [SecureString]$VMwarePassword,
    [String]$VMwareCluster = 'operations2',
    [String]$PuppetServer = 'https://puppet.ops.puppetlabs.net',
    [String]$Token = $(Get-Content -Path "$HOME/.puppetlabs/token" -ErrorAction SilentlyContinue),
)

if ($PuppetServer -match 'https://') {
    $port = 8081
    $SkipCertificateCheck = true
} else {
    $port = 8080
    $SkipCertificateCheck = false
}
$pdb_api = "${PuppetServer}:${port}/pdb/query/v4"

$headers = @{
    'Content-Type'     = 'application/json'
}
if ($Token) {
    $headers += @{'X-Authentication' = ${Token}}
}

if ($VMwareUserName -and $VMwarePassword) {
    $creds = New-Object System.Management.Automation.PSCredential($VMwareUserName, $VMwarePassword)
} else {
    $creds = Get-Credential -Message "Enter your vCenter credentials" -UserName "$($VMwareUserName)"
}
Connect-VIServer -Server $VirtualCenter -Credential $creds

$VMS = Get-Cluster -Name $VMwareCluster | Get-VM | Where-Object { $_.PowerState -eq 'PoweredOn' } 

$result_objects = @()

foreach ($vm in $VMS) {
    $nic = $vm | Get-NetworkAdapter | Select-Object -First 1

    $result_object = [PSCustomObject]@{
        VMName                = $vm.Name
        IPAddress             = $($vm.guest.IPAddress | Where-Object { $_.StartsWith('10') } | Select-Object -First 1)
        MacAddress            = $nic.MacAddress
        VMNetworkName         = $nic.NetworkName
        VMwareCluster         = $VMwareCluster
        FoundInPuppetDB       = $false
        PuppetFQDN            = $null
        PuppetReportTimestamp = $null
    }

    $mac_query = @{query = "inventory[certname]{ facts.networking.mac = '$($nic.MacAddress)' order by certname }" } | ConvertTo-Json
    if ($SkipCertificateCheck) {
        $mac_results = Invoke-RestMethod -Method Post -Uri ${pdb_api} -Headers $headers -Body $mac_query -SkipCertificateCheck
    } else {
        $mac_results = Invoke-RestMethod -Method Post -Uri ${pdb_api} -Headers $headers -Body $mac_query
    }
    
    if ($mac_results.length -gt 0) {
        $result_object.FoundInPuppetDB = $true
        $result_object.PuppetFQDN = $mac_results.certname

        $report_query = @{query = "nodes{ certname = '$($result_object.PuppetFQDN)' }" } | ConvertTo-Json
        $report_results = Invoke-RestMethod -Method Post -Uri ${pdb_api} -Headers $headers -Body $report_query -SkipCertificateCheck
        $result_object.PuppetReportTimestamp = $report_results.report_timestamp
    }

    $result_objects += $result_object
}

$result_objects
