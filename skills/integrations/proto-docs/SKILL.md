---
name: proto-docs
description: Generate comprehensive API documentation for Protocol Buffer (.proto) files — field and method descriptions, introductory articles, and usage guides. Use when you need to write or improve API docs for a gRPC or protobuf-based service.
when_to_use: "User asks to document a proto file, write API docs for a gRPC service, improve protobuf descriptions, or generate introductory articles for a proto-defined API. Trigger phrases: 'document this proto', 'write API docs', 'proto docs', 'gRPC documentation', 'add descriptions to proto'."
argument-hint: "[path to proto directory or .proto file]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
metadata:
  capability: api-documentation
  tags:
    - protobuf
    - grpc
    - api-docs
    - documentation
    - integrations
  updated-date: "2026-06-08"
---

# Proto API Documentation Skill

Generate comprehensive API documentation for Protocol Buffer services — field/method descriptions in `.proto` files, plus introductory articles and usage guides.

## Usage
```
/proto-docs [path-to-proto-directory-or-file]
```

## Arguments
- `$ARGUMENTS` — path to a proto directory or `.proto` file (e.g., `src/proto/`, `api/v1/service.proto`). If omitted, searches the current project for `.proto` files.

## Overview

This skill follows a **3-stage process**:

1. **Investigation** — Read proto files and understand the API design
2. **Description writing** — Write field, method, and message descriptions inline in the proto files
3. **Article writing** — Create introductory docs and usage guides alongside the proto files

---

## Step 1: Locate Proto Files

If `$ARGUMENTS` is provided, use that path. Otherwise, search the project:
```bash
find . -name "*.proto" -not -path "*/vendor/*" -not -path "*/node_modules/*" | head -20
```

Common locations:
- `src/proto/` or `proto/`
- `api/v1/*.proto`
- `<service>/src/main/proto/`

---

## Step 2: Investigation

Read all proto files thoroughly. Understand:
- What entities/messages exist and their relationships
- What RPC methods are exposed and their purpose
- What fields are required vs optional
- What enum values mean

Then ask the developer questions from a **third-party developer's perspective**:
- What is this API for? What problem does it solve?
- Who are the consumers?
- Are there naming inconsistencies that should be preserved or fixed in docs?
- What are the most common usage patterns?
- Are there any non-obvious behaviors, side effects, or rate limits?

---

## Step 3: Write Descriptions

Edit the proto files to add or improve documentation comments.

### Field descriptions

```protobuf
// Good — specific, explains format and behavior
// Unique identifier for the resource. Assigned server-side on creation.
// Read-only; ignored if set on create requests.
string id = 1;

// Good — explains the enum values
// Current status. Possible values:
//   PENDING — awaiting confirmation
//   CONFIRMED — accepted and scheduled
//   CANCELLED — cancelled by either party
Status status = 2;

// Bad — too vague
// The status.
Status status = 2;
```

**Rules:**
- Every field MUST have a description
- Start with what the field represents, then how/when it's used
- Use code formatting for field names, values, and enum members
- Note whether a field is required, optional, or output-only
- Document pagination cursors, timestamps (UTC? milliseconds?), and IDs explicitly

### Method descriptions

```protobuf
// Good — starts with verb, explains what, when, and response
// Creates a new resource with the specified configuration.
// Returns the created resource including server-assigned fields.
// Returns ALREADY_EXISTS if a resource with the same name exists.
rpc Create(CreateRequest) returns (CreateResponse);

// Good — documents pagination
// Lists resources matching the filter. Results are paginated.
// Use page_token from the previous response to fetch the next page.
rpc List(ListRequest) returns (ListResponse);
```

**Rules:**
- Start with a verb (Creates, Retrieves, Updates, Deletes, Lists, Searches)
- Document error codes the method can return
- Describe pagination behavior for List methods
- Note idempotency for mutating methods

### Message descriptions

```protobuf
// Represents a scheduled appointment between a provider and a client.
// Created via CreateAppointment; updated via UpdateAppointment.
message Appointment {
  ...
}
```

---

## Step 4: Write Documentation Articles

Place articles alongside the proto files, typically in `docs/` or `guides/`:

### Required: Introduction (`introduction.md`)
- 1-paragraph overview of what the API does
- 2-4 key use cases as bullets
- Prerequisites and required permissions
- Known limitations

### Required: Sample Flows (`sample-flows.md`)
- 2-4 common end-to-end workflows
- Step-by-step with the sequence of RPC calls
- Code snippets showing request/response shapes
- Explain what each step does and why

### Optional: Errors (`errors.md`)
Only needed if the API uses non-standard error handling that can't be described in 1-2 sentences in the proto.

### Optional: Terminology (`terminology.md`)
Only if there are >10 domain-specific terms that need defining.

---

## Writing Guidelines

- Use sentence case for headings (H2 and below)
- Use contractions in prose (can't, don't, isn't)
- Use **bold** only for clickable UI elements — not for emphasis
- End bulleted items with periods
- Use backticks for: code, field names, method names, enum values, file names
- Keep prose in present tense ("The method returns..." not "The method will return...")

---

## Output Structure

```
proto/
├── service.proto              # Updated with inline descriptions
├── messages.proto             # Updated with inline descriptions
└── docs/
    ├── introduction.md        # API overview
    ├── sample-flows.md        # Common workflows
    └── errors.md              # Error reference (if needed)
```

## Important

- **Verify technical accuracy** — always have a service owner review generated docs
- Generated content should be committed to the repository
- Run `buf lint` or `protoc` after editing proto files to confirm they still parse
