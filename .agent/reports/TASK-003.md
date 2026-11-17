# TASK-003: Write API tests with Vitest + supertest

## Summary
Verified that comprehensive API tests already exist and pass for all 5 CRUD endpoints.

## Files Verified
- `workspace/simple-notes-api/tests/setup.ts` - Test database setup/teardown (in-memory SQLite)
- `workspace/simple-notes-api/tests/notes.test.ts` - Test suites for all 5 endpoints

## Test Coverage (23 tests total)

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

### PUT /api/notes/:id (8 tests)
- Returns 404 for unknown UUID
- Returns 400 for invalid UUID format
- Returns 400 for empty title
- Returns 400 for title too long (>200 chars)
- Returns 400 for content too long (>10000 chars)
- Returns 200 with updated note when updating title only
- Returns 200 with updated note when updating content only
- Returns 200 with updated note when updating both fields

### DELETE /api/notes/:id (3 tests)
- Returns 404 for unknown UUID
- Returns 400 for invalid UUID format
- Returns 204 on successful delete

## Verification
```
npm test
# All 23 tests pass in 103ms
```

## Acceptance Criteria Met
- ✅ npm test runs and all tests pass
- ✅ Test coverage includes success + error paths for each of the 5 endpoints