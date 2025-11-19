# Deployment Files Summary

This document provides an overview of all deployment-related files in the AI Hub Gateway Solution Accelerator.

## 📁 Bicep Templates

### Main Templates
| File | Purpose | Usage |
|------|---------|-------|
| `bicep/infra/main.bicep` | Main infrastructure template | Primary template for deployment |
| `bicep/infra/abbreviations.json` | Azure resource abbreviations | Used by main.bicep for naming conventions |

### Bicep Parameter Files (.bicepparam)
| File | Purpose | When to Use |
|------|---------|-------------|
| `bicep/infra/main.bicepparam` | Minimal parameters for azd | Default for `azd up` deployments with environment variable support |
| `bicep/infra/main.parameters.complete.bicepparam` | Comprehensive parameter reference | Template for custom deployments, all parameters documented |
| `bicep/infra/main.parameters.dev.bicepparam` | Development environment | Cost-optimized configuration for development |
| `bicep/infra/main.parameters.prod.bicepparam` | Production environment | High-availability configuration for production |

## 📋 Environment Configuration

| File | Purpose | Usage |
|------|---------|-------|
| `.env.template` | Environment variable template | Copy to `.azure/<env>/.env` and customize |
| `.azure/<env>/.env` | Active environment variables | Created by azd, git-ignored |

## 📖 Documentation

### Quick Start Guides
| Guide | Audience | Description |
|-------|----------|-------------|
| [QUICKSTART-PARAMETERS.md](../guides/QUICKSTART-PARAMETERS.md) | All users | Fast deployment commands and common scenarios |
| [parameters-deployment-guide.md](../guides/parameters-deployment-guide.md) | Advanced users | Complete parameter file reference and customization |

### Deployment Guides
| Guide | Focus Area | Key Topics |
|-------|------------|------------|
| [deployment.md](../guides/deployment.md) | Infrastructure | Core component deployment, networking, APIM |
| [enterprise-provisioning.md](../guides/enterprise-provisioning.md) | CI/CD | Branch-based deployment, DevOps automation |
| [bring-your-own-network.md](../guides/bring-your-own-network.md) | Networking | Existing VNet integration, private endpoints |
| [deployment-troubleshooting.md](../guides/deployment-troubleshooting.md) | Support | Common issues and solutions |

### Configuration Guides
| Guide | Service | Description |
|-------|---------|-------------|
| [apim-configuration.md](../guides/apim-configuration.md) | API Management | Policies, routing, backends |
| [openai-onboarding.md](../guides/openai-onboarding.md) | Azure OpenAI | Model deployment and integration |
| [ai-search-integration.md](../guides/ai-search-integration.md) | AI Search | RAG and vector search setup |
| [ai-studio-integration.md](../guides/ai-studio-integration.md) | AI Foundry | Custom models and projects |
| [entraid-auth-validation.md](../guides/entraid-auth-validation.md) | Authentication | Microsoft Entra ID setup |

## 🔄 Deployment Workflows

### Workflow 1: Quick Start (Azure Developer CLI)

```mermaid
graph LR
    A[azd init] --> B[Configure .env]
    B --> C[azd up]
    C --> D[Deployed]
```

**Files Used:**
- `bicep/infra/main.bicep`
- `bicep/infra/main.parameters.json`
- `.azure/<env>/.env`

**Documentation:** [QUICKSTART-PARAMETERS.md](../guides/QUICKSTART-PARAMETERS.md)

---

### Workflow 2: Custom Parameters (Azure CLI)

```mermaid
graph LR
    A[Copy complete params] --> B[Customize values]
    B --> C[az deployment sub create]
    C --> D[Deployed]
```

**Files Used:**
- `bicep/infra/main.bicep`
- `bicep/infra/main.parameters.complete.json` (copy and modify)

**Documentation:** [parameters-deployment-guide.md](../guides/parameters-deployment-guide.md)

---

### Workflow 3: Enterprise CI/CD

```mermaid
graph LR
    A[Git commit] --> B[Pipeline trigger]
    B --> C[Parameter substitution]
    C --> D[Validation]
    D --> E[Deployment]
    E --> F[Deployed]
```

**Files Used:**
- `bicep/infra/main.bicep`
- Environment-specific parameter files
- CI/CD pipeline definitions

**Documentation:** [enterprise-provisioning.md](../guides/enterprise-provisioning.md)

---

## 🎯 Parameter File Selection Guide

### Choose `main.bicepparam` when
- ✅ Using Azure Developer CLI (`azd`)
- ✅ Quick proof-of-concept deployments
- ✅ Want environment variable substitution
- ✅ Following quick-start guides

### Choose environment-specific files when
- ✅ Using predefined dev or prod configurations
- ✅ Standard deployment scenarios
- ✅ Want ready-to-use optimized settings

### Choose `main.parameters.complete.bicepparam` when
- ✅ Creating custom environment configurations
- ✅ Need all parameters with documentation
- ✅ Building organization-specific templates
- ✅ Starting point for new environments

### Create custom .bicepparam files when
- ✅ Multiple environments (dev/test/staging/prod)
- ✅ CI/CD pipeline integration
- ✅ Organization-specific naming conventions
- ✅ Reusable deployment templates

## 📊 Parameter Categories Overview

| Category | Parameters | Use Cases |
|----------|-----------|-----------|
| **Basic** | environmentName, location, tags | All deployments |
| **Resource Names** | apimServiceName, cosmosDbAccountName, etc. | Custom naming |
| **Networking** | vnetName, subnets, DNS zones | BYON, private connectivity |
| **Feature Flags** | enableAIFoundry, enableAPICenter, etc. | Selective feature deployment |
| **SKU & Capacity** | apimSku, cosmosDbRUs, etc. | Cost and performance tuning |
| **AI Configuration** | aiFoundryInstances, aiFoundryModelsConfig | LLM and model setup |
| **Security** | entraAuth, network access settings | Authentication and isolation |

## 🚀 Quick Reference Commands

### Azure Developer CLI
```powershell
# Initialize
azd init

# Deploy
azd up

# Update environment
azd env set KEY=value

# Clean up
azd down
```

### Azure CLI
```powershell
# Validate
az deployment sub validate --template-file bicep/infra/main.bicep --parameters @bicep/infra/main.parameters.dev.json

# Preview
az deployment sub what-if --template-file bicep/infra/main.bicep --parameters @bicep/infra/main.parameters.dev.json

# Deploy
az deployment sub create --name citadel-deployment --location eastus --template-file bicep/infra/main.bicep --parameters @bicep/infra/main.parameters.dev.json

# Monitor
az deployment sub show --name citadel-deployment
```

## 🔐 Security Best Practices

### ✅ DO:
- Store parameter files in version control (without secrets)
- Use Azure Key Vault references for sensitive values
- Use environment variables for secrets in CI/CD
- Create separate parameter files per environment
- Document parameter customizations

### ❌ DON'T:
- Commit files with actual secrets or credentials
- Use the same parameters for dev and prod
- Hard-code subscription IDs or tenant IDs
- Share parameter files with sensitive values

## 📝 Creating New Parameter Files

### Step 1: Copy Template
```powershell
Copy-Item bicep/infra/main.parameters.complete.bicepparam bicep/infra/main.parameters.myenv.bicepparam
```

### Step 2: Customize
Edit `main.parameters.myenv.bicepparam`:
```bicep
using './main.bicep'

param environmentName = 'my-environment'
param location = 'eastus'
param apimSku = 'StandardV2'
param enableAIFoundry = true
// ... customize other parameters
```

### Step 3: Validate
```powershell
az deployment sub validate --template-file bicep/infra/main.bicep --parameters bicep/infra/main.parameters.myenv.bicepparam
```

### Step 4: Deploy
```powershell
az deployment sub create --name citadel-myenv --location eastus --template-file bicep/infra/main.bicep --parameters bicep/infra/main.parameters.myenv.bicepparam
```

---

**Last Updated:** November 2025  
**Version:** 1.0
