param (
    $VirtualCenter = "vcenter-prod1.ops.puppetlabs.net",
    $SnapShotsOlderThanXDays = 2
)

If (-not $global:DefaultVIServer) {
    #Disconnect-VIServer * -Confirm:$false -ErrorAction SilentlyContinue
    Connect-VIServer -Server $VirtualCenter
}

$Snapshots = Get-VM | Get-Snapshot | Select-Object Name,Description,Created,VM,SizeMB,SizeGB

function Get-SnapshotSize ($Snapshot)
{
    $Snapshotsize = [math]::Round($snapshot.SizeGB,3)
   return $Snapshotsize
}

function Get-VMCluster ($vm) {
    return $vm.VMHost.Parent.Name
}

function Print-PowerState ($vm) {
    return $vm.PowerState -replace 'Powered'
}

function Get-SnapshotDateStyle ($snapshot)
{
    $greenValue = (get-date).AddDays(-7)
    $RedValue = (get-date).AddDays(-14)
    
    if ($snapshot.created -gt $greenValue)
        {
            $backgroundcolor = "green"
        }
    elseif ($snapshot.Created -lt $greenValue -and $snapshot.Created -gt $RedValue)
        {
            $backgroundcolor = "yellow"
        }
    else 
        {
        $backgroundcolor = "red"
        }
    return $backgroundcolor
}

function Format-HTMLBody ($body)
{
    $newbody = @()
    foreach ($line in $body)
    {
        ## Remove the Format Header
        if ($line -like "*<th>Format</th>*")
            {
                $line = $line -replace '<th>Format</th>',''
            }
        ## Format all the Red rows
        if ($line -like "*<td>red</td>*")
            {
                $line = $line -replace '<td>red</td>','' 
                $line = $line -replace '<tr>','<tr style="background-color:lightpink;">'
            }
        ## Formating all the Yellow Rows
        elseif ($line -like "*<td>yellow</td>*")
            {
                $line = $line -replace '<td>yellow</td>','' 
                $line = $line -replace '<tr>','<tr style="background-color:Orange;">'
            }
        ## Formating all the Green Rows
        elseif ($line -like "*<td>green</td>*")
            {
                $line = $line -replace '<td>green</td>','' 
                $line = $line -replace '<tr>','<tr style="background-color:MediumSeaGreen;">'
            }
        ## Building the new HTML file
            $newbody += $line
    }
    return $newbody
}

$date = (get-date -Format d/M/yyyy)
$header =@"
 <Title>Snapshot Report - $date</Title>
<style>
body {   font-family: 'Helvetica Neue', Helvetica, Arial;
         font-size: 14px;
         line-height: 20px;
         font-weight: 400;
         color: black;
    }
table{
  margin: 0 0 40px 0;
  width: 100%;
  box-shadow: 0 1px 3px rgba(0,0,0,0.2);
  display: table;
  border-collapse: collapse;
  border: 1px solid black;
}
th {
    font-weight: 900;
    color: #ffffff;
    background: black;
   }
td {
    border: 0px;
    border-bottom: 1px solid black;
    padding:0 15px 0 15px;
    }
</style>
"@

$PreContent = "<H1> Snapshot Report for " + $date + "</H1>"

$html = $Snapshots | Select-Object VM,@{Label="Cluster";Expression={Get-VMCluster($_.VM)}},Created,@{Label="Size (GB)";Expression={Get-SnapshotSize($_)}},@{Label="Power";Expression={Print-PowerState($_.VM)}},@{Label="Snapshot Name";Expression={$_.Name}},Description,@{Label="Format";Expression={Get-SnapshotDateStyle($_)}}| Sort-Object -Property "Size (GB)" -Descending | ConvertTo-Html -Head $header -PreContent $PreContent

$Report = Format-HTMLBody ($html)

$Report | out-file -Path ./snapshot-report.html

open ./snapshot-report.html
