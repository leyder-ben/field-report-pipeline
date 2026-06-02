# Field Report Pipeline — Project Knowledge Base

## What This Is

Portfolio project knowledge base for a three-project AWS build. Tracks project history, session notes, build progress, and troubleshooting discoveries across all work sessions.

**Projects:**
- **Project A** — field-report-system (serverless field report submission)
- **Project B** — field-ops-platform (EKS GitOps platform)
- **Project C** — field-report-pipeline (AI-powered document ingestion pipeline)

---

## Origin Story

Built by a former field technician who worked for a commercial water well contractor. Field techs wrote everything on paper — pump installation reports, time and material sheets, pumping test data, well cleaning records. Those paper forms went into filing cabinets. Looking something up meant pulling boxes. Monday morning reconciliation meant a supervisor manually cross-referencing paper sheets against a mobile app before anything could go to payroll.

While on light duty from a work injury, I spent time scanning archival records — years of paper job files going back to the 1970s. Every page manually scanned, manually organized. The problem was obvious: this data existed, it was just trapped in paper. There was no reason a pipeline couldn't read it, classify it, extract the structured data, and make it queryable.

That observation became Project C. Projects A and B are the forward-facing infrastructure that Project C feeds into.

---

## Current State Snapshot

**Last Updated:** Session 2

**Overall Status:** Project A complete and live

| Project | Status | Phase | Next Action |
|---|---|---|---|
| Project A | **Complete** | All 7 phases done | Begin Project C next session |
| Project B | Not started | — | Blocked on Project A |
| Project C | Not started | — | Blocked on Project A |

**Immediate Next Steps:**
1. Begin Project C — field-report-pipeline (AI-powered document ingestion)
2. Start with Phase 1: Terraform infrastructure (S3 intake/processed/UI buckets, IAM roles, Secrets Manager)

**Synthetic Data Status:**
- Blank form inventory: Complete (10 form types documented)
- Synthetic data spec: Complete (`Wolverine_Water_Synthetic_Data_Spec.docx`)
- Image generation prompts: Complete (`Wolverine_Water_Image_Generation_Prompts.docx`)
- Generated images: Blocked — ChatGPT image generation down at time of writing
- Archival PDF assembly: Not started — blocked on image generation

---

## Architecture Decisions Log

Decisions made and why — so future sessions don't relitigate settled questions.

### ADR-001: Two-Pass Pipeline Architecture (Project C)
**Decision:** Project C uses a two-pass Lambda architecture for document ingestion rather than a single per-page extraction pass.

**Context:** Real archival job files are mixed-type PDFs — one file may contain sales orders, invoices, installation reports, correspondence letters, hydrology reports, and service contracts all interleaved. Multi-page documents (letters, contracts, technical reports) have continuation pages with no header or identifying information.

**Pass 1** classifies pages and groups them into logical documents. **Pass 2** extracts fields from each identified document group using the appropriate schema for that document type.

**Why not single-pass:** A single-pass approach that treats each page independently cannot handle multi-page documents and cannot apply the correct extraction schema without knowing the document type first.

**Trade-off:** Two Bedrock calls per document group instead of one. Cost is acceptable for a portfolio demo; would need optimization at production scale.

### ADR-002: Shared DynamoDB Table
**Decision:** All three projects write to a single DynamoDB table (`field-reports`). The `source` attribute distinguishes entry points: `'form'` (Project A mobile form), `'upload'` (Project C pipeline).

**Why:** Unified data model means the Supervisor Dashboard (Project B) shows all records regardless of how they were submitted. One query, one view. Demonstrates intentional system design rather than three isolated components.

**Constraint:** Schema changes must be backward compatible. All three projects must be considered before any schema modification.

### ADR-003: Synthetic Data — Wolverine Water, Inc.
**Decision:** All test data and demo artifacts use a fictional contractor (Wolverine Water, Inc., Millbrook, Indiana) rather than real Peerless Midwest data.

**Why:** Real client data in a public GitHub repo is a privacy and professional ethics problem. Using synthetic data is also demonstrably better practice — worth noting explicitly in the README.

**Fictional identity:** 4400 Industrial Drive, Millbrook, Indiana 46742 / 219-555-0182. Two synthetic customers: Harlan County Rural Water District and Stover Industrial Park.

### ADR-004: Project Build Order
**Decision:** Project A → Project C → Project B.

**Why:** Project A provisions the shared DynamoDB table and SNS topic that Projects B and C depend on. Project C is the most visually impressive demo artifact for the portfolio and should be built before the platform layer. Project B is the container that runs everything — built last when there's something to run.

### ADR-005: Bedrock Model Selection
**Decision:** Claude 3.5 Sonnet (vision) for Pass 1 classification and Pass 2 extraction. Claude 3 Haiku for summarization and NL query.

**Why:** Sonnet has stronger vision capabilities and better instruction-following for complex structured extraction tasks. Haiku is sufficient for summarization and NL-to-filter conversion, and is significantly cheaper per token — important for the notification and query paths which fire on every document.

---

## Shared Infrastructure Reference

Resources provisioned in Project A and referenced by B and C.

| Resource | Name | Notes |
|---|---|---|
| DynamoDB table | field-reports | PK: report_id (String), SK: submitted_at (String ISO 8601) |
| SNS topic | field-report-notifications | Email subscription for office notification |
| IAM role | field-report-lambda-role | Least privilege — DynamoDB, SNS, Secrets Manager, CloudWatch |

**DynamoDB Schema — full attribute list:**

| Attribute | Type | Source | Notes |
|---|---|---|---|
| report_id | String (PK) | Lambda | UUID |
| submitted_at | String (SK) | Lambda | ISO 8601 |
| source | String | Lambda | 'form' or 'upload' |
| document_type | String | Bedrock (C) / form field (A) | See type list below |
| tech_name | String | Extracted | Field technician name |
| job_site | String | Extracted | Site name or address |
| owner | String | Extracted | Customer/owner name |
| well_no | String | Extracted | Well number |
| job_no | String | Extracted | Job or sales order number |
| date | String | Extracted | Date on the document |
| equipment | Map | Extracted | Make, model, serial — varies by form type |
| measurements | Map | Extracted | GPM, PSI, water levels, etc. — varies by form type |
| notes | String | Extracted | Free text observations |
| summary | String | Bedrock | Plain-English 2-3 sentence summary |
| extraction_confidence | Number | Textract | 0-1 confidence score |
| original_document_key | String | Lambda | S3 key in processed bucket |
| page_range | String | Lambda (C) | e.g. "3-4" for multi-page documents |
| processing_duration_ms | Number | Lambda | Pipeline processing time |
| photo_key | String | Lambda (A) | S3 key for photo attachment — nullable |

**Document types (Project C classification vocabulary):**
`sales_order` / `invoice` / `t_and_m` / `pump_install_vt` / `pump_install_sc` / `pump_install_horizontal` / `pump_install_submersible` / `fire_pump_test` / `well_cleaning` / `pumping_test` / `observation_well` / `correspondence_letter` / `hydrology_report` / `service_contract` / `credit_memo` / `other`

---

## Form Type Inventory

Blank forms photographed and available as reference images. All field names confirmed from physical forms.

| Form | Photo File | Key Sections |
|---|---|---|
| Vertical Turbine Pump Installation Report | 20260601_171850.jpg | Motor, Head, Bowl, Column, Suction, Well, Gear Drive, Pumping Data, Monitor Systems, Blowoff |
| Short Coupled Pump Installation Report | 20260601_171857.jpg | Motor, Gear Drive, Engine, Pump Head, Column, Pump Bowl, Water Supply, Pumping Test |
| Submersible Pump Installation Report | 20260601_171905.jpg | Pump, Motor, Column, Pump Discharge, Monitor Systems, Pumping Data, Well |
| Horizontal Pump Installation Report | 20260601_171919.jpg | Motor, Engine, Pump, type selector (Split Case/End Suction/Sewage/Other), Pumping Test |
| Electric Motor Driven Horizontal Fire Pump Test Report | 20260601_171912.jpg | Equipment, Original/Rated Performance, Current Performance (4-point table), Electrical Data |
| Well Cleaning | 20260601_171939.jpg | Performance comparison table, Treatment log table (multi-row), Chemicals Required |
| Pumping Test Data Report | 20260601_171945.jpg | Time-series table (Date/Time/GPM/Water Level, 3 column groups) |
| Observation Well Report | 20260601_171952.jpg | Well specs, time-series table (same format as Pumping Test) |
| Time and Material Report | 20260601_171933.jpg | Labor table (Name/Date/Reg/OT/Work Performed), Materials, Equipment |
| Weekly Timesheet | 20260601_171926.jpg | Mon-Sun grid, Drilling vs Non-Drilling, job names/numbers/truck numbers |

**Note on time-series forms:** Pumping Test Data Report and Observation Well Report may span multiple pages when test duration is long. Page 2+ will have no form header — only continuation table rows. This is the primary boundary detection challenge for these form types.

---

## Synthetic Data Reference

### Wolverine Water, Inc.
- Address: 4400 Industrial Drive, Millbrook, Indiana 46742
- Phone: 219-555-0182 / Fax: 219-555-0183

### Worker Pool
| Role | Name |
|---|---|
| Salesman | R.L. Hartman (RH) |
| Salesman | D.W. Cole (DC) |
| Installer | Gary Moss |
| Installer | Tom Birch |
| Installer | Dale Pruitt |
| Foreman | Ray Hollis |
| Foreman | Jim Sutter |
| Office | B. Kramer |

### Synthetic Customers
**Harlan County Rural Water District**
- Contact: Dave Williams, Superintendent
- Address: 118 County Road 400 E, Harlan, Indiana 46743
- Phone: 219-555-0247
- Tax Exempt: Yes (Municipal)
- File No: 447

**Stover Industrial Park**
- Contact: Carol Fitch, Facilities Manager
- Address: 2200 Stover Parkway, Kokomo, Indiana 46902
- Phone: 765-555-0318
- Tax Exempt: No
- File No: 831

**Birch Creek Township Water Authority**
- Contact: Bob Lane, Township Trustee
- Address: 44 Township Road 18, Cromwell, Indiana 46732
- Phone: 219-555-0614
- Tax Exempt: Yes (Municipal)
- File No: 612

**Dresser Aggregates, Inc.**
- Contact: Dave Dresser, Owner
- Address: 8800 State Road 14, Mentone, Indiana 46539
- Phone: 219-555-0881
- Tax Exempt: No
- File No: 204

### Synthetic File Summary
| File | Customer | Type | Pages | Era |
|---|---|---|---|---|
| 1 | Harlan County RWD | Pump File (447-P) | 15 | 1979–1991 |
| 2 | Harlan County RWD | Well File (447-W) | 11 | 1979–1987 |
| 3 | Stover Industrial | Pump File (831-P) | 10 | 1986–1995 |
| 4 | Stover Industrial | Well File (831-W) | 9 | 1986–1994 |
| 5 | Birch Creek Township WA | Pump File (612-P) | 4 | 1982–1983 |
| 6 | Dresser Aggregates | Pump File (204-P) | 11 | 1974–1988 | 

Boundary detection test pages — hardest classification challenges:
- File 1, pages 10-11: Two-page letter, page 11 has no letterhead
- File 2, pages 3-4: Pumping test continuation, page 4 has blank header
- File 2, pages 6-8: Three-page hydrology report, pages 7-8 are plain text
- File 4, pages 5-6: Two-page service contract, page 6 is legal boilerplate
- File 6, pages 6-7: Two-page annual inspection letter, page 7 has no letterhead or header

Extraction edge cases — documents where field extraction will be ambiguous or incomplete:
- File 5, page 3: Follow-up service invoice — description deliberately vague, no equipment detail
- File 6, page 8: Disputed invoice — no paid notation, handwritten annotation and circled total not in printed text
- File 6, page 9: 1978 aborted pump test letter — terse typed correspondence, no standard form structure, partial test data only

---

## Build Checklist

### Project A — field-report-system

**Phase 1 — Infrastructure**
- [✅] Create GitHub repo: field-report-system (public)
- [✅] Add CLAUDE.md to repo
- [✅] Write Terraform: DynamoDB table (field-reports)
- [✅] Write Terraform: SNS topic (field-report-notifications)
- [✅] Write Terraform: S3 bucket (static site hosting for mobile form)
- [✅] Write Terraform: IAM role for Lambda (least privilege)
- [✅] Write Terraform: Secrets Manager placeholder
- [✅] `terraform plan` — review before apply
- [✅] `terraform apply` — provision infrastructure

**Phase 2 — Lambda**
- [✅] Write process_report Lambda (Python 3.12)
- [✅] Validate input payload
- [✅] Generate UUID and ISO timestamp
- [✅] Write record to DynamoDB
- [✅] Publish to SNS topic
- [✅] Write Terraform: Lambda function and API Gateway trigger
- [✅] Deploy Lambda
- [✅] Test via curl — confirm DynamoDB record created and SNS fires

**Phase 3 — Mobile Web Form**
- [✅] Build static HTML form (mobile-first)
- [✅] Fields: tech name, job site, report type, equipment, notes, optional photo
- [✅] Submit fires HTTPS POST to API Gateway endpoint
- [✅] Host on S3 static site
- [✅] Test end-to-end from phone

**Phase 4 — Bedrock AI Summary (optional layer)**
- [✅] Add Bedrock call to Lambda after DynamoDB write
- [✅] Claude Haiku 4.5 — generate plain-English summary from report fields
- [✅] Append summary to DynamoDB record
- [✅] Include summary in SNS notification body
- [✅] Test — confirm summary appears in email notification

**Phase 5 — Observability**
- [✅] CloudWatch log group for Lambda
- [✅] Lambda error rate alarm
- [✅] API Gateway 5xx alarm
- [✅] CloudWatch dashboard: submission rate, Lambda errors, API latency

**Phase 6 — GitHub Actions CI/CD**
- [✅] Write deploy.yml — zip Lambda, deploy via aws lambda update-function-code
- [✅] Test: push commit, confirm Lambda updates
- [✅] Run end-to-end test after deploy

**Phase 7 — README**
- [✅] Write README following portfolio documentation standards
- [✅] Include architecture diagram (project_a_architecture.svg)
- [✅] Include origin story
- [✅] Include troubleshooting section with real issues encountered

---

### Project C — field-report-pipeline

**Phase 1 — Infrastructure**
- [ ] Create GitHub repo: field-report-pipeline (public)
- [ ] Add CLAUDE.md to repo
- [ ] Write Terraform: S3 intake bucket (triggers Lambda on object creation)
- [ ] Write Terraform: S3 processed bucket (archive after successful processing)
- [ ] Write Terraform: S3 static site (upload UI)
- [ ] Write Terraform: IAM roles for both Lambdas (S3, DynamoDB, SNS, Bedrock, Textract, Secrets Manager, CloudWatch)
- [ ] Write Terraform: Secrets Manager placeholders
- [ ] `terraform plan` → `terraform apply`

**Phase 2 — Presigned URL endpoint**
- [ ] Write presigned_url Lambda — generates time-limited S3 upload URL
- [ ] Write Terraform: API Gateway endpoint → presigned_url Lambda
- [ ] Test: call endpoint, confirm presigned URL returned, upload file to S3

**Phase 3 — Pass 1: extract_report Lambda**
- [ ] Write extract_report Lambda triggered by S3 object creation
- [ ] Rasterize each PDF page using pdf2image or similar
- [ ] Send page batches to Bedrock with adjacency context
- [ ] Prompt Bedrock to classify pages and group into logical documents
- [ ] Output page manifest as structured JSON
- [ ] Unit test with single-page form photo
- [ ] Unit test with multi-page PDF (boundary detection test)
- [ ] Write Terraform: Lambda function, S3 event trigger

**Phase 4 — Pass 2: merge_summarize Lambda**
- [ ] Write merge_summarize Lambda triggered by Pass 1 completion
- [ ] For each document group in manifest: call Bedrock with type-specific extraction schema
- [ ] Generate plain-English summary via Bedrock Haiku
- [ ] Write structured record to DynamoDB (one record per document)
- [ ] Move original file to processed S3 bucket
- [ ] Publish SNS notification with summary
- [ ] Test end-to-end: upload form photo, confirm DynamoDB record appears

**Phase 5 — Bedrock Prompt Development**
- [ ] Write and test Pass 1 classification prompt
- [ ] Iterate until boundary detection is reliable on multi-page test files
- [ ] Write Pass 2 extraction prompts for each document type (14 types)
- [ ] Test each extraction prompt against corresponding synthetic form image
- [ ] Document all prompts in README — prompt engineering is a portfolio artifact

**Phase 6 — SNS Notification**
- [ ] Subscribe real email to SNS topic
- [ ] Test: upload form → confirm email arrives with plain-English summary
- [ ] Screenshot the email — this is the primary demo artifact

**Phase 7 — Upload UI**
- [ ] Build mobile-friendly upload form (one button, file picker)
- [ ] Request presigned URL from API Gateway on submit
- [ ] Upload directly to S3 via presigned URL
- [ ] Show confirmation message after upload
- [ ] Host on S3 static site
- [ ] Test from phone

**Phase 8 — Query API**
- [ ] Write query Lambda — GET /reports with filter params (tech_name, document_type, job_site, date range)
- [ ] Write Terraform: API Gateway endpoint → query Lambda
- [ ] Test with Postman or curl

**Phase 9 — GitHub Actions CI/CD**
- [ ] Write deploy.yml — package and deploy all Lambdas on push to main
- [ ] Test: push commit, confirm all Lambdas update
- [ ] Run end-to-end test after deploy

**Phase 10 — Observability**
- [ ] CloudWatch log groups for all Lambdas
- [ ] Processing duration metric (log in merge_summarize, create CloudWatch metric filter)
- [ ] Lambda error rate alarm
- [ ] p95 processing duration alarm (threshold: 30 seconds)
- [ ] Extraction failure alarm (null fields on critical attributes)
- [ ] Dashboard: submissions per day, extraction confidence, processing duration p50/p95

**Phase 11 — Natural Language Query (Phase 2)**
- [ ] Write nl_query Lambda — Bedrock Haiku converts NL string to DynamoDB filter JSON
- [ ] Wire to API Gateway POST /query
- [ ] Test with varied natural language queries
- [ ] Document example queries and responses in README

**Phase 12 — README**
- [ ] Write README following portfolio documentation standards
- [ ] Include architecture diagram (project_c_architecture.svg)
- [ ] Include origin story (scanning paper records on light duty)
- [ ] Include two-phase adoption story
- [ ] Document all Bedrock prompts with design rationale
- [ ] Include troubleshooting section
- [ ] Screenshot of SNS email notification

---

### Project B — field-ops-platform

**Phase 1 — Infrastructure**
- [ ] Create GitHub repos: field-ops-platform (public), field-ops-gitops (public)
- [ ] Add CLAUDE.md to app repo
- [ ] Write Terraform: VPC (public + private subnets, NAT gateway)
- [ ] Write Terraform: EKS cluster (managed node group, 3x t3.medium, autoscaling 2→4)
- [ ] Write Terraform: ECR repositories (field-report-api, supervisor-dashboard)
- [ ] Write Terraform: IAM roles (EKS node group, ALB controller)
- [ ] Write Terraform: ALB Ingress Controller
- [ ] Write Terraform: DevOps Guru (pointed at EKS cluster)
- [ ] `terraform plan` → `terraform apply`

**Phase 2 — Containerize Project A API**
- [ ] Write Dockerfile for process_report API (Python Flask or FastAPI wrapper)
- [ ] Build image locally, confirm it runs
- [ ] Push to ECR
- [ ] Write Helm chart: Deployment (2 replicas min), Service (ClusterIP), HPA (CPU 60%)

**Phase 3 — Supervisor Dashboard**
- [ ] Build lightweight dashboard (Python Flask or Node)
- [ ] Reads from GET /reports endpoint — no direct DynamoDB access
- [ ] Table of recent submissions, filterable by tech name and document type
- [ ] Detail view on row click
- [ ] Mobile-friendly
- [ ] Write Dockerfile, push to ECR
- [ ] Write Helm chart: Deployment, Service, Ingress (ALB)

**Phase 4 — ArgoCD GitOps**
- [ ] Install ArgoCD on EKS cluster
- [ ] Write ArgoCD Application manifests pointing at field-ops-gitops repo
- [ ] Test: update image tag in gitops repo, confirm ArgoCD syncs cluster

**Phase 5 — GitHub Actions CI**
- [ ] Write ci.yml: build Docker image, push to ECR, update image tag in gitops repo
- [ ] Test: push commit to app repo, confirm CI runs, ArgoCD syncs

**Phase 6 — Observability**
- [ ] Install kube-prometheus-stack via Helm (Prometheus, Grafana, Alertmanager)
- [ ] CloudWatch Container Insights for EKS
- [ ] Custom Grafana dashboard: field report submission rate, API error rate, pod health
- [ ] Confirm DevOps Guru is receiving EKS signals
- [ ] Load test with Siege — validate HPA scales pods

**Phase 7 — README**
- [ ] Write README following portfolio documentation standards
- [ ] Include architecture diagram (project_b_architecture.svg)
- [ ] Include CEO demo narrative
- [ ] Include troubleshooting section

---

## Session Log

---

### Session 2 — Project A Phase 3: Mobile Web Form

**Date:** June 2, 2026

**Completed:**
- Built `ui/index.html` — mobile-first static form with sticky navy header, card layout, required fields (tech name, job site, report type), optional fields (equipment, notes, photo), and full photo upload via presigned URL
- Extended `lambda/process_report/handler.py` with a `GET /reports?action=presigned_url` route that generates a 5-minute presigned PUT URL for the photos bucket; extension (S3 client, routing, function) added without touching existing POST or GET logic
- Added `aws_s3_bucket_cors_configuration.photos` to `infra/s3.tf` — required so browsers can PUT to S3 presigned URLs from the S3-hosted form
- Ran `terraform apply` — CORS resource created, Lambda redeployed in-place
- Uploaded `index.html` to `field-report-ui-387362989156` S3 bucket
- Confirmed presigned URL endpoint returns valid S3 URL
- Confirmed end-to-end: form submitted from phone, record appeared in DynamoDB

**Live URLs:**
- Form: `http://field-report-ui-387362989156.s3-website.us-east-2.amazonaws.com`
- API: `https://d9kim2z7t5.execute-api.us-east-2.amazonaws.com/prod/reports`

**Key Implementation Notes:**
- Photo upload is a two-step flow at submit time: fetch presigned URL → PUT file to S3 → include `photo_key` in the report POST. The presigned URL is fetched on submit (not on photo select) so it doesn't expire if the user fills out the form slowly.
- CORS on the photos bucket uses `allowed_origins = ["*"]` — this is safe because the bucket is private and the presigned URL carries time-limited credentials. CORS just allows the browser to make the request.
- 16px font on all inputs prevents iOS auto-zoom on focus.
- No external CDN dependencies — single self-contained HTML file.

**Also Completed (Phase 4):**
- Extended `handler.py` with `generate_summary()` — calls Claude Haiku 4.5 via Bedrock after DynamoDB write, appends summary via `update_item`, includes summary in SNS notification body
- Discovered Claude 3 Haiku and 3.5 Haiku both LEGACY on this account (T-006, T-007); upgraded to Claude Haiku 4.5 (`us.anthropic.claude-haiku-4-5-20251001-v1:0`)
- Confirmed end-to-end: summary in DynamoDB, summary in SNS email notification
- Updated CLAUDE.md ADR-005 to reflect Haiku 4.5

**Also Completed (Phase 5):**
- Verified all CloudWatch observability resources provisioned in Phase 1 are wired and showing data
- Log group `/aws/lambda/field-report-process-report` confirmed active with 30-day retention
- All three alarms (`lambda-errors`, `lambda-duration`, `api-5xx-errors`) in OK state, SNS-wired
- `field-report-dashboard` confirmed; 10 Lambda invocations visible in last-hour metrics
- No new Terraform changes required — everything was already provisioned

**Also Completed (Phase 6):**
- Implemented `.github/workflows/deploy.yml` — OIDC auth, Lambda package + deploy, S3 UI sync, smoke test (GET /reports → assert 200)
- Added `paths` filter: pipeline only triggers on `lambda/**`, `ui/**`, `.github/workflows/**` — doc-only pushes do not trigger a deploy
- First run failed: `aws lambda wait function-updated` requires `lambda:GetFunctionConfiguration` which was missing from the deploy role (T-008); added permission and redeployed
- Final run: all 5 steps green in 19 seconds

**Also Completed (Phase 7):**
- Rewrote README.md — origin story, architecture table, submission flow, key decisions, repo structure, DynamoDB schema, build instructions, troubleshooting section (8 real entries), how this connects to Projects B and C
- Fixed stale details from scaffold README: wrong function name, wrong region, wrong report_type values, stale status badge, Claude 3 Haiku model reference

**Next Session Should Start With:**
1. Begin Project C — field-report-pipeline
2. Phase 1: Terraform infrastructure (S3 intake bucket, processed bucket, UI bucket, IAM roles for both Lambdas, Secrets Manager)

---

### Session 1 — Project Planning and Scaffolding

**Date:** June 1, 2026

**Completed:**
- Reviewed all three project gameplans (Projects A, B, C)
- Reviewed all three architecture diagrams (SVG)
- Photographed and inventoried all 10 blank Peerless Midwest form types
- Reviewed 4 archival PDF files (2 customers, pump file + well file each)
- Analyzed archival PDF contents — identified mixed document types per file, multi-page documents, continuation pages without headers
- Designed two-pass pipeline architecture for Project C based on archival file complexity
- Established fictional contractor identity: Wolverine Water, Inc., Millbrook, Indiana
- Designed 4 synthetic job files (55 pages total) across 2 fictional customers
- Generated `Wolverine_Water_Synthetic_Data_Spec.docx` — complete field values for all 55 pages
- Generated `Wolverine_Water_Image_Generation_Prompts.docx` — 55 ChatGPT prompts for image generation
- Identified 4 boundary detection test cases (hardest classification challenges)
- Determined image generation tool recommendation: ChatGPT primary, Firefly backup
- Discussed two-phase adoption story for Project C (Phase 1: photo upload, Phase 2: native digital form)
- Created CLAUDE.md for this project
- Created this knowledge base

**Blocked / In Progress:**
- Synthetic image generation: blocked — ChatGPT image generation platform outage at time of writing
- All three project repos: not yet created — next logical step

**Key Decisions Made:**
- Two-pass pipeline architecture (ADR-001)
- Shared DynamoDB table (ADR-002)
- Wolverine Water synthetic data (ADR-003)
- Project A → C → B build order (ADR-004)
- Bedrock model selection (ADR-005)

**Next Session Should Start With:**
1. Create GitHub repos (field-report-system, field-report-pipeline, field-ops-platform, field-ops-gitops)
2. Add CLAUDE.md to each repo
3. Begin Project A Phase 1 — Terraform for DynamoDB, SNS, S3, IAM

---

## Troubleshooting Log

### T-001: DynamoDB tag value rejected — invalid characters
**Symptom:** CreateTable failed with ValidationException: The Tag Value provided is invalid
**Root Cause:** Em dash (—) in tag value. DynamoDB tags do not allow em dashes.
Comma in tag value also flagged as invalid in subsequent attempt.
**Fix:** Simplified tag value to plain ASCII with no punctuation beyond spaces
**Prevention:** Keep DynamoDB tag values plain ASCII. No em dashes, commas, or
special characters.
**Affected Systems:** dynamodb.tf

### T-002: GitHub Actions OIDC provider already exists
**Symptom:** CreateOpenIDConnectProvider failed with EntityAlreadyExists
**Root Cause:** Whetstone project already created the GitHub OIDC provider.
Only one can exist per AWS account — it is global.
**Fix:** terraform import aws_iam_openid_connect_provider.github \
  arn:aws:iam::387362989156:oidc-provider/token.actions.githubusercontent.com
**Prevention:** Always check for existing OIDC provider before provisioning
in a new project on the same AWS account.
**Affected Systems:** iam.tf

### T-003: S3 public bucket policy blocked by bucket-level access block
**Symptom:** PutBucketPolicy failed with AccessDenied — BlockPublicPolicy
**Root Cause:** Race condition — public access block resource applied before
AWS propagated the all-false block settings, causing the subsequent bucket
policy apply to be rejected.
**Fix:** Added depends_on = [aws_s3_bucket_public_access_block.ui] to the
bucket policy resource to enforce correct ordering.
**Prevention:** Always add explicit depends_on from bucket policy to public
access block resource when making a bucket public.
**Affected Systems:** s3.tf

### T-004: API Gateway CORS integration response race condition
**Symptom:** PutIntegrationResponse failed with NotFoundException:
Invalid Integration identifier specified
**Root Cause:** Integration response resource attempted to create before
the mock integration was fully registered.
**Fix:** Added depends_on = [aws_api_gateway_integration.options_reports,
aws_api_gateway_method_response.options_200] to the integration response.
**Prevention:** Always add explicit depends_on on integration response
resources — API Gateway has propagation delays that Terraform's implicit
dependency graph does not always catch.
**Affected Systems:** api_gateway.tf

### T-005: CloudWatch dashboard widgets missing required region property
**Symptom:** PutDashboard failed with InvalidParameterInput — 9 validation
errors, all "Should have required property 'region'"
**Root Cause:** CloudWatch dashboard widget properties blocks require an
explicit region field. Terraform does not infer it from the provider.
**Fix:** Added region = var.aws_region to each widget properties block.
**Prevention:** Always include region in CloudWatch dashboard widget
properties when defining dashboards in Terraform.
**Affected Systems:** cloudwatch.tf

### T-006: Bedrock on-demand invocation requires inference profile ID
**Symptom:** ValidationException: Invocation of model ID anthropic.claude-3-haiku-20240307-v1:0
with on-demand throughput isn't supported. Retry your request with the ID or ARN of an
inference profile that contains this model.
**Root Cause:** AWS now requires cross-region inference profile IDs instead of bare model IDs
for on-demand Bedrock calls. The `us.` prefix denotes a US cross-region inference profile.
**Fix:** Use `us.anthropic.claude-<model>` instead of `anthropic.claude-<model>`.
**Affected Systems:** lambda.tf (BEDROCK_MODEL_ID env var), any future Lambda using Bedrock.

### T-007: Claude 3 Haiku and 3.5 Haiku blocked as legacy models
**Symptom:** ResourceNotFoundException: Access denied. This Model is marked by provider as
Legacy and you have not been actively using the model in the last 30 days.
**Root Cause:** On this AWS account, Claude 3 Haiku (20240307) and Claude 3.5 Haiku (20241022)
are both marked LEGACY. Their inference profiles show ACTIVE but invocations are still blocked
because the underlying foundation models are inactive.
**Fix:** Upgrade to Claude Haiku 4.5 — inference profile `us.anthropic.claude-haiku-4-5-20251001-v1:0`.
Foundation model and inference profile both ACTIVE on this account.
**Prevention:** Before specifying any Bedrock model ID, run:
`aws bedrock list-foundation-models --region <region> --by-provider Anthropic`
and confirm the model's lifecycle status is ACTIVE, not LEGACY.
**Affected Systems:** lambda.tf, CLAUDE.md ADR-005. Also affects Project C — all Claude 3/3.5
Haiku references in the architecture must use Haiku 4.5.

### T-008: GitHub Actions Lambda waiter requires GetFunctionConfiguration
**Symptom:** `aws lambda wait function-updated` failed with AccessDeniedException:
not authorized to perform lambda:GetFunctionConfiguration
**Root Cause:** The waiter polls `GetFunctionConfiguration` internally to check
`LastUpdateStatus`. The deploy role had `GetFunction` but not `GetFunctionConfiguration` —
these are separate IAM actions despite sounding similar.
**Fix:** Added `lambda:GetFunctionConfiguration` to the `LambdaDeploy` statement in iam.tf.
**Prevention:** When using any `aws <service> wait` command in CI/CD, check the AWS docs
for which API calls the waiter uses internally — they are often different from the primary action.
**Affected Systems:** iam.tf

---

## Portfolio Notes

Observations about how to present this work — for README writing, interview prep, and portfolio site.

**The origin story matters.** This isn't a tutorial project. It was inspired by a real operational problem observed firsthand as a field technician. The scanning-on-light-duty detail is specific and human — use it.

**The two-phase adoption story is the strongest narrative.** Most technology rollouts fail because they demand too much change too fast. This architecture gives a company a migration path instead of an ultimatum. That insight is worth stating clearly in the README and in any demo.

**The three projects are one system.** Present them that way. One DynamoDB table, one SNS topic, one supervisor view. A field tech on paper, a field tech on a phone, and a supervisor seeing both in the same place — that's the pitch.

**The boundary detection problem is technically interesting.** Being able to explain why a two-pass architecture is necessary — and what breaks without it — demonstrates deeper understanding than just wiring together AWS services. That explanation belongs in the README and in interview prep.

**Prompt engineering is a skill.** Showing the actual Bedrock prompts, explaining the design choices, and documenting how they were iterated is valuable portfolio content. Don't hide the prompts.

**The synthetic data decision is worth calling out explicitly.** Noting that real client data was deliberately excluded and replaced with synthetic data demonstrates professional judgment and data handling awareness. Hiring managers and clients notice.
