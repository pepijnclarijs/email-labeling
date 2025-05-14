import logging
import azure.functions as func
import os

# This works
# def main(req: func.HttpRequest) -> func.HttpResponse:
#     logging.info("Function triggered")
    
#     try:
#         client_id = os.getenv("CLIENT_ID")
#         tenant_id = os.getenv("TENANT_ID")
#         logging.info(f"CLIENT_ID: {client_id}, TENANT_ID: {tenant_id}")
        
#         if not client_id or not tenant_id:
#             return func.HttpResponse("Missing env vars", status_code=500)

#         return func.HttpResponse("Function is alive", status_code=200)

#     except Exception as e:
#         logging.exception("Something went wrong")
#         return func.HttpResponse(str(e), status_code=500)

# TODO: try the below code:
import logging
import azure.functions as func
import urllib.parse
import os
import httpx
import asyncio

CLIENT_ID = os.getenv("CLIENT_ID")
CLIENT_SECRET = os.getenv("CLIENT_SECRET")
TENANT_ID = os.getenv("TENANT_ID")
REDIRECT_URI = os.getenv("REDIRECT_URI")
SCOPE = "https://graph.microsoft.com/Mail.Read"

AUTH_URL = f"https://login.microsoftonline.com/{TENANT_ID}/oauth2/v2.0/authorize"
TOKEN_URL = f"https://login.microsoftonline.com/{TENANT_ID}/oauth2/v2.0/token"

def main(req: func.HttpRequest) -> func.HttpResponse:
    return asyncio.run(handle_request(req))

async def handle_request(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Handling request")
    
    code = req.params.get("code")
    logging.info(f"Received code: {code}")

    if not code:
        logging.info("No code provided, redirecting to Microsoft login")
        params = {
            "client_id": CLIENT_ID,
            "response_type": "code",
            "redirect_uri": REDIRECT_URI,
            "response_mode": "query",
            "scope": SCOPE,
        }
        login_url = AUTH_URL + "?" + urllib.parse.urlencode(params)
        logging.info(f"Redirecting to: {login_url}")
        return func.HttpResponse(
            status_code=302,
            headers={"Location": login_url}
        )

    # Exchange code for token
    data = {
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": REDIRECT_URI,
        "scope": SCOPE,
    }

    try:
        async with httpx.AsyncClient() as client:
            token_response = await client.post(TOKEN_URL, data=data)
            token = token_response.json()
            logging.info(f"Token response: {token}")

            if "access_token" not in token:
                return func.HttpResponse(str(token), status_code=400)

            access_token = token["access_token"]

            # Call Microsoft Graph API
            headers = {"Authorization": f"Bearer {access_token}"}
            graph_url = "https://graph.microsoft.com/v1.0/me/messages?$top=5"
            graph_response = await client.get(graph_url, headers=headers)
            emails = graph_response.json()

            logging.info(f"Graph response: {emails}")
            return func.HttpResponse(str(emails), mimetype="application/json")

    except Exception as e:
        logging.exception("Exception while handling token or Graph call")
        return func.HttpResponse(str(e), status_code=500)
