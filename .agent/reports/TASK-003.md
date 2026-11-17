# TASK-003: Write API tests with Vitest + supertest

## Summary
Implemented comprehensive Vitest + supertest tests for all 5 CRUD endpoints in the Express API.

## Files Created
- `workspace/simple-notes-api/tests/setup.ts` - Test database setup using in-memory SQLite
- `workspace/simple-notes-api/tests/notes.test.ts` - Complete test suite with 23 tests covering all endpoints

## Files Modified (from TASK-002)
- `workspace/simple-notes-api/src/index.ts` - Already had notes router mounted
- `workspace/simple-notes-api/src/routes/notes.ts` - Already implemented all 5 endpoints with Zod validation
- `workspace/simple-notes-api/src/db.ts` - Already configured for in-memory DB in test env

## Test Coverage (23 tests)
### GET /api/notes (2 tests)
- Returns empty array when no notes exist
- Returns all notes ordered by updated_at DESC

### GET /api/notes/:id (3 tests)
- Returns 404 for unknown UUID
- Returns 400 for invalid UUID format
- Returns 200 with note for existing UUID

### POST /api/notes (7 tests)
- Returns 400 for missing title
- Returns 400 for empty title
- Returns 400 for missing content
- Returns 400 for empty content
- Returns 400 for title too long (>200 chars)
- Returns 400 for content too long (>10000 chars)
- Returns 201 with created note on success

### PUT /api/notes/:id (7 tests)
- Returns 404 for unknown UUID
- Returns 400 for invalid UUID format
- Returns 400 for empty title
- Returns 400 for title too long
- Returns 400 for content too long
- Returns 200 with updated note when updating title only
- Returns 200 with updated note when updating content only
- Returns 200 with updated note when updating both fields

### DELETE /api/notes/:id (3 tests)
- Returns 404 for unknown UUID
- Returns 400 for invalid UUID format
- Returns 204 on successful delete

## Verification
- All 23 tests pass: `npm test` ✓
- Build passes: `npm run build` ✓
- Manual endpoint testing confirms all endpoints work correctly ✓
- Error responses match expected format (400 for validation, 404 for not found) ✓

## Acceptance Criteria Met
- [x] `npm test` runs and all tests pass
- [x] Test coverage includes success + error paths for each of the 5 endpoints