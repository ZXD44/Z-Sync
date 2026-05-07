# AI Action Protocol — JSON Schema
## Version 1.0

This document defines the strict JSON format for AI-written commands that modify the Roblox Studio map in real-time.

---

## How It Works

1. The **AI** writes `.json` files into the `data/actions/` directory (or POSTs to `/action`).
2. The **Node.js server** ingests those files and queues them.
3. The **Roblox Studio plugin** polls `GET /sync` and receives the queued actions.
4. The **plugin** executes each action in order, modifying the live map.

---

## Action Types

### `create` — Create a new Instance

```json
{
  "action": "create",
  "className": "Part",
  "name": "MyPart",
  "parent": "Workspace",
  "properties": {
    "Position": { "_type": "Vector3", "X": 0, "Y": 10, "Z": 0 },
    "Size": { "_type": "Vector3", "X": 4, "Y": 1, "Z": 4 },
    "Color": { "_type": "Color3", "R": 255, "G": 100, "B": 50 },
    "Anchored": true,
    "Material": { "_type": "Enum", "EnumType": "Material", "Name": "SmoothPlastic" }
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | `"create"` | ✅ | Action type |
| `className` | `string` | ✅ | Roblox ClassName (e.g., `Part`, `Model`, `Script`) |
| `name` | `string` | ❌ | Instance name (defaults to className) |
| `parent` | `string` | ❌ | Dot-separated path (defaults to `"Workspace"`) |
| `properties` | `object` | ❌ | Key-value property map |

---

### `update` — Modify an existing Instance

```json
{
  "action": "update",
  "target": "Workspace.MyPart",
  "properties": {
    "Size": { "_type": "Vector3", "X": 10, "Y": 10, "Z": 10 },
    "Transparency": 0.5
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | `"update"` | ✅ | Action type |
| `target` | `string` | ✅ | Dot-separated path to the Instance |
| `properties` | `object` | ✅ | Properties to update |

---

### `delete` — Remove an Instance

```json
{
  "action": "delete",
  "target": "Workspace.MyPart"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | `"delete"` | ✅ | Action type |
| `target` | `string` | ✅ | Dot-separated path to the Instance to destroy |

---

### `rename` — Rename an Instance

```json
{
  "action": "rename",
  "target": "Workspace.MyPart",
  "name": "CoolPart"
}
```

---

### `move` — Reparent an Instance

```json
{
  "action": "move",
  "target": "Workspace.MyPart",
  "parent": "Workspace.MyModel"
}
```

---

### `execute` — Run a Luau code snippet

```json
{
  "action": "execute",
  "source": "print('Hello from AI!'); workspace.Baseplate.BrickColor = BrickColor.new('Bright red')"
}
```

> ⚠️ **Warning:** This action runs arbitrary Luau code inside Studio. Use with caution.

---

## Property Value Types

When setting properties, use these typed wrappers for Roblox datatypes:

### Vector3
```json
{ "_type": "Vector3", "X": 10, "Y": 5, "Z": 0 }
```

### CFrame
```json
{ "_type": "CFrame", "components": [0, 10, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1] }
```

### Color3 (RGB 0-255)
```json
{ "_type": "Color3", "R": 255, "G": 128, "B": 0 }
```

### BrickColor
```json
{ "_type": "BrickColor", "Name": "Bright red" }
```

### UDim2
```json
{ "_type": "UDim2", "XScale": 0, "XOffset": 100, "YScale": 0, "YOffset": 50 }
```

### Enum
```json
{ "_type": "Enum", "EnumType": "Material", "Name": "Neon" }
```

### Primitives
Numbers, strings, and booleans are passed directly:
```json
{
  "Anchored": true,
  "Transparency": 0.5,
  "Name": "MyCoolPart"
}
```

---

## Batch Actions

You can write an array of actions in a single file:

```json
[
  { "action": "create", "className": "Model", "name": "House", "parent": "Workspace" },
  { "action": "create", "className": "Part", "name": "Wall1", "parent": "Workspace.House", "properties": { "Size": { "_type": "Vector3", "X": 10, "Y": 8, "Z": 1 }, "Anchored": true } },
  { "action": "create", "className": "Part", "name": "Wall2", "parent": "Workspace.House", "properties": { "Size": { "_type": "Vector3", "X": 1, "Y": 8, "Z": 10 }, "Anchored": true } }
]
```

---

## File Naming Convention

When writing action files to `data/actions/`, use timestamp-prefixed names to ensure ordering:

```
data/actions/1715000001_create_house.json
data/actions/1715000002_update_lighting.json
```

Files are processed in alphabetical order and deleted after ingestion.
