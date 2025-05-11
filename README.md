# email-labeling
Email labeling project


# Diary
1) Firstly, create git repo for new project
2) Create AFA definition
3) Create tf file
4) Setup infracost cli tool
5) run terraform init
6) Login to azure in cli (az login)
7) Run terraform plan
8) Run infracost breakdown --path . to see the estimated costs
9) Run terraform apply if costs are ok
10) Looking for a good way to deploy python code to my azure function app. This is a lot harder than expected. I need:
	A Service Principal to login to my azure via the workflow. A service principal is a way of identification that can be used by scripts and programs. I first need to make this service principal (SP) for my azure  The SP credentials are put in the secrets of the GitHub repository. You can create the SP via the azure cli using sth like:
az ad sp create-for-rbac \
  --name my-scoped-sp \
  --role "Storage Blob Data Contributor" \
  --scopes /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-rg/providers/Microsoft.Storage/storageAccounts/mystorage

It's, however, quite annoying to find the right credential names, as in one place the, what I would see as the username, is called ClientID, whereas in another it's called appId. This means that these credentials need to be mapped to the right name when you use them in a GitHub workflow to login to azure.

Next, I need the SP to have the right role assignments in order for my workflow to have the right permissions to do its tasks. 
az ad sp list --query "[?appOwnerOrganizationId=='99633252-0db6-403c-accf-a4f1b870eca0'].{Name:displayName, AppId:appId}" --output table



# --- CI/CD via GitHub --- #
Sadly, since I am using the consumption tier, I cannot upload the zip file directly to the azure functions app. Instead, you need to create an azure blob storage, upload the zip file containing the code to the blob storage

To setup CI/CD via GitHub actions, the idea is to have a gh workflow/actions running when a merge to prod happens. The workflow then pushes the new code to an azure storage container. This storage container is being watched by the azure functions and this is the place where the code for the azure function app resides. In order to make this push from gh workflow to azure storage container possible, the gh workflow needs to have the right authorizations. For this we need to create some stuff in azure. The goal is to create an object that is authorized to do specific stuff and that has credentials. These credentials can then be used by other (for example third party) applications to authenticate, kind of, as such an object. They are then granted the authorizations of that object. To create such an object, though, you first need to create an app registration. This is just like classes and objects in programming. You first create a class and then use this class to create the object (class instance) itself. The App Registration contains the 'authorization definitions', so the rules of what this thing is allowed to do. The Service Principal is like an account for this App Service that can be used by apps to make changes to, for example, resources. The creation of the App Registration (class definition) and Service Principal (class instance) can be done by a single command:

az ad sp create-for-rbac --name "<name for both the App Registration and Service Principal>" --role contributor --scopes /subscriptions/<your-subscription-id>

This command does three things:
1) It creates an App Registration
2) It creates a Service Principal
3) It generates a client secret which can be used by my GitHub workflow to log in and use the authorizations set for this service principal.

What the App Registration (or rather the Service Principal) is allowed to do is defined by the --role and --scopes arguments:
Role: Contributor → can read/write any resource.
Scope: Entire subscription → means across all resource groups and resources.
This service principal has full contributor access to everything in your subscription.

The command should have the output of the form:

{
	"app_id": "",
	"password": "",
	"tennant": ""
}

The information maps like this:
Azure output key	What GitHub expects
appId	                clientId
password	        clientSecret
tenant			tenantId

What you want to save as a secret in gh is the following:
*) Create gh secret for azure credentials:
echo '{
  "clientId": "<appId>",
  "clientSecret": "<password>",
  "tenantId": "<tenant>",
  "subscriptionId": "<GetYourSubscription(I would propose from a dotenv file or sth)>",
  "resourceManagerEndpointUrl": "https://management.azure.com/"
}' | gh secret set AZURE_CREDENTIALS --repo pepijnclarijs/email-labeling

These are the credentials for the Service Principal and can be used to unlock the authorization of the SP. Using this, the GitHub workflow can now push code changes to the azure blob container

	
# --- Setup Azure App Registration authorizations --- #
An app registration is a formal record of an app inside Microsoft's identity system. Such a registration can be re-used for other apps as long as they:

- Use the same OAuth scopes
- Belong to the same overall application
- Use the same client ID and secret
- Use consistent redirect URIs

Such an app registration defines:

- Who your app is (e.g., client ID)
- What it’s allowed to do (e.g., read mail)
- How users log in to it (e.g., redirect URI)
- How it authenticates (e.g., client secret or cert)
- Who can use it (your tenant only, or others too)



# --- Seting up Microsoft Graph for Email fetching --- #
My function app needs to have the right permissions in order to fetch emails from outlook mailboxes. For this, the function app needs:

*) An App Registration

