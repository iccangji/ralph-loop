# PRD Creation Through Structured Questioning

Help beginner-level developers transform software ideas into comprehensive PRD.md files through structured questioning delegated to the **grilling** skill.

## Conversation Flow

1. Introduce yourself briefly and explain you'll use the **grilling** skill for requirements elicitation
2. Invoke **grilling** skill to interview the user relentlessly until reaching a shared understanding
3. Verify project prerequisites (access, MCPs, docs, env vars, test users)
4. Create executive summary for user validation
5. Research competitive landscape (if applicable)
6. Generate comprehensive PRD.md
6. Iterate based on feedback

**CRITICAL**: Use the **grilling** skill for all structured questioning. It handles the interview tree, rounds, recommended answers, and shared understanding mapping. Do NOT inline questioning prose or AskUserQuestion patterns here.

## Topics to Cover

Gather information on these aspects through **grilling**:

1. Core features and functionality
2. Target audience
3. Platform (web, mobile, desktop)
4. User flows (how users move through the app)
5. UI/UX concepts
6. Data storage and management
7. Authentication (if relevant) and security
8. Third-party integrations (if relevant)
9. [optional] Wireframes or diagrams
10. [optional] Competitive landscape
11. Execution prerequisites: database access, service access, MCPs, documentation, environment variables, and login/test users
12. Dependencies

## PRD Creation Workflow

**CRITICAL**: Don't create the PRD until you have all necessary information, including needed libraries, frameworks, 3rd party integrations, etc. Use **grilling** skill for all clarification.

Copy and track progress through these steps:

```
PRD Progress:
- [ ] Gather all required information via grilling skill
- [ ] Verify project prerequisites and create `.env.local` placeholders
- [ ] Create executive summary for user validation
- [ ] Get user confirmation to proceed
- [ ] Research competitive landscape (if not done)
- [ ] Generate comprehensive PRD
- [ ] Present and gather feedback
- [ ] Iterate based on feedback
```

### Step 1: Gather Information and Verify Prerequisites

Invoke **grilling** skill to:
- Clarify core features that are unclear
- Present technology options and user preferences with trade-offs
- Resolve priorities between conflicting requirements
- Surface assumptions that could significantly impact the PRD

#### Mandatory Prerequisite Gate

Before finalizing Step 1 or moving to executive summary validation, verify what the implementation needs to run and be tested.

Explore the repository first when possible. Look for `.env`, `.env.example`, `.env.local`, config files, package dependencies, database clients, migrations/schema files, SDK imports, auth routes, README setup instructions, and existing test credentials or seed data. If a question can be answered by exploring the codebase, explore the codebase instead of asking the user.

Collect and document:
- Database access requirements and whether the agent/user can verify connectivity
- Required MCP servers/tools and whether they are installed and authenticated
- Required third-party service accounts, API dashboards, CLIs, SDKs, or docs
- Required environment variable names, where they are written, and what each variable is used for
- Login/test user requirements, including role, permissions, and how to create or request the user
- Any local setup commands needed before implementation or verification

Create or update `PROJECT_ROOT/.env.local` during this step with placeholder values for every required environment variable name discovered. Never write real secret values, passwords, API keys, tokens, or connection strings. If `.env.local` already exists, preserve existing values and append missing variable names with placeholders only. Make it clear to the user that they must add real values manually.

In the PRD, record environment variable names and the target file path only. Do not include secret values or real credentials. Example:

```markdown
- `STRIPE_SECRET_KEY`: required for Stripe server API calls; written to `PROJECT_ROOT/.env.local`; value must be filled manually by the user.
```

If any prerequisite cannot be verified, ask the user case-by-case whether to block PRD finalization until it is resolved or proceed with an explicit prerequisite gap. Record the decision in the PRD.

### Step 2: Executive Summary Validation

Before writing the full PRD:
1. Summarize in 2-3 paragraphs: problem solved, target users, core value proposition, key features, key user flows
2. List main assumptions you're making
3. Ask: "Does this accurately capture your vision? Should I proceed with the full PRD?"
4. **Only continue after confirmation**

### Step 3: Competitive Research

If this is a commercial app with a potential revenue model, you should research the competitive landscape to identify differentiators and opportunities.

Use WebSearch to:
- Find similar products: "[app category] apps 2026", "best [problem space] tools"
- Identify differentiators
- Use the findings to further refine the PRD
- For each identified differentiator, use **grilling** skill to clarify if it should be included in the PRD

### Step 4: Generate PRD

Create PRD containing all identified requirements and use an ID to track each requirement, formatted as `TASK-${ID}`. Reserve `TASK-1` for prerequisite verification in the generated implementation tasks. Start feature and implementation requirement IDs at `TASK-2`.

Include the following sections:
- App overview, objectives and success criteria
- Short summary of target audience
- (for commercial apps): Competitive landscape and differentiation
- Core features and functionality
- Key user flows and journeys
- Technical stack recommendations
- Prerequisites and access
- Conceptual data model
- UI design principles (include wireframe analysis if provided)
- Security considerations
- Development phases/milestones
- Assumptions and dependencies

The `Prerequisites and Access` section must include:
- Database access status
- Required MCPs and authentication status
- Required service documentation links
- Required environment variable names and the target file path where placeholders were written
- Login/test user requirements without passwords or secret values
- Open prerequisite gaps and the user's proceed/block decision for each gap

Save as: `PROJECT_ROOT/.agent/prd/PRD.md`

### Step 5: Iterate

Ask specific questions about sections rather than general feedback. Use Sequential Thinking for systematic feedback processing. Present revised version with change explanations.

## Developer Handoff Guidelines

Optimize for handoff to engineers (human or AI):

- Include implementation details without prescriptive code
- Define clear acceptance criteria per feature
- Use terminology mappable to code components
- Structure data models with explicit field names, types, relationships
- Specify technical constraints and API integration points
- Organize features in logical sprint groupings
- Include pseudocode for complex features
- Link to relevant technology documentation

## Specification Examples

**Feature Specification:**
```
User Authentication Feature:
- Support email/password and OAuth 2.0 (Google, Apple) login methods
- Implement JWT token-based session management
- Required user profile fields: email (string, unique), name (string), avatar (image URL)
- Acceptance criteria: Users can create accounts, log in via both methods, recover passwords, and maintain persistent sessions across app restarts
```

**User Flow:**
```
Content Creation Flow:
1. User clicks 'Create' button on dashboard
2. User selects content type (text post, image, video)
3. User fills in content details (title, description, tags)
4. User previews content before publishing
5. User clicks 'Publish' → Content appears in their profile feed
6. User can share via native share sheet (iOS/Android) or copy link (Web)
- Error states: Handle upload failures, size limits exceeded, network timeouts
```

## Wireframe Analysis

When users provide wireframes or mockups:

1. Use Read tool to view image files
2. For each screen, identify:
   - UI components (buttons, forms, navigation)
   - User interactions (taps, swipes, submissions)
   - State changes on interaction
   - Navigation flow between screens
   - Data sources
3. Use **grilling** skill for clarifying questions:
   - "What happens when the user clicks [element]?"
   - "Where does [data/content] come from?"
   - "What error states should we handle?"
4. Include insights in PRD's "UI Design Principles" section
5. Map to user flows in "Key User Flows" section

## After PRD Completion

Once the PRD is complete and approved, inform the user:
"Your PRD is complete and saved. Would you like me to proceed to the next step and generate implementation tasks for developers? See [JSON.md](JSON.md)."

**CRITICAL**: Make the plan extremely concise. Sacrifice grammar for the sake of concision.

---

## Checklist

Before saving the PRD:

- [ ] Used **grilling** skill for structured questioning
- [ ] Incorporated user's answers from grilling rounds
- [ ] Verified prerequisites before executive summary validation
- [ ] Created or updated `PROJECT_ROOT/.env.local` with placeholder values only
- [ ] Documented required environment variable names without secret values
- [ ] User stories are small and specific
- [ ] Functional requirements are numbered and unambiguous
- [ ] Non-goals section defines clear boundaries
- [ ] Saved to `PROJECT_ROOT/.agent/prd/PRD.md`