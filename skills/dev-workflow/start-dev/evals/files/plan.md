# Feature Plan: User Profile Avatars

## Goal
Allow users to upload and display a profile avatar image.

## Tasks

1. **Add avatar upload endpoint** — `POST /api/users/:id/avatar`
   - Accept multipart/form-data with `image` field
   - Validate file type (JPEG, PNG, WebP only) and size (max 2 MB)
   - Store file to `uploads/avatars/<user-id>.<ext>`
   - Return `{ avatarUrl: string }` on success

2. **Expose avatarUrl in user profile endpoint** — `GET /api/users/:id`
   - Add `avatarUrl` field to response (null if not set)

3. **Add integration tests**
   - Upload a valid image → 200 with avatarUrl
   - Upload oversized file → 400
   - Upload invalid type → 400
   - GET profile after upload → avatarUrl is present

## Acceptance criteria
- All three existing user tests continue to pass
- New integration tests pass
- No secrets committed
