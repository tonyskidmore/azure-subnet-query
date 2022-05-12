#Requires -Modules Az.Accounts, Az.Network

<#

.SYNOPSIS
Query Azure subnet for connected devices.

.DESCRIPTION
The script will attempt to query subnet connected device using the Ip configuration of each connected device.  Requires that Azure PowerShell modules are installed.

.EXAMPLE
./Get-AzureSubnetDevices.ps1 -VirtualNetworkName my-network -ResourceGroupName rg-my-network -SubnetName my-subnet -Subscription 52f83193-8813-4c1b-ae89-bf568f347360

.EXAMPLE
./Get-AzureSubnetDevices.ps1 -VirtualNetworkName my-network -ResourceGroupName rg-my-network -SubnetName my-subnet -Subscription 52f83193-8813-4c1b-ae89-bf568f347360 -Flatten:$true

.PARAMETER VirtualNetworkName
Name of the Azure virtual network.

.PARAMETER ResourceGroupName
Name of the Azure resource group that contains the target virtual network.

.PARAMETER SubnetName
Name of the Azure subnet.

.PARAMETER SubscriptionID
ID of the Azure subscription.

.PARAMETER Flatten
Whether to try and flatten so that teh data can be output as CSV.  Would lose some data if there were multiple private link service connections.

.PARAMETER Transcript
Create a transcript of the execution for debugging purposes.

.LINK
https://github.com/tonyskidmore/azure-subnet-query

#>

[cmdletBinding()]
param(
    [Parameter(mandatory=$True)]
    [string]
    $VirtualNetworkName,

    [Parameter(mandatory=$True)]
    [string]
    $ResourceGroupName,

    [Parameter(mandatory=$True)]
    [string]
    $SubnetName,

    [Parameter(mandatory=$True)]
    [string]
    $SubscriptionID,

    [boolean]
    $Flatten = $False,

    [boolean]
    $Transcript = $false
)

if ($Transcript) { Start-Transcript -Path "./Get-AzureSubnetDevices.log"}

$azContext = Get-AzContext

Write-Output "Connected to: $($azContext.Subscription.Name)"

if ($($azContext.Subscription.Name) -ne $SubscriptionID) {
  Set-AzContext -Subscription $SubscriptionID
}


$params = @{
  Name = $VirtualNetworkName
  ResourceGroupName = $ResourceGroupName
}

$vnet = Get-AzVirtualNetwork @params -ExpandResource 'subnets/ipConfigurations'

# Could use this method also?  using above -ExpandResource on vnet instead
# $subnetConfig = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet | Where-Object Name -eq $SubnetName
# $subnetConfig

$subnet = $vnet.Subnets | Where-Object Name -eq $SubnetName


$deviceList = [System.Collections.Generic.List[PSCustomObject]]@()


foreach ($ipConf in $subnet.IpConfigurations) {

  Write-Output "Querying private IP address: $($ipConf.PrivateIpAddress)"
  $nicId = $ipConf.Id.Substring(0, $ipConf.Id.IndexOf("/ipConfigurations"))
  Write-Verbose -Message "ipConfiguration: $($ipConf | ConvertTo-Json -Depth 5 -Compress)"
  try {
    $nicResource = Get-AzResource -ResourceId $nicId -ErrorAction Stop
    Write-Verbose -Message "nicResource: $($nicResource | ConvertTo-Json -Depth 5 -Compress)"
  } catch {
    # TODO: check for specific issue i.e. wrong subscription rather than just ignoring
    $nicResource = $null
  }

  try {
    $nic = Get-AzNetworkInterface -ResourceId $nicId -ErrorAction Stop
    Write-Verbose -Message "nic: $($nic | ConvertTo-Json -Depth -Compress)"
  } catch {
    $nic = $null
  }

  $vmId = $nic.VirtualMachine.Id

  if(-not [string]::IsNullOrEmpty($vmId)) {
    $vmName = $vmId.split("/")[-1]
    $vmResourceGroupName = $vmId.split("/")[$vmId.split("/").IndexOf("resourceGroups") + 1]
  }

  $pe = Get-AzPrivateEndpoint | Where-Object {$_.NetworkInterfaces.Id -contains $nicId}
  Write-Verbose -Message "pe: $($pe | ConvertTo-Json -Depth 5 -Compress)"

  $privateLinkList = [System.Collections.Generic.List[PSCustomObject]]@()
  foreach($privateLinkServiceConnection in $pe.PrivateLinkServiceConnections) {
    $plSid = $privateLinkServiceConnection.PrivateLinkServiceId
    $privateEC = Get-AzPrivateEndpointConnection -PrivateLinkResourceId $plSid
    Write-Verbose -Message "privateEC: $($privateEC | ConvertTo-Json -Depth 5 -Compress)"
    $plResource = Get-AzPrivateLinkResource -PrivateLinkResourceId $plSid
    Write-Verbose -Message "plResource: $($plResource | ConvertTo-Json -Depth 5 -Compress)"

    try {
      $resID = $plResource.Id.Substring(0, $plResource.Id.IndexOf("/privateLinkResources"))
      $res = Get-AzResource -ResourceId $resID -ErrorAction Stop
      Write-Verbose -Message "res: $($res | ConvertTo-Json -Depth 5 -Compress)"
    } catch {
      # TODO: check for issues rather than just ignoring
    }

    if($Flatten) {
      $PrivateLinkResource = $res.Name
      $PrivateLinkResourceResourceGroup = $plResource.ResourceGroupName
      $PrivateEndpointConnectionName = $privateEC.Name
      $PrivateEndpointProvisioningState = $privateEC.ProvisioningState
    } else {
      $privateLink = [PSCustomObject]@{
        PrivateLinkResource = $res.Name
        PrivateLinkResourceResourceGroup = $plResource.ResourceGroupName
        PrivateEndpointConnectionName = $privateEC.Name
        PrivateEndpointProvisioningState = $privateEC.ProvisioningState
      }
      $privateLinkList.Add($privateLink)
    }
  }

  # basic workaround for flattening for out to CSV
  # not a great method but should work for a basic CSV output
  if($Flatten) {
    $connectedDevice = [PSCustomObject]@{
      IPConfiguration = $ipConf.Name
      PrivateIpAddress = $ipConf.PrivateIpAddress
      IPConfigurationID = $ipConf.Id
      NicId = $nicId
      Device = $nicResource.Name
      VMId = $nic.VirtualMachine.Id
      VMName = $vmName
      VMResourceGroupName = $vmResourceGroupName
      PrivateLinkResource = $PrivateLinkResource
      PrivateLinkResourceResourceGroup = $PrivateLinkResourceResourceGroup
      PrivateEndpointConnectionName =  $PrivateEndpointConnectionName
      PrivateEndpointProvisioningState = $PrivateEndpointProvisioningState
    }
  } else {
    $connectedDevice = [PSCustomObject]@{
      IPConfiguration = $ipConf.Name
      PrivateIpAddress = $ipConf.PrivateIpAddress
      IPConfigurationID = $ipConf.Id
      NicId = $nicId
      Device = $nicResource.Name
      VMId = $nic.VirtualMachine.Id
      VMName = $vmName
      VMResourceGroupName = $vmResourceGroupName
      PrivateLink = $privateLinkList
    }
  }
  $deviceList.Add($connectedDevice)
  $connectedDevice = $null
  $nicId = $null
  $nicResource = $null
  $nic = $null
  $vmName = $null
  $privateLinkList = $null
  $vmResourceGroupName = $null
  $PrivateLinkResource = $null
  $PrivateLinkResourceResourceGroup = $null
  $PrivateEndpointConnectionName = $null
  $PrivateEndpointProvisioningState = $null
  $resID = $null
  $res = $null
  $plResource = $null
  $privateEC  = $null
  $plSid = $null
}

# dump results to screen
$deviceList

if($Flatten) {
  $csvData = $deviceList | ConvertTo-Csv -NoTypeInformation
  $csvData | Out-File "./$SubnetName-connected-devices.csv"
} else {
  $jsonData = $deviceList | ConvertTo-Json -Depth 10
  $jsonData | Out-File "./$SubnetName-connected-devices.json"
}

if ($Transcript) { Stop-Transcript }
