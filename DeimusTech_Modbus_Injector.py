#!/usr/bin/env python3
"""Guided Modbus TCP exercise client for the DeimusTech lab."""
import argparse
import datetime as dt
import ipaddress
import json
import pathlib
import socket
import struct
import sys
import threading

AUDIT_PATH = pathlib.Path.home() / "deimustech_modbus_injector.jsonl"
READ_KINDS = ("coil", "discrete_input", "holding_register", "input_register")
WRITE_KINDS = ("coil", "holding_register")

FLEET = [
    {"id": "SUB-RTU-01", "name": "Substation and ATS RTU",
     "host": "172.24.4.50", "port": 502, "unit_id": 1},
    {"id": "BMS-RTU-01", "name": "Facilities Chiller RTU",
     "host": "172.24.4.51", "port": 502, "unit_id": 2},
    {"id": "ACS-RTU-01", "name": "Access Control RTU",
     "host": "172.24.4.52", "port": 502, "unit_id": 3},
    {"id": "GRID-RTU-01", "name": "Microgrid and BESS RTU",
     "host": "172.24.4.53", "port": 502, "unit_id": 4},
    {"id": "TPS-RTU-01", "name": "Traction and Rail Interlocking RTU",
     "host": "172.24.4.54", "port": 502, "unit_id": 5},
]


class ModbusError(RuntimeError):
    """Modbus transport or protocol error."""


class ModbusClient:
    """Small standard-library-only Modbus TCP client."""

    def __init__(self, host, port=502, unit=1, timeout=2.0):
        self.host, self.port, self.unit, self.timeout = host, port, unit, timeout
        self._transaction, self._socket = 0, None
        self._lock = threading.Lock()

    def _connect(self):
        if self._socket is None:
            self._socket = socket.create_connection((self.host, self.port), self.timeout)
            self._socket.settimeout(self.timeout)

    def close(self):
        if self._socket:
            try:
                self._socket.close()
            except OSError:
                pass
        self._socket = None

    @staticmethod
    def _recv_exact(sock, count):
        data = b""
        while len(data) < count:
            chunk = sock.recv(count - len(data))
            if not chunk:
                raise ModbusError("connection closed by RTU")
            data += chunk
        return data

    def query(self, function, payload):
        with self._lock:
            try:
                self._connect()
                self._transaction = (self._transaction + 1) & 0xFFFF
                pdu = bytes([function]) + payload
                header = struct.pack("!HHHB", self._transaction, 0, len(pdu) + 1, self.unit)
                self._socket.sendall(header + pdu)
                transaction, protocol, length, unit = struct.unpack(
                    "!HHHB", self._recv_exact(self._socket, 7)
                )
                response = self._recv_exact(self._socket, length - 1)
                if transaction != self._transaction or protocol or unit != self.unit:
                    raise ModbusError("invalid MBAP response")
                if response[0] & 0x80:
                    raise ModbusError(
                        f"Modbus exception 0x{response[1]:02X} ({response[1]})"
                    )
                return response
            except (OSError, ModbusError) as exc:
                self.close()
                raise ModbusError(
                    f"{self.host}:{self.port}/unit {self.unit}: {exc}"
                ) from exc

    def read(self, kind, address, count=1):
        function = {
            "coil": 1, "discrete_input": 2,
            "holding_register": 3, "input_register": 4,
        }[kind]
        response = self.query(function, struct.pack("!HH", address, count))
        if response[0] != function:
            raise ModbusError("malformed response")
        if function in (1, 2):
            return [bool(response[2 + index // 8] & (1 << index % 8))
                    for index in range(count)]
        if response[1] < count * 2:
            raise ModbusError("short register response")
        return list(struct.unpack(f"!{count}H", response[2:2 + count * 2]))

    def write(self, kind, address, value):
        if kind == "coil":
            self.query(5, struct.pack("!HH", address, 0xFF00 if value else 0))
        elif kind == "holding_register":
            self.query(6, struct.pack("!HH", address, int(value) & 0xFFFF))
        else:
            raise ModbusError(f"{kind} is read-only")


def load_fleet():
    return FLEET


def resolve_lab_target(host, port, unit):
    """Describe a known tuple without blocking uncommissioned test values."""
    try:
        normalized = str(ipaddress.ip_address(host))
    except ValueError as exc:
        raise ValueError("--target must be a literal IP address, not a hostname") from exc
    for device in load_fleet():
        if normalized == device["host"] and port == device["port"] and unit == device["unit_id"]:
            return device
    return {
        "id": "UNCOMMISSIONED-TUPLE",
        "name": "student-supplied Modbus endpoint",
        "host": normalized,
        "port": port,
        "unit_id": unit,
    }


def parse_value(kind, text):
    if kind == "coil":
        values = {"1": True, "true": True, "on": True, "closed": True,
                  "0": False, "false": False, "off": False, "open": False}
        try:
            return values[text.lower()]
        except KeyError as exc:
            raise ValueError("coil value must be 0/1, true/false, on/off or open/closed") from exc
    value = int(text, 0)
    if not 0 <= value <= 65535:
        raise ValueError("holding-register value must be between 0 and 65535")
    return value


def append_audit(event):
    event = {"timestamp": dt.datetime.now(dt.timezone.utc).isoformat(), **event}
    with AUDIT_PATH.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(event, sort_keys=True) + "\n")


def audit_records():
    if not AUDIT_PATH.exists():
        return []
    records = []
    for line in AUDIT_PATH.read_text(encoding="utf-8").splitlines():
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return records


def client_for(args):
    device = resolve_lab_target(args.target, args.port, args.unit)
    with socket.create_connection((args.target, args.port), timeout=2):
        pass
    return device, ModbusClient(args.target, args.port, args.unit, timeout=2.0)


def print_target(args, device):
    print(f"Authorized asset : {device['id']} ({device['name']})")
    print(f"Endpoint         : {args.target}:{args.port}")
    print(f"Unit ID          : {args.unit}")


def command_check(args):
    device, client = client_for(args)
    try:
        # Coil zero exists on every commissioned simulator. Unlike a TCP-only
        # probe, this forces the target to accept or reject the supplied unit.
        value = client.read("coil", 0, 1)[0]
        print_target(args, device)
        print(f"Modbus probe     : coil[0]={value}")
        print("Result           : Modbus endpoint and supplied unit responded")
        return 0
    finally:
        client.close()


def command_read(args):
    device, client = client_for(args)
    try:
        values = client.read(args.kind, args.address, args.count)
    finally:
        client.close()
    print_target(args, device)
    print(f"Object           : {args.kind}, zero-based address {args.address}, count {args.count}")
    print(f"Raw values       : {values}")
    append_audit({"operation": "read", "device": device["id"], "host": args.target,
                  "port": args.port, "unit": args.unit, "kind": args.kind,
                  "address": args.address, "count": args.count, "values": values})
    return 0


def command_write(args):
    requested = parse_value(args.kind, args.value)
    device, client = client_for(args)
    try:
        before = client.read(args.kind, args.address)[0]
        print_target(args, device)
        print(f"Object           : {args.kind}, zero-based address {args.address}")
        print(f"Observed baseline: {before}")
        print(f"Requested value  : {requested}")
        if args.note:
            print(f"Student note     : {args.note.strip()}")
        if not args.execute and input("\nReview the target and baseline above. Type WRITE to continue: ").strip() != "WRITE":
            print("[CANCELLED] No write was sent.")
            return 2
        client.write(args.kind, args.address, requested)
        observed = client.read(args.kind, args.address)[0]
        verified = observed == requested
        append_audit({"operation": "write",
                      "device": device["id"], "host": args.target, "port": args.port,
                      "unit": args.unit, "kind": args.kind, "address": args.address,
                      "before": before, "requested": requested, "readback": observed,
                      "verified": verified, "note": args.note.strip()})
        print(f"Readback         : {observed}")
        print(f"Verification     : {'PASS' if verified else 'FAIL'}")
        print("Restoration      : instructor-managed; record the baseline shown above")
        return 0 if verified else 1
    finally:
        client.close()


def command_history(args):
    records = [r for r in audit_records() if r.get("operation") == "write"]
    if not records:
        print("No write or restoration transactions are recorded.")
        return 0
    for record in records[-args.limit:]:
        value = record.get("requested")
        print(f"{record.get('timestamp','?')}  {record.get('device','?'):<12}  "
              f"{record.get('kind','?')}[{record.get('address','?')}] "
              f"{record.get('before','?')} -> {value}  "
              f"verified={record.get('verified', False)}")
    return 0


def prompt(text, default=None):
    suffix = f" [{default}]" if default is not None else ""
    value = input(f"{text}{suffix}: ").strip()
    return value if value else default


def prompt_int(text, default=None, minimum=0, maximum=65535):
    value = prompt(text, default)
    try:
        parsed = int(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{text} must be a number") from exc
    if not minimum <= parsed <= maximum:
        raise ValueError(f"{text} must be between {minimum} and {maximum}")
    return parsed


def guided_endpoint():
    return argparse.Namespace(
        target=prompt("Target RTU IP"),
        port=prompt_int("Modbus TCP port", "502", 1, 65535),
        unit=prompt_int("Modbus unit ID", None, 1, 247),
    )


def guided_menu(_args=None):
    print("\nDEIMUSTECH MODBUS EXERCISE CLIENT")
    print("You choose the RTU and point; the tool handles checks, verification and restoration.")
    while True:
        print("\n1) Check an endpoint  2) Read a point  3) Write a point")
        print("4) Show write history 5) Exit")
        choice = input("Select 1-5: ").strip()
        try:
            if choice == "1":
                args = guided_endpoint(); command_check(args)
            elif choice == "2":
                args = guided_endpoint()
                args.kind = prompt("Object type (coil/discrete_input/holding_register/input_register)")
                if args.kind not in READ_KINDS: raise ValueError("unsupported object type")
                args.address = prompt_int("Zero-based address")
                args.count = prompt_int("Number of values", "1", 1, 16)
                command_read(args)
            elif choice == "3":
                args = guided_endpoint()
                args.kind = prompt("Writable type (coil/holding_register)")
                if args.kind not in WRITE_KINDS: raise ValueError("writes support coil or holding_register")
                args.address = prompt_int("Zero-based address")
                args.value = prompt("Raw value")
                args.note = prompt("Optional short note", "")
                args.execute = False
                command_write(args)
            elif choice == "4":
                command_history(argparse.Namespace(limit=20))
            elif choice == "5":
                print("Exit complete. Notify the instructor of all exercise writes.")
                return 0
            else:
                print("Choose a number from 1 through 5.")
        except (ValueError, OSError, ModbusError) as exc:
            print(f"[ERROR] {exc}")


def add_endpoint(parser):
    parser.add_argument("--target", required=True, help="RTU IP determined during reconnaissance")
    parser.add_argument("--port", required=True, type=int, help="Modbus TCP port")
    parser.add_argument("--unit", required=True, type=int, choices=range(1, 248), metavar="1-247")


def main():
    parser = argparse.ArgumentParser(
        description="Guided Modbus engineering exercise client",
        epilog="Addresses are zero-based protocol offsets, not 4xxxx display references.")
    sub = parser.add_subparsers(dest="command")

    check = sub.add_parser("check", help="validate a student-identified lab endpoint")
    add_endpoint(check)
    check.set_defaults(handler=command_check)

    read = sub.add_parser("read", help="read an explicitly identified Modbus object")
    add_endpoint(read)
    read.add_argument("--kind", required=True, choices=READ_KINDS)
    read.add_argument("--address", required=True, type=int, choices=range(0, 65536), metavar="0-65535")
    read.add_argument("--count", type=int, choices=range(1, 17), default=1, metavar="1-16")
    read.set_defaults(handler=command_read)

    write = sub.add_parser("write", help="write one student-identified writable object")
    add_endpoint(write)
    write.add_argument("--kind", required=True, choices=WRITE_KINDS)
    write.add_argument("--address", required=True, type=int, choices=range(0, 65536), metavar="0-65535")
    write.add_argument("--value", required=True, help="raw protocol value; apply scaling yourself")
    write.add_argument("--note", default="", help="optional short exercise note")
    write.add_argument("--execute", action="store_true", help="instructor automation: skip typed phrase")
    write.set_defaults(handler=command_write)

    history = sub.add_parser("history", help="show recent local write records")
    history.add_argument("--limit", type=int, default=20)
    history.set_defaults(handler=command_history)

    args = parser.parse_args()
    if not args.command:
        return guided_menu()
    try:
        return args.handler(args)
    except (ValueError, OSError, ModbusError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
