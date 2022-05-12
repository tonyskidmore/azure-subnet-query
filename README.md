# Azure Subnet Query

Basic PowerShell script to gather information about the connected devices on An Azure subnet.

## Usage

Clone the repository and switch directory

````bash

git clone https://github.com/tonyskidmore/azure-subnet-query.git

cd azure-subnet-query

````
Query and export to a JSON file named after the targeted subnet.

````powershell

./Get-AzureSubnetDevices.ps1 -VirtualNetworkName my-network -ResourceGroupName rg-my-network -SubnetName my-subnet -Subscription 52f83193-8813-4c1b-ae89-bf568f347360

````

Query and export to CSV file named after the targeted subnet.

````powershell

./Get-AzureSubnetDevices.ps1 -VirtualNetworkName my-network -ResourceGroupName rg-my-network -SubnetName my-subnet -Subscription 52f83193-8813-4c1b-ae89-bf568f347360 -Flatten:$true

````
