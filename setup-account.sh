#!/bin/sh
ansible-playbook -i hosts playbooks/setup-account.yml -c ssh $*
