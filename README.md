# GemSlice

A web-based **3D Print Asset Manager & Cloud Slicer** — upload STL/3MF files, organize them in projects, configure print settings on an interactive build plate, trigger cloud-based slicing with OrcaSlicer, and download G-code with injected color-swap pause commands for multi-color prints.

Built with **Ruby on Rails 8.1** (API) + **Vue 3** (SPA) + **Three.js** (3D) + **Sidekiq** (background jobs) + **PostgreSQL** (Supabase-hosted).

---

## Tech Stack

### Backend
| Technology | Version | Purpose |
|---|---|---|
| Ruby | 3.4.9 | Language |
| Rails | 8.1.3 | API-only web framework |
| PostgreSQL | — | Database (hosted on Supabase) |
| Redis | 7 Alpine | Sidekiq job queue broker |
| Sidekiq | ~7.0 | Background job processing |
| Devise + devise-jwt | — | Authentication (JWT tokens) |
| Active Storage | — | File uploads (STL, 3MF, G-code) |
| OrcaSlicer | 2.3.2 | CLI slicer (runs headless in Docker) |
| Puma | ≥5.0 | HTTP server |
| Docker | — | Containerized development & deployment |

### Frontend
| Technology | Version | Purpose |
|---|---|---|
| Vue 3 | 3.5.34 | UI framework (Composition API) |
| Vue Router | 4.6.4 | Client-side routing |
| Pinia | 3.0.4 | State management |
| Three.js | 0.184.0 | 3D rendering (STL viewer, G-code preview) |
| Axios | 1.16.1 | HTTP client with JWT interceptor |
| Vite | 8.0.12 | Build tool & dev server |
| Tailwind CSS | 4.3.0 | Utility-first CSS |
| fflate | 0.8.3 | Zlib decompression (3MF parsing) |

### Infrastructure
| Service | Purpose |
|---|---|
| Supabase | Hosted PostgreSQL database |
| Docker Compose | Local dev orchestration (api, sidekiq, redis) |
| Kamal | Production container deployment |

---

## Features

### Project Management
- Create, edit, and delete projects
- Upload STL and 3MF files via drag-and-drop
- Tag assets for organization
- Per-user data isolation (JWT auth)

### Interactive 3D Build Plate
- Render STL and 3MF models with Three.js
- **Transform controls** — translate, rotate, scale objects with gizmos or precise numeric inputs
- **Multi-object scenes** — load multiple assets onto the same build plate
- **Multi-plate tabs** — organize objects across multiple virtual plates
- **Auto-orient** — algorithmically find the optimal print orientation (scores by overhang area vs flat base contact)
- **Undo/redo** — 30-step history stack (Ctrl+Z / Ctrl+Y)
- **Clipboard** — cut (Ctrl+X), copy (Ctrl+C), paste (Ctrl+V) objects
- **Drag-and-drop** — drop STL/3MF files directly onto the viewport
- **Reactive bed size** — build plate grid updates when bed dimensions change
- **Scene export** — combine all objects into a single binary STL with Y↔Z axis swap for slicer compatibility
- **Persistent state** — plate layouts, transforms, and plate assignments saved to localStorage and restored on navigation

### Cloud Slicing
- **OrcaSlicer CLI** running headless in Docker containers
- Configurable print settings:
  - Layer height, first layer height
  - Infill density and pattern
  - Wall count, top/bottom shell layers
  - Support (on/off, type, density)
  - Brim width, skirt loops
  - Print speed, nozzle diameter
  - Bed dimensions (width × depth)
- Base profiles from Creality Ender-3 V3 presets with user overrides merged at runtime
- Position preservation (`--arrange 0`) to respect build plate layout
- Explicit brim control (prevents OrcaSlicer's default `auto_brim`)

### G-code Post-Processing
- **Color swap injection** — insert M600 (filament change) or M400 U1 (pause/resume) commands at specified layers
- Line-by-line processing (memory-efficient for 100MB+ files)
- Metadata extraction: estimated print time, material usage
- Layer tracking via OrcaSlicer `;LAYER_CHANGE` / `;Z:` comments

### G-code Preview
- Layer-by-layer 3D visualization of sliced G-code
- Layer slider to scrub through the print
- Color-coded toolpaths
- Build plate grid overlay

### Authentication
- Email/password registration and login
- JWT tokens (24h expiry) with JTI revocation on logout
- Automatic 401 → redirect to login
- All API endpoints require authentication

---

## Architecture

```
┌─────────────────────┐         JSON/JWT        ┌──────────────────────────┐
│   Vue 3 SPA         │  ◄───── /api/v1/ ─────► │   Rails 8.1 API          │
│   (Port 5173)       │       HTTP requests      │   (Port 3000)            │
│                     │                          │                          │
│  ┌───────────────┐  │                          │  ┌────────────────────┐  │
│  │ Pinia Stores  │  │                          │  │ Devise + JWT Auth  │  │
│  │ auth/projects │  │                          │  │ Controllers        │  │
│  │ assets/slice  │  │                          │  │ Models + Services  │  │
│  └───────────────┘  │                          │  └────────────────────┘  │
│                     │                          │           │              │
│  ┌───────────────┐  │                          │  ┌────────▼───────────┐  │
│  │ Three.js      │  │                          │  │ Sidekiq Workers    │  │
│  │ STL Viewer    │  │                          │  │ (queue: slicing)   │  │
│  │ Gcode Preview │  │                          │  └────────┬───────────┘  │
│  └───────────────┘  │                          │           │              │
└─────────────────────┘                          │  ┌────────▼───────────┐  │
                                                 │  │ OrcaSlicer CLI     │  │
                                                 │  │ GcodePostProcessor │  │
                                                 │  └────────────────────┘  │
                                                 │           │              │
                                                 │  ┌────────▼───────────┐  │
                                                 │  │ PostgreSQL         │  │
                                                 │  │ (Supabase)         │  │
                                                 │  │ Active Storage     │  │
                                                 │  │ Redis              │  │
                                                 │  └────────────────────┘  │
                                                 └──────────────────────────┘
```

---

## Database Schema

```
User
 └─► Project (1:N)
      └─► PrintAsset (1:N)
            ├─► SliceJob (1:N)
            │    ├─► ColorSwap (1:N)
            │    ├─► output_gcode (Active Storage)
            │    └─► scene_file (Active Storage)
            ├─► AssetTag (1:N) ──► Tag (N:M)
            └─► source_file (Active Storage)
```

### Tables

| Table | Key Columns | Purpose |
|---|---|---|
| `users` | email, encrypted_password, jti | Authentication (Devise) |
| `projects` | name, description, user_id | Organize assets |
| `print_assets` | name, file_type, notes, project_id | STL/3MF/G-code files |
| `slice_jobs` | status (enum 0-4), slicer, estimated_time, material_used, error_message, print_asset_id | Slicing job tracking |
| `color_swaps` | layer_number, pause_type, color_label, slice_job_id | Filament change pauses |
| `tags` | name (unique, case-insensitive) | Asset categorization |
| `asset_tags` | print_asset_id, tag_id | Join table |
| `active_storage_blobs` | filename, content_type, byte_size, checksum | File metadata |
| `active_storage_attachments` | name, record_type, record_id, blob_id | Polymorphic file links |

**Slice Job Status Enum**: `pending(0)` → `slicing(1)` → `post_processing(2)` → `completed(3)` | `failed(4)`

---

## API Endpoints

### Authentication
| Method | Path | Description |
|---|---|---|
| POST | `/api/v1/login` | Login, returns JWT in Authorization header |
| DELETE | `/api/v1/logout` | Logout, revokes JWT |
| POST | `/api/v1/signup` | Register new user |

### Projects
| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/projects` | List user's projects |
| POST | `/api/v1/projects` | Create project |
| GET | `/api/v1/projects/:id` | Get project with assets |
| PATCH | `/api/v1/projects/:id` | Update project |
| DELETE | `/api/v1/projects/:id` | Delete project and all assets |

### Print Assets
| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/projects/:project_id/print_assets` | List assets |
| POST | `/api/v1/projects/:project_id/print_assets` | Upload asset (multipart) |
| GET | `/api/v1/projects/:project_id/print_assets/:id` | Get asset with latest slice job |
| PATCH | `/api/v1/projects/:project_id/print_assets/:id` | Update asset |
| DELETE | `/api/v1/projects/:project_id/print_assets/:id` | Delete asset |

### Slice Jobs
| Method | Path | Description |
|---|---|---|
| POST | `/api/v1/print_assets/:print_asset_id/slice` | Start slicing job |
| GET | `/api/v1/slice_jobs/:id` | Poll job status |
| GET | `/api/v1/slice_jobs/:id/download` | Download output G-code |
| GET | `/api/v1/slice_jobs/:id/gcode_text` | Get raw G-code text |
| PATCH | `/api/v1/slice_jobs/:id/cancel` | Cancel job |

---

## Project Structure

```
gemslice/
├── layerhub_api/                          # Rails API backend
│   ├── app/
│   │   ├── controllers/api/v1/           # REST controllers
│   │   │   ├── projects_controller.rb
│   │   │   ├── print_assets_controller.rb
│   │   │   ├── slice_jobs_controller.rb
│   │   │   ├── sessions_controller.rb
│   │   │   └── registrations_controller.rb
│   │   ├── models/                        # ActiveRecord models
│   │   │   ├── user.rb                    # Devise + JWT auth
│   │   │   ├── project.rb
│   │   │   ├── print_asset.rb
│   │   │   ├── slice_job.rb               # Status enum + attachments
│   │   │   ├── color_swap.rb
│   │   │   ├── tag.rb
│   │   │   └── asset_tag.rb
│   │   ├── services/
│   │   │   ├── gcode_post_processor.rb    # Color swap injection
│   │   │   └── slicers/
│   │   │       ├── base_slicer.rb         # Abstract base
│   │   │       └── orca_slicer.rb         # OrcaSlicer CLI wrapper
│   │   └── workers/
│   │       └── slice_worker.rb            # Sidekiq background job
│   ├── config/
│   │   ├── routes.rb                      # API routes
│   │   ├── database.yml                   # PostgreSQL (Supabase)
│   │   └── initializers/
│   │       ├── cors.rb                    # CORS for Vue
│   │       ├── devise.rb                  # JWT config
│   │       └── sidekiq.rb                 # Queue config
│   ├── db/
│   │   ├── schema.rb                      # Full schema
│   │   └── migrate/                       # 8 migrations
│   ├── Dockerfile.dev                     # Dev image + OrcaSlicer
│   ├── docker-compose.yml                 # api + sidekiq + redis
│   └── Gemfile
│
├── layerhub_ui/                           # Vue 3 SPA frontend
│   ├── src/
│   │   ├── main.js                        # App bootstrap
│   │   ├── App.vue                        # Root layout + nav
│   │   ├── api/
│   │   │   └── client.js                  # Axios + JWT interceptor
│   │   ├── router/
│   │   │   └── index.js                   # 5 routes + auth guard
│   │   ├── stores/                        # Pinia state
│   │   │   ├── auth.js                    # Login/register/logout
│   │   │   ├── projects.js                # CRUD projects
│   │   │   ├── assets.js                  # Upload/manage assets
│   │   │   └── slice.js                   # Slice jobs + polling
│   │   ├── views/                         # Page components
│   │   │   ├── LoginView.vue
│   │   │   ├── RegisterView.vue
│   │   │   ├── DashboardView.vue          # Project list
│   │   │   ├── ProjectDetailView.vue      # Asset list + upload
│   │   │   └── AssetDetailView.vue        # Build plate + slicer
│   │   └── components/                    # Reusable components
│   │       ├── StlViewer.vue              # 3D model viewer
│   │       └── GcodePreview.vue           # G-code layer viewer
│   ├── vite.config.js                     # Dev server + proxy
│   └── package.json
│
├── learning.md                            # Technical notes
└── PLAN.md                                # Architecture plan
```

---

## Getting Started

### Prerequisites
- Docker & Docker Compose
- Node.js ≥ 18
- A Supabase project (or any PostgreSQL instance)

### Backend Setup

```bash
cd layerhub_api

# Create .env with database credentials
cat > .env << 'EOF'
DATABASE_URL=postgresql://user:pass@host:5432/gemslice
REDIS_URL=redis://redis:6379/0
DEVISE_JWT_SECRET_KEY=your-secret-key-here
RAILS_MASTER_KEY=your-master-key
EOF

# Start all services (api + sidekiq + redis)
docker compose up -d --build

# Run database migrations
docker compose exec api rails db:create db:migrate
```

The API server runs at `http://localhost:3000`.

### Frontend Setup

```bash
cd layerhub_ui

npm install
npm run dev
```

The dev server runs at `http://localhost:5173` with proxy to the API.

### Deploy Changes

The backend code is volume-mounted in Docker. To pick up Ruby changes:

```bash
docker compose restart sidekiq
```

---

## Slicing Pipeline

```
1. User arranges models on build plate (StlViewer.vue)
2. User configures print settings (layer height, infill, support, etc.)
3. User clicks "Slice Now"
   └─► Frontend exports scene as binary STL (Y↔Z axis swap)
   └─► POST /api/v1/print_assets/:id/slice (multipart: scene_file + settings JSON)
4. Rails creates SliceJob (status: pending) + enqueues SliceWorker
5. SliceWorker runs in Sidekiq:
   a. Acquires row-level lock, transitions to :slicing
   b. Downloads input STL to temp directory
   c. Builds OrcaSlicer presets (process + machine JSON with user overrides)
   d. Runs: orca-slicer --slice 0 --arrange 0 --load-settings "machine.json;process.json" input.stl
   e. Validates output G-code completeness (checks for end markers)
   f. Transitions to :post_processing
   g. GcodePostProcessor injects color swap pauses at specified layers
   h. Attaches output G-code to Active Storage
   i. Transitions to :completed with estimated_time + material_used
6. Frontend polls GET /api/v1/slice_jobs/:id every 3 seconds
7. On completed: fetches G-code text, renders GcodePreview
8. User can download the processed G-code file
```

---

## Race Condition Protections

### Frontend
- **`loadingUrls` Set** — prevents timing-window duplicates by tracking in-flight model loads
- **`unmounted` flag** — cancels async operations if component destroys during load
- **`plateRestored` flag** — prevents `loadOtherAssets()` from re-adding models after plate restore
- **`isAssetOnAnyPlate()` check** — deduplicates across all plates before any load
- **Plate assignment metadata** — `{assetId: plateId}` map in localStorage routes models to correct plates regardless of load order
- **Exponential retry backoff** — `loadOtherAssets` retries with 200ms × 1.5^n delay, max 25 attempts

### Backend
- **Row-level locking** (`with_lock` / SELECT FOR UPDATE) on all SliceJob state transitions
- **Isolated temp directories** — `Dir.mktmpdir` per job prevents file collisions
- **G-code completeness validation** — checks for slicer end markers before accepting output
- **Atomic attach + status update** — locked together to prevent duplicate attachments

---

## Keyboard Shortcuts (Build Plate)

| Shortcut | Action |
|---|---|
| Ctrl+Z | Undo |
| Ctrl+Y | Redo |
| Ctrl+C | Copy selected object |
| Ctrl+X | Cut selected object |
| Ctrl+V | Paste object |
| Delete / Backspace | Delete selected object |

---

## License

Private — All rights reserved.
