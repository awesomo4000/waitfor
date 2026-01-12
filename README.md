# waitfor

A portable command-line utility that blocks until files appear or disappear.

## Usage

```
waitfor [-d] [-t timeout] pathname [pathname ...]
```

### Options

- `-d` — Wait for files to be deleted (disappear) instead of appear
- `-t timeout` — Timeout in seconds (supports decimals like `2.5`). Default: wait forever
- `-h, --help` — Show help message

### Exit Status

- `0` — All conditions met
- `1` — Timeout expired
- `2` — Interrupted by signal
- `3` — Error

## Examples

Wait for a file to appear:
```sh
waitfor /tmp/ready
```

Wait up to 5 seconds:
```sh
waitfor -t 5 /tmp/ready || echo "timed out"
```

Wait for a lock file to be removed:
```sh
waitfor -d /tmp/lockfile
```

Wait for multiple files:
```sh
waitfor /tmp/file1 /tmp/file2 /tmp/file3
```

## Building

```sh
# Build for current platform
zig build

# Release build
zig build -Doptimize=ReleaseSafe

# Cross-compile
zig build -Dtarget=x86_64-linux-musl
zig build -Dtarget=aarch64-linux-musl
zig build -Dtarget=x86_64-windows-gnu
```

Output is in `zig-out/bin/`.

## Testing

```sh
# Unit tests
zig build test

# Integration tests
./tests/test_waitfor.sh
```

## Supported Platforms

- macOS (x86_64, aarch64)
- Linux (x86, x86_64, aarch64) — statically linked with musl
- Windows (x86_64)
- FreeBSD (x86_64)

## License

MIT
