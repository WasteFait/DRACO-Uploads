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

Copy this directory to the server and run:

```bash
chmod +x *.sh *.py
./install_teamserver.sh
```

To discard an existing Mythic deployment and rebuild it with a clean database,
known administrator credential, all numbered operators, the Havoc service, and
the complete pinned agent/C2 catalog, use:

```bash
./rebuild_teamserver_clean.sh
```

This requires typing `REBUILD-MYTHIC`. For unattended instructor automation,
pass `--yes`. It deletes only Mythic-labeled/named containers, volumes, networks,
their referenced images, `/opt/deimustech/Mythic`, and Mythic catalog state. It
does not delete Havoc or unrelated Docker workloads. The lab defaults are:

- Mythic administrator: `mythic_admin` / `DeimusTech-Mythic-Admin!`
- Numbered operators: `operator-01` through `operator-99` /
  `DeimusTech-Lab-Operator!`

The rebuild writes both credential summaries beneath `/etc/deimustech-c2` with
mode `0600`.

The installer does not require `172.16.113.66/24` to exist during setup. Havoc
binds to `0.0.0.0:40056`, Mythic provisioning uses loopback, and a missing lab
address produces a warning instead of aborting. Assign `172.16.113.66/24`
before students connect; their launchers continue to use that stable address.
The installer installs both Havoc and Mythic core, Go 1.22.12 for the Havoc build, and current
Docker CE plus Docker Compose v2 from Docker's official Ubuntu repository for
Mythic. Ubuntu's older `docker.io` package is replaced when necessary without
deleting Docker images, containers, volumes, or `/var/lib/docker`. Mythic
initially contains no agent or C2-profile add-ons. The installer starts Mythic
and installs `deimustech-havoc.service`, which starts Havoc immediately and at
every subsequent boot. It then installs the pinned Mythic community catalog:
36 payload agents and 14 C2 profiles listed in `mythic_catalog.tsv`. Ancillary
loggers, webhooks, eventing providers, wrappers, browsers and authentication
plugins are intentionally not included because they are not agents or C2
profiles.

Mythic nginx is explicitly configured with `NGINX_BIND_LOCALHOST_ONLY=false`
and IPv4 enabled. On first start, the installer discovers nginx's actual Docker
bridge gateway and restricts the login allowlist to `127.0.0.1/32`, that exact
gateway `/32` (or `/128`), the required `172.19.0.1/32` bridge address, and
`172.16.113.0/24`. This matters because a host
request to `127.0.0.1:7443` can appear to nginx as the Docker bridge gateway.
Local provisioning therefore works without leaving Mythic open to arbitrary
source networks.

Catalog projects are installed sequentially to avoid concurrent build spikes.
Successful entries are recorded and skipped on reruns. Since these are separate
community projects, a failure in one is logged without uninstalling successful
entries or taking down the base teamserver. Review:

```bash
cat /var/lib/deimustech-c2/mythic-catalog-failures.tsv
sudo /opt/deimustech/Mythic/mythic-cli services
```

The complete catalog requires temporary Internet access and at least 20 GiB of
free disk. It is not included in the base air-gap bundle because every project
has its own repository and container images.

Verify both services with:

```bash
sudo /opt/deimustech/Mythic/mythic-cli status
sudo systemctl status deimustech-havoc --no-pager
sudo ss -lntp | grep -E ':(40056|7443)[[:space:]]'
```

If an earlier attempt stopped because Docker was too old, the installation is
safe to resume in place:

```bash
./ensure_docker_engine.sh
sudo docker version
docker compose version
./install_teamserver.sh
```

Do not delete `/opt/deimustech/Havoc` or `/opt/deimustech/Mythic`; the installers
reuse completed downloads and builds.

### Default operator roster

The teamserver installer creates matching non-administrator accounts in Havoc
and Mythic:

- Usernames: `operator-01` through `operator-99`
- Initial password: `DeimusTech-Lab-Operator!`
- Mythic operation: `DeimusTech Operations`

The matching workstation is straightforward: `ops-01` uses `operator-01`, and
so on through `ops-99` and `operator-99`. The generated Havoc profile is stored
at `/opt/deimustech/Havoc/profiles/deimustech-lab.yaotl`. A root-readable account
summary is stored at `/etc/deimustech-c2/operator-accounts.txt` with mode `0600`.

The shared password is an initial classroom credential, not a production
secret. Restrict TCP `40056` and `7443` to the operator VLAN and rotate the
passwords if the lab is exposed beyond the isolated exercise environment. To
choose a different initial password on the very first installation:

```bash
export DEIMUSTECH_OPERATOR_PASSWORD='Your-Lab-Initial-Password!'
./install_teamserver.sh
```

Rerunning the installer creates only missing Mythic accounts and memberships;
it does not overwrite passwords that students may already have changed.

## Verify an uploaded copy

From the directory containing this README, verify that no file was corrupted:

```bash
sha256sum -c UPLOAD_SHA256SUMS.txt
bash -n ./*.sh
```

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
./install_teamserver.sh
```

An air-gapped first start requires the exported container archive. Merely
copying the Mythic Git repository is insufficient because Mythic is container
based.

## Preparing the Ubuntu student gold image

Run the single gold-image entry point on Ubuntu Desktop:

```bash
chmod +x *.sh *.py
./install_student_gold_image.sh
```

It installs the Havoc GUI, Firefox, VMware guest tools, two desktop launchers,
and a boot-time clone personalization service. When the install finishes, shut
the VM down and convert it to a vCenter template without booting it again.

Assign every deployed clone exactly one address from
`172.16.113.101-172.16.113.199`. On first boot, the service waits for networking
and derives the hostname from the last octet:

| Assigned address | Resulting hostname |
|---|---|
| `172.16.113.101` | `ops-01` |
| `172.16.113.150` | `ops-50` |
| `172.16.113.199` | `ops-99` |

The service accepts no addresses outside that range and refuses to choose when
more than one valid pool address is present. If DHCP or vCenter customization is
late, it waits up to two minutes; a failure is retried at the next boot. After a
successful assignment it writes
`/var/lib/deimustech/operator-clone-personalized` and disables itself, so a later
address change does not silently rename an assigned workstation.

Give every clone a unique vCenter MAC address. Address allocation may come from
a DHCP reservation or vCenter guest customization, but it must complete during
boot and remain stable for the exercise.

Students connect the Havoc GUI to `172.16.113.66:40056` and browse to
`https://172.16.113.66:7443` for Mythic, using their separate named credentials.

## Firewall baseline

- Permit `172.16.113.0/24` to `172.16.113.66` TCP `40056` and `7443`.
- Because Havoc binds all IPv4 interfaces to permit pre-network installation,
  enforce this source restriction in vCenter port groups or the host firewall.
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
