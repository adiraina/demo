// OVERVIEW 
// This Bicep deployment sets up an Azure Function App, an App Service Plan, and a Service Bus with a queue. The Function App is configured to receive messages from a Service Bus queue. The Function App is also configured to use a Virtual Network.
//Common Parameters
//*****************************************************************************************************
@description('Region ')
param region string

@description('{businessUnit}')
param businessUnit string

@description('{Stage}')
param deploymentStage string

@description('Product Name')
param productName string

@description('''  ''')
param tags object

@description('Application Name')
param applicationName string

@description('Application Id')
param applicationId string

@description('Shared Log Anaytics Workspace Id')
param funcApiInsightWorkspaceId string

param role string
// *****************************************************************************************************

// VNET Parameters
// *****************************************************************************************************
@description('(Optional) Virtual network subnet resource ids')
param subnetIds array
// *****************************************************************************************************

// App Service Plan Parameters
// *****************************************************************************************************
@description('plan kind Backend and Frontend')
param planKind string

@description('SKU of Web App Service ')
param planSkuName string

@description('planSkuTier app, func')
param planSkuTier string

// *****************************************************************************************************

// Function App Parameters
// *****************************************************************************************************
@description('(Require) The Name of Storage account.')
@maxLength(24)
param funcApiAppStName string

@description('(Optional) Sets the virtual network rules')
param funcApiAppStVirtualNetwork array = []

@description('func vnet int')
param funcVnet string

@description('(Optional) Log Analytics Contributor RoleId')
param funcApiAppiDefinitionResourceName string 


// *****************************************************************************************************

// App Service Plan for both Function Apps & Appservices
//*****************************************************************************************************
//Configuration Module
//*****************************************************************************************************
module configModule 'br/acr-prod:modules/core/config:v3' = {
  name: 'configModule'
  params: {
    applicationId: applicationId
    applicationName: applicationName
    businessUnit: businessUnit
    deploymentStage: deploymentStage
    productName: productName
    role: role
  }
}

//   ServiceBus module
//*****************************************************************************************************
module serviceBusModule 'br/acr-prod:modules/core/servicebus:v3' = {
  name: 'serviceBusModule'
  params: {
    region: region
    sbnsName: configModule.outputs.namingConventions.ServiceBusNamespaceName
    sbnsSku: 'Premium'
    sbnsIdentityType: 'SystemAssigned'
    tags: tags
    sbnsZoneRedundant: false
    SubnetResourceIdsForServiceEndpoints: subnetIds
  }
}

//   ServiceBus module Queue
//*****************************************************************************************************
module serviceBusQueuesModule 'br/acr-prod:modules/core/servicebus-queues:v4' = {
  name: 'serviceBusQueuesModule'
  dependsOn: [serviceBusModule]
  params: {
    sbnsName: serviceBusModule.outputs.sbnsName
    sbnsQueueSuffix: 'paverd'
    sbnsQueuelockDuration: 'PT5M'
    sbnsQueuemaxSizeInMegabytes: 1024
    sbnsQueuerequiresDuplicateDetection: false
    sbnsQueuerequiresSession: false
    sbnsQueuedefaultMessageTimeToLive: 'P14D'
    sbnsQueuedeadLetteringOnMessageExpiration: false
    sbnsQueueduplicateDetectionHistoryTimeWindow: 'PT10M'
    sbnsQueuemaxDeliveryCount: 10
    sbnsQueueenablePartitioning: false
    sbnsQueueenableExpress: false
  }
}

//App Plan
//*****************************************************************************************************
module appServPlan 'br/acr-prod:modules/core/appplan:v4' = {
  name: 'appServPlan'
  params: {
    aspName: configModule.outputs.namingConventions.AppPlanName
    aspSkuName: planSkuName
    aspSkuTier: planSkuTier
    aspKind: planKind
    region: region
    tags: tags
  }
}

//App Insights for Function App
//*****************************************************************************************************
module appInsights 'br/acr-prod:modules/core/appinsights:v2' = {
  name: 'appInsights'
  params: {
    region: region
    appiName: configModule.outputs.namingConventions.ApplicationInsightsName
    workspaceId: funcApiInsightWorkspaceId
    appiInstKeyEnabled: true
    tags: tags
  }
}

//Function App
//**************************************************************************************************
module FunctionApp 'br:crtoprodbicepregistrya.azurecr.io/modules/core/functionapp:v3' = {
  dependsOn: [appServPlan, appInsights]
  name: 'FunctionApp'
  params: {
    region: region
    stName: funcApiAppStName
    funcName: configModule.outputs.namingConventions.FunctionAppName
    funcAspId: appServPlan.outputs.aspId
    funcAppiConnectionString: appInsights.outputs.appiIntConString
    funcVnetintId: funcVnet
    stVirtualNetworkRules: funcApiAppStVirtualNetwork
    tags: tags
  }
}

// Assign RBAC access Function App to Application Insights
//******************************************************************************************************
module rbacAppInsights 'br:crtoprodbicepregistrya.azurecr.io/modules/core/rbac:v3' = {
  name: 'rbacAppInsightsModule'
  params:{
   appiName: appInsights.outputs.appiName
   roleDefinitionResourceName: funcApiAppiDefinitionResourceName
   principalId: FunctionApp.outputs.functionIdentityId
   }
}

// Grant the function the necessary role to receive messages from the Service Bus
// ******************************************************************************************************
module rbacApitoEvent 'br:crtoprodbicepregistrya.azurecr.io/modules/core/rbac:v3' = {
  name: 'rbacApitoStorage'
  params: {
    svbName: serviceBusModule.outputs.sbnsName
    roleDefinitionResourceName: 'Azure Service Bus Data Receiver'
    principalId: FunctionApp.outputs.functionIdentityId

  }
}
