```bash
docker compose run --rm --build ansible ansible-playbook -i /inventory/inventory.ini --private-key /root/.ssh/id_ed25519 -u ubuntu -b cluster.yml
```

If, need update labels for nodes

```bash
docker compose run --rm --build ansible ansible-playbook -i /inventory/inventory.ini --private-key /root/.ssh/id_ed25519 -u ubuntu -b cluster.yml --tags node-label
```