---
name: proto-docs
description: Generate API documentation for proto files. Creates descriptions, intro articles, and usage guides. Use when you need to write or update API docs.
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
---

# API Docs Generation Skill

Generate comprehensive API documentation for proto files using Wix tech writer guidelines.

## Usage
```
/api-docs [path-to-proto-directory]
```

## Arguments
- `$ARGUMENTS` - Path to the proto directory containing the API definition (e.g., `bookings-backend/bookingsV2/bookings-service/src/main/proto`)

## Overview

This skill guides you through a **3-stage process** to generate complete API documentation:

1. **Investigation Mode** - Gather information about the API by reading proto files and asking questions
2. **Writing Mode (Descriptions)** - Write field, method, and entity descriptions in proto files
3. **Writing Mode (Articles)** - Write introductory articles for the API reference

## Instructions

### Step 1: Locate Proto Directory

If `$ARGUMENTS` is provided, use that path. Otherwise, search for proto files:
```
Look for proto directories in the current project, typically under:
- src/main/proto/
- proto/
```

The proto directory typically contains:
- `.proto` files - API structure and field definitions
- `appendices/docs/guides/` - Introductory articles
- `documentation.yaml` - Configuration for docs publishing

### Step 2: Investigation Mode

Read all files in the proto directory and gather information:

1. **Find and read ALL `.proto` files** - There may be several subdirectories. Make sure you find every single file.
2. **Find and read introductory docs** - Usually in `appendices/docs/guides/`
3. **Read code samples** if they exist

Then ask the user questions about the API from a **third-party developer's perspective**:

**API Design & Structure:**
- Naming consistency across fields, endpoints, and objects
- Naming clarity - Is it clear what each field/endpoint/object is for?
- Logical grouping and organization of endpoints

**Documentation Clarity:**
- Field/endpoint descriptions that are missing or unclear
- Whether developers will understand what to do with each field/endpoint

**Developer Experience:**
- Overall API structure logic and consistency
- Gaps in functionality or confusing workflows
- Integration patterns and how this API fits into larger systems
- Any unexpected behavior that needs documentation
- Rate limits, quotas, or other usage considerations

### Step 3: Writing Mode - Descriptions

After gathering information, edit the proto files to improve descriptions.

#### Field Description Guidelines
- Every field MUST have a description
- Use sentence case, end with a period
- Explain what the field is and how it's used
- For enums, describe what each value means
- Use backticks for field names, values, and code
- Don't use backticks for generic English descriptions

**Examples:**
```protobuf
// Good
// Unique identifier for the booking.
string id = 1;

// Good
// Current status of the booking. One of: `PENDING`, `CONFIRMED`, `CANCELLED`.
BookingStatus status = 2;

// Bad - too vague
// The ID.
string id = 1;
```

#### Method Description Guidelines
- Start with a verb (Creates, Retrieves, Updates, Deletes, Lists)
- Explain what the method does and when to use it
- Document required vs optional parameters
- Describe the response structure
- Note any side effects or important behaviors

**Examples:**
```protobuf
// Good
// Creates a new booking for a specified service and time slot.
// Returns the created booking with a generated ID.
rpc CreateBooking(CreateBookingRequest) returns (CreateBookingResponse);

// Good
// Retrieves a list of bookings matching the specified filters.
// Results are paginated. Use `cursor` to retrieve the next page.
rpc QueryBookings(QueryBookingsRequest) returns (QueryBookingsResponse);
```

#### Entity/Message Description Guidelines
- Explain what the entity represents
- Describe its purpose in the API
- Note relationships to other entities

### Step 4: Writing Mode - Articles

Create/edit introductory articles in `appendices/docs/guides/`:

#### Required Articles:

**1. Submodule Introduction (`introduction.md`)**
- Brief overview of what the API does
- Key use cases (2-4 bullet points)
- Terminology list (if under 10 terms, include inline; otherwise separate article)
- Prerequisites and permissions
- Limitations

**2. Sample Flows (`sample-flows.md`)**
- 2-4 common use cases with step-by-step flows
- Include code snippets showing API calls
- Show the sequence of API calls for each workflow
- Explain what happens at each step

#### Optional Articles (add only if needed):

**3. Terminology (`terminology.md`)** - Only if >10 domain-specific terms

**4. Errors (`errors.md`)** - Only if non-standard validation errors exist that require special handling and can't be documented in 1-2 sentences in the proto

**5. API-specific articles** - For complex topics needing more than 2-4 paragraphs

#### For Service Plugins (SPIs)
SPIs (identified by `.wix.spi.service` annotation) require all standard articles plus SPI-specific content:
- How to implement the SPI
- Configuration requirements
- Deployment instructions

### Step 5: Update documentation.yaml

If you add new articles, ensure they're listed in `documentation.yaml`:

```yaml
guides:
  - path: appendices/docs/guides/introduction.md
  - path: appendices/docs/guides/sample-flows.md
```

## Writing Guidelines

### General Rules
- Use contractions (can't, don't, isn't)
- End bullet points with periods (unless ≤3 words)
- Use **title case only for H1** headings; sentence case for all others (H2, H3, etc.)
- Don't use "Wix" as a person - avoid "Wix receives" or "Wix responds"
- Use **"method"** instead of "endpoint" or "function"
- Use **"specify"** instead of "pass" for parameters

### Code Formatting
- Use backticks for: code, JSON keys, file names, parameter names, field names, enum values
- Don't use backticks when speaking generically in regular English
- For JSON: code font for keys, quotation marks for values

### Text Formatting
- **Bold** only clickable UI elements (e.g., Click **Save**)
- Don't use bold for emphasis
- Don't use italics for emphasis

### Common Mistakes to Avoid
- ❌ In the **Additional Information** section... (don't bold non-clickable UI)
- ❌ The email is sent **only** to... (don't bold for emphasis)
- ✅ Click **More**.
- ✅ A rich text box is an input element for entering information in rich text format.

## Memory File

The tool creates `.auto-api-docs-memory.json` in the root of each proto directory to track:
- API context at the end of the session
- Progress through the workflow

This enables incremental documentation updates - subsequent sessions only focus on new changes.

## Output Locations

Generated documentation is typically placed in:
```
proto/
├── *.proto                    # API definitions with descriptions
├── documentation.yaml         # Docs configuration
└── appendices/
    └── docs/
        └── guides/
            ├── introduction.md
            ├── sample-flows.md
            └── ...
```

## Examples

```
/api-docs                                                    # Search for protos in current project
/api-docs bookings-backend/bookingsV2/bookings-service/src/main/proto
/api-docs calendar-3/schedules/src/main/proto
```

## Important Notes

- **VERIFY TECHNICAL ACCURACY**: AI-generated docs MUST be reviewed for accuracy!
- Documentation follows Wix API documentation standards and P13N AIPs
- Generated content should be committed to the repository
- Before requesting a tech writer review, run this tool first (required by TW guild)

## Resources

- **Slack**: #techwriters-help - Questions for Wix tech writers
- **Slack**: #ai-docs-tools-beta - Feedback on API tools
- **Jira**: APIDOCS project - Request tech writer review
- **Docs**: https://dev.wix.com/docs/tw-guild/api-docs-tools/