# Example: workload subnets

Demonstrates the subnet shapes a real spoke grows once workloads arrive, and
which parts of each shape Azure is strict about.

```bash
terraform init
terraform plan     # creates a resource group, a VNet and 8 subnets
terraform destroy
```

## What each subnet is for

| Subnet | Why it looks like that |
|---|---|
| `snet-appsvc` | App Service VNet integration requires a delegation to `Microsoft.Web/serverFarms` with the `/subnets/action` action |
| `snet-containerapps` | Container Apps environments require a delegation to `Microsoft.App/environments`, sized `/23` or larger |
| `snet-devops` | Managed DevOps pools require a delegation to `Microsoft.DevOpsInfrastructure/pools` with the `join` action |
| `snet-privateendpoints` | private endpoints only work when `private_endpoint_network_policies` is `"Disabled"` |
| `snet-privatelinkservice` | Private Link Service needs endpoint policies off and `private_link_service_network_policies_enabled = false` |
| `snet-appgateway` | Application Gateway needs a subnet of its own, with nothing else in it |
| `snet-storage` | service endpoints keep Storage/KeyVault/SQL traffic on the Azure backbone; the resource itself still needs a network ACL |
| `snet-general` | anything without special requirements |

## Things that are easy to get wrong

**Delegation is an exact match.** A wrong `name`, or a missing action, fails at
plan time with an error from Azure rather than from Terraform. The three
delegations above are the current values for those services.

**`private_endpoint_network_policies` is a string.** It takes `"Disabled"`,
`"Enabled"`, `"NetworkSecurityGroupEnabled"` or `"RouteTableEnabled"`. The
boolean `private_endpoint_network_policies_enabled` was removed from the provider
in azurerm 4.0; use the string.

**`"Disabled"` does not disable NSGs.** It disables network policies for private
endpoints only. Every other resource in the subnet still obeys the NSG.

**GatewaySubnet is a name, not a convention.** If you add a VPN or ExpressRoute
gateway, the subnet must be called exactly `GatewaySubnet`, sized `/27` or
larger, and must have no delegation. It is commented out here because this
template has no gateway by design.

**Size for growth, not for the demo.** A `/26` is fine for a test and too small
for a Container Apps environment. A delegated subnet cannot be resized later
without recreating it.

## Using these in the template

Copy the subnet entries into the `subnets` map of your spoke's
`azure-virtual-network` call. Nothing else changes: NSGs and route tables are
keyed by subnet name, so a new subnet appears in both without further edits — add
its role to the rules map and it gets policy.
