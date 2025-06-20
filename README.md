# Basic Load Balancer UDR Configuration Audit

This PowerShell script audits Azure Basic SKU Load Balancers and identifies the route tables and next hop configurations associated with the subnets connected to their backend pools.

## 📌 Purpose

The script is designed to:
- Identify all Basic SKU Load Balancers in your Azure environment.
- Trace backend pool associations to network interfaces and their subnets.
- Retrieve route tables assigned to those subnets.
- Extract default route (`0.0.0.0/0`) next hop configurations.
- Export the results to a CSV file for further analysis or reporting.

## 🧰 Prerequisites

- PowerShell 7.x or later
- Azure PowerShell module (`Az`)
- Permissions to read network resources and route tables across subscriptions

Install the Az module if needed:

```powershell
Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
