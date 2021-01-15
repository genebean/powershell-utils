$myCol = @()
ForEach ($Cluster in Get-Cluster) {
  ForEach ($vmhost in ($cluster | Get-VMHost)) {
    $VMView = $VMhost | Get-View
      $VMSummary = “” | Select HostName, ClusterName, MemorySizeGB, CPUSockets, CPUCores, CPUThreads, HyperThreading
      $VMSummary.HostName = $VMhost.Name
      $VMSummary.ClusterName = $Cluster.Name
      $VMSummary.MemorySizeGB = [math]::Round($VMview.hardware.memorysize / 1024Mb)
      $VMSummary.CPUSockets = $VMview.hardware.cpuinfo.numCpuPackages
      $VMSummary.CPUCores = $VMview.hardware.cpuinfo.numCpuCores
      $VMSummary.CPUThreads = $VMview.hardware.cpuinfo.numCpuThreads
      if ($VMSummary.CPUThreads -gt $VMSummary.CPUCores) {
        $VMSummary.HyperThreading = $true
      } else {
        $VMSummary.HyperThreading = $false
      }
      $myCol += $VMSummary
  }
}
$myCol |Sort-Object -Property ClusterName,HostName |Format-Table -AutoSize
Write-Output "Total sockets: $(($myCol |Measure-Object 'CPUSockets' -Sum).Sum)"
