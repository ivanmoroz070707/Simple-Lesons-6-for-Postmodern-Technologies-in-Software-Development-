import json
import boto3
import os
import urllib.parse
import datetime

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    dest_bucket = os.environ['DEST_BUCKET']
    table_name = os.environ['DYNAMODB_TABLE']
    table = dynamodb.Table(table_name)
    
    for record in event['Records']:
        source_bucket = record['s3']['bucket']['name']
        object_key = urllib.parse.unquote_plus(record['s3']['object']['key'], encoding='utf-8')
        
        
        copy_source = {
            'Bucket': source_bucket,
            'Key': object_key
        }
        s3.copy_object(CopySource=copy_source, Bucket=dest_bucket, Key=object_key)
        print(f"Copied {object_key} from {source_bucket} to {dest_bucket}")
        
        
        timestamp = datetime.datetime.now().isoformat()
        table.put_item(
            Item={
                'FileName': object_key,
                'Timestamp': timestamp,
                'Action': 'Copy',
                'Status': 'Success',
                'SourceBucket': source_bucket
            }
        )
        print(f"Audit log written to DynamoDB for {object_key}")
        
    return {
        'statusCode': 200,
        'body': json.dumps('File copied and logged successfully!')
    }