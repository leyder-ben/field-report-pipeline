import base64
import json
import os
import time
import uuid
from datetime import datetime, timezone
from decimal import Decimal

import boto3

s3 = boto3.client('s3')
bedrock = boto3.client('bedrock-runtime')
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

INTAKE_BUCKET = os.environ['INTAKE_BUCKET']
PROCESSED_BUCKET = os.environ['PROCESSED_BUCKET']
DYNAMODB_TABLE = os.environ['DYNAMODB_TABLE']
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']
BEDROCK_MODEL_SONNET = os.environ['BEDROCK_MODEL_SONNET']
BEDROCK_MODEL_HAIKU = os.environ['BEDROCK_MODEL_HAIKU']

table = dynamodb.Table(DYNAMODB_TABLE)

_FIELD_HINTS = {
    'pump_install_vt': (
        "motor (make, model, HP, RPM, voltage, phase, frame), bowl assembly (make, model, no. stages), "
        "column (size, length), shaft size, discharge head, gear drive (make, ratio) if present, "
        "pumping data (GPM, TDH, discharge pressure, column pressure), well specs (casing size, "
        "static water level, pumping water level), monitor systems checked"
    ),
    'pump_install_sc': (
        "motor (make, model, HP), gear drive (make, ratio) if present, engine (make, model, HP) if engine-driven, "
        "pump head (make, model, size), column size, water supply details, "
        "pumping test data (GPM, pressure, water level, duration)"
    ),
    'pump_install_submersible': (
        "pump (make, model, HP, size), motor (make, model), cable (size, length), "
        "column pipe size, pump discharge size, pumping data (GPM, discharge pressure, "
        "static water level, pumping water level), well casing size and depth"
    ),
    'pump_install_horizontal': (
        "motor (make, model, HP) or engine (make, model, HP), pump (make, model, size), "
        "pump type (split case / end suction / sewage / other), "
        "pumping test (GPM, TDH, suction pressure, discharge pressure, RPM)"
    ),
    'fire_pump_test': (
        "motor or engine (make, model, serial), pump (make, model, size, serial), "
        "original/rated performance (GPM, PSI), test results at four points "
        "(shutoff, rated flow, 150pct flow, peak/churn), electrical data (voltage, current, phase)"
    ),
    'well_cleaning': (
        "pre-cleaning and post-cleaning performance comparison (GPM, drawdown, specific capacity), "
        "treatment method, chemicals used (name, quantity, concentration), "
        "treatment log entries (time, chemical, amount added), post-treatment pumping data"
    ),
    'pumping_test': (
        "pumping rate (GPM), pump setting depth, casing size, static water level before test, "
        "time-series readings (time elapsed, depth to water, drawdown), "
        "recovery measurements if present, aquifer type if noted"
    ),
    'observation_well': (
        "well location and distance from pumping well, casing size and depth, "
        "time-series water level readings (date, time, depth to water), "
        "any aquifer or interference data noted"
    ),
    't_and_m': (
        "labor entries (technician name, date, regular hours, overtime hours, work performed description), "
        "materials list (item description, quantity, unit, unit price), "
        "equipment used (description, hours, rate), job total"
    ),
    'sales_order': (
        "customer name, job site address, description of work ordered, equipment or materials specified, "
        "quantities, unit prices, total amount, salesman, date ordered, date required"
    ),
    'invoice': (
        "invoice number, customer name, billing address, line items (description, quantity, unit price, extended), "
        "subtotal, tax amount, total amount due, payment terms, due date"
    ),
    'credit_memo': (
        "credit memo number, original invoice number or reference, reason for credit, credit amount, customer name"
    ),
    'correspondence_letter': (
        "date of letter, recipient name and address or company, sender name and title, "
        "subject or re: line, key points of the letter body, any requests or action items, "
        "whether a response or follow-up is requested"
    ),
    'hydrology_report': (
        "report title, author name, date, study area or location, aquifer type and characteristics, "
        "test methodology, key findings, yield estimates, recommendations"
    ),
    'service_contract': (
        "contract number if present, customer name and address, equipment or systems covered, "
        "service frequency, contract start and end dates, annual or monthly cost, "
        "any notable exclusions or special terms"
    ),
    'other': (
        "describe what type of document this appears to be, then extract any visible dates, "
        "names, job or well numbers, dollar amounts, and operational data"
    ),
}

_EXTRACTION_TEMPLATE = """You are extracting structured data from a scanned water well contractor document.

Document type: {document_type}
Page range in this file: {page_range}
{page_focus}

Extract these standard fields (null if not present on the document):
- tech_name: name of the field technician or installer
- job_site: job site name or address
- owner: customer or property owner name
- well_no: well number or identifier
- job_no: job number, work order number, or sales order number
- date: date on the document in YYYY-MM-DD format
- notes: any handwritten annotations, special conditions, or observations not captured elsewhere

Also extract fields specific to {document_type}:
{field_hints}

Put equipment data (makes, models, serial numbers, sizes, specifications) in the "equipment" map.
Put measurement data (flow rates, pressures, water levels, hours, dollar amounts) in the "measurements" map.

Return ONLY valid JSON with no explanation or markdown. Use exactly this structure:
{{
  "tech_name": null,
  "job_site": null,
  "owner": null,
  "well_no": null,
  "job_no": null,
  "date": null,
  "equipment": {{}},
  "measurements": {{}},
  "notes": null
}}

Use null for any field not found. Do not invent or estimate values."""

_SUMMARY_TEMPLATE = """Write a 2-3 sentence plain-English summary of this water well contractor document for a supervisor.

Document type: {document_type}
Extracted data: {extracted_fields}

Rules:
- Start with a specific operational detail, not "This document" or "The document"
- Include the most relevant facts: who, what job site, what work, key measurements
- If the document is blank or has no data filled in, say so plainly in one sentence
- Do not repeat the document type label -- the supervisor already knows it"""


def lambda_handler(event, context):
    start_time = time.time()

    source_key = event['source_key']
    source_bucket = event['source_bucket']
    pipeline_id = event['pipeline_id']
    documents = event['documents']

    print(f"Pass 2 starting: pipeline_id={pipeline_id}, {len(documents)} document(s) from {source_key}")

    obj = s3.get_object(Bucket=source_bucket, Key=source_key)
    file_bytes = obj['Body'].read()
    content_type = obj.get('ContentType', '')
    is_pdf = 'pdf' in content_type.lower() or source_key.lower().endswith('.pdf')

    report_ids = []
    summaries = []
    processed_key = _processed_key(source_key)

    for doc in documents:
        doc_start = time.time()

        extracted = _extract_fields(file_bytes, content_type, is_pdf, doc)
        summary = _generate_summary(doc['document_type'], extracted)

        report_id = str(uuid.uuid4())
        submitted_at = datetime.now(timezone.utc).isoformat()
        processing_ms = int((time.time() - doc_start) * 1000)

        item = {
            'report_id':              report_id,
            'submitted_at':           submitted_at,
            'source':                 'upload',
            'document_type':          doc['document_type'],
            'page_range':             doc['page_range'],
            'tech_name':              extracted.get('tech_name'),
            'job_site':               extracted.get('job_site'),
            'owner':                  extracted.get('owner'),
            'well_no':                extracted.get('well_no'),
            'job_no':                 extracted.get('job_no'),
            'date':                   extracted.get('date'),
            'equipment':              extracted.get('equipment') or {},
            'measurements':           extracted.get('measurements') or {},
            'notes':                  extracted.get('notes'),
            'summary':                summary,
            'extraction_confidence':  Decimal(str(doc.get('confidence', 0))),
            'original_document_key':  processed_key,
            'processing_duration_ms': processing_ms,
            'pipeline_id':            pipeline_id,
        }

        item = {k: v for k, v in item.items() if v is not None}
        table.put_item(Item=item)

        report_ids.append(report_id)
        summaries.append(f"[{doc['document_type']}] {summary}")
        print(f"Wrote report_id={report_id} type={doc['document_type']} pages={doc['page_range']} ({processing_ms}ms)")

    s3.copy_object(
        CopySource={'Bucket': source_bucket, 'Key': source_key},
        Bucket=PROCESSED_BUCKET,
        Key=processed_key,
    )
    s3.delete_object(Bucket=source_bucket, Key=source_key)
    print(f"Archived {source_key} -> s3://{PROCESSED_BUCKET}/{processed_key}")

    total_ms = int((time.time() - start_time) * 1000)
    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject='Field Report Pipeline -- Documents Processed',
        Message=_notification_body(source_key, documents, summaries, total_ms),
    )

    print(f"Pass 2 complete: {len(documents)} record(s) written, notification sent ({total_ms}ms total)")
    return {'statusCode': 200, 'reports_written': len(documents), 'report_ids': report_ids}


def _extract_fields(file_bytes, content_type, is_pdf, doc):
    document_type = doc['document_type']
    pages = doc['pages']
    page_range = doc['page_range']

    if len(pages) == 1:
        page_focus = f"This is a single-page document on page {pages[0]}."
    else:
        page_focus = (
            f"This document spans pages {page_range}. "
            f"Focus only on those pages; ignore all other pages in the file."
        )

    prompt = _EXTRACTION_TEMPLATE.format(
        document_type=document_type,
        page_range=page_range,
        page_focus=page_focus,
        field_hints=_FIELD_HINTS.get(document_type, _FIELD_HINTS['other']),
    )

    content = _build_content(file_bytes, content_type, is_pdf, prompt)

    response = bedrock.invoke_model(
        modelId=BEDROCK_MODEL_SONNET,
        body=json.dumps({
            'anthropic_version': 'bedrock-2023-05-31',
            'max_tokens': 1500,
            'messages': [{'role': 'user', 'content': content}],
        }),
    )

    text = json.loads(response['body'].read())['content'][0]['text'].strip()
    return json.loads(_strip_fences(text))


def _generate_summary(document_type, extracted):
    prompt = _SUMMARY_TEMPLATE.format(
        document_type=document_type,
        extracted_fields=json.dumps(extracted, indent=2),
    )

    response = bedrock.invoke_model(
        modelId=BEDROCK_MODEL_HAIKU,
        body=json.dumps({
            'anthropic_version': 'bedrock-2023-05-31',
            'max_tokens': 300,
            'messages': [{'role': 'user', 'content': [{'type': 'text', 'text': prompt}]}],
        }),
    )

    return json.loads(response['body'].read())['content'][0]['text'].strip()


def _build_content(file_bytes, content_type, is_pdf, prompt):
    encoded = base64.standard_b64encode(file_bytes).decode()
    if is_pdf:
        media_block = {'type': 'document', 'source': {'type': 'base64', 'media_type': 'application/pdf', 'data': encoded}}
    else:
        media_type = content_type if content_type in ('image/jpeg', 'image/png', 'image/gif', 'image/webp') else 'image/jpeg'
        media_block = {'type': 'image', 'source': {'type': 'base64', 'media_type': media_type, 'data': encoded}}
    return [media_block, {'type': 'text', 'text': prompt}]


def _strip_fences(text):
    if text.startswith('```'):
        text = text.split('```')[1]
        if text.startswith('json'):
            text = text[4:]
    return text.strip()


def _processed_key(source_key):
    if 'uploads/' in source_key:
        return source_key.replace('uploads/', 'processed/', 1)
    return f"processed/{source_key.split('/')[-1]}"


def _notification_body(source_key, documents, summaries, total_ms):
    filename = source_key.split('/')[-1]
    lines = [
        f"File: {filename}",
        f"Documents extracted: {len(documents)}",
        f"Processing time: {total_ms / 1000:.1f}s",
        '',
        '--- Summaries ---',
    ] + summaries
    return '\n'.join(lines)
