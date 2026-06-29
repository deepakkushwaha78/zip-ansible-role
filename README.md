# Enterprise Windows ZIP Deployment with Ansible

This project deploys a ZIP-based application from an Ubuntu controller to
Windows Server 2019/2022 hosts over WinRM. It is agentless on Windows, processes
hosts in rolling batches, validates every deployment, and can restore the last
pre-deployment copy automatically or through a dedicated rollback playbook.

## Project structure

```text
.
├── ansible.cfg
├── requirements.yml
├── README.md
└── ansible
    ├── files
    │   └── app.zip
    ├── inventories
    │   └── production
    │       ├── hosts.ini
    │       └── group_vars.yml
    ├── playbooks
    │   ├── deploy.yml
    │   ├── rollback.yml
    │   └── validate.yml
    └── roles
        └── windows_deploy
            ├── defaults/main.yml
            ├── handlers/main.yml
            ├── vars/main.yml
            └── tasks
                ├── main.yml
                ├── backup.yml
                ├── copy.yml
                ├── unzip.yml
                ├── restart.yml
                ├── validate.yml
                └── rollback.yml
```

## How deployment works

For each rolling batch, Ansible:

1. Checks WinRM connectivity.
2. Creates `deployment_path` and `backup_path`.
3. Replaces the fixed rollback point with a copy of the current application.
4. Transfers the archive and compares controller/target SHA-256 checksums.
5. Stops the configured Windows service.
6. Removes old application files except the archive and configured preserved
   file patterns.
7. Extracts the ZIP and optionally removes the archive.
8. Starts the service and polls until Windows reports it as `started`.
9. Checks the folder, executable, service, and optional HTTP endpoint.
10. Restores the rollback point if a post-mutation deployment task fails.

The fixed rollback point is:

```text
<backup_path>\<application_name>_previous
```

Each successful backup replaces the older rollback point. Use a versioned
artifact repository or external backup retention system if multiple historical
releases must be retained.

## Prerequisites

Controller:

- Ubuntu 22.04
- A currently supported Python version for the selected `ansible-core`
- `ansible-core`, `pywinrm`, and the collections in `requirements.yml`
- Network access to WinRM TCP 5985 (HTTP) or 5986 (HTTPS)
- `file` package, used by the local artifact MIME preflight check

Windows targets:

- Windows Server 2019 or 2022
- PowerShell 5.1 or later
- WinRM enabled
- An administrative deployment account
- The configured Windows service already installed
- Enough free space for the deployment, uploaded ZIP, and one full backup
- No Ansible agent and no Python installation are required

Current Ansible releases require newer controller-side Python versions than the
Python 3.10 shipped by Ubuntu 22.04. For a production controller, install Python
3.12 through your organization's approved package/runtime method, or run Ansible
in a maintained execution environment. Do not pin an end-of-life Ansible release
only to retain Python 3.10.

## Install on Ubuntu

Using `pipx` keeps Ansible isolated from system Python packages:

```bash
sudo apt update
sudo apt install -y pipx file
pipx ensurepath
pipx install --python python3.12 ansible-core
pipx inject ansible-core "pywinrm>=0.4.0"
```

Start a new shell after `pipx ensurepath`, then install the collections:

```bash
cd /home/deepakkhushwaha/Desktop/NewGen-Ansible
ansible-galaxy collection install -r requirements.yml
ansible --version
ansible-galaxy collection list
```

The project uses:

- `ansible.windows` for WinRM, file, service, checksum, and HTTP operations.
- `community.windows` for native ZIP extraction.

## Configure WinRM

Run the following baseline in an elevated PowerShell session on each target, or
apply equivalent settings through Group Policy:

```powershell
Enable-PSRemoting -Force
Set-Service -Name WinRM -StartupType Automatic
Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $false
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $false
winrm enumerate winrm/config/listener
```

The supplied inventory uses NTLM over HTTP on port 5985. NTLM provides WinRM
message encryption even on HTTP. For an enterprise environment, HTTPS on port
5986 with a CA-issued certificate and certificate validation is preferable.
After configuring an HTTPS listener, change the inventory to:

```ini
ansible_port=5986
ansible_winrm_scheme=https
ansible_winrm_server_cert_validation=validate
```

For AWS EC2, allow the chosen WinRM port in the instance security group only
from the controller's fixed IP/CIDR. Never expose 5985 or 5986 to
`0.0.0.0/0`. Confirm that Windows Firewall and any network ACLs allow the same
traffic.

See the official
[Windows WinRM guide](https://docs.ansible.com/projects/ansible/latest/os_guide/windows_winrm.html)
for HTTPS listener, certificate, NTLM, Kerberos, and CredSSP details.

## Inventory and credentials

The supplied target is represented without a plaintext password:

```ini
[windows]
winserver01 ansible_host=18.138.224.111
```

Add the remaining 300-400 hosts beneath it, using unique inventory names:

```ini
winserver02 ansible_host=10.0.2.12
winserver03 ansible_host=10.0.2.13
```

The inventory reads the password from `WINDOWS_ANSIBLE_PASSWORD`. Entering it
with `read` prevents shell metacharacters from being interpreted and avoids
placing it in shell history:

```bash
read -rsp "Windows password: " WINDOWS_ANSIBLE_PASSWORD
echo
export WINDOWS_ANSIBLE_PASSWORD
```

Clear it after the run:

```bash
unset WINDOWS_ANSIBLE_PASSWORD
```

For automation, use Ansible Vault or your CI/CD secret manager. A Vault file can
override the inventory value without changing the project:

```bash
ansible-vault create windows-secrets.yml
```

Place this YAML in the encrypted file:

```yaml
---
ansible_password: "replace-with-secret"
```

Then add `-e @windows-secrets.yml --ask-vault-pass` to playbook commands. Do not
commit Vault password files or unencrypted credentials.

## Configure deployment variables

Edit `ansible/inventories/production/group_vars.yml`.

| Variable | Purpose | Default |
|---|---|---|
| `application_name` | Backup namespace | `myapp` |
| `service_name` | Existing Windows service name | `MyAppService` |
| `deployment_path` | Application destination | `C:\Deploy` |
| `backup_path` | Backup root | `C:\Backup` |
| `zip_file` | Archive in `ansible/files` | `app.zip` |
| `application_executable` | Required executable relative to deployment root | `MyApp.exe` |
| `health_check_url` | URL requested from each Windows target; blank disables | blank |
| `health_check_status_codes` | Accepted HTTP status codes | `[200]` |
| `deployment_timeout` | Service/HTTP timeout in seconds | `120` |
| `service_poll_interval` | Service polling interval in seconds | `5` |
| `parallel_batch_size` | Hosts in each rolling batch | `20` |
| `maximum_failure_percentage` | Batch failure threshold | `10` |
| `delete_archive_after_unzip` | Delete remote ZIP after extraction | `true` |
| `auto_rollback_on_failure` | Restore backup after a mutated deployment fails | `true` |
| `preserve_config_patterns` | Case-insensitive regexes for retained files | config formats |

`service_poll_interval` must be greater than zero. Preserved files remain in
place and the ZIP may overwrite a preserved file if it contains the same path.
Exclude production configuration from the ZIP when the deployed copy must
always win.

Replace `ansible/files/app.zip` before running. The repository file is an
intentional text placeholder; deployment preflight rejects it. Also update
`service_name` and `application_executable` to match the real application.

## Validate configuration and connectivity

Run all commands from the project root:

```bash
ansible-inventory --graph
ansible-playbook ansible/playbooks/deploy.yml --syntax-check
ansible windows -m ansible.windows.win_ping
```

Use `--limit` for a canary before fleet deployment. Include `localhost` so the
artifact preflight and final summary plays are not filtered out:

```bash
ansible-playbook ansible/playbooks/deploy.yml \
  --limit 'winserver01:localhost'
```

## Run deployment

Full rolling deployment:

```bash
ansible-playbook ansible/playbooks/deploy.yml
```

Override batch size or another variable for one run:

```bash
ansible-playbook ansible/playbooks/deploy.yml \
  -e parallel_batch_size=10
```

Supported phase tags:

```bash
ansible-playbook ansible/playbooks/deploy.yml --tags backup
ansible-playbook ansible/playbooks/deploy.yml --tags copy
ansible-playbook ansible/playbooks/deploy.yml --tags deploy
ansible-playbook ansible/playbooks/deploy.yml --tags validate
ansible-playbook ansible/playbooks/deploy.yml --tags connectivity
```

`--tags deploy` runs the complete backup, copy, extraction, restart, and
validation sequence. The narrower tags are useful for controlled diagnostics;
for example, `--tags copy` only stages and verifies the archive.

The final summary lists successful, failed, and skipped inventory hosts plus
elapsed wall-clock time. Hosts omitted by a limit or not reached after a failure
threshold are shown as skipped.

## Run validation

```bash
ansible-playbook ansible/playbooks/validate.yml
```

Validation checks:

- Deployment directory exists and is a directory.
- Configured executable exists and is a file.
- Configured service exists and reports `started`.
- Optional health endpoint returns an accepted HTTP status.

The HTTP request runs on the Windows target, so `localhost` in
`health_check_url` means that target server, not the Ubuntu controller.

## Run rollback

Rollback restores the most recent fixed rollback point, starts the service, and
runs the same application validation:

```bash
ansible-playbook ansible/playbooks/rollback.yml
```

Rollback fails safely when no backup exists. A first-ever deployment has no
previous application to back up, so it cannot be rolled back by this project.

## Scaling and operations

- `serial` limits deployment to `parallel_batch_size` hosts at a time.
- `forks = 50` limits concurrent controller workers. Tune this with controller
  CPU, memory, network capacity, and WinRM behavior in mind.
- Begin with a small canary and batch size, then increase after measuring.
- Large ZIP transfer over WinRM is inefficient. For very large artifacts,
  publish the ZIP to an authenticated internal artifact endpoint and replace
  `win_copy` with `ansible.windows.win_get_url`.
- Keep the controller clock synchronized and centralize Ansible output in your
  CI/CD or automation platform. Avoid verbose logs in shared locations because
  task data can contain operational details.

## Troubleshooting

`UNREACHABLE` or timeout:

- Check the EC2 security group, network ACL, route, Windows Firewall, and WinRM
  listener.
- Test from Ubuntu with `nc -vz <host> 5985` or `5986`.
- Confirm the username, password source, transport, and port.
- Increase `ansible_winrm_operation_timeout_sec` and keep read timeout higher
  than operation timeout for slow hosts.

Authentication failure:

- Confirm the account is an administrator and not locked or expired.
- For a local account, use `HOSTNAME\username` if plain `Administrator` is
  ambiguous.
- Use Kerberos for Active Directory where organizational policy requires it.

ZIP preflight failure:

- Replace the placeholder with a real ZIP archive.
- Confirm `zip_source_path` and `zip_file`.
- Run `file ansible/files/app.zip` and `unzip -t ansible/files/app.zip`.

Service validation failure:

- `service_name` must be the service name, not necessarily its display name.
- Check Windows Event Viewer and service dependencies.
- Ensure the service executable path remains valid after deployment.

Executable validation failure:

- Set `application_executable` relative to `deployment_path`.
- Check whether the ZIP contains an extra top-level directory.

For detailed diagnostics:

```bash
ansible-playbook ansible/playbooks/deploy.yml -vvv
```

Use verbose output carefully because it contains host and connection metadata.
