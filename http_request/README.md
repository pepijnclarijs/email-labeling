# How does this directory work?
Azure Functions looks inside each directory to identify if it's an Azure Function. This is 
recognized when function.json is defined with the right trigger configuration. Based on the trigger,
the Azure Function App will run the code that is located inside __init__.py. 