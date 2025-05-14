import logging
import azure.functions as func
import urllib.parse
import os
import httpx

CLIENT_ID = os.getenv("CLIENT_ID")
CLIENT_SECRET = os.getenv("CLIENT_SECRET")
TENANT_ID = os.getenv("TENANT_ID")
REDIRECT_URI = os.getenv("REDIRECT_URI") or "https://<your-function-url>/api/azure_app"
SCOPE = "Mail.Read"

AUTH_URL = f"https://login.microsoftonline.com/{TENANT_ID}/oauth2/v2.0/authorize"
TOKEN_URL = f"https://login.microsoftonline.com/{TENANT_ID}/oauth2/v2.0/token"

async def main(req: func.HttpRequest) -> func.HttpResponse:
    code = req.params.get('code')

    if not code:
        # No code yet: redirect to Microsoft login
        params = {
            "client_id": CLIENT_ID,
            "response_type": "code",
            "redirect_uri": REDIRECT_URI,
            "response_mode": "query",
            "scope": SCOPE,
        }
        login_url = AUTH_URL + "?" + urllib.parse.urlencode(params)
        return func.HttpResponse(
            status_code=302,
            headers={"Location": login_url}
        )

    # We got a code → exchange for access token
    data = {
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": REDIRECT_URI,
        "scope": SCOPE,
    }

    async with httpx.AsyncClient() as client:
        token_response = await client.post(TOKEN_URL, data=data)
        token = token_response.json()

        if "access_token" not in token:
            return func.HttpResponse(str(token), status_code=400)

        access_token = token["access_token"]

        # Use token to call Microsoft Graph
        headers = {"Authorization": f"Bearer {access_token}"}
        graph_url = "https://graph.microsoft.com/v1.0/me/messages?$top=5"

        graph_response = await client.get(graph_url, headers=headers)
        emails = graph_response.json()

        return func.HttpResponse(str(emails), mimetype="application/json")
