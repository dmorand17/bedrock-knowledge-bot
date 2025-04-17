import datetime

from aws_cdk import Duration, Stack
from aws_cdk import aws_ec2 as ec2
from aws_cdk import aws_ecr as ecr
from aws_cdk import aws_ecs as ecs
from aws_cdk import aws_ecs_patterns as ecs_patterns
from aws_cdk import aws_events as events
from aws_cdk import aws_events_targets as targets
from aws_cdk import aws_iam as iam
from aws_cdk import aws_lambda as _lambda
from constructs import Construct


class BedrockKnowledgeBotStack(Stack):
    """Creates the stack for deploying the Streamlit app on ECS Fargate."""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Read VPC ID from context
        vpc_id = self.node.try_get_context("vpc_id")
        if vpc_id:
            vpc = ec2.Vpc.from_lookup(self, "ImportedVPC", vpc_id=vpc_id)
        else:
            # Create a new VPC if no VPC ID is provided
            vpc = ec2.Vpc(self, "BedrockKnowledgeBotVPC", max_azs=2)

        # Create an ECS cluster
        cluster = ecs.Cluster(self, "BedrockKnowledgeBotCluster", vpc=vpc)

        # Get the ECR repository name from context
        ecr_repository_name = self.node.try_get_context("ecr_repository_name")

        # Get the container port from context, defaulting to 8501
        container_port = self.node.try_get_context("container_port") or 8501

        # Create an ECS task role with permissions to pull from ECR
        task_role = iam.Role(
            self,
            "BedrockKnowledgeBotTaskRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
        )
        # Add Bedrock and Nova permissions to the task role
        task_role.add_to_policy(
            iam.PolicyStatement(
                actions=[
                    "bedrock:InvokeModel",
                    "bedrock:RetrieveAndGenerate",
                    "bedrock:Retrieve",
                    "bedrock:ListFoundationModels",
                    "bedrock:GetFoundationModel",
                ],
                resources=["*"],
            )
        )

        # Determine the model type from context, defaulting to Nova Lite
        model_type = self.node.try_get_context("model_type") or "Nova Lite"
        if model_type not in ["Nova Lite", "Nova Pro"]:
            raise ValueError("Invalid model_type. Must be 'Nova Lite' or 'Nova Pro'.")

        # Create an ECS execution role with the required policy
        execution_role = iam.Role(
            self,
            "BedrockKnowledgeBotExecutionRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
        )
        execution_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "service-role/AmazonECSTaskExecutionRolePolicy"
            )
        )

        # Create Lambda function for knowledge base sync
        sync_lambda = _lambda.Function(
            self,
            "KnowledgeBaseSyncFunction",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="index.handler",
            code=_lambda.Code.from_asset("lambda/knowledge_base_sync"),
            environment={
                "DATA_SOURCE_ID": self.node.try_get_context("data_source_id"),
                "KNOWLEDGE_BASE_ID": self.node.try_get_context("knowledge_base_id"),
            },
            timeout=Duration.minutes(15),
        )

        # Add Bedrock permissions to the Lambda function
        sync_lambda.add_to_role_policy(
            iam.PolicyStatement(
                actions=["bedrock:StartIngestionJob", "bedrock:GetIngestionJob"],
                resources=["*"],
            )
        )

        # Create EventBridge rule for weekly sync
        weekly_sync_rule = events.Rule(
            self,
            "WeeklyKnowledgeBaseSyncRule",
            schedule=events.Schedule.cron(
                minute="0",
                hour="0",
                day="7",  # First day of the week
                month="*",
                year="*",
            ),
        )

        # Add Lambda as target for the EventBridge rule
        weekly_sync_rule.add_target(targets.LambdaFunction(sync_lambda))

        load_balanced_fargate_service = (
            ecs_patterns.ApplicationLoadBalancedFargateService(
                self,
                "BedrockKnowledgeBotService",
                cluster=cluster,
                task_image_options={
                    "image": ecs.ContainerImage.from_ecr_repository(
                        ecr.Repository.from_repository_name(
                            self, "BedrockKnowledgeBotRepo", ecr_repository_name
                        )
                    ),
                    "container_port": container_port,
                    "execution_role": execution_role,
                    "task_role": task_role,
                    "environment": {
                        "KNOWLEDGE_BASE_ID": self.node.try_get_context(
                            "knowledge_base_id"
                        ),
                        "DEPLOY_TIME": datetime.datetime.now().strftime(
                            "%Y-%m-%d %H:%M:%S"
                        ),
                    },
                },
                public_load_balancer=True,
                runtime_platform=ecs.RuntimePlatform(
                    cpu_architecture=ecs.CpuArchitecture.ARM64,
                    operating_system_family=ecs.OperatingSystemFamily.LINUX,
                ),
            )
        )
