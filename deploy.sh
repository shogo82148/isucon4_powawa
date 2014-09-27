#!/bin/sh
ansible-playbook -i hosts playbooks/deploy.yml -c ssh $*