import os
import boto3
import json
import uuid
import datetime

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")

# Lấy biến môi trường chỉ một lần
S3_BUCKET = os.environ["S3_BUCKET"]
DYNAMO_TABLE = os.environ["DYNAMO_TABLE"]
table = dynamodb.Table(DYNAMO_TABLE)

# --- Hàm trả về Response CORS chuẩn ---
def build_cors_response(status_code, body=None):
    # ⭐ Các headers này bắt buộc phải có cho cả OPTIONS và POST thành công ⭐
    headers = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, X-Amz-Date, Authorization, X-Api-Key, X-Amz-Security-Token"
    }
    
    return {
        "statusCode": status_code,
        "headers": headers,
        "body": json.dumps(body) if body else ""
    }

# --- Cập nhật hàm chính ---
def lambda_handler(event, context):
    
    http_method = event.get("requestContext", {}).get("http", {}).get("method")
    
    # ⭐ 1. Xử lý yêu cầu OPTIONS (Preflight) ⭐
    if http_method == "OPTIONS":
        print("Handling OPTIONS request for CORS.")
        # Trả về 200 OK ngay lập tức với CORS headers
        return build_cors_response(200)

    # 2. Xử lý yêu cầu POST
    try:
        body = json.loads(event.get("body", "{}"))
        file_content = body.get("data", "Demo content")
        
        if not file_content:
            return build_cors_response(400, {"error": "No file content provided"})
            
        # Lưu file lên S3
        file_id = str(uuid.uuid4())
        s3.put_object(
            Bucket=S3_BUCKET,
            Key=f"{file_id}.txt",
            Body=file_content
        )
        
        # Lưu metadata vào DynamoDB
        table.put_item(Item={
            "file_id": file_id,
            "status": "processed",
            "summary": "This is a demo summary",
            "timestamp": datetime.datetime.now().isoformat()
        })
        print(f"File {file_id} processed and stored.")
        
        # Trả về phản hồi thành công (Sử dụng hàm CORS)
        return build_cors_response(200, {
            "file_id": file_id,
            "summary": "This is a demo summary"
        })
        
    except Exception as e:
        print(f"Error processing POST request: {e}")
        return build_cors_response(500, {"error": f"Internal Server Error: {str(e)}"})