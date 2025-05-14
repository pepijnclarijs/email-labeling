import logging
import azure.functions as func
import os

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Function triggered")
    
    try:
        client_id = os.getenv("CLIENT_ID")
        tenant_id = os.getenv("TENANT_ID")
        logging.info(f"CLIENT_ID: {client_id}, TENANT_ID: {tenant_id}")
        
        if not client_id or not tenant_id:
            return func.HttpResponse("Missing env vars", status_code=500)

        return func.HttpResponse("Function is alive", status_code=200)

    except Exception as e:
        logging.exception("Something went wrong")
        return func.HttpResponse(str(e), status_code=500)
