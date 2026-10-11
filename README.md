# DeimusTech isolated C2 lab deployment

This package installs the management components of Havoc and Mythic for an
authorized, isolated training lab. It does not generate payloads, configure
persistence, or automate target access.

## Fixed management layout

| Role | Address | Purpose |
|---|---|---|
| Combined C2 management server | `172.16.113.66/24` | Havoc teamserver and Mythic core/UI |
| Student Ubuntu workstations | `172.16.113.XX/24` | Havoc GUI and browser access to Mythic |
| Redirector | Separate instructor-assigned segment/address | Relays exercise callback traffic toward the authorized target network |

Student operator traffic terminates directly on `172.16.113.66`: Havoc uses
TCP `40056`, and Mythic uses HTTPS `7443` by default. The redirector is not a
Havoc or Mythic operator-login endpoint. Do not publish the management ports
through it. Listener/callback design is exercise-specific and must follow the
approved network plan.

## Connected installation of both servers

Configure the server NIC as `172.16.113.66/24`, copy this directory to it, and
run:

```bash
chmod +x *.sh *.py
./install_c2_teamserver_ubuntu.sh
```

The wrapper validates that the host owns `172.16.113.66/24`, then installs both
Havoc and Mythic core. Mythic initially contains no agent or C2-profile add-ons.

## Air-gapped installation

On an Internet-connected staging VM with the same Ubuntu release and CPU
architecture as the final server:

```bash
./prepare_offline_bundle_ubuntu.sh /path/to/deimustech-c2-offline-bundle
```

Complete one Mythic start on that staging system so its container images exist,
then export them:

```bash
./export_mythic_images_ubuntu.sh /path/to/deimustech-c2-offline-bundle
```

Move the complete bundle into the air gap, verify the image checksum, and run:

```bash
cd /media/offline/deimustech-c2-offline-bundle
sha256sum -c mythic-images.tar.sha256
export DEIMUSTECH_OFFLINE_BUNDLE="$PWD"
./install_c2_teamserver_ubuntu.sh
```

An air-gapped first start requires the exported container archive. Merely
copying the Mythic Git repository is insufficient because Mythic is container
based.

## Unique student accounts

Generate one independent Havoc password and one independent Mythic password per
student:

```bash
./generate_student_access.py alice bob charlie --output-dir class-accounts
```

The output contains:

- `deimustech-lab.yaotl`: a complete profile bound to
  `172.16.113.66:40056`, populated with the unique class roster. Copy it to
  `/opt/deimustech/Havoc/profiles/`.
- `havoc-operators.yaotl`: the same generated account block by itself, for an
  instructor who is merging it into a custom profile.
- `mythic-operator-import.csv`: instructor worksheet for creating the same
  named users from Mythic's administrator Settings interface or an approved
  Mythic scripting client.
- `student-credentials.csv`: the full sensitive roster. Give each person only
  their own row and require first-login rotation.

Mythic requires administrators to pre-create operator accounts; cloned clients
must never share the bootstrap administrator identity.

## Preparing cloned Ubuntu student devices

Install the Havoc GUI in the gold image. Online:

```bash
./install_havoc_client_ubuntu.sh
```

Offline, point it at the prepared bundle:

```bash
export DEIMUSTECH_OFFLINE_BUNDLE=/media/offline/deimustech-c2-offline-bundle
./install_havoc_client_ubuntu.sh
```

After cloning—but before giving a VM to a student—run once with that student's
roster identifier:

```bash
./personalize_student_clone.sh alice 101
# Or apply the address after identifying the NetworkManager connection:
./personalize_student_clone.sh alice 101 'Wired connection 1'
```

This assigns a unique hostname/workstation ID and regenerates the Linux
machine-id and SSH host keys. The optional last octet is recorded as a reminder,
or applied when a NetworkManager connection name is supplied as the third
argument. Do not assign `.66`, which belongs to the teamserver. Also give every
clone a unique vCenter MAC address.

Students connect the Havoc GUI to `172.16.113.66:40056` and browse to
`https://172.16.113.66:7443` for Mythic, using their separate named credentials.

## Firewall baseline

- Permit `172.16.113.0/24` to `172.16.113.66` TCP `40056` and `7443`.
- Deny those operator-management ports from target and redirector segments.
- Allow only the separately approved listener path between teamserver,
  redirector and target network.
- Disable Internet egress after connected installation or use the offline
  bundle from the outset.
- Preserve authentication, framework and firewall logs for instructor review.

Official references: [Havoc installation](https://havocframework.com/docs/installation),
[Havoc teamserver configuration](https://havocframework.com/docs/teamserver),
[Mythic installation](https://docs.mythic-c2.net/installation), and the
[official Mythic repository](https://github.com/its-a-feature/Mythic).
