<#
.SYNOPSIS
    Initializes terraform.tfvars from the current Azure CLI session.

.DESCRIPTION
    Reads subscription_id and tenant_id from the active Azure CLI account,
    generates a unique alphanumeric suffix for globally unique resource names,
    and creates infra/terraform.tfvars.
    Run this after 'az login' and before 'terraform apply'.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$infraDir = Join-Path $PSScriptRoot "..\infra"
$tfvarsFile = Join-Path $infraDir "terraform.tfvars"
$exampleFile = Join-Path $infraDir "terraform.tfvars.example"

# ---- Check Azure CLI login ----
Write-Host "Reading current Azure CLI session..." -ForegroundColor Yellow
$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    throw "Not logged in. Run 'az login' (or 'az login --use-device-code' in Codespaces) first."
}

$subscriptionId = $account.id
$tenantId = $account.tenantId
$subscriptionName = $account.name

Write-Host "  Subscription : $subscriptionName ($subscriptionId)" -ForegroundColor Green
Write-Host "  Tenant       : $tenantId" -ForegroundColor Green

# ---- Generate unique suffix (6 chars, lowercase alphanumeric) ----
$chars = 'abcdefghijklmnopqrstuvwxyz0123456789'
$uniqueSuffix = -join (1..6 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
Write-Host "  Unique suffix: $uniqueSuffix" -ForegroundColor Green

# ---- Generate terraform.tfvars ----
if (Test-Path $tfvarsFile) {
    Write-Host ""
    Write-Host "  terraform.tfvars already exists. Overwrite? (y/N) " -ForegroundColor Yellow -NoNewline
    $answer = Read-Host
    if ($answer -ne 'y') {
        Write-Host "  Skipped." -ForegroundColor Gray
        return
    }
}

$lines = Get-Content $exampleFile
$output = @()
foreach ($line in $lines) {
    if ($line -match '^\s*subscription_id\s*=') {
        $output += "subscription_id    = `"$subscriptionId`""
    } elseif ($line -match '^\s*tenant_id\s*=') {
        $output += "tenant_id          = `"$tenantId`""
    } elseif ($line -match '^\s*unique_suffix\s*=') {
        $output += "unique_suffix      = `"$uniqueSuffix`""
    } elseif ($line -match '^\s*location\s*=') {
        $output += "location           = `"swedencentral`""
    } elseif ($line -match '^\s*search_location\s*=') {
        $output += "search_location = `"northeurope`""
    } elseif ($line -match '^\s*create_resource_group\s*=') {
        # Preserve the user's choice from the example file
        $output += $line
    } else {
        $output += $line
    }
}

$output | Set-Content -Path $tfvarsFile -Encoding utf8

Write-Host ""
Write-Host "Created: infra/terraform.tfvars" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  cd ../infra"
Write-Host "  terraform init"
Write-Host "  terraform apply"
