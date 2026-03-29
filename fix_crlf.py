from pathlib import Path

files = list(Path('.').rglob('*'))
for p in files:
    try:
        if p.suffix.lower() in {'.sh', '.py', '.yml', '.yaml', '.ini', '.env', '.conf'} and p.is_file():
            b = p.read_bytes()
            if b'\r\n' in b:
                p.write_bytes(b.replace(b'\r\n', b'\n'))
                print(f"Fixed CRLF in {p}")
    except Exception as e:
        pass
