from google import genai
from dotenv import load_dotenv
import os
from typing import List


load_dotenv(override=True)

LABELS = ["Urgent", "Meeting", "General", "Fun"]
client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))

def label_email(email_body: str) -> List[str]:
    """
    Labels the email based on its content.
    """
    
    response = client.models.generate_content(
        model="gemma-3-12b-it",
        contents=[f"Label the following email: {email_body} using the labels {LABELS}. Your output must strictly use the labels {LABELS} and nothing else."],
    )

    return response
