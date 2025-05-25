# email-labeling
Email labeling project

# TODO's
TODO: 
TODO: CI/CD is a mess, the project structure is a mess, the secret handling is a mess, the terraform 
main.tf is a mess. Refactor step by step.

# Prerequisites
🔐 GitHub CLI Prerequisite: Authenticate to GitHub
To securely add Azure credentials to your GitHub repository as secrets, ensure the following setup is complete:

✅ Prerequisite
You must be authenticated with GitHub via the command line using the GitHub CLI (gh):
gh auth login
This command will guide you through logging into your GitHub account and authorizing the CLI to access your repositories.

⚠️ This step must be completed before running any gh secret set commands used to configure secrets for GitHub Actions.

Azure Login.
To be able to connect to azure, you must be logged in using the cli command:
```az login```
This will guide you through the steps to logging in to your azure account. To check if you logged in
successfully, run 
```az account show```

# Quickstart
Make sure the requirements in the prerequisites are met. Then run 

```terraform plan```

To see what resources will be created.
If you agree with the plan, run 

```terraform apply```

When prompted, type yes. When terraform is done creating resources, it should show:

```
Outputs:

github_actions_credentials_json = <sensitive>
```

These credentials must be set as a secret in your github repo to allow the github actions to push files to your newly created azure storage container.


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
My function app needs to have the right permissions in order to fetch emails from outlook mailboxes. For this, the function app needs an App Registration with the right permissions set. 
I am using a managed identity to have my azure function app authenticate against microsoft graph.
I need to create a workflow where the user can authenticate via Azure AD and authorize my function app to access their email using OAuth 2.0 Authorization Code Grant Flow.

### So who is authenticating against what?
There are two "Who's" involved:

1) The function app
This is the code running in Azure.
This code needs permission to call Microsoft Graph

2) The user
This is the human logging into the app.
The user is the owner of their mailbox and must consent the app to read their mail.

Azure AD manages users, apps, logins and consent. When your app wants to read John’s email, Azure AD asks John:

“Hey, this app wants to read your email. Do you agree?”

If he agrees, Azure AD gives the app an access token which the app can use to call Microsoft Graph on John's behalf.

### What is OAuth 2.0?
OAuth 2.0 is an industry standard way of letting apps act on behalf of users. It defines how:
*) A user logs in
*) The app gets permission
*) The app gets an access token



I am now going to try using the o365 python library to handle logins. I am also going to refactor
code so that I can run the az function app locally. For this, I need the azure functions core tool,
which is a cli tool. Install it by:

```
npm install -g azure-functions-core-tools@4 --unsafe-perm true
```


### AZ function app
To get started with azure functions, it is reccommendable to use the quickstart guide:
https://learn.microsoft.com/en-us/azure/azure-functions/create-first-function-azure-developer-cli?pivots=programming-language-python&tabs=linux%2Cget%2Cbash%2Cpowershell

It is highly recommendable to test the app locally first, and then push it later. 

The current setup uses the o365 library to handle login flows and read emails. The authentication, 
permissions and azure function configurations are the most difficult aspects of this project. 


tried adding AzureWebJobsFeatureFlags=EnableWorkerIndexing to environment variables, but not working
also tried: Azure: Enter PYTHON_ENABLE_WORKER_EXTENSIONS=1 in your app settings. (https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-python?tabs=get-started%2Casgi%2Capplication-level&pivots=python-mode-decorators#environment-variables)
I have set SCM_DO_BUILD_DURING_DEPLOYMENT=true
I added ENABLE_ORYX_BUILD=true in app settings env var.

TODO: make local deployment sh script that zips the needed files into a deployment zip.
TODO: ADD gemini_api_key automatically
TODO: When deploying manually logout works fine, but when deploying via gh actions, it does not0...

NOTE: I had to change the scope for the SP to specify the functionapp directly, not the resource group its in.