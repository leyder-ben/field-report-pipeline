import base64
import json
import os
import uuid

import boto3

s3 = boto3.client('s3')
bedrock = boto3.client('bedrock-runtime')
lambda_client = boto3.client('lambda')

INTAKE_BUCKET = os.environ['INTAKE_BUCKET']
MERGE_SUMMARIZE_FUNCTION = os.environ['MERGE_SUMMARIZE_FUNCTION']
BEDROCK_MODEL_ID = os.environ['BEDROCK_MODEL_ID']

DOCUMENT_TYPES = (
    'sales_order', 'invoice', 't_and_m',
    'pump_install_vt', 'pump_install_sc', 'pump_install_horizontal', 'pump_install_submersible',
    'fire_pump_test', 'well_cleaning', 'pumping_test', 'observation_well',
    'correspondence_letter', 'hydrology_report', 'service_contract', 'credit_memo', 'other',
)

CLASSIFICATION_PROMPT = """You are reviewing a scanned archive file from a water well contractor. The file may contain multiple distinct documents — forms, reports, invoices, and letters — all scanned into one PDF or photographed individually.

Your job:
1. Identify each distinct logical document in the file
2. Determine which pages belong together as one complete record
3. Classify each document by type

Valid document types:
- sales_order       Sales order or work order
- invoice           Invoice or billing statement
- credit_memo       Credit memorandum
- t_and_m           Time and material report (labor, materials, equipment log)
- pump_install_vt   Vertical turbine pump installation report
- pump_install_sc   Short coupled pump installation report
- pump_install_horizontal  Horizontal pump installation report
- pump_install_submersible Submersible pump installation report
- fire_pump_test    Electric motor driven fire pump test report
- well_cleaning     Well cleaning record and treatment log
- pumping_test      Pumping test data report (time-series table)
- observation_well  Observation well report (time-series table)
- correspondence_letter  Letter or written correspondence
- hydrology_report  Hydrology or technical report
- service_contract  Service contract or maintenance agreement
- other             Does not fit any category above

Boundary detection rules — read carefully:
- A page that immediately follows a multi-page document type and has no form header, no letterhead, and no identifying information at the top is almost certainly a continuation of the previous document. Do NOT classify it as a new document.
- pumping_test and observation_well reports commonly run 2-4 pages when the test is long. Continuation pages contain only the data table, no header.
- correspondence_letter pages 2+ have body text only — no letterhead, no salutation line.
- hydrology_report and service_contract pages 2+ may be plain typed text or legal boilerplate.
- A genuinely new document will have a visible form header, a company letterhead, or a clear title at the top of the page.

For a single-page image (one photo of one form): return exactly one document entry covering page 1.

Return ONLY valid JSON — no explanation, no markdown, no code fences. Use this exact structure:
{
  "documents": [
    {
      "document_id": "doc-001",
      "document_type": "<type from list above>",
      "pages": [1, 2],
      "page_range": "1-2",
      "confidence": 0.95,
      "classification_notes": "<one sentence describing what you saw>"
    }
  ]
}

Pages are 1-indexed. Every page must appear in exactly one document."""


def lambda_handler(event, context):
    record = event['Records'][0]
    bucket = record['s3']['bucket']['name']
    key = record['s3']['object']['key']

    print(f"Pass 1 starting: s3://{bucket}/{key}")

    obj = s3.get_object(Bucket=bucket, Key=key)
    file_bytes = obj['Body'].read()
    content_type = obj.get('ContentType', '')

    if _is_pdf(key, content_type):
        content = _pdf_content(file_bytes)
    else:
        content = _image_content(file_bytes, content_type)

    bedrock_response = bedrock.invoke_model(
        modelId=BEDROCK_MODEL_ID,
        body=json.dumps({
            'anthropic_version': 'bedrock-2023-05-31',
            'max_tokens': 2048,
            'messages': [{'role': 'user', 'content': content}],
        }),
    )

    raw = json.loads(bedrock_response['body'].read())
    manifest_text = raw['content'][0]['text'].strip()

    # Strip accidental markdown fences if the model adds them despite instructions
    if manifest_text.startswith('```'):
        manifest_text = manifest_text.split('```')[1]
        if manifest_text.startswith('json'):
            manifest_text = manifest_text[4:]

    manifest = json.loads(manifest_text)
    manifest['source_key'] = key
    manifest['source_bucket'] = bucket
    manifest['pipeline_id'] = str(uuid.uuid4())

    doc_count = len(manifest.get('documents', []))
    print(f"Pass 1 complete: {doc_count} document(s) identified — invoking Pass 2")

    lambda_client.invoke(
        FunctionName=MERGE_SUMMARIZE_FUNCTION,
        InvocationType='Event',
        Payload=json.dumps(manifest).encode(),
    )

    return {'statusCode': 200, 'documents_found': doc_count}


def _is_pdf(key, content_type):
    return 'pdf' in content_type.lower() or key.lower().endswith('.pdf')


def _pdf_content(pdf_bytes):
    return [
        {
            'type': 'document',
            'source': {
                'type': 'base64',
                'media_type': 'application/pdf',
                'data': base64.standard_b64encode(pdf_bytes).decode(),
            },
        },
        {'type': 'text', 'text': CLASSIFICATION_PROMPT},
    ]


def _image_content(image_bytes, content_type):
    media_type = content_type if content_type in (
        'image/jpeg', 'image/png', 'image/gif', 'image/webp'
    ) else 'image/jpeg'
    return [
        {
            'type': 'image',
            'source': {
                'type': 'base64',
                'media_type': media_type,
                'data': base64.standard_b64encode(image_bytes).decode(),
            },
        },
        {'type': 'text', 'text': CLASSIFICATION_PROMPT},
    ]
