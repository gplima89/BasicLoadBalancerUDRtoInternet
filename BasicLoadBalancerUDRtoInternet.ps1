<#
The MIT License (MIT)
Copyright © 2025

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated 
documentation files (the “Software”), to deal in the Software without restriction, including without limitation 
the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, 
and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions 
of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED 
TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL 
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF 
CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
DEALINGS IN THE SOFTWARE.
#>

# Optional: Uncomment to authenticate to Azure
# Connect-AzAccount

# Initialize an array to store results
$results = @()

# Define the KQL query to find Basic SKU load balancers and their backend pool associations
$query = @"
resources
| where type =~ 'Microsoft.Network/loadBalancers'
| where sku.name == 'Basic'
| mv-expand backendPools = properties.backendAddressPools
| extend backendPoolId = tostring(backendPools.id)
| project lbName = name, resourceGroup, subscriptionId, location, lbId = id, backendPoolId, tags
| join kind=leftouter (
    resources
    | where type =~ 'Microsoft.Network/networkInterfaces'
    | mv-expand ipConfigs = properties.ipConfigurations
    | mv-expand lbPools = ipConfigs.properties.loadBalancerBackendAddressPools
    | extend backendPoolId = tostring(lbPools.id)
    | extend nicId = id
    | extend subnetId = tostring(ipConfigs.properties.subnet.id)
    | summarize poolMembers = count(), networkInterfaceIds = make_list(nicId), subnetIds = make_list(subnetId) by backendPoolId
) on backendPoolId
| where isnotnull(poolMembers) and poolMembers != 0
| project lbName, resourceGroup, subscriptionId, location, lbId, tags, NetworkInterfaces = poolMembers, networkInterfaceIds, subnetIds, backendPoolId
"@

# Execute the KQL query using Azure Resource Graph
$KQL = Search-AzGraph -Query $query

# Extract unique subnet IDs from the query result
$UniqueSubIDs = $KQL.subnetIds | Sort-Object -Unique

# Loop through each unique subnet ID
foreach ($subnet in $UniqueSubIDs) {
    # Extract the subscription ID from the subnet resource ID
    $SubID = $subnet.Split('/')[-9]

    # Extract the current context's subscription ID (cleaned of parentheses)
    $Context = ((Get-AzContext).Name.split(' ')[-5]) -replace '[()]',''

    Write-Output "Current Context: $Context, and SubID: $SubID"

    # If the current context doesn't match the subnet's subscription, switch context
    if ($SubID -ne $Context) {
        Write-Output "Changing Context to: $SubID"
        Set-AzContext -SubscriptionId $SubID
    }

    # Define a KQL query to get route table info for the current subnet
    $queryroutetable = @"
resources
| where type =~ "Microsoft.Network/virtualNetworks"
| mv-expand subnet = properties.subnets
| extend
    subnetName = tostring(subnet.name),
    subnetId = tostring(subnet.id),
    routetableID = tostring(subnet.properties.routeTable.id)
| where subnetId =~ "$subnet"
| project subscriptionId, resourceGroup, vNetName = name, subnetName, subnetId, routetableID
"@

    # Execute the subnet-specific query
    $Subnetinfo = Search-AzGraph -Query $queryroutetable

    # Retrieve the default route (0.0.0.0/0) from the associated route table
    $RouteTableNextHop = (Get-AzRouteTable -Name $Subnetinfo.routetableID.Split('/')[-1] -ResourceGroupName $Subnetinfo.routetableID.Split('/')[-5]).Routes | Where-Object {
        $_.AddressPrefix -eq "0.0.0.0/0"
    }

    # Create a custom object with the relevant information
    $NetHopInfo = [PSCustomObject]@{
        SubscriptionID        = $Subnetinfo.subscriptionId
        ResourceGroupName     = $Subnetinfo.resourceGroup
        VNetName              = $Subnetinfo.vNetName
        SubnetName            = $Subnetinfo.subnetName
        RouteTable            = $Subnetinfo.routetableID
        RTAddressPrefix       = $RouteTableNextHop.AddressPrefix
        RTName                = $RouteTableNextHop.Name
        RTNextHopType         = $RouteTableNextHop.NextHopType
        RTNextHopIP           = $RouteTableNextHop.NextHopIpAddress
    }

    # Add the object to the results array
    $results += $NetHopInfo
}

# Output the results to the console
$results

# Export the results to a CSV file
$results | Export-Csv -Path "C:\temp\BasicLBUDRConfiguration.csv" -NoTypeInformation
