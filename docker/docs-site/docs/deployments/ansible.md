# Ansible
```bash
# To run "main.yaml"
ansible-playbook ansible/main.yaml
```

## Bootstrap new machine
These steps will bootstrap and configure a new debian host.

1. Manually install the latest version of debian on the host
  - Skip the root user and create a `bhamm` user
  - Give a relevant hostname and domain of `bhamm-lab.com`
  - Disable a DE and enable ssh and utils
2. After rebooting, check the ip address of the host with `ip a`
3. Create a new record in the `ansible/inventory/hosts` file and use the bootstrap args
4. Be intentional and configure the `ansible/templates/<hostname>.j2` file carefully to build the desired network state
5. Run on framework machine:
  - `ansible-playbook ansible/main.yml --ask-pass --ask-become-pass`
6. Once this completes, you can remove bootstrap args and the machine should be good to got

## Proxmox
Configured with this role: https://github.com/lae/ansible-role-proxmox . Adjust the `ansible/inventory/group_vars/proxmox.yml` file accordingly and ensure a new host is in the `proxmox` group.
