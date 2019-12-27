[cmdletbinding()]
Param (
    [String]$VirtualCenter = "vcenter-prod1.ops.puppetlabs.net",
    [String]$VMwareUserName,
    [SecureString]$VMwarePassword,
    [String]$VMwareCluster = 'operations2',
    [String]$PuppetServer = 'https://puppet.ops.puppetlabs.net',
    [String]$Token = $(Get-Content -Path "$HOME/.puppetlabs/token" -ErrorAction SilentlyContinue),
    [Boolean]$AttemptRemediation = $true,
    [Boolean]$PrintDetails = $false
)

###########################################
# Variable setup
###########################################

if ($PuppetServer -match 'https://') {
    $port = 8081
    $SkipCertificateCheck = $true
} else {
    $port = 8080
    $SkipCertificateCheck = $false
}

$pdb_api = "${PuppetServer}:${port}/pdb/query/v4"

$headers = @{
    'Content-Type' = 'application/json'
}

if ($Token) {
    $headers += @{'X-Authentication' = ${Token} }
}

if ($VMwareUserName -and $VMwarePassword) {
    $creds = New-Object System.Management.Automation.PSCredential($VMwareUserName, $VMwarePassword)
} elseif ($VMwareUserName) {
    $creds = Get-Credential -Message "Enter your vCenter credentials" -UserName "$($VMwareUserName)"
} else {
    $creds = Get-Credential -Message "Enter your vCenter credentials"
}

###########################################
# Functions
###########################################

function Get-PuppetCommand {
    Param( [String]$IP )

    $regular_args = @(
        ${IP},
        "facter",
        "kernel"
    )

    $cygwin_args = @(
        ${IP},
        "powershell",
        "facter",
        "kernel"
    )

    $result = &"ssh" $regular_args

    if ($result -and ($result -ne 'windows')) {
        'sudo puppet'
    } elseif ($result -and ($result -eq 'windows')) {
        'puppet'
    } else {
        $result = &"ssh" $cygwin_args

        if ($result -and ($result -eq 'windows')) {
            'powershell puppet'
        } else {
            $false
        }
    }
}

function Get-PuppetServer {
    Param(
        [String]$IP,
        [String]$CommandString
    )

    $SplitCommand = $CommandString.Split(' ')
    $puppet_args = @(
        'config',
        'print',
        'server'
    )
    $cmd_args = $SplitCommand + $puppet_args

    $server = &"ssh" ${IP} $cmd_args

    if ($server) {
        $server
    } else {
        $false
    }
}

function Invoke-PDBRestMethod {
    param (
        $body
    )

    if ($SkipCertificateCheck) {
        Invoke-RestMethod -Method Post -Uri ${pdb_api} -SkipCertificateCheck -Headers $headers -Body $body
    } else {
        Invoke-RestMethod -Method Post -Uri ${pdb_api} -Headers $headers -Body $body
    }
}

function Invoke-Puppet {
    Param(
        [String]$IP,
        [String]$CommandString
    )

    $SplitCommand = $CommandString.Split(' ')
    $puppet_args = @(
        'agent',
        '-t'
    )
    $cmd_args = $SplitCommand + $puppet_args

    &"ssh" ${IP} $cmd_args
}

function AttemptRemediation {
    param (
        [String]$IP,
        [String]$VMName
    )

    $commandstring = Get-PuppetCommand -IP $IP
    if ($commandstring) {
        $server = Get-PuppetServer -IP $IP -CommandString $commandstring
        if ($server -eq $PuppetServer.split('/')[-1]) {
            if ($PrintDetails) { Write-Output "Attempting to run puppet on $($VMName)..." }
            $run_output = Invoke-Puppet -IP $IP -CommandString $commandstring
            if ($PrintDetails) { Write-Output $run_output }
            $true
        } else {
            $false
        }
    } else {
        $false
    }
}

###########################################
# Get VMware VM's
###########################################

if ($PrintDetails) { Write-Output "Connecting to $($VirtualCenter)..." }
Connect-VIServer -Server $VirtualCenter -Credential $creds | Out-Null

if ($PrintDetails) { Write-Output "Getting powered on VM's from $($VMwareCluster)..." }
$VMS = Get-Cluster -Name $VMwareCluster | Get-VM | Where-Object { $_.PowerState -eq 'PoweredOn' } 

###########################################
# Process each VM
###########################################

$result_objects = @()

foreach ($vm in $VMS) {
    $ip = $vm.guest.IPAddress | Where-Object { $_.StartsWith('10') } | Select-Object -First 1
    $nic = $vm | Get-NetworkAdapter | Select-Object -First 1
    if ($PrintDetails) { Write-Output "Checking $($vm.Name) [$($ip)]..." }

    $result_object = [PSCustomObject]@{
        VMName                = $vm.Name
        IPAddress             = $ip
        MacAddress            = $nic.MacAddress
        VMNetworkName         = $nic.NetworkName
        VMwareCluster         = $VMwareCluster
        FoundInPuppetDB       = $false
        PuppetReportTimestamp = $null
        RemediationAttempted  = $false
        PuppetFQDN            = $null
    }

    $mac_query = @{query = "inventory[certname]{ facts.networking.mac = '$($nic.MacAddress)' order by certname }" } | ConvertTo-Json
    $mac_results = Invoke-PDBRestMethod $mac_query
    
    if ($mac_results.length -gt 0) {
        $result_object.FoundInPuppetDB = $true
        $result_object.PuppetFQDN = $mac_results.certname

        $report_query = @{query = "nodes{ certname = '$($result_object.PuppetFQDN)' }" } | ConvertTo-Json
        $report_results = Invoke-PDBRestMethod $report_query
        $result_object.PuppetReportTimestamp = $report_results.report_timestamp

        if ($AttemptRemediation -and -not $report_results.report_timestamp) {
            $result_object.RemediationAttempted = AttemptRemediation -IP $result_object.IPAddress -VMName $vm.Name

            $second_report_query = @{query = "nodes{ certname = '$($result_object.PuppetFQDN)' }" } | ConvertTo-Json
            $second_report_results = Invoke-PDBRestMethod $second_report_query
            $result_object.PuppetReportTimestamp = $second_report_results.report_timestamp
        }
    } elseif ($AttemptRemediation) {
        $result_object.RemediationAttempted = AttemptRemediation -IP $result_object.IPAddress -VMName $vm.Name
    }

    $result_objects += $result_object
}

$result_objects
