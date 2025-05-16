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

# TODO: try the below code locally:
import logging
import azure.functions as func
import urllib.parse
import os
import httpx
import asyncio
from O365 import Account, FileSystemTokenBackend

CLIENT_ID = os.getenv("CLIENT_ID")
CLIENT_SECRET = os.getenv("CLIENT_SECRET")
TENANT_ID = os.getenv("TENANT_ID")
REDIRECT_URI = os.getenv("REDIRECT_URI")
SCOPES = [
    'offline_access',
    "https://graph.microsoft.com/Mail.Read",
    "https://graph.microsoft.com/Mail.ReadWrite",
    "https://graph.microsoft.com/Mail.Send",
    "https://graph.microsoft.com/MailboxSettings.ReadWrite"
]

AUTH_URL = f"https://login.microsoftonline.com/{TENANT_ID}/oauth2/v2.0/authorize"
TOKEN_URL = f"https://login.microsoftonline.com/{TENANT_ID}/oauth2/v2.0/token"

credentials = (CLIENT_ID, CLIENT_SECRET)
# This will save the token locally (e.g., for reuse)
token_backend = FileSystemTokenBackend(token_path='.', token_filename='o365_token.txt')
account = Account(credentials, token_backend=token_backend)

if not account.is_authenticated:
    # Authenticate the account
    # This will open a browser window for the user to log in
    if account.authenticate(scopes=[SCOPES]):
        logging.info("Authentication successful")
    else:
        raise RuntimeError('Authentication Failed')

# Use the API after login
mailbox = account.mailbox()
inbox = mailbox.inbox_folder()

for message in inbox.get_messages(limit=1):
    print('Subject:', message.subject)

# To send a message
m = mailbox.new_message()
m.to.add('pepijnclarijs@gmail.com')
m.subject = 'Hello from O365!'
m.body = 'This is a test email.'
m.send()
