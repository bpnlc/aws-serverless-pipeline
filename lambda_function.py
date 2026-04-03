import json
import boto3
import os
import urllib.parse
from datetime import datetime

# Initialize AWS clients
dynamodb = boto3.client('dynamodb')
sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        # Get infrastructure details from Terraform
        table_name = os.environ['DYNAMODB_TABLE']
        topic_arn = os.environ['SNS_TOPIC_ARN']

        # Extract the bucket name and the uploaded file name from the S3 event
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'], encoding='utf-8')
        
        timestamp = datetime.now().isoformat()

        # Write a record of the upload to DynamoDB
        dynamodb.put_item(
            TableName=table_name,
            Item={
                'file_id': {'S': key},
                'bucket_name': {'S': bucket},
                'processed_at': {'S': timestamp}
            }
        )

        # Send an email alert via SNS
        message = f"Success! The file '{key}' was uploaded to '{bucket}' at {timestamp}."
        sns.publish(
            TopicArn=topic_arn,
            Subject="Serverless Pipeline Alert: New File Processed",
            Message=message
        )

        return {
            'statusCode': 200,
            'body': json.dumps(f"Successfully processed {key}")
        }
    except Exception as e:
        print(f"Error processing object {key} from bucket {bucket}: {e}")
        raise e