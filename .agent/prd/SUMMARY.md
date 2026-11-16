# Simple Notes App (API + Webapp)

## Overview
A simple notes application consisting of:
1. **API**: Express.js + TypeScript + SQLite (via Better-SQLite3 / Kysely / Drizzle or plain sqlite) with Zod validation.
2. **Webapp**: React + Vite single page application connected to the API via dev proxy.

## Architecture & Data Model
- DB: SQLite table `notes` with columns (`id` TEXT PRIMARY KEY, `title` TEXT, `content` TEXT, `created_at` TEXT, `updated_at` TEXT).
- API Base Path: `/api/notes`
- Endpoints:
  - `GET /api/notes`: List all notes (ordered by updated_at desc)
  - `GET /api/notes/:id`: Get note by ID
  - `POST /api/notes`: Create note (`title`, `content`)
  - `PUT /api/notes/:id`: Update note (`title`, `content`)
  - `DELETE /api/notes/:id`: Delete note by ID
- UI: Single-page React app with inline list, view, create, edit, and delete functionality.
