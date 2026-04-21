<#
.SYNOPSIS
    Exports Terraform outputs to a shared config file.

.DESCRIPTION
    Reads all terraform outputs and saves them to scripts/.infra-config.json.
    This allows all scripts to work without direct terraform access
    (e.g., when running from a Codespace or a different machine).
    Run this after 'terraform apply'.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$infraDir  = Join-Path $PSScriptRoot "..\infra"
$configFile = Join-Path $PSScriptRoot ".infra-config.json"

Write-Host "Exporting Terraform outputs to scripts/.infra-config.json..." -ForegroundColor Yellow

Push-Location $infraDir
try {
    $config = @{
        search_service_endpoint        = (terraform output -raw search_service_endpoint)
        search_admin_key               = (terraform output -raw search_admin_key)
        openai_endpoint                = (terraform output -raw openai_endpoint)
        openai_key                     = (terraform output -raw openai_key)
        openai_embedding_deployment    = (terraform output -raw openai_embedding_deployment)
        gpt51_deployment_name          = (terraform output -raw gpt51_deployment_name)
        app_registration_client_id     = (terraform output -raw app_registration_client_id)
        app_registration_client_secret = (terraform output -raw app_registration_client_secret)
        tenant_id                      = (terraform output -raw tenant_id)
        resource_group_name            = (terraform output -raw resource_group_name)
        search_service_name            = (terraform output -raw search_service_name)
    }
} finally {
    Pop-Location
}

$config | ConvertTo-Json | Set-Content -Path $configFile -Encoding utf8

Write-Host "  Saved $($config.Count) outputs to .infra-config.json" -ForegroundColor Green
Write-Host ""
Write-Host "All scripts will now use this config file." -ForegroundColor Cyan
