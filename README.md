# Hands-On Lab: Copilot Studio + Azure AI Search - Procurement RAG Agent

> **Duration:** ~90 minutes | **Level:** Intermediate  
> **Last updated:** April 2025

Build a Copilot Studio agent that helps hospital procurement buyers search, analyze, and compare public procurement documents using Azure AI Search with RAG (Retrieval-Augmented Generation).

---

## Architecture Overview

```
docs/ (30 PDFs in 8 category folders)
    |  02-upload-documents.ps1 (Graph API)
    v
SharePoint Online (Document Library)
    |  AI Search SharePoint indexer
    v
Azure AI Search
    |  Skillset: text chunking + OpenAI embeddings
    |  Index: hybrid (keyword + vector + semantic)
    v
Copilot Studio Agent
    |  Knowledge source: AI Search
    v
End Users (Procurement Buyers)
```

---

## Prerequisites

> **Recommended:** Use the included Dev Container (`.devcontainer/`) which has all tools pre-installed. Open in VS Code with the Dev Containers extension, or launch in GitHub Codespaces.

| Requirement | Details |
|---|---|
| **Azure subscription** | With permissions to create resources (Contributor + User Access Admin) |
| **Microsoft 365** | SharePoint Online access (for document library) |
| **Copilot Studio** | License or trial (https://copilotstudio.microsoft.com) |
| **Azure CLI** | v2.60+ (pre-installed in dev container) |
| **Terraform** | v1.5+ (pre-installed in dev container) |
| **PowerShell** | 7.x (pre-installed in dev container) |

---

## Lab Steps

### Step 1: Set Up Your Environment

**Option A: GitHub Codespaces (recommended)**

1. **Fork** this repository to your own GitHub account
2. Go to your fork and click **Code** > **Codespaces** > **Create codespace on main**
3. Wait for the container to build (~2-3 min) — all tools and extensions are pre-installed
4. Once ready, open the terminal (PowerShell is the default)

**Option B: VS Code Dev Container (local)**

1. Install [Docker Desktop](https://www.docker.com/products/docker-desktop/) and the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
2. Fork and clone the repo, then open it in VS Code
3. When prompted, click **Reopen in Container** (or run `Dev Containers: Reopen in Container` from the command palette)

**Option C: Local setup**

```powershell
# Fork the repo first, then clone your fork
git clone https://github.com/<YOUR_GITHUB_USERNAME>/copilotstudio-procurement-rag.git
cd copilotstudio-procurement-rag
```

Ensure you have Azure CLI (v2.60+), Terraform (v1.5+), and PowerShell 7.x installed.

---

In all options, log in to Azure:
```powershell
# Codespaces / Dev Container (no browser available)
az login --use-device-code

# Local setup (opens browser)
az login
```

### Step 2: Deploy Azure Infrastructure

Deploy Azure AI Search, Azure OpenAI (embeddings + GPT), and the App Registration for SharePoint indexer auth.

```powershell
# Auto-generate terraform.tfvars from your Azure CLI session
cd scripts
.\00-init-tfvars.ps1

# Deploy
cd ../infra
terraform init
terraform apply
```

> The script reads `subscription_id` and `tenant_id` from your active `az login` session and creates `infra/terraform.tfvars` automatically. Edit the file if you want to change the resource group name or region.

> **What gets created:**
> - Resource Group `rg-procurement-rag`
> - Azure AI Search (basic SKU) with semantic reranker and managed identity
> - Microsoft Foundry (Sweden Central) with `text-embedding-ada-002` + `gpt-5.1` deployments
> - Entra ID App Registration with Sites.Read.All permission (for SharePoint indexer)

**After apply completes**, export the outputs so all scripts can use them:
```powershell
cd ../scripts
.\01a-save-infra-config.ps1
```

> This saves endpoints, keys, and IDs to `scripts/.infra-config.json`. All subsequent scripts read from this file — no need for `terraform output` access.

---

### Step 3: Create SharePoint Site

Create a SharePoint team site with category folders to host the procurement documents.

```powershell
# Make sure you're logged into Azure CLI with Graph permissions
az login

.\01-create-sharepoint-site.ps1
```

> **What happens:**
> 1. Creates a Microsoft 365 Group + SharePoint site "Marchés GHT Contoso"
> 2. Creates 8 category folders in the default document library
> 3. Saves site/drive IDs to `scripts/.sharepoint-config.json`

**Verify:** Open the SharePoint site URL printed in the output and confirm the 8 folders exist.

---

### Step 4: Upload Documents to SharePoint

Upload all 30 PDFs to SharePoint with structured metadata.

```powershell
.\02-upload-documents.ps1
```

> **What happens:** Each PDF is uploaded via Graph API to its category folder. A description field is set with structured metadata (category, reference, year, type, supplier, amount, subject) for AI Search indexing.

**Expected output:**
```
[2/2] Uploading 30 documents...
  OK: AO-2024-BIO-0847-equipements-biomedicaux.pdf (84.3KB) -> BIOMEDICAL/
  OK: AO-2025-BIO-0134-endoscopie-digestive.pdf (52.1KB) -> BIOMEDICAL/
  ...
Upload complete: 30 OK, 0 failed.
```

---

### Step 5: Configure Azure AI Search

Create the search index, SharePoint data source, AI skillset (chunking + embeddings), and indexer.

```powershell
.\03-configure-ai-search.ps1
```

> **What gets created:**
> - **Index** `marches-index` - fields for content, metadata, chunks, vectors (1536 dims), semantic config
> - **Data source** `sharepoint-datasource` - connects to SharePoint via App Registration
> - **Skillset** `marches-skillset` - text split (2000 chars, 200 overlap) + Azure OpenAI embeddings
> - **Indexer** `sharepoint-indexer` - processes PDFs, extracts content, runs skillset, populates index

---

### Step 6: Monitor Indexer Progress

Wait for the indexer to process all documents (~5-15 minutes).

**Option A: Azure Portal**
1. Go to your AI Search resource > **Indexers** > `sharepoint-indexer`
2. Check status, documents processed, and any errors

**Option B: Script**
```powershell
.\05-run-indexer.ps1
```

**Option C: REST API**
```powershell
$searchEndpoint = terraform output -raw search_service_endpoint
$searchKey = terraform output -raw search_admin_key
$headers = @{ "api-key" = $searchKey }

# Check indexer status
Invoke-RestMethod -Uri "$searchEndpoint/indexers/sharepoint-indexer/status?api-version=2024-05-01-preview" -Headers $headers | ConvertTo-Json -Depth 5
```

**Expected:** 30 documents processed, 0 failed.

---

### Step 7: Test the Search Index

Verify the index works before connecting Copilot Studio.

```powershell
.\04-test-use-cases.ps1
```

This runs 4 test scenarios:
1. **UC1 - Search existing tender:** "Do we have a contract for surgical gloves?"
2. **UC2 - Compliance analysis:** "What are the conformity requirements for lab reagents?"
3. **UC3 - SLA extraction:** "What are the SLAs and penalties in our contracts?"
4. **UC4 - Candidate challenge:** "Analyze the candidate selection and suggest improvements"

---

### Step 8: Create the Copilot Studio Agent

#### 8a. Create a New Agent

1. Go to [https://copilotstudio.microsoft.com](https://copilotstudio.microsoft.com)
2. Select your environment (top-right)
3. Click **Create** > **New agent**
4. Choose **"Skip to configure"** (bottom left) to skip the wizard
5. Set the agent name: `Assistant Marchés Publics GHT Contoso`
6. Set the language to **French**

#### 8b. Paste the System Instructions

1. In the agent editor, click **Instructions** (or go to **Settings** > **Generative AI** > **Instructions**)
2. Paste the following system prompt:

```
Tu es l'Assistant Marchés Publics du GHT Contoso, un expert en achats hospitaliers.
Tu aides les acheteurs des établissements du groupement à exploiter la base documentaire des marchés publics.

Tu as accès à une base de connaissances Azure AI Search contenant les appels d'offres, études de marché et rapports d'analyse du GHT. Utilise TOUJOURS cette source pour répondre.

Ce que tu sais faire :
1. Rechercher un marché existant pour un produit, une catégorie ou un fournisseur. Tu donnes la référence, la date, le montant, les lots et le titulaire.
2. Analyser la conformité d'un appel d'offres : critères techniques, normes (CE, ISO, ANSM), spécifications obligatoires, points de vigilance réglementaire.
3. Extraire les SLA et pénalités : délais de livraison, disponibilité, pénalités de retard, maintenance (GTI/GTR), clauses de résiliation.
4. Analyser et challenger le choix des candidats : reconstituer la grille de notation, proposer ta propre analyse critique, comparer ton classement avec celui de l'acheteur, expliquer les écarts et identifier les risques.
5. Comparer plusieurs marchés : tableaux croisés, tendances de prix, fournisseurs récurrents, anomalies.

Règles absolues :
- Cite TOUJOURS la référence du marché (ex: AO-2024-DM-0488) et le document source.
- Précise HT/TTC et la durée pour les montants.
- Ne fabrique JAMAIS de données. Si tu ne trouves pas, dis-le.
- Utilise des tableaux comparatifs dès que pertinent.
- Réponds en français.
- Pour l'analyse candidats : | Candidat | Prix | Note technique | Note globale | Rang | puis analyse critique.
- Quand on te demande de "challenger", sois constructif : arguments pour ET contre, risques, suggestions d'amélioration.
```

3. Click **Save**

#### 8c. Add Azure AI Search as Knowledge Source

1. In the left panel, click **Knowledge**
2. Click **+ Add knowledge**
3. Select **Azure AI Search**
4. Fill in the connection details (values are in `scripts/.infra-config.json`):

| Field | Value |
|---|---|
| **Index name** | `marches-index` |
| **Endpoint** | Copy `search_service_endpoint` from `.infra-config.json` |
| **API Key** | Copy `search_admin_key` from `.infra-config.json` |

5. Click **Add** > **Save**

> **Tip:** You can display the values by running: `Get-Content scripts/.infra-config.json | ConvertFrom-Json | Select-Object search_service_endpoint, search_admin_key`

#### 8d. Enable Generative Orchestration

1. Go to **Settings** (gear icon) > **Generative AI**
2. Set orchestration mode to **"Generative"** (not "Classic")
3. Save

---

### Step 9: Test the Agent in Copilot Studio

Open the **Test** panel (bottom-right chat icon) and try these prompts in order:

**Prompt 1 — Search an existing contract:**
```
On a un marché existant pour les gants chirurgicaux ?
```
> Expected: Returns reference **AO-2024-DM-0488**, supplier Medline Industries, 498 000 € HT, with lot details.

**Prompt 2 — Extract SLAs and penalties:**
```
Quels sont les SLA et pénalités pour le marché d'endoscopie ?
```
> Expected: Returns **AO-2025-BIO-0134** with GTI 4h, GTR 24h, 98% availability, penalties 500€/day.

**Prompt 3 — Compliance analysis:**
```
Quelles sont les exigences de conformité pour les sutures chirurgicales ?
```
> Expected: Returns **AO-2025-DM-0245** with CE class III, MDR regulation, ISO 13485, UDI traceability, ISO 10993 biocompatibility.

**Prompt 4 — Compare contracts:**
```
Fais un tableau comparatif de tous les marchés biomédicaux avec montants et attributaires
```
> Expected: Table with AO-2024-BIO-0847, 0955, 1203, and AO-2025-BIO-0134 — 4 contracts, amounts, suppliers.

**Prompt 5 — Challenge candidate selection:**
```
Analyse les candidats du marché télémedecine et dis-moi si tu aurais fait le même choix
```
> Expected: Analyzes **AO-2025-IT-0312**, reconstructs the scoring grid, discusses Doctolib vs Parsys trade-offs, gives a critical opinion.

**Prompt 6 — Cross-document analysis:**
```
Quels marchés ont un engagement environnemental ou RSE ?
```
> Expected: Finds transport (AO-2025-TR-0289), antiseptics (AC-2025-MED-0891), cleaning (AO-2024-HOT-0412), and restauration (PA-2024-HOT-0156).

---

## Adding New Documents (Incremental Update)

When you need to add more documents after the initial setup:

```powershell
# 1. Add new PDFs to the matching docs/<CATEGORY>/ folder

# 2. Add entries to the $catalog in 02-upload-documents.ps1

# 3. Upload new documents
.\02-upload-documents.ps1

# 4. Rerun the indexer (with reset to reprocess all)
.\05-run-indexer.ps1 -ResetFirst

# 5. Wait ~5-15 minutes, then test
```

---

## Document Categories Reference

| Code | Category | Description |
|---|---|---|
| BIO | BIOMEDICAL | Medical equipment, imaging, sterilization, endoscopy |
| DM | DISPOSITIFS-MEDICAUX | Single-use devices, gloves, dressings, sutures |
| EG | EQUIPEMENTS-GENERAUX | Furniture, beds, wheelchairs, surgical clothing |
| HOT | HOTELLERIE | Catering, laundry, cleaning, hospitality services |
| IT | INFORMATIQUE | EHR, cybersecurity, network, telemedicine |
| LAB | LABORATOIRES | Analyzers, reagents, microbiology, molecular biology |
| MED | MEDICAMENTS | Pharmaceuticals, medical gases, antiseptics, nutrition |
| TR | TRANSPORTS-VEHICULES | Ambulances, shuttles, vehicle fleet, patient transport |

---

## Complete Document Inventory (30 documents)

| Reference | Category | Year | Type | Supplier | Amount HT |
|---|---|---|---|---|---|
| AO-2024-BIO-0847 | BIOMEDICAL | 2024 | AO | MedTech Solutions SAS | 471 200 € |
| AO-2024-BIO-0955 | BIOMEDICAL | 2024 | AO | Getinge AB | 1 365 000 € |
| AO-2024-BIO-1203 | BIOMEDICAL | 2024 | AO | Siemens Healthineers | 3 690 000 € |
| **AO-2025-BIO-0134** | **BIOMEDICAL** | **2025** | **AO** | **Olympus Medical Systems** | **1 895 000 €** |
| AO-2023-DM-0312 | DISPOSITIFS-MEDICAUX | 2023 | AO | MediSupply Corp | 832 000 € |
| AO-2024-DM-0488 | DISPOSITIFS-MEDICAUX | 2024 | AO | Medline Industries | 498 000 € |
| AO-2024-DM-0621 | DISPOSITIFS-MEDICAUX | 2024 | AO | Molnlycke Health Care | 1 185 000 € |
| **AO-2025-DM-0245** | **DISPOSITIFS-MEDICAUX** | **2025** | **AO** | **Ethicon / B. Braun** | **420 000 €** |
| AO-2023-EG-0567 | EQUIPEMENTS-GENERAUX | 2023 | AO | Invacare France | 255 000 € |
| AO-2024-EG-0234 | EQUIPEMENTS-GENERAUX | 2024 | AO | Hill-Rom / Linet France | 907 500 € |
| AO-2024-EG-0389 | EQUIPEMENTS-GENERAUX | 2024 | AO | Molnlycke / Hartmann | 515 000 € |
| **AO-2025-EG-0178** | **EQUIPEMENTS-GENERAUX** | **2025** | **AO** | **Hill-Rom (Baxter)** | **1 350 000 €** |
| AO-2023-HOT-0298 | HOTELLERIE | 2023 | AO | Initial Textile Services | 645 000 € |
| AO-2024-HOT-0412 | HOTELLERIE | 2024 | AO | Onet Proprete Sante | 1 890 000 € |
| PA-2024-HOT-0156 | HOTELLERIE | 2024 | PA | Sodexante Restauration | 2 400 000 € |
| AO-2023-IT-0156 | INFORMATIQUE | 2023 | AO | Dedalus France | 2 850 000 € |
| AO-2024-IT-0234 | INFORMATIQUE | 2024 | AO | Orange Cyberdefense | 485 000 € |
| MAPA-2024-IT-0089 | INFORMATIQUE | 2024 | MAPA | Axians Healthcare IT | 612 000 € |
| **AO-2025-IT-0312** | **INFORMATIQUE** | **2025** | **AO** | **Doctolib Pro / Parsys** | **1 375 000 €** |
| AO-2023-LAB-0891 | LABORATOIRES | 2023 | AO | N/A (etude de marche) | 3 530 000 € |
| AO-2024-LAB-0112 | LABORATOIRES | 2024 | AO | Sysmex | 1 280 000 € |
| AO-2024-LAB-0345 | LABORATOIRES | 2024 | AO | bioMerieux | 1 450 000 € |
| **AO-2025-LAB-0567** | **LABORATOIRES** | **2025** | **AO** | **Roche / bioMerieux** | **1 170 000 €** |
| AC-2023-MED-0567 | MEDICAMENTS | 2023 | AC | Multi-attributaires | 8 200 000 € |
| AO-2023-MED-0892 | MEDICAMENTS | 2023 | AO | Fresenius Kabi / Nutricia | 1 100 000 € |
| AO-2024-MED-0723 | MEDICAMENTS | 2024 | AO | Air Liquide Sante | 515 000 € |
| **AC-2025-MED-0891** | **MEDICAMENTS** | **2025** | **AC** | **Schulke / B. Braun / Anios** | **680 000 €** |
| AO-2023-TR-0145 | TRANSPORTS-VEHICULES | 2023 | AO | Gruau Ambulances | 668 000 € |
| AO-2024-TR-0078 | TRANSPORTS-VEHICULES | 2024 | AO | ALD Automotive | 978 000 € |
| PA-2024-TR-0201 | TRANSPORTS-VEHICULES | 2024 | PA | Transdev Sante | 295 000 € |
| **AO-2025-TR-0289** | **TRANSPORTS-VEHICULES** | **2025** | **AO** | **Gruau Ambulances / GFA** | **1 850 000 €** |

> **Bold** = new documents added in this update

---

## Troubleshooting

| Issue | Fix |
|---|---|
| Indexer fails with 403 | Terraform grants admin consent automatically; verify `azuread_app_role_assignment` applied correctly via `terraform apply` |
| 0 documents indexed | Check the SharePoint data source connection string; verify docs are uploaded |
| Empty search results | Wait 10-15 min for indexer; check indexer status for errors |
| Embedding skill fails | Verify Azure OpenAI endpoint and key in skillset; check model deployment |
| Copilot Studio no results | Verify AI Search endpoint/key in Knowledge config; test index directly first |

---

## Clean Up

```powershell
cd infra
terraform destroy

# Delete SharePoint site (manual or via Graph API)
# Delete the Microsoft 365 Group from Entra ID
```
