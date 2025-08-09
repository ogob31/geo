#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --cluster CLUSTER --service SERVICE --taskdef TASKDEF --image IMAGE --region REGION"
  exit 1
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster) CLUSTER="$2"; shift 2;;
    --service) SERVICE="$2"; shift 2;;
    --taskdef) TASKDEF="$2"; shift 2;;
    --image)   IMAGE="$2"; shift 2;;
    --region)  REGION="$2"; shift 2;;
    *) usage;;
  esac
done

[[ -z "${CLUSTER:-}" || -z "${SERVICE:-}" || -z "${TASKDEF:-}" || -z "${IMAGE:-}" || -z "${REGION:-}" ]] && usage

echo "Updating task definition ${TASKDEF} with image ${IMAGE} in ${REGION}"

# Get current task definition JSON
TD_ARN=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --query 'services[0].taskDefinition' --output text --region "$REGION")
aws ecs describe-task-definition --task-definition "$TD_ARN" --region "$REGION" --query 'taskDefinition' > /tmp/td.json

# Replace container image (assumes first container; tweak if multiple)
jq --arg IMG "$IMAGE" '.containerDefinitions[0].image=$IMG | del(.status,.taskDefinitionArn,.requiresAttributes,.compatibilities,.revision,.registeredAt,.registeredBy)' /tmp/td.json > /tmp/td-new.json

# Register new task definition revision
NEW_TD_ARN=$(aws ecs register-task-definition --cli-input-json file:///tmp/td-new.json --query 'taskDefinition.taskDefinitionArn' --output text --region "$REGION")
echo "New task definition: $NEW_TD_ARN"

# Update service to use new task def (rolling update via service scheduler)
aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --task-definition "$NEW_TD_ARN" --region "$REGION" >/dev/null
echo "Service update initiated. Waiting for stability..."

aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION"
echo "Service is stable ✅"
