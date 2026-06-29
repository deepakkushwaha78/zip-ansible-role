# Setup and Run Guide

This guide explains how to run the existing Ansible project against one or
hundreds of Windows Server 2019/2022 machines.

Run every command from:

```bash
cd /home/deepakkhushwaha/Desktop/NewGen-Ansible
```

## 1. Understand the two supported operations

### Copy a ZIP only

Use the `copy` tag when the requirement is only to place a ZIP on Windows:

```bash
ansible-playbook ansible/playbooks/deploy.yml \
  --tags copy \
  -e zip_file=OpenSSH-Win64.zip
```

This operation:

- verifies WinRM connectivity;
- creates `C:\Deploy` when required;
- copies the ZIP;
- calculates SHA-256 on Ubuntu and Windows;
- fails if the checksums differ.

It does not extract the ZIP, stop a service, install OpenSSH, or modify the
contents already under `C:\Deploy`.

### Full application deployment

Running without a tag performs the complete workflow:

```bash
ansible-playbook ansible/playbooks/deploy.yml
```

This operation backs up the existing application, stops the configured service,
deletes non-preserved application files, extracts the ZIP, starts the service,
and validates the executable and optional health endpoint.

Do not run the full deployment until these values in
`ansible/inventories/production/group_vars.yml` describe a real Windows
application:

```yaml
application_name: "myapp"
service_name: "MyAppService"
zip_file: "app.zip"
application_executable: "MyApp.exe"
```

The current `OpenSSH-Win64.zip` copy use case should use `--tags copy`. The
existing role is not an OpenSSH installer.

## 2. Controller prerequisites

The Ubuntu controller requires:

- Ansible Core;
- the `pywinrm` Python package;
- the `ansible.windows` collection;
- the `community.windows` collection;
- network access to each target's WinRM listener.

Install the collections:

```bash
ansible-galaxy collection install -r requirements.yml
```

If Ansible was installed with `pipx`, install WinRM support with:

```bash
pipx inject ansible-core "pywinrm>=0.4.0"
```

Confirm the controller:

```bash
ansible --version
ansible-galaxy collection list
```

No Ansible agent or Python installation is required on Windows.

## 3. Windows prerequisites

Before Ansible can manage a Windows server, it needs:

- Windows PowerShell 5.1 or later;
- a running WinRM service;
- an HTTP or HTTPS WinRM listener;
- a Windows account permitted to administer the server;
- network/firewall access from the Ansible controller.

The current inventory uses:

```text
Protocol: WinRM over HTTP
Port:     TCP 5985
Auth:     NTLM
```

Opening port 5985 alone does not enable WinRM. If WinRM is not configured and
interactive login is unavailable, bootstrap the server through AWS Systems
Manager, EC2 user data, Group Policy, or a preconfigured AMI.

For an AWS Systems Manager Run Command bootstrap, run as Administrator/SYSTEM:

```powershell
Enable-PSRemoting -Force -SkipNetworkProfileCheck
Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM
Test-WSMan -ComputerName localhost
Get-ChildItem WSMan:\localhost\Listener
```

AWS-provided Windows Server AMIs normally include SSM Agent. The EC2 instance
must also have an IAM instance profile with Systems Manager permissions and
outbound connectivity to the Systems Manager endpoints.

Security requirements:

- Restrict inbound 5985 to the Ansible controller IP/CIDR.
- Never expose WinRM to `0.0.0.0/0`.
- Prefer private IP connectivity through the VPC, VPN, or Direct Connect.
- For production, prefer WinRM HTTPS on 5986 with certificate validation.

Official references:

- [Ansible WinRM guide](https://docs.ansible.com/projects/ansible/latest/os_guide/windows_winrm.html)
- [AWS SSM Agent for Windows](https://docs.aws.amazon.com/systems-manager/latest/userguide/ssm-agent-windows.html)

## 4. Configure multiple Windows servers

Edit `ansible/inventories/production/hosts.ini`.

### Servers sharing one administrative account

```ini
[windows]
winserver01 ansible_host=10.10.1.11
winserver02 ansible_host=10.10.1.12
winserver03 ansible_host=10.10.1.13
winserver04 ansible_host=10.10.1.14

[controller]
localhost ansible_connection=local

[windows:vars]
ansible_user=Administrator
ansible_password="{{ lookup('ansible.builtin.env', 'WINDOWS_ANSIBLE_PASSWORD') }}"
ansible_connection=winrm
ansible_port=5985
ansible_winrm_scheme=http
ansible_winrm_transport=ntlm
ansible_winrm_server_cert_validation=ignore
ansible_winrm_operation_timeout_sec=120
ansible_winrm_read_timeout_sec=180
```

Inventory names such as `winserver01` must be unique. `ansible_host` can be a
private IP, public IP, or resolvable DNS name.

For 300-400 servers, add every server below `[windows]`. Prefer private IP
addresses and generate the inventory from the AWS inventory source rather than
manually maintaining public addresses.

### Different usernames

Override the username on an individual inventory line:

```ini
winserver01 ansible_host=10.10.1.11 ansible_user=Administrator
winserver02 ansible_host=10.10.1.12 ansible_user=deployadmin
```

For a local Windows account where the name is ambiguous, use:

```ini
winserver02 ansible_host=10.10.1.12 ansible_user=SERVER02\deployadmin
```

For Active Directory accounts, Kerberos is preferred over NTLM. Kerberos
requires DNS, time synchronization, SPNs, and controller-side Kerberos
configuration.

## 5. Configure credentials securely

### Shared password

The current inventory reads one shared password from an environment variable:

```bash
read -rsp "Windows password: " WINDOWS_ANSIBLE_PASSWORD
echo
export WINDOWS_ANSIBLE_PASSWORD
```

This avoids storing the password in the repository or shell history. Remove it
after the run:

```bash
unset WINDOWS_ANSIBLE_PASSWORD
```

### Different password per server

Create a host variables directory:

```bash
mkdir -p ansible/inventories/production/host_vars
```

Create an encrypted file for each inventory hostname:

```bash
ansible-vault create \
  ansible/inventories/production/host_vars/winserver01.yml
```

Its encrypted content should define:

```yaml
---
ansible_user: "Administrator"
ansible_password: "server-specific-secret"
```

Repeat for `winserver02.yml`, `winserver03.yml`, and so on. Run with:

```bash
ansible-playbook ansible/playbooks/deploy.yml --ask-vault-pass
```

For automation, retrieve secrets from AWS Secrets Manager, HashiCorp Vault, or
your CI/CD secret store. Do not commit unencrypted passwords or a Vault password
file.

## 6. Configure the deployment

Edit `ansible/inventories/production/group_vars.yml`.

Important variables:

| Variable | Description |
|---|---|
| `application_name` | Application and backup identifier |
| `service_name` | Existing Windows service name |
| `deployment_path` | Destination directory, currently `C:\Deploy` |
| `backup_path` | Backup root, currently `C:\Backup` |
| `zip_file` | ZIP filename inside `ansible/files` |
| `application_executable` | Executable required during validation |
| `health_check_url` | Optional endpoint; blank disables HTTP validation |
| `deployment_timeout` | Service and HTTP timeout |
| `parallel_batch_size` | Number of servers in each rolling batch |
| `maximum_failure_percentage` | Batch failure threshold |
| `preserve_config_patterns` | Configuration files retained during deployment |

Place the real ZIP under:

```text
ansible/files/
```

Validate it before deployment:

```bash
file ansible/files/application.zip
unzip -t ansible/files/application.zip
sha256sum ansible/files/application.zip
```

Either update `zip_file` permanently:

```yaml
zip_file: "application.zip"
```

or override it for one run:

```bash
ansible-playbook ansible/playbooks/deploy.yml \
  --tags copy \
  -e zip_file=application.zip
```

## 7. Validate inventory and WinRM

Display the inventory:

```bash
ansible-inventory --graph
ansible-playbook ansible/playbooks/deploy.yml --list-hosts
```

Check YAML/playbook syntax:

```bash
ansible-playbook ansible/playbooks/deploy.yml --syntax-check
ansible-playbook ansible/playbooks/rollback.yml --syntax-check
ansible-playbook ansible/playbooks/validate.yml --syntax-check
```

Test every Windows server without deploying:

```bash
ansible windows -m ansible.windows.win_ping
```

Expected result for every server:

```text
SUCCESS => {
    "ping": "pong"
}
```

Do not start a fleet deployment until all unexpected connectivity failures are
resolved.

## 8. Run a canary first

Always test one server before targeting the fleet:

```bash
ansible-playbook ansible/playbooks/deploy.yml \
  --tags copy \
  -e zip_file=OpenSSH-Win64.zip \
  --limit 'winserver01:localhost'
```

`localhost` must be included in `--limit` because the controller preflight and
deployment summary run there.

For several canary servers:

```bash
ansible-playbook ansible/playbooks/deploy.yml \
  --tags copy \
  -e zip_file=OpenSSH-Win64.zip \
  --limit 'winserver01:winserver02:winserver03:localhost'
```

## 9. Run against all Windows servers

### Copy the OpenSSH ZIP to every server

```bash
ansible-playbook ansible/playbooks/deploy.yml \
  --tags copy \
  -e zip_file=OpenSSH-Win64.zip
```

The destination on each server is:

```text
C:\Deploy\OpenSSH-Win64.zip
```

### Copy a different ZIP

```bash
ansible-playbook ansible/playbooks/deploy.yml \
  --tags copy \
  -e zip_file=application.zip
```

### Run the full application deployment

```bash
ansible-playbook ansible/playbooks/deploy.yml
```

### Change rolling batch size for one run

```bash
ansible-playbook ansible/playbooks/deploy.yml \
  -e parallel_batch_size=10
```

The default is:

```yaml
parallel_batch_size: 20
```

With 400 servers, Ansible processes approximately 20 servers per rolling batch.
`forks = 50` in `ansible.cfg` is the controller-wide worker limit; `serial`
controls how many Windows servers enter a deployment batch.

Start with 5-10 servers, measure controller/network load, and increase only
after successful canary runs.

## 10. Tags

Available deployment tags:

```bash
# Connectivity check
ansible-playbook ansible/playbooks/deploy.yml --tags connectivity

# Backup phase
ansible-playbook ansible/playbooks/deploy.yml --tags backup

# ZIP transfer and checksum only
ansible-playbook ansible/playbooks/deploy.yml --tags copy

# Complete deployment workflow
ansible-playbook ansible/playbooks/deploy.yml --tags deploy

# Validation only
ansible-playbook ansible/playbooks/deploy.yml --tags validate
```

The `deploy` tag runs backup, copy, extraction, restart, and validation. It is
not equivalent to the safe copy-only operation.

## 11. Validation

Run validation independently:

```bash
ansible-playbook ansible/playbooks/validate.yml
```

It checks:

- deployment directory;
- configured executable;
- configured Windows service;
- optional HTTP health endpoint.

Validation is intended for a deployed Windows application. It is not applicable
to a ZIP that was only copied for later manual use.

## 12. Rollback

Run:

```bash
ansible-playbook ansible/playbooks/rollback.yml
```

Rollback restores:

```text
C:\Backup\<application_name>_previous
```

It then starts the configured service and runs application validation. Rollback
is available only when a previous application deployment existed and the backup
phase completed successfully. A first deployment has no earlier version to
restore.

## 13. Results and failure handling

The deployment summary reports:

- successful servers;
- failed servers;
- skipped servers;
- elapsed time;
- rolling batch size.

The role uses `block`, `rescue`, and `always`. If a full deployment fails after
application files were modified, it attempts automatic rollback when a usable
backup exists.

If the failure percentage exceeds `maximum_failure_percentage`, Ansible stops
advancing the rolling deployment. Investigate the failed batch before retrying.

## 14. Troubleshooting

### WinRM times out

- Verify the instance is running and its IP/DNS is current.
- Check the EC2 security group, network ACL, route table, and Windows Firewall.
- Confirm TCP 5985 or 5986 is reachable from the controller.
- Confirm the WinRM service and listener exist.

```bash
nc -vz <windows-ip> 5985
```

### Authentication fails

- Confirm username and password.
- Confirm the account is not disabled, locked, or expired.
- Confirm the account has the required administrator privileges.
- Prefix local accounts with the server name when necessary.

### ZIP preflight fails

```bash
file ansible/files/<archive>.zip
unzip -t ansible/files/<archive>.zip
```

Confirm that the filename passed through `zip_file` exactly matches the file,
including case.

### Copy is slow

`win_copy` sends data through WinRM and is not efficient for very large
artifacts. For large fleet deployments, store the ZIP in an authenticated
internal artifact repository or S3 distribution path and use
`ansible.windows.win_get_url` with checksum validation.

### Detailed Ansible output

```bash
ansible-playbook ansible/playbooks/deploy.yml -vvv
```

Verbose output can contain infrastructure details. Store and share it securely.
