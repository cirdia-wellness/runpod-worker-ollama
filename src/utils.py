import os

class JobInput:
    def __init__(self, job):
        self.llm_input = job.get("messages", job.get("prompt"))
        self.stream = job.get("stream", False)
        self.openai_route = job.get("openai_route")
        self.openai_input = job.get("openai_input")
        self.model = job.get("model", os.getenv("OLLAMA_MODEL_NAME", "llama3.2:1b"))
        self.format = job.get("format") or job.get("response_format")
        self.pull_if_missing = job.get("pull_if_missing", False)
        self.system = job.get("system", None)
        self.options = job.get("options", None)