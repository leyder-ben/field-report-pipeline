import json
import os
import uuid

import boto3
from botocore.exceptions import ClientError

s3 = boto3.client('s3')

INTAKE_BUCKET = os.environ['INTAKE_BUCKET']
URL_EXPIRY_SECONDS = 300

CONTENT_TYPE_EXT = {
    'application/pdf': 'pdf',
    'image/jpeg':      'jpg',
    'image/png':       'png',
}


def lambda_handler(event, context):
    path = event.get('path', '')

    if path == '/upload-url':
        return _presigned_url(event)

    return _not_found()


def _presigned_url(event):
    params = event.get('queryStringParameters') or {}
    content_type = params.get('content_type', 'application/pdf')
    ext = CONTENT_TYPE_EXT.get(content_type, 'pdf')
    key = f"uploads/{uuid.uuid4()}.{ext}"

    try:
        url = s3.generate_presigned_url(
            'put_object',
            Params={'Bucket': INTAKE_BUCKET, 'Key': key, 'ContentType': content_type},
            ExpiresIn=URL_EXPIRY_SECONDS,
        )
        return _ok({'upload_url': url, 'key': key})
    except ClientError as e:
        return _error(str(e))


def _ok(body):
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
        'body': json.dumps(body),
    }


def _error(message):
    return {
        'statusCode': 500,
        'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
        'body': json.dumps({'error': message}),
    }


def _not_found():
    return {
        'statusCode': 404,
        'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
        'body': json.dumps({'error': 'not found'}),
    }
