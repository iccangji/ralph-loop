# Graph Report - workspace  (2026-11-17)

## Corpus Check
- 22 files · ~5,336 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 8 file(s) not represented in the graph (top: (none) 6, .css 2)

## Summary
- 203 nodes · 286 edges · 12 communities (11 shown, 1 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 1 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `1eb0f83b`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- compilerOptions
- simple-notes-webapp/package.json
- notes.ts
- simple-notes-api/package.json
- compilerOptions
- scripts
- compilerOptions
- App.tsx
- .oxlintrc.json
- api
- React + TypeScript + Vite
- simple-notes-webapp/tsconfig.json

## God Nodes (most connected - your core abstractions)
1. `compilerOptions` - 18 edges
2. `compilerOptions` - 15 edges
3. `compilerOptions` - 15 edges
4. `Note` - 9 edges
5. `App()` - 9 edges
6. `UpdateNoteInput` - 7 edges
7. `api` - 6 edges
8. `webapp` - 6 edges
9. `handleResponse()` - 6 edges
10. `NoteForm()` - 6 edges

## Surprising Connections (you probably didn't know these)
- `NoteListProps` --references--> `Note`  [EXTRACTED]
  simple-notes-webapp/src/components/NoteList.tsx → simple-notes-webapp/src/types.ts
- `NoteDetailProps` --references--> `Note`  [EXTRACTED]
  simple-notes-webapp/src/components/NoteDetail.tsx → simple-notes-webapp/src/types.ts
- `NoteDetailProps` --references--> `UpdateNoteInput`  [EXTRACTED]
  simple-notes-webapp/src/components/NoteDetail.tsx → simple-notes-webapp/src/types.ts
- `NoteFormProps` --references--> `CreateNoteInput`  [EXTRACTED]
  simple-notes-webapp/src/components/NoteForm.tsx → simple-notes-webapp/src/types.ts
- `NoteFormProps` --references--> `Note`  [EXTRACTED]
  simple-notes-webapp/src/components/NoteForm.tsx → simple-notes-webapp/src/types.ts

## Import Cycles
- None detected.

## Communities (12 total, 1 thin omitted)

### Community 0 - "compilerOptions"
Cohesion: 0.11
Nodes (17): compilerOptions, declaration, declarationMap, esModuleInterop, forceConsistentCasingInFileNames, lib, module, moduleResolution (+9 more)

### Community 1 - "simple-notes-webapp/package.json"
Cohesion: 0.09
Nodes (28): oxlint, react-dom, @types/react, @types/react-dom, vite, @vitejs/plugin-react, dependencies, react@^19.3.1 (+20 more)

### Community 2 - "notes.ts"
Cohesion: 0.13
Nodes (17): better-sqlite3, express, uuid, zod, dependencies, better-sqlite3@^11.0.0, express@^4.19.2, uuid@^10.0.0 (+9 more)

### Community 3 - "simple-notes-api/package.json"
Cohesion: 0.10
Nodes (23): supertest, tsx, @types/better-sqlite3, @types/express, @types/supertest, @types/uuid, vitest, description (+15 more)

### Community 4 - "compilerOptions"
Cohesion: 0.10
Nodes (19): compilerOptions, allowArbitraryExtensions, allowImportingTsExtensions, erasableSyntaxOnly, jsx, lib, module, moduleDetection (+11 more)

### Community 5 - "scripts"
Cohesion: 0.40
Nodes (5): scripts, build, dev, start, test

### Community 6 - "compilerOptions"
Cohesion: 0.12
Nodes (16): compilerOptions, allowImportingTsExtensions, erasableSyntaxOnly, lib, module, moduleDetection, noEmit, noFallthroughCasesInSwitch (+8 more)

### Community 7 - "App.tsx"
Cohesion: 0.21
Nodes (20): react, createNote(), deleteNote(), getAllNotes(), getNoteById(), handleResponse(), updateNote(), App() (+12 more)

### Community 8 - ".oxlintrc.json"
Cohesion: 0.33
Nodes (5): plugins, rules, react/only-export-components, react/rules-of-hooks, $schema

### Community 9 - "api"
Cohesion: 0.10
Nodes (21): build, condition, environment, healthcheck, ports, volumes, context, dockerfile (+13 more)

### Community 10 - "React + TypeScript + Vite"
Cohesion: 0.50
Nodes (3): Expanding the Oxlint configuration, React Compiler, React + TypeScript + Vite

## Knowledge Gaps
- **1 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `react` connect `App.tsx` to `simple-notes-webapp/package.json`?**
  _High betweenness centrality (0.037) - this node is a cross-community bridge._
- **Should `compilerOptions` be split into smaller, more focused modules?**
  _Cohesion score 0.1111111111111111 - nodes in this community are weakly interconnected._
- **Should `simple-notes-webapp/package.json` be split into smaller, more focused modules?**
  _Cohesion score 0.08735632183908046 - nodes in this community are weakly interconnected._
- **Should `notes.ts` be split into smaller, more focused modules?**
  _Cohesion score 0.13438735177865613 - nodes in this community are weakly interconnected._
- **Should `simple-notes-api/package.json` be split into smaller, more focused modules?**
  _Cohesion score 0.09971509971509972 - nodes in this community are weakly interconnected._
- **Should `compilerOptions` be split into smaller, more focused modules?**
  _Cohesion score 0.1 - nodes in this community are weakly interconnected._
- **Should `compilerOptions` be split into smaller, more focused modules?**
  _Cohesion score 0.11764705882352941 - nodes in this community are weakly interconnected._