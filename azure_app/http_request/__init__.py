import logging
import azure.functions as af

# test
def main(req: af.HttpRequest) -> af.HttpResponse:
    logging.info("Python HTTP trigger function processed a request.")
    return af.HttpResponse("Hello from Azure Function!", status_code=200)
