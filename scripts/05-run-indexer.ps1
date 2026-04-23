<#
.SYNOPSIS
    Reruns the Azure AI Search indexer to pick up new/updated documents.

.DESCRIPTION
    Resets and reruns the SharePoint indexer so that newly uploaded documents
    are indexed. Use this after uploading new documents with 02-upload-documents.ps1.
#>

[CmdletBinding()]
param(
    [switch]$ResetFirst
)

$ErrorActionPreference = 'Stop'

Write-Host "[1/3] Reading infrastructure config..." -ForegroundColor Yellow
$infraConfigFile = Join-Path $PSScriptRoot ".infra-config.json"
if (-not (Test-Path $infraConfigFile)) { throw "Run 01a-save-infra-config.ps1 first (after terraform apply)." }
$infra = Get-Content $infraConfigFile | ConvertFrom-Json
$searchEndpoint = $infra.search_service_endpoint
$searchKey      = $infra.search_admin_key

$indexerName = "sharepoint-indexer"
$headers = @{ "api-key" = $searchKey; "Content-Type" = "application/json" }

# ---- Check current indexer status ----
Write-Host "[2/3] Checking indexer status..." -ForegroundColor Yellow
try {
    $status = Invoke-RestMethod -Uri "$searchEndpoint/indexers/$indexerName/status?api-version=2025-11-01-preview" -Method GET -Headers $headers
    $lastRun = $status.lastResult
    if ($lastRun) {
        Write-Host "  Last run: $($lastRun.status) at $($lastRun.startTime)" -ForegroundColor Gray
        Write-Host "  Documents processed: $($lastRun.itemsProcessed) | Failed: $($lastRun.itemsFailed)" -ForegroundColor Gray
    }
} catch {
    Write-Host "  Could not get status: $($_.Exception.Message)" -ForegroundColor Yellow
}

# ---- Optional: Reset indexer (reprocess all documents) ----
if ($ResetFirst) {
    Write-Host "  Resetting indexer (will reprocess ALL documents)..." -ForegroundColor Yellow
    try {
        Invoke-RestMethod -Uri "$searchEndpoint/indexers/$indexerName/reset?api-version=2025-11-01-preview" -Method POST -Headers $headers | Out-Null
        Write-Host "  Reset OK" -ForegroundColor Green
    } catch {
        Write-Host "  Reset failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ---- Run indexer ----
Write-Host "[3/3] Running indexer..." -ForegroundColor Yellow
try {
    Invoke-RestMethod -Uri "$searchEndpoint/indexers/$indexerName/run?api-version=2025-11-01-preview" -Method POST -Headers $headers | Out-Null
    Write-Host "  Indexer started successfully!" -ForegroundColor Green
} catch {
    $msg = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
    if ($msg -match "already running") {
        Write-Host "  Indexer is already running. Wait for it to finish." -ForegroundColor Yellow
    } else {
        Write-Host "  Failed to start indexer: $msg" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "The indexer runs asynchronously. New documents should be available in ~5-15 minutes." -ForegroundColor Cyan
Write-Host "Check status: $searchEndpoint/indexers/$indexerName/status?api-version=2025-11-01-preview" -ForegroundColor Gray
