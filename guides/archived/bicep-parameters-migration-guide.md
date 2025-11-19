# Migration Guide: JSON to Bicep Parameter Files

This guide helps you migrate from JSON parameter files (.json) to native Bicep parameter files (.bicepparam).

## Why Migrate?

Bicep parameter files (.bicepparam) offer several advantages over JSON:

- ✅ **Type Safety** - Parameter types are validated at design time
- ✅ **IntelliSense** - Full autocomplete support in VS Code
- ✅ **Better Syntax** - Cleaner, more readable Bicep syntax
- ✅ **Functions** - Use `readEnvironmentVariable()` and other Bicep functions
- ✅ **No Wrapper** - Parameters don't need `{ "value": ... }` wrappers
- ✅ **Comments** - Native `//` and `/* */` comment support
- ✅ **Validation** - Errors caught before deployment

## Migration Steps

### Step 1: Install/Update Bicep

Ensure you have Bicep CLI (comes with Azure CLI 2.20.0+):

```powershell
# Check version
az bicep version

# Update if needed
az bicep upgrade
```

### Step 2: Create .bicepparam File

#### Option A: Manual Conversion

1. Create a new `.bicepparam` file:
```powershell
New-Item bicep/infra/main.parameters.dev.bicepparam
```

2. Add the `using` statement:
```bicep
using './main.bicep'
```

3. Convert each parameter:

**From JSON:**
```json
"environmentName": {
  "value": "citadel-dev"
}
```

**To Bicep:**
```bicep
param environmentName = 'citadel-dev'
```

#### Option B: Use Provided Templates

We've already created template files for you:

```powershell
# Use the complete template as starting point
Copy-Item bicep/infra/main.parameters.complete.bicepparam bicep/infra/main.parameters.myenv.bicepparam

# Or use pre-configured environments
# Development
bicep/infra/main.parameters.dev.bicepparam

# Production
bicep/infra/main.parameters.prod.bicepparam
```

### Step 3: Handle Special Cases

#### Arrays
**JSON:**
```json
"aiFoundryInstances": {
  "value": [
    {
      "name": "",
      "location": "eastus"
    }
  ]
}
```

**Bicep:**
```bicep
param aiFoundryInstances = [
  {
    name: ''
    location: 'eastus'
  }
]
```

#### Objects
**JSON:**
```json
"tags": {
  "value": {
    "Environment": "Development",
    "CostCenter": "Engineering"
  }
}
```

**Bicep:**
```bicep
param tags = {
  Environment: 'Development'
  CostCenter: 'Engineering'
}
```

#### Environment Variables
**JSON (azd only):**
```json
"environmentName": {
  "value": "${AZURE_ENV_NAME}"
}
```

**Bicep:**
```bicep
param environmentName = readEnvironmentVariable('AZURE_ENV_NAME', 'default-value')
```

#### Comments
**JSON:**
```json
{
  "// BASIC PARAMETERS": {
    "value": "Configuration for environment"
  },
  "environmentName": {
    "value": "citadel-dev"
  }
}
```

**Bicep:**
```bicep
// BASIC PARAMETERS
// Configuration for environment
param environmentName = 'citadel-dev'

/* Or use block comments
   for multi-line descriptions */
param location = 'eastus'
```

### Step 4: Validate Migration

Test your new .bicepparam file:

```powershell
# Validate syntax and parameters
az deployment sub validate `
  --location "eastus" `
  --template-file "bicep/infra/main.bicep" `
  --parameters "bicep/infra/main.parameters.dev.bicepparam"

# Preview changes
az deployment sub what-if `
  --location "eastus" `
  --template-file "bicep/infra/main.bicep" `
  --parameters "bicep/infra/main.parameters.dev.bicepparam"
```

### Step 5: Update Deployment Commands

#### Azure CLI

**Old (JSON):**
```powershell
az deployment sub create `
  --name "citadel-deployment" `
  --location "eastus" `
  --template-file "bicep/infra/main.bicep" `
  --parameters "@bicep/infra/main.parameters.dev.json"
```

**New (Bicep):**
```powershell
az deployment sub create `
  --name "citadel-deployment" `
  --location "eastus" `
  --template-file "bicep/infra/main.bicep" `
  --parameters "bicep/infra/main.parameters.dev.bicepparam"
```

**Key Difference:** No `@` prefix for .bicepparam files!

#### Azure Developer CLI (azd)

The `azd` tool automatically looks for `.bicepparam` files before `.json` files:

```powershell
# No changes needed - azd automatically uses .bicepparam if available
azd up
```

Priority order:
1. `main.bicepparam` (if exists)
2. `main.parameters.json` (fallback)

### Step 6: Update CI/CD Pipelines

#### Azure DevOps Pipeline

**Before:**
```yaml
- task: AzureCLI@2
  inputs:
    azureSubscription: 'MyServiceConnection'
    scriptType: 'ps'
    scriptLocation: 'inlineScript'
    inlineScript: |
      az deployment sub create `
        --template-file bicep/infra/main.bicep `
        --parameters @bicep/infra/main.parameters.prod.json
```

**After:**
```yaml
- task: AzureCLI@2
  inputs:
    azureSubscription: 'MyServiceConnection'
    scriptType: 'ps'
    scriptLocation: 'inlineScript'
    inlineScript: |
      az deployment sub create `
        --template-file bicep/infra/main.bicep `
        --parameters bicep/infra/main.parameters.prod.bicepparam
```

#### GitHub Actions

**Before:**
```yaml
- name: Deploy to Azure
  run: |
    az deployment sub create \
      --template-file bicep/infra/main.bicep \
      --parameters @bicep/infra/main.parameters.prod.json
```

**After:**
```yaml
- name: Deploy to Azure
  run: |
    az deployment sub create \
      --template-file bicep/infra/main.bicep \
      --parameters bicep/infra/main.parameters.prod.bicepparam
```

## Common Migration Patterns

### Pattern 1: Simple Value Parameters

```bicep
// JSON: "param": { "value": "stringValue" }
param stringParam = 'stringValue'

// JSON: "param": { "value": 123 }
param intParam = 123

// JSON: "param": { "value": true }
param boolParam = true
```

### Pattern 2: Array Parameters

```bicep
param arrayParam = [
  'item1'
  'item2'
  'item3'
]
```

### Pattern 3: Object Parameters

```bicep
param objectParam = {
  property1: 'value1'
  property2: 'value2'
  nested: {
    nestedProp: 'nestedValue'
  }
}
```

### Pattern 4: Empty/Default Values

```bicep
param optionalString = ''
param optionalArray = []
param optionalObject = {}
```

### Pattern 5: Environment-Based Values

```bicep
param environmentName = readEnvironmentVariable('AZURE_ENV_NAME', 'citadel-dev')
param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus')
param enableFeature = bool(readEnvironmentVariable('ENABLE_FEATURE', 'true'))
param capacity = int(readEnvironmentVariable('CAPACITY', '1'))
```

## Troubleshooting

### Issue: Syntax errors in .bicepparam file

**Solution:** Install Bicep VS Code extension for syntax highlighting and validation:
```powershell
code --install-extension ms-azuretools.vscode-bicep
```

### Issue: "Cannot find module './main.bicep'"

**Solution:** Ensure the `using` statement path is correct and relative to the .bicepparam file:
```bicep
using './main.bicep'  // Correct if files are in same directory
using '../main.bicep' // If .bicepparam is in subdirectory
```

### Issue: Type mismatch errors

**Solution:** Bicep validates types automatically. Ensure your values match the expected types:
```bicep
// Wrong - string instead of int
param apimSkuUnits = '1'

// Correct
param apimSkuUnits = 1
```

### Issue: Environment variable not resolving

**Solution:** Ensure environment variable exists and use default value:
```bicep
// May fail if CUSTOM_VAR not set
param value = readEnvironmentVariable('CUSTOM_VAR')

// Better - provides fallback
param value = readEnvironmentVariable('CUSTOM_VAR', 'default-value')
```

## Backward Compatibility

### Keep Both Formats (Transition Period)

You can maintain both .json and .bicepparam files during migration:

```
bicep/infra/
  ├── main.bicep
  ├── main.bicepparam                    # New - for azd and local dev
  ├── main.parameters.json               # Old - for CI/CD (temporary)
  ├── main.parameters.dev.bicepparam     # New - development
  ├── main.parameters.dev.json           # Old - development (remove later)
  ├── main.parameters.prod.bicepparam    # New - production
  └── main.parameters.prod.json          # Old - production (remove later)
```

### Gradual Migration Strategy

1. **Week 1:** Create .bicepparam equivalents
2. **Week 2:** Test .bicepparam in dev environment
3. **Week 3:** Update CI/CD to use .bicepparam
4. **Week 4:** Migrate all environments
5. **Week 5:** Remove .json files (after backup)

## Best Practices

1. **Use Templates:** Start from `main.parameters.complete.bicepparam`
2. **Environment Variables:** Use `readEnvironmentVariable()` for secrets
3. **Comments:** Document why specific values are set
4. **Validation:** Always run `az deployment sub validate` before deploying
5. **Version Control:** Commit .bicepparam files (without secrets)
6. **Naming:** Use consistent naming: `main.parameters.<env>.bicepparam`

## Resources

- [Bicep Parameter Files Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/parameter-files)
- [Bicep Functions Reference](https://learn.microsoft.com/azure/azure-resource-manager/bicep/bicep-functions)
- [VS Code Bicep Extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep)
- [Parameters Deployment Guide](./parameters-deployment-guide.md)
- [Quick Start Guide](./QUICKSTART-PARAMETERS.md)

## Need Help?

- Check [Deployment Troubleshooting](./deployment-troubleshooting.md)
- Review example files in `bicep/infra/`
- Open an issue in the repository
