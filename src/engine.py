import json
import os

from dotenv import load_dotenv
import ollama

class OllamaEngine:
    def __init__(self):
        load_dotenv()
        print("OllamaEngine initialized")

    async def generate(self, job_input):
        # Get model from OLLAMA_MODEL_NAME defauting to llama3.2:1b
        model = os.getenv("OLLAMA_MODEL_NAME", "llama3.2:1b")

        try:
            if job_input.openai_route == "/v1/models":
                models = ollama.list()
                yield {"object": "list", "data": models['models']}
                return

            is_chat = job_input.openai_route == "/v1/chat/completions" or isinstance(job_input.llm_input, list)

            options = {
                'model': model,
                'stream': job_input.stream,
            }

            if job_input.format:
                options['format'] = job_input.format

            if is_chat:
                options['messages'] = job_input.llm_input
                response = ollama.chat(**options)
            else:
                options['prompt'] = job_input.llm_input
                response = ollama.generate(**options)

            if not job_input.stream:
                yield response
            else:
                async for chunk in response:
                    yield "data: " + json.dumps(chunk, separators=(',', ':')) + "\n\n"
                yield "data: [DONE]"

        except Exception as e:
            yield {"error": str(e)}