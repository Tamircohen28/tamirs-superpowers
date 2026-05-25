---
name: query-fire-console
description: Query production entities via FireConsole MCP. Get bookings, services, events, resources, staff, schedules, categories, fees, and settings by ID or query.
allowed-tools:
  - mcp__MCP-S__fire-console__invoke_rpc
  - mcp__MCP-S__fire-console__generate_server_signature
  - mcp__MCP-S__fire-console__search_services
  - mcp__MCP-S__fire-console__list_services
  - mcp__MCP-S__fire-console__get_method_schema
  - mcp__MCP-S__fire-console__get_instances
  - mcp__MCP-S__fire-console__get_artifact_info
  - mcp__MCP-S__fire-console__get_client_spec_map
  - mcp__MCP-S__fire-console__get_cli_command
  - mcp__MCP-S__fire-console__find_site
  - mcp__MCP-S__fire-console__find_user
---

# FireConsole MCP - Bookings Entity Queries

Query production entities in the Wix Bookings platform via FireConsole RPC invocation.

## Usage

```
/fireconsole <entity> <method> metaSiteId: <meta_site_id> [entityId: <id>] [payload: <json>]
```

## MANDATORY: Server Signing with MetaSite ID

**Every `invoke_rpc` call MUST include a server signature identity with the correct appDefId and metaSiteId.** Without this, calls will fail with authentication errors.

### App Definition IDs

| Domain | App Def ID |
|--------|-----------|
| Bookings (bookings, services, resources, staff, availability, categories, fees, settings) | `13d21c63-b5ec-5912-8397-c3a5ddb27a97` |
| Calendar (events, schedules) | `482f413c-67ec-4700-acb3-d64d742e7751` |

### Identity Template

Always include this in every `invoke_rpc` call:

```json
"identities": [
  {
    "type": "serverSignature",
    "serverSignature": {
      "appDefId": "<APP_DEF_ID>",
      "metaSiteId": "<META_SITE_ID>"
    }
  }
]
```

---

## Entities Reference

### 1. Booking

| Field | Value |
|-------|-------|
| Artifact | `com.wixpress.bookings.bookings-service` |
| Service FQDN | `com.wixpress.bookings.bookings.v2.Bookings` |
| Entity FQDN | `wix.bookings.v2.booking` |
| App Def ID | `13d21c63-b5ec-5912-8397-c3a5ddb27a97` |

#### Get Booking

```
invoke_rpc:
  target: { artifactId: "com.wixpress.bookings.bookings-service" }
  service: "com.wixpress.bookings.bookings.v2.Bookings"
  method: "GetBooking"
  payload: { "bookingId": "<BOOKING_ID>" }
  identities: [{ type: "serverSignature", serverSignature: { appDefId: "13d21c63-b5ec-5912-8397-c3a5ddb27a97", metaSiteId: "<META_SITE_ID>" } }]
```

#### Query Bookings

```
invoke_rpc:
  target: { artifactId: "com.wixpress.bookings.bookings-service" }
  service: "com.wixpress.bookings.bookings.v2.Bookings"
  method: "Query"
  payload: { "query": { "filter": "{\"status\": \"CONFIRMED\"}", "paging": { "limit": 10 } } }
  identities: [{ type: "serverSignature", serverSignature: { appDefId: "13d21c63-b5ec-5912-8397-c3a5ddb27a97", metaSiteId: "<META_SITE_ID>" } }]
```

#### Key Methods

| Method | Description |
|--------|-------------|
| `GetBooking` | Get by ID |
| `Query` | Query with filters |
| `ConsistentQuery` | Strongly consistent query |
| `CreateBooking` | Create booking |
| `UpdateBooking` | Update booking |
| `CancelBooking` | Cancel booking |
| `ConfirmBooking` | Confirm booking |
| `DeclineBooking` | Decline booking |
| `RescheduleBooking` | Reschedule booking |
| `CountBookings` | Count bookings |
| `BulkCalculateAllowedActions` | Get allowed actions |

---

### 2. Service (Offering)

| Field | Value |
|-------|-------|
| Artifact | `com.wixpress.bookings.services-2` |
| Service FQDN | `wix.bookings.services.v2.ServicesService` |
| Entity FQDN | `wix.bookings.services.v2.service` |
| App Def ID | `13d21c63-b5ec-5912-8397-c3a5ddb27a97` |

#### Get Service

```
invoke_rpc:
  target: { artifactId: "com.wixpress.bookings.services-2" }
  service: "wix.bookings.services.v2.ServicesService"
  method: "GetService"
  payload: { "serviceId": "<SERVICE_ID>" }
  identities: [{ type: "serverSignature", serverSignature: { appDefId: "13d21c63-b5ec-5912-8397-c3a5ddb27a97", metaSiteId: "<META_SITE_ID>" } }]
```

#### Query Services

```
invoke_rpc:
  target: { artifactId: "com.wixpress.bookings.services-2" }
  service: "wix.bookings.services.v2.ServicesService"
  method: "QueryServices"
  payload: { "query": { "paging": { "limit": 10 } } }
  identities: [{ type: "serverSignature", serverSignature: { appDefId: "13d21c63-b5ec-5912-8397-c3a5ddb27a97", metaSiteId: "<META_SITE_ID>" } }]
```

#### Key Methods

| Method | Description |
|--------|-------------|
| `GetService` | Get by ID |
| `QueryServices` | Query with filters |
| `SearchServices` | Full-text search |
| `CreateService` | Create service |
| `UpdateService` | Update service |
| `DeleteService` | Delete service |
| `CountServices` | Count services |
| `CloneService` | Clone service |
| `SetCustomSlug` | Set URL slug |

---

### 3. Calendar Event

| Field | Value |
|-------|-------|
| Artifact | `com.wixpress.calendar.events-3` |
| Service FQDN | `wix.calendar.events.v3.EventsService` |
| Entity FQDN | `wix.calendar.v3.event` |
| App Def ID | `482f413c-67ec-4700-acb3-d64d742e7751` |

#### Get Event

```
invoke_rpc:
  target: { artifactId: "com.wixpress.calendar.events-3" }
  service: "wix.calendar.events.v3.EventsService"
  method: "GetEvent"
  payload: { "eventId": "<EVENT_ID>" }
  identities: [{ type: "serverSignature", serverSignature: { appDefId: "482f413c-67ec-4700-acb3-d64d742e7751", metaSiteId: "<META_SITE_ID>" } }]
```

#### Query Events

```
invoke_rpc:
  target: { artifactId: "com.wixpress.calendar.events-3" }
  service: "wix.calendar.events.v3.EventsService"
  method: "QueryEvents"
  payload: { "query": { "filter": "{\"scheduleId\": \"<SCHEDULE_ID>\"}", "paging": { "limit": 10 } } }
  identities: [{ type: "serverSignature", serverSignature: { appDefId: "482f413c-67ec-4700-acb3-d64d742e7751", metaSiteId: "<META_SITE_ID>" } }]
```

#### Key Methods

| Method | Description |
|--------|-------------|
| `GetEvent` | Get by ID |
| `QueryEvents` | Query with filters |
| `ListEvents` | List events |
| `CreateEvent` | Create event |
| `UpdateEvent` | Update event |
| `CancelEvent` | Cancel event |
| `SplitRecurringEvent` | Split recurring event |
| `UpdateEventParticipants` | Update participants |

---

### 4. Resource

| Field | Value |
|-------|-------|
| Artifact | `com.wixpress.bookings.resources-2` |
| Service FQDN | `wix.bookings.resources.v2.ResourcesService` |
| Entity FQDN | `wix.bookings.resources.v2.resource` |
| App Def ID | `13d21c63-b5ec-5912-8397-c3a5ddb27a97` |

#### Get Resource

```
invoke_rpc:
  target: { artifactId: "com.wixpress.bookings.resources-2" }
  service: "wix.bookings.resources.v2.ResourcesService"
  method: "GetResource"
  payload: { "resourceId": "<RESOURCE_ID>" }
  identities: [{ type: "serverSignature", serverSignature: { appDefId: "13d21c63-b5ec-5912-8397-c3a5ddb27a97", metaSiteId: "<META_SITE_ID>" } }]
```

#### Query Resources

```
invoke_rpc:
  target: { artifactId: "com.wixpress.bookings.resources-2" }
  service: "wix.bookings.resources.v2.ResourcesService"
  method: "QueryResources"
  payload: { "query": { "paging": { "limit": 10 } } }
  identities: [{ type: "serverSignature", serverSignature: { appDefId: "13d21c63-b5ec-5912-8397-c3a5ddb27a97", metaSiteId: "<META_SITE_ID>" } }]
```

#### Key Methods

| Method | Description |
|--------|-------------|
| `GetResource` | Get by ID |
| `QueryResources` | Query with filters |
| `SearchResources` | Full-text search |
| `CreateResource` | Create resource |
| `UpdateResource` | Update resource |
| `DeleteResource` | Delete resource (trash bin) |
| `CountResources` | Count resources |
| `RestoreResourceFromTrashBin` | Restore from trash |

---

### 5. Staff Member

| Field | Value |
|-------|-------|
| Artifact | `com.wixpress.bookings.staff-members` |
| Service FQDN | `wix.bookings.staff.v1.StaffMembersService` |
| Entity FQDN | `wix.bookings.staff.v1.staff_member` |
| App Def ID | `13d21c63-b5ec-5912-8397-c3a5ddb27a97` |

#### Get Staff Member

```
invoke_rpc:
  target: { artifactId: "com.wixpress.bookings.staff-members" }
  service: "wix.bookings.staff.v1.StaffMembersService"
  method: "GetStaffMember"
  payload: { "staffMemberId": "<STAFF_MEMBER_ID>" }
  identities: [{ type: "serverSignature", serverSignature: { appDefId: "13d21c63-b5ec-5912-8397-c3a5ddb27a97", metaSiteId: "<META_SITE_ID>" } }]
```

#### Query Staff Members

```
invoke_rpc:
  target: { artifactId: "com.wixpress.bookings.staff-members" }
  service: "wix.bookings.staff.v1.StaffMembersService"
  method: "QueryStaffMembers"
  payload: { "query": { "paging": { "limit": 10 } } }
  identities: [{ type: "serverSignature", serverSignature: { appDefId: "13d21c63-b5ec-5912-8397-c3a5ddb27a97", metaSiteId: "<META_SITE_ID>" } }]
```

#### Key Methods

| Method | Description |
|--------|-------------|
| `GetStaffMember` | Get by ID |
| `QueryStaffMembers` | Query with filters |
| `SearchStaffMembers` | Full-text search |
| `CreateStaffMember` | Create staff member |
| `UpdateStaffMember` | Update staff member |
| `DeleteStaffMember` | Delete (trash bin) |
| `CountStaffMembers` | Count staff members |
| `ConnectStaffMemberToUser` | Link to Wix user |
| `RestoreStaffMemberFromTrashBin` | Restore from trash |

---

### 6. Schedule

| Field | Value |
|-------|-------|
| Artifact | `com.wixpress.calendar.schedules-3` |
| Service FQDN | `wix.calendar.schedules.v3.SchedulesService` |
| Entity FQDN | `wix.calendar.v3.schedule` |
| App Def ID | `482f413c-67ec-4700-acb3-d64d742e7751` |

#### Get Schedule

```
invoke_rpc:
  target: { artifactId: "com.wixpress.calendar.schedules-3" }
  service: "wix.calendar.schedules.v3.SchedulesService"
  method: "GetSchedule"
  payload: { "scheduleId": "<SCHEDULE_ID>" }
  identities: [{ type: "serverSignature", serverSignature: { appDefId: "482f413c-67ec-4700-acb3-d64d742e7751", metaSiteId: "<META_SITE_ID>" } }]
```

#### Query Schedules

```
invoke_rpc:
  target: { artifactId: "com.wixpress.calendar.schedules-3" }
  service: "wix.calendar.schedules.v3.SchedulesService"
  method: "QuerySchedules"
  payload: { "query": { "paging": { "limit": 10 } } }
  identities: [{ type: "serverSignature", serverSignature: { appDefId: "482f413c-67ec-4700-acb3-d64d742e7751", metaSiteId: "<META_SITE_ID>" } }]
```

#### Key Methods

| Method | Description |
|--------|-------------|
| `GetSchedule` | Get by ID |
| `QuerySchedules` | Query with filters |
| `CreateSchedule` | Create schedule |
| `UpdateSchedule` | Update schedule |
| `CloneSchedule` | Clone schedule |
| `CancelSchedule` | Cancel schedule |

---

### 7. Category

| Field | Value |
|-------|-------|
| Artifact | `com.wixpress.bookings.categories` |
| Service FQDN | `wix.bookings.categories.v2.CategoriesService` |
| Entity FQDN | `wix.bookings.categories.v2.category` |
| App Def ID | `13d21c63-b5ec-5912-8397-c3a5ddb27a97` |

#### Get Category

```
invoke_rpc:
  target: { artifactId: "com.wixpress.bookings.categories" }
  service: "wix.bookings.categories.v2.CategoriesService"
  method: "GetCategory"
  payload: { "categoryId": "<CATEGORY_ID>" }
  identities: [{ type: "serverSignature", serverSignature: { appDefId: "13d21c63-b5ec-5912-8397-c3a5ddb27a97", metaSiteId: "<META_SITE_ID>" } }]
```

#### Query Categories

```
invoke_rpc:
  target: { artifactId: "com.wixpress.bookings.categories" }
  service: "wix.bookings.categories.v2.CategoriesService"
  method: "QueryCategories"
  payload: { "query": { "paging": { "limit": 10 } } }
  identities: [{ type: "serverSignature", serverSignature: { appDefId: "13d21c63-b5ec-5912-8397-c3a5ddb27a97", metaSiteId: "<META_SITE_ID>" } }]
```

#### Key Methods

| Method | Description |
|--------|-------------|
| `GetCategory` | Get by ID |
| `QueryCategories` | Query with filters |
| `CreateCategory` | Create category |
| `UpdateCategory` | Update category |
| `DeleteCategory` | Delete category |
| `CountCategories` | Count categories |
| `MoveCategory` | Reorder category |

---

### 8. Booking Fee

| Field | Value |
|-------|-------|
| Artifact | `com.wixpress.bookings.fees.booking-fees` |
| Service FQDN | `wix.bookings.fees.v1.BookingFees` |
| Entity FQDN | `wix.bookings.fees.v1.booking_fee` |
| App Def ID | `13d21c63-b5ec-5912-8397-c3a5ddb27a97` |

#### List Fees by Booking IDs

```
invoke_rpc:
  target: { artifactId: "com.wixpress.bookings.fees.booking-fees" }
  service: "wix.bookings.fees.v1.BookingFees"
  method: "ListBookingFeesByBookingIds"
  payload: { "bookingIds": ["<BOOKING_ID>"] }
  identities: [{ type: "serverSignature", serverSignature: { appDefId: "13d21c63-b5ec-5912-8397-c3a5ddb27a97", metaSiteId: "<META_SITE_ID>" } }]
```

#### Key Methods

| Method | Description |
|--------|-------------|
| `ListBookingFeesByBookingIds` | List fees for bookings |
| `ApplyBookingFeesToOrder` | Apply fees to order |
| `CollectAppliedBookingFees` | Collect applied fees |

---

### 9. Bookings Settings

| Field | Value |
|-------|-------|
| Artifact | `com.wixpress.bookings.bookings-settings` |
| Service FQDN | `wix.bookings.settings.v2.BookingsSettingsService` |
| Entity FQDN | `wix.bookings.v2.bookings_settings` |
| App Def ID | `13d21c63-b5ec-5912-8397-c3a5ddb27a97` |

#### Get Settings

```
invoke_rpc:
  target: { artifactId: "com.wixpress.bookings.bookings-settings" }
  service: "wix.bookings.settings.v2.BookingsSettingsService"
  method: "GetBookingsSettings"
  payload: {}
  identities: [{ type: "serverSignature", serverSignature: { appDefId: "13d21c63-b5ec-5912-8397-c3a5ddb27a97", metaSiteId: "<META_SITE_ID>" } }]
```

#### Key Methods

| Method | Description |
|--------|-------------|
| `GetBookingsSettings` | Get settings |
| `UpdateBookingsSettings` | Update settings |

---

### 10. Availability Calendar

| Field | Value |
|-------|-------|
| Artifact | `com.wixpress.bookings.availability.availability-calendar` |
| Service FQDN | `com.wixpress.bookings.availability.AvailabilityCalendar` |
| App Def ID | `13d21c63-b5ec-5912-8397-c3a5ddb27a97` |

#### Query Availability

```
invoke_rpc:
  target: { artifactId: "com.wixpress.bookings.availability.availability-calendar" }
  service: "com.wixpress.bookings.availability.AvailabilityCalendar"
  method: "QueryAvailability"
  payload: {
    "query": {
      "filter": {
        "serviceId": ["<SERVICE_ID>"],
        "startDate": "2025-01-01T00:00:00Z",
        "endDate": "2025-01-07T00:00:00Z"
      }
    }
  }
  identities: [{ type: "serverSignature", serverSignature: { appDefId: "13d21c63-b5ec-5912-8397-c3a5ddb27a97", metaSiteId: "<META_SITE_ID>" } }]
```

#### Key Methods

| Method | Description |
|--------|-------------|
| `QueryAvailability` | Query available slots |
| `GetSlotAvailability` | Check specific slot |
| `GetScheduleAvailability` | Schedule availability |

---

## Other Useful FireConsole Tools

### Discover Services on an Artifact

Use `list_services` to see all gRPC services and methods exposed by an artifact:

```
list_services:
  artifactId: "com.wixpress.bookings.bookings-service"
```

### Get Method Schema

Use `get_method_schema` to see the full request/response schema for any method:

```
get_method_schema:
  artifactId: "com.wixpress.bookings.bookings-service"
  service: "com.wixpress.bookings.bookings.v2.Bookings"
  method: "GetBooking"
```

### Search for Services

Use `search_services` to find artifacts, services, or methods by keyword:

```
search_services:
  query: "bookings"
  type: "artifact"
  limit: 10
```

### Get Running Instances

Use `get_instances` to find running pods for an artifact:

```
get_instances:
  artifactId: "com.wixpress.bookings.bookings-service"
```

### Find Site by URL or MetaSite ID

Use `find_site` to look up site information:

```
find_site:
  query: "<site-url-or-metasite-id>"
```

### Find User

Use `find_user` to look up user information:

```
find_user:
  query: "<email-or-user-id>"
```

### Get Client Spec Map

Use `get_client_spec_map` to see what apps are installed on a site:

```
get_client_spec_map:
  metaSiteId: "<META_SITE_ID>"
```

### Generate Server Signature

Use `generate_server_signature` to create a signed token (useful for debugging):

```
generate_server_signature:
  appDefId: "13d21c63-b5ec-5912-8397-c3a5ddb27a97"
  metaSiteId: "<META_SITE_ID>"
```

### Get CLI Command

Use `get_cli_command` to get a reproducible shell command for any RPC call:

```
get_cli_command:
  target: { artifactId: "com.wixpress.bookings.bookings-service" }
  service: "com.wixpress.bookings.bookings.v2.Bookings"
  method: "GetBooking"
  payload: { "bookingId": "<BOOKING_ID>" }
  identities: [{ type: "serverSignature", serverSignature: { appDefId: "13d21c63-b5ec-5912-8397-c3a5ddb27a97", metaSiteId: "<META_SITE_ID>" } }]
```

---

## Quick Reference

| Entity | Artifact | Service FQDN | App Def ID |
|--------|----------|-------------|-----------|
| Booking | `com.wixpress.bookings.bookings-service` | `com.wixpress.bookings.bookings.v2.Bookings` | `13d21c63-...` |
| Service | `com.wixpress.bookings.services-2` | `wix.bookings.services.v2.ServicesService` | `13d21c63-...` |
| Event | `com.wixpress.calendar.events-3` | `wix.calendar.events.v3.EventsService` | `482f413c-...` |
| Resource | `com.wixpress.bookings.resources-2` | `wix.bookings.resources.v2.ResourcesService` | `13d21c63-...` |
| Staff | `com.wixpress.bookings.staff-members` | `wix.bookings.staff.v1.StaffMembersService` | `13d21c63-...` |
| Schedule | `com.wixpress.calendar.schedules-3` | `wix.calendar.schedules.v3.SchedulesService` | `482f413c-...` |
| Category | `com.wixpress.bookings.categories` | `wix.bookings.categories.v2.CategoriesService` | `13d21c63-...` |
| Fee | `com.wixpress.bookings.fees.booking-fees` | `wix.bookings.fees.v1.BookingFees` | `13d21c63-...` |
| Settings | `com.wixpress.bookings.bookings-settings` | `wix.bookings.settings.v2.BookingsSettingsService` | `13d21c63-...` |
| Availability | `com.wixpress.bookings.availability.availability-calendar` | `com.wixpress.bookings.availability.AvailabilityCalendar` | `13d21c63-...` |

## Troubleshooting

### Authentication Errors
- Verify `metaSiteId` is correct (use `find_site` to look up)
- Ensure `appDefId` matches the entity domain (bookings vs calendar)
- Check that the site has the Bookings app installed (use `get_client_spec_map`)

### Entity Not Found
- Verify the entity ID format (should be a GUID)
- Check if the entity exists on the specified metaSite
- For deleted entities, try `GetDeleted*` or `ListDeleted*` methods

### Method Not Found
- Use `list_services` to see available methods on the artifact
- Use `get_method_schema` to verify request/response structure
- Service FQDNs are case-sensitive
