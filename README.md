# infrastructure
This repository contains instructions for setting up the Archetype server on your machine.   
Following the instructions require a little bit of a technical background.

**For all instructions, you will require a terminal window open**

## Prerequisites 
- `Xcode Command Line Tools` Required only for mac
  - Open a terminal and run `xcode-select --install`
- `Git`: Install from https://git-scm.com/downloads
- `Docker`: Install from https://docs.docker.com/engine/install/
- `Makefile`: Not included with windows! User is encouraged to install Makefile on windows independently.


## Steps

1. Get a copy of the needed files from github:
    ```bash 
    >>> git clone git@github.com:archetype-pal/infrastructure.git

    # Navigate to the project directory
    >>> cd infrastructure
    ```

2. Adust the project configuration to suit your needs.  
    Create a new file `env_file` and fill it with the required variables. A working example can be found [here](./env_file.example).

    Existing deployments with PostgreSQL 17 data need a one-time database upgrade before starting the normal PostgreSQL 18 stack. Follow [the PostgreSQL 18 upgrade runbook](./docs/postgresql-18-upgrade.md) first.

3. Run the project in the background 
    ```bash
    >>> make up-background
    ```
4. Run the database migrations
    ```bash
    >>> make migrate
    ```
5. Build the search indexes (creates the Meilisearch schemas and loads documents from the DB)
    ```bash
    >>> make reindex
    ```
6. Open the website in your browser by navigating to `http://localhost`

> Run `make` (or `make help`) at any time to see every available command.


## Setup the TLS certificates on your server
This is *optional* for those who want to deploy their website securely using `https` on a custom domain.

assuming your domain is called: `archetype.myserver.com`,  
start by adding an `A record` that points to your server before continuing.

To generate TLS certificates, run the following commands:
```bash
>>> make certbot
```

### Enable TLS on the server nginx 
After running the above command, the `certs/` folder is populated with the
files Let's Encrypt issued. `nginx.conf` already points at
`certs/live/$DOMAIN/fullchain.pem` and `privkey.pem`, so once the certs exist
you only need to reload nginx:
```bash
>>> docker compose restart nginx
```

> Certificates expire after 90 days. Re-run `make certbot` (then restart nginx)
> to renew, or wire it into a cron job on the host.

## troubleshooting
Since this setup process is very delicate, it's important to know how to check the logs.  
Run the following command
```bash
>>> make logs
```
to see a real-time view of the logs across all services. `make ps` shows which
services are up.
