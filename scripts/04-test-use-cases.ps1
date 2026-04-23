<#
.SYNOPSIS
    Test prompts for each use case against AI Search + GPT-5.1 via REST API.

.DESCRIPTION
    Queries the AI Search index and sends results to GPT for analysis.
    By default uses API key auth. Use -WithACL to enable permission-filtered queries
    (requires ACL query-time preview registration on the subscription).

.PARAMETER WithACL
    Enable ACL-filtered queries using Bearer token + x-ms-query-source-authorization.
    Requires: RBAC role on search service + ACL preview registration.

.EXAMPLE
    .\04-test-use-cases.ps1              # API key auth, all documents visible
    .\04-test-use-cases.ps1 -WithACL     # Bearer auth + ACL permission filtering
#>
param(
    [switch]$WithACL
)
$ErrorActionPreference = 'Stop'

Write-Host "Reading infrastructure config..." -ForegroundColor Yellow
$infraConfigFile = Join-Path $PSScriptRoot ".infra-config.json"
if (-not (Test-Path $infraConfigFile)) { throw "Run 01a-save-infra-config.ps1 first (after terraform apply)." }
$infra = Get-Content $infraConfigFile | ConvertFrom-Json
$searchEndpoint  = $infra.search_service_endpoint
$searchKey       = $infra.search_admin_key
$foundryEndpoint = $infra.openai_endpoint.TrimEnd('/')
$foundryKey      = $infra.openai_key
$gptDeployment   = $infra.gpt51_deployment_name

$gptHeaders = @{ "api-key" = $foundryKey; "Content-Type" = "application/json" }

if ($WithACL) {
    # ACL mode: Bearer token + x-ms-query-source-authorization
    Write-Host "ACL mode - getting user token via Azure CLI..." -ForegroundColor Yellow
    $searchToken = az account get-access-token --resource "https://search.azure.com" --query accessToken -o tsv
    if (-not $searchToken) { throw "Failed to get search token. Run 'az login' first." }

    $graphToken = az account get-access-token --resource "https://graph.microsoft.com" --query accessToken -o tsv
    $me = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/me?`$select=displayName,userPrincipalName,id" -Headers @{"Authorization"="Bearer $graphToken"}
    Write-Host "  User: $($me.displayName) ($($me.userPrincipalName))" -ForegroundColor Green
    Write-Host "  OID:  $($me.id)" -ForegroundColor Green
    Write-Host "  Queries filtered by SharePoint permissions" -ForegroundColor Cyan

    $searchHeaders = @{
        "Authorization"                    = "Bearer $searchToken"
        "x-ms-query-source-authorization"  = "Bearer $searchToken"
        "Content-Type"                     = "application/json"
    }
} else {
    Write-Host "Standard mode (API key, no ACL filter)" -ForegroundColor Gray
    $searchHeaders = @{ "api-key" = $searchKey; "Content-Type" = "application/json" }
}

$apiVersion = "2025-11-01-preview"

function Search-Index([string]$Query, [int]$Top = 5) {
    $body = @{
        search                = $Query
        top                   = $Top
        select                = "title,chunk"
        queryType             = "semantic"
        semanticConfiguration = "default"
    } | ConvertTo-Json
    $r = Invoke-RestMethod -Uri "$searchEndpoint/indexes/marches-index/docs/search?api-version=$apiVersion" -Method POST -Headers $searchHeaders -Body ([System.Text.Encoding]::UTF8.GetBytes($body))

    $count = $r.value.Count
    if ($WithACL) {
        Write-Host "  Results: $count documents (ACL-filtered)" -ForegroundColor Gray
    } else {
        Write-Host "  Results: $count documents" -ForegroundColor Gray
    }

    return ($r.value | ForEach-Object { "[$($_.title)]`n$($_.chunk)" }) -join "`n---`n"
}

function Ask-GPT([string]$SystemPrompt, [string]$UserPrompt) {
    $body = @{
        messages = @(
            @{ role = "system"; content = $SystemPrompt }
            @{ role = "user"; content = $UserPrompt }
        )
        temperature = 0.3
        max_completion_tokens = 2000
    } | ConvertTo-Json -Depth 5
    $r = Invoke-RestMethod -Uri "$foundryEndpoint/openai/deployments/$gptDeployment/chat/completions?api-version=2024-10-21" -Method POST -Headers $gptHeaders -Body ([System.Text.Encoding]::UTF8.GetBytes($body))
    return $r.choices[0].message.content
}

$systemPrompt = @"
Tu es l'Assistant Marchés Publics du GHT Contoso. Tu aides les acheteurs hospitaliers.
Règles :
- Cite TOUJOURS la référence du marché et le document source
- Structure avec des tableaux quand pertinent
- Ne fabrique JAMAIS de données
- Réponds en français
"@

# ============================================================================
# USE CASE 1: Recherche de marché existant
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " UC1: RECHERCHE MARCHE EXISTANT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$q1 = "gants chirurgicaux examen candidats attribution"
Write-Host "Recherche: $q1" -ForegroundColor Gray
$context1 = Search-Index $q1
$answer1 = Ask-GPT $systemPrompt "Voici des extraits de marchés publics :`n$context1`n`nQuestion de l'acheteur : Est-ce qu'on a un marché existant pour les gants chirurgicaux ? Donne-moi la référence, les candidats et le titulaire."
Write-Host $answer1

# ============================================================================
# USE CASE 2: Étude de marché et conformité
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " UC2: ETUDE DE MARCHE ET CONFORMITE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$q2 = "étude marché réactifs laboratoire conformité normes"
Write-Host "Recherche: $q2" -ForegroundColor Gray
$context2 = Search-Index $q2
$answer2 = Ask-GPT $systemPrompt "Voici des extraits de marchés publics :`n$context2`n`nQuestion de l'acheteur : Quels sont les critères de conformité et les normes exigées pour les marchés de réactifs de laboratoire ? Fais une synthèse de l'étude de marché si disponible."
Write-Host $answer2

# ============================================================================
# USE CASE 3: Vérification SLA et pénalités
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " UC3: SLA ET PENALITES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$q3 = "SLA pénalités délai livraison maintenance disponibilité"
Write-Host "Recherche: $q3" -ForegroundColor Gray
$context3 = Search-Index $q3
$answer3 = Ask-GPT $systemPrompt "Voici des extraits de marchés publics :`n$context3`n`nQuestion de l'acheteur : Quels sont les SLA, les pénalités de retard et les conditions de maintenance dans nos marchés ? Compare les engagements entre différents marchés si possible."
Write-Host $answer3

# ============================================================================
# USE CASE 4: Challenge du choix candidats
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " UC4: CHALLENGE CHOIX CANDIDATS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$q4 = "candidats notation critères attribution choix score classement"
Write-Host "Recherche: $q4" -ForegroundColor Gray
$context4 = Search-Index $q4
$answer4 = Ask-GPT $systemPrompt "Voici des extraits de marchés publics :`n$context4`n`nQuestion de l'acheteur : Analyse les candidats et leurs notations. Est-ce que toi, en tant qu'IA, tu aurais fait le même choix d'attribution ? Si non, explique pourquoi et donne ton propre classement avec tes arguments."
Write-Host $answer4

# ============================================================================
# USE CASE 5: Comparaison inter-marchés
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " UC5: COMPARAISON INTER-MARCHES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$q5 = "montant budget prix marché attribution fournisseur"
Write-Host "Recherche: $q5" -ForegroundColor Gray
$context5 = Search-Index $q5
$answer5 = Ask-GPT $systemPrompt "Voici des extraits de marchés publics :`n$context5`n`nQuestion de l'acheteur : Fais-moi un tableau récapitulatif des marchés que tu trouves avec la référence, la catégorie, le montant et le titulaire. Identifie les fournisseurs qui reviennent plusieurs fois."
Write-Host $answer5

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " TESTS TERMINES $(if ($WithACL) { '(ACL MODE)' } else { '(NO ACL)' })" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
if (-not $WithACL) {
    Write-Host ""
    Write-Host "Tip: Run with -WithACL to test permission-filtered queries:" -ForegroundColor Gray
    Write-Host "  .\04-test-use-cases.ps1 -WithACL" -ForegroundColor Gray
}
