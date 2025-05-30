import azure.functions as func
import os
import logging
from dotenv import load_dotenv
from O365 import Account, FileSystemTokenBackend
from google import genai
from typing import List

# --- Handle Emails --- #
logging.info("executing load_dotenv")
load_dotenv(override=True)
LABELS = ["Urgent", "Meeting", "General", "Fun"]


def label_email(email_body: str) -> List[str]:
    """
    Labels the email based on its content.
    """
    client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))
    response = client.models.generate_content(
        model="gemini-1.5-flash",
        contents=[f"Label the following email: {email_body} using the labels {LABELS}. Your output must strictly use the labels {LABELS} and nothing else."],
    )
    return response.text


app = func.FunctionApp()
logging.info("loading environment variable CLIENT_ID")
CLIENT_ID = os.getenv("CLIENT_ID")
CLIENT_SECRET = os.getenv("CLIENT_SECRET")
REDIRECT_URI = os.getenv("REDIRECT_URI")
TENNANT_ID = os.getenv("TENANT_ID")
state_map = {}
CREDENTIALS = (CLIENT_ID, CLIENT_SECRET)
SCOPES = [
    'https://graph.microsoft.com/Mail.ReadWrite',
    'https://graph.microsoft.com/Mail.Send'
]
# Initialize the token backend
if not os.path.exists('./o365_token_data'):
    os.makedirs('./o365_token_data')
token_backend = FileSystemTokenBackend(token_path='./o365_token_data', token_filename='token.txt')


def _get_account(): 
    """
    Get the account object from the state map.
    If it doesn't exist, create a new one.
    """
    account = state_map.get("account")
    if not account:
        account = Account(CREDENTIALS, token_backend=token_backend)
        state_map["account"] = account
    return account


def handle_is_authenticated():
    """
    Check if the user is authenticated.
    If not, redirect to the login page.
    """
    html_content = """
    <h1>Already logged in!</h1><a href="/api/get-first-email">Get First Email</a>
    <h2>If you want to log out, please click the link below:</h2>
    <a href="/api/logout">Logout</a>
    """
    
    return func.HttpResponse(html_content, mimetype="text/html")

@app.function_name(name="go-to-login")
@app.route(route="go-to-login", auth_level=func.AuthLevel.ANONYMOUS)
def go_to_login(req: func.HttpRequest) -> func.HttpResponse:
    account = _get_account()
    if account.is_authenticated:
        return handle_is_authenticated()
    
    auth_url, auth_flow = account.connection.get_authorization_url(
        requested_scopes=SCOPES,
        redirect_uri=REDIRECT_URI
    )
    html_content = f'<a href="{auth_url}">Click here to login</a>'
    
    # Save mapping so we can retrieve the authorization_url later using the state
    state_map["auth_flow"] = auth_flow
    state_map["auth_url"] = auth_url

    return func.HttpResponse(html_content, mimetype="text/html")

@app.function_name(name="auth-callback")
@app.route(route="auth-callback", auth_level=func.AuthLevel.ANONYMOUS)
def login(req: func.HttpRequest) -> func.HttpResponse:
    account = _get_account()
    if token_backend.load_token():
        # If the token is already loaded, we can skip the login process
        html_content = '<h1>Already logged in!</h1><a href="/api/get-first-email">Get First Email</a>'
        return func.HttpResponse(html_content, mimetype="text/html")

    auth_flow = state_map.get("auth_flow")

    if not auth_flow:
        return func.HttpResponse("Missing auth flow state", status_code=400)

    authorization_response_url = req.url

    result = account.connection.request_token(
        authorization_response_url,
        flow=auth_flow
    )
    if result:
        html_content = """<h1>Authentication successful!</h1><a href="/api/get-first-email">Get First Email</a>
        <h2>Or</h2>
        <a href="/api/logout">Logout</a>
        """
    else:
        html_content = '<h1>Authentication failed</h1>'

    return func.HttpResponse(html_content, mimetype="text/html")

@app.function_name(name="logout")
@app.route(route="logout", auth_level=func.AuthLevel.ANONYMOUS)
def logout(req: func.HttpRequest) -> func.HttpResponse:
    # remove the token.txt from token backend
    if token_backend.delete_token():
        username = state_map["account"].username
        token_backend.remove_data(username=username)
        new_account = Account(CREDENTIALS, token_backend=token_backend)
        state_map["account"] = new_account
        html_content = '<h1>Logged out successfully!</h1><a href="/api/go-to-login">Login again</a>'
    else:
        html_content = f'<h1>Logout failed</h1> {token_backend.delete_token()}'
    return func.HttpResponse(html_content, mimetype="text/html")

@app.function_name(name="get-first-email")
@app.route(route="get-first-email", auth_level=func.AuthLevel.ANONYMOUS)
def get_first_email(req: func.HttpRequest) -> func.HttpResponse:
    account = _get_account()
    if not account.is_authenticated:
        html_content = '<h1>You are not authenticated.</h1><a href="/api/go-to-login">Login</a>'
        return func.HttpResponse(html_content, mimetype="text/html")
    mailbox = account.mailbox()
    inbox = mailbox.inbox_folder()
    messages = list(inbox.get_messages(limit=1))
    logging.info(f"type(messages): {type(messages)}, messages: {messages}")
    
    if messages:
        message = messages[0]
        subject = message.subject
        sender = message.sender.address
        body = message.body
        label = label_email(body)
        html_content = f'<h1>First Email</h1><p>Subject: {subject}</p><p>Sender: {sender}</p></br>The label is: {label} <br><br><a href="/api/logout">Go-to-logout</a>'
    else:
        html_content = '<h1>No emails found</h1>'
    
    return func.HttpResponse(html_content, mimetype="text/html")


