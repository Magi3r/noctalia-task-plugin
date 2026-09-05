# Tasks

A task and todo management plugin for Noctalia with native TaskChampion sync server support via Taskwarrior 3.x. Manage, track, and complete tasks from the status bar, desktop widget, launcher, or an interactive panel.

## Plugin

| Field | Value |
| --- | --- |
| ID | `magi3r/noctalia-task-plugin` |
| Entries | Bar widget: `bar`; panel: `panel`; desktop widget: `desktop`; launcher provider: `launcher`; service: `service` |
| Launcher Prefix | `/todo` |

## Requirements

Install `task` (Taskwarrior 3.x) on `PATH` (or configure its path in settings via `task_binary`).

To enable remote synchronization across devices, configure your TaskChampion sync server credentials in Taskwarrior:

```sh
# Configure sync server URL, client ID, and encryption secret
task config sync.server.url https://your-taskchampion-server.example.com
task config sync.server.client_id <YOUR_CLIENT_UUID>
task config sync.encryption_secret <YOUR_SECRET_KEY>

# Verify connection with an initial sync
task sync
```

## Usage

### Bar Widget (`bar`)

Add the **Tasks** widget (`magi3r/noctalia-task-plugin:bar`) in Noctalia Settings (**Bar** → **Widgets**).
- **Status Display**: Shows the pending task count and a checklist icon (changes color during sync).
- **Tooltip**: Hover to preview top urgent pending tasks, due dates, and last sync timestamp.
- **Left-Click**: Toggles the Tasks panel.
- **Middle-Click**: Triggers an immediate TaskChampion sync.

### Panel (`panel`)

Toggle the panel via the bar widget or with the IPC command:

```sh
noctalia msg panel-toggle magi3r/noctalia-task-plugin:panel
```

**Workflow**:
- **View & Filter**: Switch between `Pending`, `Completed`, and `All` tabs. Filter by project via the dropdown, or use the search bar to filter tasks in real-time by description, project, and tags.
- **Create Tasks**: Click **New Task** (`+`) to open the creation form. Enter a description, priority (`None`, `Low`, `Med`, `High`), project, due date (e.g. `today`, `tomorrow`, `YYYY-MM-DD`), and comma-separated tags. Click **Create Task** or press Enter.
- **Manage Tasks**: Click the checkbox on any task to toggle its completion status. Click the trash icon to delete a task.
- **Manual Sync**: Click the refresh button in the header to sync immediately with TaskChampion.

### Desktop Widget (`desktop`)

Add the **Tasks** desktop widget (`magi3r/noctalia-task-plugin:desktop`) to your desktop layout in Noctalia Settings.
- Displays urgent pending tasks directly on your desktop wallpaper layer.
- Click the checkbox on any task item to complete it directly from the desktop.
- Click the refresh icon to sync, or the plus icon to open the panel.

### Launcher Provider (`launcher`)

Type `/todo` in the Noctalia launcher followed by an optional search query (e.g. `/todo write report`).
- Searches through pending tasks using fuzzy matching across descriptions and projects.
- Activating a result (pressing Enter) marks that task as completed and displays a notification toast.

### Service (`service`)

A headless background service that runs automatically when the plugin is enabled. It monitors task state, periodically polls Taskwarrior, and synchronizes with your TaskChampion server in the background and on task changes.

## Settings

### Plugin Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `task_binary` | `string` | `"task"` | Executable name or absolute path to the Taskwarrior binary on `PATH`. |
| `auto_sync` | `bool` | `true` | Periodically synchronize tasks with the TaskChampion server in the background. |
| `sync_interval_mins` | `int` | `10` | Frequency of automatic background synchronization in minutes (set to `0` to disable periodic timer). |
| `sync_on_change` | `bool` | `true` | Trigger synchronization immediately after adding, completing, or deleting a task. |
| `show_completed` | `bool` | `false` | Display completed tasks in the panel and desktop widget by default. |
| `notify_on_sync` | `bool` | `false` | Show a desktop notification if a sync error occurs. |

### Widget Settings

**Bar Widget (`bar`)**

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `show_count` | `bool` | `true` | Display the pending task count next to the icon. |
| `glyph` | `glyph` | `"checklist"` | Icon displayed on the status bar widget. |

**Desktop Widget (`desktop`)**

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `desktop_max_tasks` | `int` | `8` | Maximum number of pending tasks displayed on the desktop widget. |

## IPC

Send IPC commands to the background service:

```sh
# Trigger TaskChampion background sync
noctalia msg plugin magi3r/noctalia-task-plugin:service all SYNC

# Reload local task data from Taskwarrior
noctalia msg plugin magi3r/noctalia-task-plugin:service all REFRESH
```

- `SYNC`: Executes `task sync` to push and pull task changes with the TaskChampion server, then refreshes local task state.
- `REFRESH`: Re-exports tasks from Taskwarrior (`task export`) and updates the Noctalia state store without contacting the sync server.

## Notes

- **Commands spawned**: Spawns `task` commands asynchronously via `noctalia.runAsync` with `rc.confirmation=no rc.verbose=nothing`.
- **Network access**: The plugin initiates network requests only when `task sync` connects to your configured TaskChampion sync server over HTTPS.
- **Files written**: Task data and sync state are managed by Taskwarrior in its database directory (`~/.task` or `~/.local/share/taskwarrior`).
- **Compositor support**: The panel and desktop widgets use standard Wayland layer-shell protocol features supported by Noctalia.
- **Development & Testing**: To test the plugin locally:
  ```sh
  noctalia msg plugins source add tasks git magi3r/noctalia-task-plugin
  noctalia msg plugins enable magi3r/noctalia-task-plugin
  ```
- **Disclosure**: This project is 100% vibecoded for personal use and shared for the Noctalia community. Maybe you will find this useful.
