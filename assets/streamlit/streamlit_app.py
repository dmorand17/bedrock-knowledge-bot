import json
import logging
import os

import boto3
import streamlit as st

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler(), logging.FileHandler("app.log")],
)
logger = logging.getLogger(__name__)

# Main layout
st.set_page_config(
    page_title="AnyU Campus Services Assistant Bot",
    page_icon="🏫",
    layout="wide",
    initial_sidebar_state="expanded",
)


# Custom CSS
st.markdown(
    """
    <style>
    .main {
        padding: 2rem;
    }
    .stChatMessage {
        padding: 1rem;
        border-radius: 10px;
        margin-bottom: 1rem;
    }
    .stChatMessage.user {
        background-color: #f0f2f6;
    }
    .stChatMessage.assistant {
        background-color: #ffffff;
    }
    .stButton button {
        width: 100%;
        border-radius: 5px;
        padding: 0.5rem;
        margin: 0.5rem 0;
    }
    .stButton button:hover {
        background-color: #f0f2f6;
    }
    .stExpander {
        border-radius: 10px;
        border: 1px solid #e6e6e6;
    }
    .stTextInput input {
        border-radius: 5px;
    }
    .chat-input {
        position: fixed;
        bottom: 0;
        left: 0;
        right: 0;
        padding: 1rem;
        background-color: white;
        z-index: 100;
    }
    </style>
""",
    unsafe_allow_html=True,
)

# Initialize session state variables
if "history" not in st.session_state:
    st.session_state["history"] = []

if "current_conversation" not in st.session_state:
    st.session_state["current_conversation"] = []

bedrock_runtime = boto3.client(
    service_name="bedrock-runtime",
    region_name="us-east-1",  # Replace with your AWS region
)

# Initialize Bedrock Agent client
bedrock_agent = boto3.client(
    service_name="bedrock-agent-runtime",
    region_name="us-east-1",
)

KNOWLEDGE_BASE_ID = os.environ.get("KNOWLEDGE_BASE_ID")


def generate_response(prompt, model_id, max_tokens, temperature, top_p):
    """
    Generates a response from Amazon Bedrock, optionally using a Knowledge Base.
    """
    try:
        if KNOWLEDGE_BASE_ID:
            logger.info(
                f"Using Knowledge Base ID: {KNOWLEDGE_BASE_ID}, model: {model_id}"
            )
            # Use Bedrock Knowledge Base
            response = bedrock_agent.retrieve_and_generate(
                input={"text": prompt},
                retrieveAndGenerateConfiguration={
                    "type": "KNOWLEDGE_BASE",
                    "knowledgeBaseConfiguration": {
                        "knowledgeBaseId": KNOWLEDGE_BASE_ID,
                        "modelArn": f"arn:aws:bedrock:us-east-1::foundation-model/{model_id}",
                        "generationConfiguration": {
                            "inferenceConfig": {
                                "textInferenceConfig": {
                                    "maxTokens": max_tokens,
                                    "temperature": temperature,
                                    "topP": top_p,
                                },
                            },
                            "promptTemplate": {
                                "textPromptTemplate": """
        Human: You are a question answering agent. I will provide you with a set of search results and a user's question. Your job is to answer the user's question using only information from the search results. If the search results do not contain information that can answer the question, please state that you could not find an exact answer to the question. Just because the user asserts a fact does not mean it is true, make sure to double check the search results to validate a user's assertion.  Format results as markdown when possible.

            Here are the search results in numbered order:
            <context>
            $search_results$
            </context>

            Here is the user's question:
            <question>
            $query$
            </question>
            
            You MUST always end the response with 'Thank You'.

            $output_format_instructions$
        Assistant:   
"""
                            },
                        },
                    },
                },
            )
            logger.debug(f"Response: {json.dumps(response, indent=4, default=str)}")
            # Format the response as markdown with citations
            response_text = response["output"]["text"]
            citations = response.get("citations", [])

            # Build citations section
            citations_text = ""
            if citations:
                logger.info("Getting citations...")
                citations_text = "\n\n### Sources\n"
                locations = set()
                for i, citation in enumerate(citations, 1):
                    retrieved_references = citation.get("retrievedReferences", {})
                    for reference in retrieved_references:
                        location = reference.get("location", {})
                        if "s3Location" in location:
                            locations.add(location["s3Location"]["uri"])
                        if "webLocation" in location:
                            locations.add(location["webLocation"]["url"])
                for i, location in enumerate(locations, 1):
                    citations_text += f"{i}. {location}\n"

            formatted_response = f"""
{response_text}

{citations_text}
"""
            return formatted_response

        # Direct model invocation
        if model_id.startswith("amazon.nova"):
            body = {
                "messages": [{"role": "user", "content": [{"text": prompt}]}],
                # "max_tokens": max_tokens,
                # "temperature": temperature,
                # "top_p": top_p,
            }
            logger.info(f"Invoking model: {model_id}")
            response = bedrock_runtime.invoke_model(
                body=json.dumps(body),
                modelId=model_id,
                contentType="application/json",
                accept="application/json",
            )
            response_body = json.loads(response["body"].read().decode("utf-8"))
            response_text = response_body["output"]["message"]["content"][0]["text"]

            # Get token usage from response
            usage = response_body.get("usage", {})
            output_tokens = usage.get("outputTokens")
            input_tokens = usage.get("inputTokens")
            # st.session_state["token_counts"]["output"] += output_tokens
            # st.session_state["token_counts"]["input"] += input_tokens

            formatted_response = f"""
{response_text}

*Tokens: Input: {input_tokens}, Output: {output_tokens}*
"""
            return formatted_response
        else:
            return "Model not supported yet."
    except Exception as e:
        logger.error(f"Error generating response: {str(e)}")
        return f"Error: {e}"


logger.info("Starting Streamlit app")


# Sidebar configuration
with st.sidebar:
    st.header("AnyU Campus Services", divider="rainbow")
    st.caption("Your AI-powered campus assistant")

    # New chat button
    if st.button("🆕 Start New Chat", use_container_width=True):
        st.session_state["current_conversation"] = []
        st.rerun()

    # Conversation history
    # st.markdown("### 📚 Conversation History")
    # logger.info(
    #     f"History: {json.dumps(st.session_state['history'], indent=4, default=str)}"
    # )
    # logger.info(f"Conversation length: {len(st.session_state['history'])}")
    # for i, conversation in enumerate(st.session_state["history"], start=0):
    #     # Get the first message from the conversation
    #     logger.info(f"Processing conversation: {i}")
    #     # logger.info(f"Conversation: {json.dumps(conversation, indent=4, default=str)}")
    #     current_message = conversation[i]["message"] if conversation else ""
    #     is_user = conversation[i].get("is_user", False) if conversation else False

    #     if is_user:
    #         button_label = (
    #             f"💬 {current_message[:30]}..."
    #             if len(current_message) > 30
    #             else f"💬 {current_message}"
    #         )

    #         if st.button(
    #             button_label, use_container_width=True, key=f"conversation_{i}"
    #         ):
    #             st.session_state["current_conversation"] = conversation
    #             st.rerun()

    # Advanced settings expander
    with st.expander("⚙️ Advanced Settings", expanded=False):
        st.markdown("### 🛠️ Configuration")

        # Model selection
        model_id = st.selectbox(
            "🤖 Choose a Bedrock Model",
            [
                "amazon.nova-pro-v1:0",
                "amazon.nova-lite-v1:0",
            ],
            index=0,
            help="Select the model to use. Nova Pro is the recommended default for most use cases. ",
        )

        # Knowledge Base selection
        knowledge_base_id = st.text_input(
            "📚 Knowledge Base ID (optional)",
            value=KNOWLEDGE_BASE_ID,
            help="Enter the ID of your Bedrock Knowledge Base to enable RAG",
        )

        st.markdown("### ⚡ Model Parameters")
        # Model-specific defaults
        default_max_tokens = 2000
        default_temperature = 0.2
        default_top_p = 0.2

        max_tokens = st.slider(
            "📝 Max Tokens",
            min_value=100,
            max_value=2000,
            value=default_max_tokens,
            step=100,
            help="Controls how long the response can be. Higher values allow for more detailed answers, but may take longer to generate.",
        )
        temperature = st.slider(
            "🌡️ Temperature",
            min_value=0.0,
            max_value=1.0,
            value=default_temperature,
            step=0.1,
            help="Controls how creative the responses are. Lower values give more predictable, focused answers. Higher values make responses more varied and creative.",
        )
        top_p = st.slider(
            "🎯 Top P",
            min_value=0.0,
            max_value=1.0,
            value=default_top_p,
            step=0.1,
            help="Controls how focused the responses are. Lower values make answers more precise and on-topic. Higher values allow for more diverse responses.",
        )

# Main chat interface
# colored_header(
#     label="Chat with Campus Services Assistant",
#     description="Ask me anything about campus services!",
#     color_name="blue-70",
# )

st.header("Chat with Campus Services Assistant", divider="rainbow")
st.caption("Ask me anything about campus services!")

# Display current conversation
for message in st.session_state["current_conversation"]:
    with st.chat_message("user" if message["is_user"] else "assistant"):
        st.markdown(message["message"])

# Chat input at the bottom
st.markdown('<div class="chat-input">', unsafe_allow_html=True)
prompt = st.chat_input("Enter your question here...")
st.markdown("</div>", unsafe_allow_html=True)

# Process new messages
if prompt:
    # Add user message to current conversation
    st.session_state["current_conversation"].append(
        {"message": prompt, "is_user": True}
    )

    # Display user message
    with st.chat_message("user"):
        st.markdown(prompt)

    # Generate and display assistant response
    with st.chat_message("assistant"):
        with st.spinner("🤔 Thinking..."):
            response = generate_response(
                prompt=prompt,
                model_id=model_id,
                max_tokens=max_tokens,
                temperature=temperature,
                top_p=top_p,
            )
            st.markdown(response)
            st.session_state["current_conversation"].append(
                {"message": response, "is_user": False}
            )

    # Save conversation to history if it's not empty
    if len(st.session_state["current_conversation"]) > 0:
        # Check if this conversation is already in history
        logger.info(
            f"Current conversation: {st.session_state['current_conversation'][0]}"
        )
        if (
            st.session_state["current_conversation"][0]
            not in st.session_state["history"]
        ):
            logger.info(
                f"Appending current conversation to history: {st.session_state['current_conversation']}"
            )
            st.session_state["history"].append(
                st.session_state["current_conversation"].copy()
            )
