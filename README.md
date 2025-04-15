# Bedrock Knowledge Bot

The Bedrock Knowledge Bot is a Streamlit-based application that interacts with Amazon Bedrock models to provide intelligent responses to user queries. It is designed to be easily deployable and extensible for various use cases.

## Features

- Query multiple Amazon Bedrock models.
- Interactive Streamlit interface with a two-column layout.
- Configurable model list via a YAML file.
- Modular design with a knowledge base and Bedrock client.

## Prerequisites

### Build Requirements

- Python 3.8 or higher
- AWS CLI with proper credentials
- Docker (optional for containerized deployment)

### Amazon Bedrock Requirements

- Access to Amazon Bedrock in your AWS account
- Proper IAM permissions to invoke Bedrock models

## 🏁 Getting Started

1. Clone the repository:

   ```bash
   git clone https://github.com/your-repo/bedrock-knowledge-bot.git
   cd bedrock-knowledge-bot
   ```

2. Install dependencies:

   ```bash
   pip install -r requirements.txt
   ```

3. Configure the available models in `config/bedrock_models.yaml`.

4. Run the Streamlit application:

   ```bash
   streamlit run streamlit_app.py
   ```

5. Open the application in your browser at `http://localhost:8501`.

## 🛠️ Development

This project uses [`uv`](https://github.com/victorgarric/uv) for managing the development environment. To set up:

1. Install `uv`:

   ```bash
   pip install uv
   ```

2. Sync the environment:

   ```bash
   uv sync
   ```

3. Create requirements.txt file for deployment

   ```bash
   uv pip compile pyproject.toml -o requirements.txt
   ```

4. Create tar.gz file for deployment

   ```bash
   git ls-files -z | tar -czvf sagemaker-presign-poc.tar.gz --null -T -
   ```

5. Use `uv` commands to manage dependencies, run tests, and more.

Refer to the `uv` documentation for additional details.

## 🧪 Testing

### Unit Tests

Run unit tests using:

```bash
pytest
```

### Local Testing

To test the application locally with Docker:

```bash
docker build -t bedrock-knowledge-bot:latest .
docker run -p 8501:8501 bedrock-knowledge-bot:latest
```

## License

This project is licensed under the MIT-0 License. See the LICENSE file for details.
