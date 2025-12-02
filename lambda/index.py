import os
import boto3
import json
import uuid

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["DYNAMO_TABLE"])

def lambda_handler(event, context):
    # Giả lập nhận file JSON trong body
    body = json.loads(event.get("body", "{}"))
    file_content = body.get("data", "Demo content")
    
    # Lưu file lên S3
    file_id = str(uuid.uuid4())
    s3.put_object(
        Bucket=os.environ["S3_BUCKET"],
        Key=f"{file_id}.txt",
        Body=file_content
    )
    
    # Lưu metadata vào DynamoDB
    table.put_item(Item={
        "file_id": file_id,
        "status": "processed",
        "summary": "This is a demo summary"
    })
    
    return {
        "statusCode": 200,
        "body": json.dumps({"file_id": file_id, "summary": "Demo summary"})
    }
