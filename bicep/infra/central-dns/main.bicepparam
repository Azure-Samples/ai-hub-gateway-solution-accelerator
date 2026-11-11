using './main.bicep'

param tags = {
  'managed-by': 'citadel-central-dns'
}

// Add existing VNet IDs now, or redeploy with them after the accelerator creates its VNet.
param virtualNetworkIds = []
