import json
import sys
import argparse


def find_machine_ips(
        json_data: str,
        machine_name: str
) -> dict[str, str | None]:
    """Find a machine by name and return its IPs."""
    machines = json.loads(json_data)
    for machine in machines:
        name = machine.get("given_name") or machine.get("name")
        if name == machine_name:
            ips = machine.get("ip_addresses", [])
            return {
                "ipv4": next((ip for ip in ips if "." in ip), None),
                "ipv6": next((ip for ip in ips if ":" in ip), None),
            }
    return {"ipv4": None, "ipv6": None}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-e", "--endpoint", required=True)
    parser.add_argument("-m", "--machine", required=True)
    parser.add_argument("--ipv4-only", action="store_true")
    parser.add_argument("--ipv6-only", action="store_true")
    args = parser.parse_args()

    data = sys.stdin.read()

    ips = find_machine_ips(data, args.machine)
    if not ips["ipv4"] and not ips["ipv6"]:
        sys.exit(f"Error: Machine '{args.machine}' not found")

    records = []
    if ips["ipv4"] and not args.ipv6_only:
        records.append({
            "name": args.endpoint,
            "type": "A",
            "value": ips["ipv4"]
        })
    if ips["ipv6"] and not args.ipv4_only:
        records.append({
            "name": args.endpoint,
            "type": "AAAA",
            "value": ips["ipv6"]
        })

    print(json.dumps(records, indent=2))


if __name__ == "__main__":
    main()
