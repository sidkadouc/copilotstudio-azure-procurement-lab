<#
.SYNOPSIS
    Configures Azure AI Search: index, SharePoint data source, skillset, and indexer.
#>
param()
$ErrorActionPreference = 'Stop'

$spConfig = Get-Content (Join-Path $PSScriptRoot ".sharepoint-config.json") | ConvertFrom-Json

Write-Host "[1/5] Reading infrastructure config..." -ForegroundColor Yellow
$infraConfigFile = Join-Path $PSScriptRoot ".infra-config.json"
if (-not (Test-Path $infraConfigFile)) { throw "Run 01a-save-infra-config.ps1 first (after terraform apply)." }
$infra = Get-Content $infraConfigFile | ConvertFrom-Json
$searchEndpoint = $infra.search_service_endpoint
$searchKey      = $infra.search_admin_key
$openaiEndpoint = $infra.openai_endpoint.TrimEnd('/')
$openaiKey      = $infra.openai_key
$embeddingModel = $infra.openai_embedding_deployment
$appClientId    = $infra.app_registration_client_id
$appSecret      = $infra.app_registration_client_secret
$tenantId       = $infra.tenant_id

$headers = @{ "api-key" = $searchKey }
$indexName = "marches-index"
$dsName = "sharepoint-datasource"
$skillsetName = "marches-skillset"
$indexerName = "sharepoint-indexer"
$siteUrl = $spConfig.siteUrl
$connStr = "SharePointOnlineEndpoint=$siteUrl;ApplicationId=$appClientId;ApplicationSecret=$appSecret;TenantId=$tenantId"

function Call-Search([string]$Uri, [string]$Body, [string]$Label) {
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
        Invoke-RestMethod -Uri $Uri -Method PUT -Headers $headers -Body $bytes -ContentType "application/json; charset=utf-8" | Out-Null
        Write-Host "  $Label - OK" -ForegroundColor Green
    } catch {
        $msg = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        Write-Host "  $Label - FAILED:" -ForegroundColor Red
        Write-Host "  $msg" -ForegroundColor Red
    }
}

# Clean existing
Write-Host "Cleaning existing resources..." -ForegroundColor Gray
foreach ($r in @("indexers/$indexerName","skillsets/$skillsetName","datasources/$dsName","indexes/$indexName")) {
    try { Invoke-RestMethod -Uri "$searchEndpoint/$r`?api-version=2025-11-01-preview" -Method DELETE -Headers $headers } catch {}
}

Write-Host "[2/5] Creating index..." -ForegroundColor Yellow
Call-Search "$searchEndpoint/indexes/$indexName`?api-version=2025-11-01-preview" @"
{"name":"$indexName","description":"Index des marchés publics hospitaliers du GHT Contoso. Contient les appels d'offres, études de marché et rapports d'analyse (30 documents PDF) dans 8 catégories: biomédical, dispositifs médicaux, équipements généraux, hôtellerie, informatique, laboratoires, médicaments, transports.","fields":[{"name":"id","type":"Edm.String","key":true,"filterable":true,"retrievable":true,"analyzer":"keyword"},{"name":"content","type":"Edm.String","searchable":true,"retrievable":true},{"name":"metadata_spo_item_name","type":"Edm.String","searchable":true,"filterable":true,"retrievable":true},{"name":"metadata_spo_item_path","type":"Edm.String","filterable":true,"retrievable":true},{"name":"metadata_spo_item_last_modified","type":"Edm.DateTimeOffset","filterable":true,"sortable":true,"retrievable":true},{"name":"metadata_spo_site_library_item_id","type":"Edm.String","filterable":true,"retrievable":true},{"name":"chunk","type":"Edm.String","searchable":true,"retrievable":true},{"name":"chunk_id","type":"Edm.String","filterable":true,"retrievable":true},{"name":"parent_id","type":"Edm.String","filterable":true,"retrievable":true},{"name":"title","type":"Edm.String","searchable":true,"filterable":true,"retrievable":true},{"name":"content_vector","type":"Collection(Edm.Single)","searchable":true,"retrievable":false,"stored":false,"dimensions":1536,"vectorSearchProfile":"vector-profile"},{"name":"UserIds","type":"Collection(Edm.String)","permissionFilter":"userIds","filterable":true,"retrievable":false},{"name":"GroupIds","type":"Collection(Edm.String)","permissionFilter":"groupIds","filterable":true,"retrievable":false}],"permissionFilterOption":"disabled","vectorSearch":{"algorithms":[{"name":"hnsw-algo","kind":"hnsw","hnswParameters":{"m":4,"efConstruction":400,"efSearch":500,"metric":"cosine"}}],"profiles":[{"name":"vector-profile","algorithm":"hnsw-algo","vectorizer":"openai-vectorizer"}],"vectorizers":[{"name":"openai-vectorizer","kind":"azureOpenAI","azureOpenAIParameters":{"resourceUri":"$openaiEndpoint","deploymentId":"$embeddingModel","modelName":"text-embedding-ada-002","apiKey":"$openaiKey"}}]},"semantic":{"defaultConfiguration":"default","configurations":[{"name":"default","prioritizedFields":{"titleField":{"fieldName":"title"},"prioritizedContentFields":[{"fieldName":"chunk"}]}}]}}
"@ "Index"

Write-Host "[3/5] Creating SharePoint data source..." -ForegroundColor Yellow
Call-Search "$searchEndpoint/datasources/$dsName`?api-version=2025-11-01-preview" @"
{"name":"$dsName","type":"sharepoint","indexerPermissionOptions":["userIds","groupIds"],"credentials":{"connectionString":"$connStr"},"container":{"name":"defaultSiteLibrary","query":null}}
"@ "Data source"

Write-Host "[4/5] Creating skillset..." -ForegroundColor Yellow
Call-Search "$searchEndpoint/skillsets/$skillsetName`?api-version=2025-11-01-preview" @"
{"name":"$skillsetName","skills":[{"@odata.type":"#Microsoft.Skills.Text.SplitSkill","name":"text-split","context":"/document","inputs":[{"name":"text","source":"/document/content"}],"outputs":[{"name":"textItems","targetName":"chunks"}],"textSplitMode":"pages","maximumPageLength":2000,"pageOverlapLength":200},{"@odata.type":"#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill","name":"embedding","context":"/document/chunks/*","inputs":[{"name":"text","source":"/document/chunks/*"}],"outputs":[{"name":"embedding","targetName":"vector"}],"resourceUri":"$openaiEndpoint","deploymentId":"$embeddingModel","modelName":"text-embedding-ada-002","apiKey":"$openaiKey"}],"indexProjections":{"selectors":[{"targetIndexName":"$indexName","parentKeyFieldName":"parent_id","sourceContext":"/document/chunks/*","mappings":[{"name":"chunk","source":"/document/chunks/*"},{"name":"content_vector","source":"/document/chunks/*/vector"},{"name":"title","source":"/document/metadata_spo_item_name"},{"name":"UserIds","source":"/document/metadata_user_ids"},{"name":"GroupIds","source":"/document/metadata_group_ids"}]}],"parameters":{"projectionMode":"skipIndexingParentDocuments"}}}
"@ "Skillset"

Write-Host "[5/5] Creating indexer..." -ForegroundColor Yellow
Call-Search "$searchEndpoint/indexers/$indexerName`?api-version=2025-11-01-preview" @"
{"name":"$indexerName","dataSourceName":"$dsName","targetIndexName":"$indexName","skillsetName":"$skillsetName","parameters":{"configuration":{"indexedFileNameExtensions":".pdf,.docx","dataToExtract":"contentAndMetadata"}},"fieldMappings":[{"sourceFieldName":"metadata_spo_site_library_item_id","targetFieldName":"id","mappingFunction":{"name":"base64Encode"}},{"sourceFieldName":"metadata_spo_item_name","targetFieldName":"title"},{"sourceFieldName":"metadata_user_ids","targetFieldName":"UserIds"},{"sourceFieldName":"metadata_group_ids","targetFieldName":"GroupIds"}],"schedule":{"interval":"PT1H"}}
"@ "Indexer"

Write-Host ""
Write-Host "Done. Grant admin consent: https://portal.azure.com/#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/Permissions/appId/$appClientId" -ForegroundColor Cyan

