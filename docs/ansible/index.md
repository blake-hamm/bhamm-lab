# Ansible
```bash
# To run "main.yaml"
ansible-playbook ansible/main.yaml
```

## Bootstrap
This role bootstraps a new debian host; however, it requires some manual steps:

1. Alter `hosts` file with new entry for server (you can put any free ip address for now and include bootstrap flags).
2. Run playbook with bootstrap args.
  - This will create a preseed file and promote it to netboot-assets
  - Then, the playbook will continuously try to ssh to the host
3. Boot host with ipxe and select debian 11 with preseed file
4. Once ssh is available, playbook will finish and preseed assets will be removed
5. Update `hosts` file with correct ip address and run :
  - `ansible-playbook ansible/main.yml --ask-pass --ask-become-pass`
6. Once this completes, you can remove bootstrap args and the machine should be good to got

## Proxmox
Configured with this: https://github.com/lae/ansible-role-proxmox
