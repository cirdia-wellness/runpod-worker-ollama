import json

from dotenv import load_dotenv
import ollama

class OllamaEngine:
    def __init__(self):
        load_dotenv()
        print("OllamaEngine initialized")

    async def generate(self, job_input):
        try:
            # Check if requested model is available
            available_models = ollama.list().models
            if job_input.model not in available_models:
                if job_input.pull_if_missing:
                    try:
                        print(f"Pulling model {job_input.model}...")
                        ollama.pull(job_input.model)
                    except Exception as pull_error:
                        print(f"Failed to pull model: {pull_error}")
                        yield {"error": f"Model {job_input.model} not found and pull failed: {str(pull_error)}"}
                        return
            
            if job_input.openai_route == "/v1/models":
                model_list = ollama.list().models
                yield {"object": "list", "data": [model_list.to_dict() for model_list in response.data]}
                return

            is_chat = job_input.openai_route == "/v1/chat/completions" or isinstance(job_input.llm_input, list)

            options = {
                'model': job_input.model,
                'stream': job_input.stream,
            }

            if job_input.format:
                options['format'] = job_input.format

            if is_chat:
                options['messages'] = job_input.llm_input
                response = ollama.chat(**options).message.model_dump()
            else:
                options['prompt'] = job_input.llm_input
                response = ollama.generate(**options).model_dump()

            if not job_input.stream:
                yield response
            else:
                async for chunk in response:
                    yield "data: " + json.dumps(chunk, separators=(',', ':')) + "\n\n"
                yield "data: [DONE]"

        except Exception as e:
            yield {"error": str(e)}