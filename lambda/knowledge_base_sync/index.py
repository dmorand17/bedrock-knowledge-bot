import json
import logging
import os

import boto3

logger = logging.getLogger(__name__)


def handler(event, context):
    """
    Lambda function to sync a single knowledge base data source.
    Reads data source configuration from environment variable.
    """

    logging.info(f"Received event: {json.dumps(event, indent=4, default=str)}")
    # Get data source from environment variable
    data_source_id = os.environ.get("DATA_SOURCE_ID")
    knowledge_base_id = os.environ.get("KNOWLEDGE_BASE_ID")

    # Initialize Bedrock client
    client = boto3.client("bedrock-agent")

    try:
        response = client.start_ingestion_job(
            dataSourceId=data_source_id,
            knowledgeBaseId=knowledge_base_id,
        )
        logging.info(
            f"start_ingestion_job response: {json.dumps(response, indent=4, default=str)}"
        )
        result = {"status": "success", "message": "Ingestion job started"}
    except Exception as e:
        result = {"status": "error", "message": str(e)}

    return {"statusCode": 200, "body": json.dumps(result)}
