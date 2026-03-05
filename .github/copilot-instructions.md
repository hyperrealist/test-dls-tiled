# Copilot Instructions for test-dls-tiled

## Project Overview

**test-dls-tiled** is a FastAPI-based extension for the [Tiled data catalog](https://blueskyproject.io/tiled/), providing DLS (Diamond Light Source) specific API endpoints for accessing and visualizing scientific data. The project wraps Tiled's server infrastructure to add custom routes and domain-specific processing.

**Key Components:**
- `src/test_dls_tiled/routers.py` - FastAPI routers with custom endpoints (e.g., `/binned/{path}`)
- `src/test_dls_tiled/__main__.py` - CLI entry point
- `src/test_dls_tiled/__init__.py` - Package exports (routers, version)
- `typings/tiled/` - Type stubs for the Tiled library (incomplete runtime API)

## Architecture Patterns

### Tiled Server Integration

The project tightly integrates with Tiled's server authentication and dependency injection:

- **Authentication**: Uses `tiled.server.authentication` module for principal/scope validation
  - `get_current_principal()` - Retrieves authenticated user context
  - `get_current_scopes()` - Accesses user's permission scopes
  - `check_scopes()` - Security dependency enforcing required scopes (e.g., `["read:data"]`)

- **Dependencies**: Injects Tiled resources via FastAPI's `Depends()`
  - `get_root_tree()` - Root catalog access
  - `get_entry()` - Retrieves individual data entries with access control
  - `get_session_state()` - Session context for performance tracking

- **Type Aliases**: `AccessTags`, `Scopes` from `tiled.type_aliases`

### Custom Router Pattern

The `binned()` endpoint in routers.py exemplifies the project's approach:

```python
@visr_router.get("/binned/{path:path}")
async def binned(
    path: str,
    principal: Principal | None = Depends(get_current_principal),
    authn_access_tags: AccessTags | None = Depends(get_current_access_tags),
    authn_scopes: Scopes = Depends(get_current_scopes),
    _=Security(check_scopes, scopes=["read:data"]),  # Enforce 'read:data' scope
):
```

**Pattern details:**
- Path parameters specify data location in Tiled catalog
- All Tiled dependencies are explicitly injected (not auto-discovered)
- Security scope enforcement is via `Security()` dependency (not just `Depends()`)
- `# type: ignore` comments suppress warnings on untyped Tiled imports
- `record_timing()` context manager tracks operation performance metrics
- `ensure_awaitable()` handles both sync/async entry read operations

### Data Processing Flow

Example from `binned()` endpoint:

1. **Access Control**: `get_entry()` validates user permissions against access tags and scopes
2. **Data Retrieval**: `entry.read()` fetches the actual data (may be async)
3. **Dimensional Processing**: Parse query params for slicing (e.g., `slice_dim=2:0.5:0.1`)
4. **NumPy Computation**: Mask and bin multi-dimensional arrays for visualization
5. **Response**: Return processed data as dict with image arrays and axis edges

## Development Workflows

### Running All Tests, Linting, and Type Checking

```bash
tox -p  # Runs pre-commit, type-checking, and tests in parallel
```

This is the **primary command** for validating changes. Equivalent to:

```bash
tox -e pre-commit  # Ruff linting, import sorting
tox -e type-checking  # Pyright type checker
tox -e tests  # Pytest with coverage
```

### Testing Strategy

- **Test Location**: `tests/test_cli.py` (currently minimal)
- **Coverage**: Pytest with coverage reporting; aim to maintain or improve coverage on PRs
- **Fixtures**: `conftest.py` is empty; add pytest fixtures here as needed
- **Coverage Config**: Runs from installed location; mapped to source in `pyproject.toml`

### Type Checking

- **Tool**: Pyright with `basic` mode (not strict)
- **Config**: `tool.pyright.reportMissingImports = false` because Tiled has incomplete stubs
- **Import Stubs**: `typings/tiled/` contains stub files (not the actual Tiled library)

### Code Quality Standards

**Ruff Linting Rules** (src/tests):
- `E`, `W` - PEP 8 errors/warnings
- `F` - Pyflakes (undefined names, unused imports)
- `I` - isort (import ordering)
- `UP` - pyupgrade (modern Python syntax)
- `B` - flake8-bugbear (common bugs)
- `SLF001` - Private member access (allowed in tests only)

**Pre-commit Hooks**: Ruff formatting, import sorting, and lint checks must pass before commit.

## Project-Specific Conventions

### Async/Await Usage

- All endpoint functions are `async` to integrate with FastAPI's async handling
- Use `ensure_awaitable()` to normalize both sync and async callables
- Never block with sync operations in async contexts

### Error Handling

- Raise `HTTPException(status_code=..., detail=...)` for API-level errors
- Include the path and context in error messages (e.g., `f"Error reading array data from entry at path '{path}': {e}"`)
- Validate input formats before processing; return 400 for bad input, 500 for read/processing errors

### Query Parameter Parsing

- Optional query params use `Query()` with defaults (e.g., `width: int | None = None`)
- Repeatable params use `list[str] | None = Query(None)` (see `slice_dim`)
- Parse repeatable params as colon-delimited strings: `"dim:center:thickness"`

### NumPy Operations

- Use vectorized operations for performance (e.g., `numpy.histogram2d()`, boolean masking)
- Handle division by zero safely: `numpy.divide(..., where=counts > 0, out=zeros_like(...))`
- Multi-dimensional arrays use dimension indices (x, y) passed as parameters

## Dependencies and External Integration

- **Tiled >= any version in [tool.dependency-groups.dev]**: Main framework; provides server authentication, dependencies, schemas
- **FastAPI**: Async web framework for routing and dependency injection
- **NumPy**: Numerical computing for data binning and masking
- **Pyright, Ruff, Pytest**: Development tools in `tox.toml`

**Note**: Tiled imports use `# type: ignore` because the installed library lacks complete type information. The `typings/tiled/` stubs are reference only and may not be up-to-date.

## File Structure Reference

```
src/test_dls_tiled/
  __init__.py        # Exports routers and __version__
  __main__.py        # CLI entry point
  routers.py         # Custom FastAPI endpoints (main logic)
  _version.py        # Auto-generated by setuptools_scm

tests/
  test_cli.py        # CLI tests (minimal)
  conftest.py        # Pytest fixtures (empty)

typings/tiled/       # Type stubs for Tiled library
```

## Quick Reference for Common Tasks

| Task | Command |
|------|---------|
| Validate all changes | `tox -p` |
| Run only tests | `tox -e tests` |
| Run only linting | `tox -e pre-commit` |
| Run only type checking | `tox -e type-checking` |
| Add a new endpoint | Create async function in `routers.py`, decorate with `@visr_router.get/post(...)`, inject Tiled dependencies |
| Add a test | Create test function in `tests/test_cli.py` or new test file; run `tox -e tests` to validate |
| Handle missing type info | Use `# type: ignore` comment on problematic Tiled imports |
