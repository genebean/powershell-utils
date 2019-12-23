param (
    [String]$VirtualCenter = "vcenter-prod1.ops.puppetlabs.net",
    [String]$VMwareUserName,
    [SecureString]$VMwarePassword,
    [String]$VMwareCluster = 'operations2',
    [String]$PupppetServer = 'https://puppet.ops.puppetlabs.net',
    [Sstring]$Token = $(Get-Content -Path "$HOME/.puppetlabs/token")
)

$pdb_api = "${PupppetServer}:8081/pdb/query/v4"

$headers = @{
    'Content-Type'     = 'application/json'
    'X-Authentication' = ${Token}
}

$creds = New-Object System.Management.Automation.PSCredential($VMwareUserName, $VMwarePassword)

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
    $mac_results = Invoke-RestMethod -Method Post -Uri ${pdb_api} -Headers $headers -Body $mac_query -SkipCertificateCheck
    
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
