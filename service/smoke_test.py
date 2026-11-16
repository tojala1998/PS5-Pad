"""Exercise the PMCP listener with the host pad stub on loopback."""

import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
from tempfile import TemporaryDirectory
import time

HEADER = struct.Struct("<4sBBH")
STATE = struct.Struct("<II4B16x")


def read_exact(client, size):
    buffer = bytearray()
    while len(buffer) < size:
        data = client.recv(size - len(buffer))
        if not data:
            raise EOFError("Listener closed before the complete response arrived.")
        buffer.extend(data)
    return buffer


def receive(client):
    magic, version, kind, size = HEADER.unpack(read_exact(client, HEADER.size))
    assert magic == b"PMCP" and version == 1
    return kind, read_exact(client, size)


def send(client, kind, payload=b""):
    client.sendall(HEADER.pack(b"PMCP", 1, kind, len(payload)) + payload)


def main():
    with socket.socket() as reserved:
        reserved.bind(("127.0.0.1", 0))
        port = reserved.getsockname()[1]
    with TemporaryDirectory() as directory:
        trace = Path(directory, "trace.jsonl")
        with subprocess.Popen(
            [sys.argv[1], "--port", str(port), "--log-dir", directory, "--watchdog-ms", "80"],
            env={**os.environ, "PADD_TRACE": str(trace)},
        ) as proc:
            try:
                for attempt in range(30):
                    try:
                        client = socket.create_connection(("127.0.0.1", port), timeout=1)
                        break
                    except ConnectionRefusedError:
                        if attempt == 29 or proc.poll() is not None:
                            raise
                        time.sleep(0.02)
                with client:
                    kind, hello = receive(client)
                    assert kind == 1 and len(hello) == 20
                    _, _, pad_id, user_id, flags, _ = struct.unpack("<HHiiII", hello)
                    assert pad_id == -1 and user_id == -1 and flags & 1 == 0, 'Loading must not create a controller.'
                    send(client,128)
                    kind, status=receive(client)
                    assert kind==128 and struct.unpack('<iiiiiIII',status)[2]==-1
                    send(client,129)
                    kind,status=receive(client)
                    values=struct.unpack('<iiiiiIII',status)
                    assert kind==129 and values[0]==0
                    pad_id=values[4]
                    send(client, 8, struct.pack("<II32s", 1, 4, b"PPSA00001"))
                    assert receive(client)[0] == 5, "The console-management command must be rejected."
                    send(client, 2, STATE.pack(42, 0x4000, 128, 128, 128, 128))
                    kind, ack = receive(client)
                    assert kind == 4 and struct.unpack("<Ii", ack) == (42, 0)
                    time.sleep(0.25)
                    send(client, 7)
                    kind, state = receive(client)
                    assert kind == 2 and STATE.unpack(state)[1:] == (0, 128, 128, 128, 128)
                    send(client, 128)
                    kind, status = receive(client)
                    assert kind == 128 and len(status) == 32
                    assert struct.unpack('<iiiiiIII',status)[2] == 1
                    send(client, 129)
                    kind, status = receive(client)
                    values = struct.unpack('<iiiiiIII',status)
                    assert kind == 129 and values[0] == 0 and values[4] != pad_id and values[7] == 2
                    for command in (130,131):
                        send(client, command)
                        kind, result = receive(client)
                        assert kind == command and struct.unpack('<i',result)[0] == 0
                    send(client, 130, b'invalid')
                    assert receive(client)[0] == 5
                    send(client, 6)
                    assert receive(client)[0] == 4
                assert proc.wait(timeout=3) == 0
            finally:
                if proc.poll() is None:
                    proc.kill()
                    proc.wait()
        events = [json.loads(line) for line in trace.read_text().splitlines()]
        assert any(event.get("buttons") == 0x4000 for event in events)
        assert any(event["call"] == "pad_remove" for event in events)
    print("PMCP handshake, input, watchdog release, command rejection, and service stop passed.")


if __name__ == "__main__":
    main()
