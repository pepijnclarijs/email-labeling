import azure.functions as func
import os
from dotenv import load_dotenv
from O365 import Account
import logging

load_dotenv(override=True)

CLIENT_ID = os.getenv("CLIENT_ID")
CLIENT_SECRET = os.getenv("CLIENT_SECRET")
REDIRECT_URI = os.getenv("REDIRECT_URI")
print(CLIENT_ID, CLIENT_SECRET, REDIRECT_URI)

app = func.FunctionApp()

state_map = {}
credentials = (CLIENT_ID, CLIENT_SECRET)
scopes = ['https://graph.microsoft.com/Mail.ReadWrite', 'https://graph.microsoft.com/Mail.Send']

def _get_account(): 
    """
    Get the account object from the state map.
    If it doesn't exist, create a new one.
    """
    account = state_map.get("account")
    if not account:
        account = Account(credentials)
        state_map["account"] = account
    return account

@app.route(route="go-to-login", auth_level=func.AuthLevel.ANONYMOUS)
def go_to_login(req: func.HttpRequest) -> func.HttpResponse:
    account = _get_account()
    state_map["account"] = account
    auth_url, _ = account.connection.get_authorization_url(
        requested_scopes=scopes,
        redirect_uri=REDIRECT_URI
    )
    # Save mapping so we can retrieve the authorization_url later using the state
    state_map["state"] = auth_url

    html_content = f'<a href="{auth_url}">Click here to login</a>'
    return func.HttpResponse(html_content, mimetype="text/html")

@app.route(route="auth-callback", auth_level=func.AuthLevel.ANONYMOUS)
def login(req: func.HttpRequest) -> func.HttpResponse:
    account = _get_account()
    
    # ask for a login using console based authentication. See Authentication for other flows
    if not account.is_authenticated:
        is_auth_successful = account.authenticate(scopes=scopes, redirect_uri=REDIRECT_URI)
        html_content = f'<h1>Hello There! is_auth_successful: {is_auth_successful}<h1>'
    else: 
        html_content = '<h1>Hello There! You are already authenticated<h1> </br> Click here to get the first email in your inbox <a href="/api/get-first-email">Get First Email</a>'

    return func.HttpResponse(html_content, mimetype="text/html")

@app.route(route="get-first-email", auth_level=func.AuthLevel.ANONYMOUS)
def get_first_email(req: func.HttpRequest) -> func.HttpResponse:
    account = _get_account()

    mailbox = account.mailbox()
    inbox = mailbox.inbox_folder()
    messages = list(inbox.get_messages(limit=1))
    logging.info(f"type(messages): {type(messages)}, messages: {messages}")
    
    if messages:
        message = messages[0]
        subject = message.subject
        sender = message.sender.address
        html_content = f'<h1>First Email</h1><p>Subject: {subject}</p><p>Sender: {sender}</p>'
    else:
        html_content = '<h1>No emails found</h1>'
    
    return func.HttpResponse(html_content, mimetype="text/html")

