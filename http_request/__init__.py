import logging
import azure.functions as func

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Python HTTP trigger function processed a request.")
    return func.HttpResponse("Hello from Azure Function!", status_code=200)
